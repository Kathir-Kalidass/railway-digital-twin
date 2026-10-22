class_name FleetController
extends Node3D

@export var track_registry_path: NodePath = NodePath("../TrackRegistry")
@export var bridge_path: NodePath = NodePath("../MQTTBridge")
@export var reconciler_path: NodePath = NodePath("../TrainReconciler")
@export var default_train_path: NodePath = NodePath("../Train")
@export var crossover_duration_sec := 1.5

var _trains: Dictionary = {}
var _train_lines: Dictionary = {}
var _train_blocks: Dictionary = {}
var _crossovers_in_progress: Dictionary = {}
var _route_crossings: Dictionary = {}
var _pending_states: Dictionary = {}
var _wrong_line: Dictionary = {}

var _registry: TrackRegistry
var _bridge: MQTTBridge
var _reconciler: TrainReconciler


func _ready() -> void:
	_registry = get_node_or_null(track_registry_path) as TrackRegistry
	_bridge = get_node_or_null(bridge_path) as MQTTBridge
	_reconciler = get_node_or_null(reconciler_path) as TrainReconciler

	var default_train := get_node_or_null(default_train_path) as LTSTrain
	if is_instance_valid(default_train):
		_trains["T1"] = default_train
		_train_lines["T1"] = "UP"
		_train_blocks["T1"] = "UP-B0"

	if _bridge:
		_bridge.message_received.connect(_on_message)
		_bridge.connected.connect(_subscribe)
		if _bridge.is_broker_connected():
			_subscribe()


func _subscribe() -> void:
	if not _bridge:
		return
	_bridge.subscribe("railway/state")


func _on_message(topic: String, payload: Dictionary) -> void:
	if topic == "railway/state":
		apply_state(payload)


func apply_state(state: Dictionary) -> void:
	var trains_var: Variant = state.get("trains", [])
	if not (trains_var is Array):
		return
	var routes_var: Variant = state.get("routes", {})
	if routes_var is Dictionary:
		var wl_var: Variant = routes_var.get("wrongLine", {})
		if wl_var is Dictionary:
			_wrong_line = wl_var

	var seen_ids: Array[String] = []

	for item in trains_var:
		if not (item is Dictionary):
			continue
		var id := str(item.get("id", ""))
		if id.is_empty():
			continue

		seen_ids.append(id)
		var line := str(item.get("line", "UP")).to_upper()
		var block := str(item.get("block", ""))
		var offset_m := float(item.get("offsetM", 0.0))
		var speed_kmh := float(item.get("speedKmh", 0.0))
		var target_kmh := float(item.get("targetSpeedKmh", speed_kmh))
		var travel_sign := float(item.get("travelSign", -1.0 if line == "DOWN" else 1.0))
		var route_phase := str(item.get("routePhase", ""))
		var route_crossing := route_phase == "CROSS_ENTRY" or route_phase == "CROSS_EXIT"
		var crossing_progress := clampf(float(item.get("crossingProgress", 0.0)), 0.0, 1.0)
		var crossover_id := str(item.get("crossoverId", ""))
		var target_line := str(item.get("targetLine", line))
		if target_line.is_empty():
			target_line = line

		# Tighten target speed with local safety reconciler if active
		if is_instance_valid(_reconciler) and _reconciler.get_local_wildlife_limit() >= 0.0:
			target_kmh = minf(target_kmh, _reconciler.get_local_wildlife_limit())

		var track_node: LTSTrack = null
		if _registry:
			track_node = _registry.track(line)
		elif line == "UP":
			track_node = get_node_or_null("../Track") as LTSTrack

		var physical_var: Variant = item.get("physicalM")
		var dist_m := calculate_track_distance(line, block, offset_m, float(physical_var) if physical_var != null else NAN)

		var train: LTSTrain = _trains.get(id, null)
		if not is_instance_valid(train):
			if id == "T1" and is_instance_valid(get_node_or_null(default_train_path)):
				train = get_node_or_null(default_train_path) as LTSTrain
			else:
				train = LTSTrain.new()
				train.name = "Train_%s" % id
				train.travel_sign = travel_sign
				if is_instance_valid(track_node):
					train.set_track(track_node)
				train.set_remote_mode(true)
				train.set_track_position_m(dist_m)
				add_child(train)
			_trains[id] = train
		train.travel_sign = travel_sign
		train.train_id = id
		train.line_id = line
		train.block_id = block
		var detector := train.get_detector()
		if detector:
			detector.train_id = id
			detector.line = line

		if route_crossing:
			_apply_route_crossing(id, target_line, crossing_progress, crossover_id, route_phase, line)
			train.set_remote_target(dist_m, speed_kmh, target_kmh)
		elif _route_crossings.has(id):
			_finish_route_crossing(id, line)
			if is_instance_valid(track_node):
				train.set_track(track_node)
			train.set_remote_target(dist_m, speed_kmh, target_kmh)
		elif is_instance_valid(track_node) and train.get_node_or_null(train.track_path) != track_node and not _crossovers_in_progress.has(id):
			var previous_line := str(_train_lines.get(id, ""))
			if not previous_line.is_empty() and previous_line != line:
				transition_train_line(id, line, crossover_duration_sec)
			else:
				train.set_track(track_node)
			if _crossovers_in_progress.has(id):
				_pending_states[id] = {
					"line": line,
					"dist_m": dist_m,
					"speed_kmh": speed_kmh,
					"target_kmh": target_kmh
				}
			else:
				train.set_remote_target(dist_m, speed_kmh, target_kmh)
				_train_lines[id] = line
		elif _crossovers_in_progress.has(id):
			_pending_states[id] = {
				"line": line,
				"dist_m": dist_m,
				"speed_kmh": speed_kmh,
				"target_kmh": target_kmh
			}
		else:
			train.set_remote_target(dist_m, speed_kmh, target_kmh)
			_train_lines[id] = line
		_train_blocks[id] = block

	for tid in _trains:
		var camera_train: LTSTrain = _trains[tid]
		if is_instance_valid(camera_train) and camera_train.has_method("apply_camera_state"):
			camera_train.apply_camera_state(state)

	# Safely remove trains that disappeared from backend state
	var current_ids := _trains.keys()
	for cid in current_ids:
		if not seen_ids.has(cid) and cid != "T1":
			var removed_train: LTSTrain = _trains[cid]
			if is_instance_valid(removed_train):
				removed_train.queue_free()
			_trains.erase(cid)
			_train_lines.erase(cid)
			_train_blocks.erase(cid)
			_route_crossings.erase(cid)
			_crossovers_in_progress.erase(cid)
			_pending_states.erase(cid)


func _apply_route_crossing(train_id: String, to_line: String, progress: float, crossover_id: String, phase: String, state_line: String) -> void:
	var train := get_train(train_id)
	if not is_instance_valid(train):
		return
	var target_track: LTSTrack = _registry.track(to_line) if _registry else null
	if not is_instance_valid(target_track):
		return
	var from_line := get_train_line(train_id)
	if from_line.is_empty():
		if phase == "CROSS_ENTRY":
			from_line = "UP" if to_line == "DOWN" else "DOWN"
		else:
			from_line = state_line
		_train_lines[train_id] = from_line
	if from_line == to_line:
		train.set_track_blend(target_track, progress)
		return
	var scenery_name := _scenery_crossover_name(crossover_id, from_line, phase)
	var now_ms := Time.get_ticks_msec()
	var visual_progress := progress
	if not _route_crossings.has(train_id):
		_route_crossings[train_id] = {
			"from_line": from_line,
			"to_line": to_line,
			"target_track": target_track,
			"crossover_name": crossover_id,
			"scenery_name": scenery_name,
			"visual_progress": progress,
			"target_progress": progress,
			"last_target_progress": progress,
			"last_update_ms": now_ms,
			"rate": 0.45,
		}
		_crossovers_in_progress[train_id] = {
			"from_line": from_line,
			"to_line": to_line,
			"progress": progress,
			"duration": 1.0,
			"crossover_name": scenery_name,
			"target_track": target_track,
		}
	else:
		var info: Dictionary = _route_crossings[train_id]
		var elapsed := float(now_ms - int(info.get("last_update_ms", now_ms))) / 1000.0
		var delta := progress - float(info.get("last_target_progress", progress))
		if elapsed >= 0.05 and delta > 0.0001:
			info["rate"] = clampf(delta / elapsed, 0.05, 2.0)
		var current_visual := float(info.get("visual_progress", progress))
		if progress + 0.05 < current_visual:
			current_visual = progress
		visual_progress = current_visual
		info["to_line"] = to_line
		info["target_track"] = target_track
		info["crossover_name"] = crossover_id
		info["scenery_name"] = scenery_name
		info["target_progress"] = progress
		info["last_target_progress"] = progress
		info["last_update_ms"] = now_ms
		info["visual_progress"] = visual_progress
		var cross_info: Dictionary = _crossovers_in_progress.get(train_id, {})
		cross_info["target_track"] = target_track
		cross_info["to_line"] = to_line
		cross_info["crossover_name"] = scenery_name
		_crossovers_in_progress[train_id] = cross_info
	_scenery_active(scenery_name, true)
	train.set_track_blend(target_track, visual_progress)


func _finish_route_crossing(train_id: String, line: String) -> void:
	var info: Dictionary = _route_crossings.get(train_id, {})
	var train := get_train(train_id)
	if is_instance_valid(train):
		var from_line := str(info.get("from_line", ""))
		var target_track: LTSTrack = info.get("target_track")
		train.clear_track_blend()
		if is_instance_valid(target_track) and from_line != line:
			train.set_track(target_track)
		_train_lines[train_id] = line
		var scenery_name := str(info.get("scenery_name", info.get("crossover_name", "")))
		_scenery_active(scenery_name, false)
	_route_crossings.erase(train_id)
	_crossovers_in_progress.erase(train_id)
	_pending_states.erase(train_id)


func _scenery_crossover_name(crossover_id: String, from_line: String, phase: String) -> String:
	if crossover_id == "X-A" or crossover_id == "CrossoverA":
		return "CrossoverA"
	if crossover_id == "X-B" or crossover_id == "CrossoverB":
		return "CrossoverB"
	if not crossover_id.is_empty():
		return crossover_id
	if phase == "CROSS_ENTRY":
		return "CrossoverA" if from_line == "UP" else "CrossoverB"
	return "CrossoverB" if from_line == "DOWN" else "CrossoverA"


func _scenery_active(node_name: String, active: bool) -> void:
	if node_name.is_empty():
		return
	var scenery := get_node_or_null("../Scenery")
	if scenery and scenery.has_method("set_crossover_active"):
		scenery.call("set_crossover_active", node_name, active)


func calculate_track_distance(line: String, block_id: String, offset_m: float, physical_m := NAN) -> float:
	if not is_nan(physical_m):
		var physical_len := _registry.length_m(line) if _registry else (1253.9822 if line == "UP" else 1228.8495)
		return fposmod(physical_m, physical_len)
	var line_len := 1253.9822
	if _registry:
		line_len = _registry.length_m(line)
	elif line == "DOWN":
		line_len = 1228.8495

	var block_len := line_len / 5.0
	var block_index := 0
	if block_id.contains("-B"):
		var parts := block_id.split("-B")
		if parts.size() > 1:
			block_index = int(parts[1])

	var operational := block_index * block_len + offset_m
	if line == "DOWN":
		return fposmod(line_len - operational, line_len)
	return fposmod(operational, line_len)


func get_train(train_id: String) -> LTSTrain:
	return _trains.get(train_id, null) as LTSTrain


func get_train_line(train_id: String) -> String:
	return _train_lines.get(train_id, "")


func get_train_block(train_id: String) -> String:
	return _train_blocks.get(train_id, "")


func train_ids() -> Array:
	return _trains.keys()


func train_count() -> int:
	return _trains.size()


func is_train_crossing_over(train_id: String) -> bool:
	return _crossovers_in_progress.has(train_id)


func transition_train_line(train_id: String, to_line: String, duration_sec: float = 1.0) -> void:
	if _crossovers_in_progress.has(train_id):
		return
	var train := get_train(train_id)
	if not is_instance_valid(train):
		return
	var from_line := get_train_line(train_id)
	if from_line == to_line:
		return

	var scenery := get_node_or_null("../Scenery")
	var xover_name := "CrossoverA" if from_line == "UP" else "CrossoverB"
	if scenery and scenery.has_method("set_crossover_active"):
		scenery.call("set_crossover_active", xover_name, true)

	var target_track: LTSTrack = null
	if _registry:
		target_track = _registry.track(to_line)

	_crossovers_in_progress[train_id] = {
		"from_line": from_line,
		"to_line": to_line,
		"progress": 0.0,
		"duration": maxf(0.1, duration_sec),
		"crossover_name": xover_name,
		"target_track": target_track
	}
	if is_instance_valid(target_track):
		train.set_track_blend(target_track, 0.0)


func _finish_crossover(train_id: String, info: Dictionary) -> void:
	var train := get_train(train_id)
	if not is_instance_valid(train):
		return

	var source_track := train.get_node_or_null(train.track_path) as LTSTrack
	var source_distance := train.get_track_position_m()
	var target_track: LTSTrack = info.get("target_track")
	train.clear_track_blend()
	if is_instance_valid(target_track):
		var target_distance := source_distance
		if is_instance_valid(source_track) and source_track.length > 0.0:
			target_distance = source_track.map_to_parallel(source_distance)
		train.set_track(target_track)
		train.set_track_position_m(target_distance)

	_train_lines[train_id] = info["to_line"]
	var scenery := get_node_or_null("../Scenery")
	if scenery and scenery.has_method("set_crossover_active"):
		scenery.call("set_crossover_active", info["crossover_name"], false)


func _process(delta: float) -> void:
	var done: Array[String] = []
	for train_id in _crossovers_in_progress:
		var train := get_train(train_id)
		if not is_instance_valid(train):
			done.append(train_id)
			continue
		if _route_crossings.has(train_id):
			var route_info: Dictionary = _route_crossings[train_id]
			var target := float(route_info.get("target_progress", 1.0))
			var visual := float(route_info.get("visual_progress", 0.0))
			var rate := float(route_info.get("rate", 0.45))
			visual = move_toward(visual, target, rate * delta)
			route_info["visual_progress"] = visual
			var route_track: LTSTrack = route_info.get("target_track")
			if is_instance_valid(route_track):
				train.set_track_blend(route_track, visual)
			continue
		var info: Dictionary = _crossovers_in_progress[train_id]

		info["progress"] += delta / float(info["duration"])
		var t: float = clampf(info["progress"], 0.0, 1.0)
		var target_track: LTSTrack = info.get("target_track")
		if is_instance_valid(target_track):
			train.set_track_blend(target_track, t)

		if t >= 1.0:
			_finish_crossover(train_id, info)
			done.append(train_id)

	for tid in done:
		_crossovers_in_progress.erase(tid)
		var pending: Dictionary = _pending_states.get(tid, {})
		if pending.is_empty():
			continue
		var pending_line := str(pending.get("line", ""))
		if pending_line != str(_train_lines.get(tid, "")):
			_pending_states.erase(tid)
			transition_train_line(tid, pending_line, crossover_duration_sec)
			if _crossovers_in_progress.has(tid):
				_pending_states[tid] = pending
			continue
		var train := get_train(tid)
		if is_instance_valid(train):
			train.set_remote_target(float(pending["dist_m"]), float(pending["speed_kmh"]), float(pending["target_kmh"]))
		_pending_states.erase(tid)

