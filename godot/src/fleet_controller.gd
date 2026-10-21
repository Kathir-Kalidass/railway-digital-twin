class_name FleetController
extends Node3D

@export var track_registry_path: NodePath = NodePath("../TrackRegistry")
@export var bridge_path: NodePath = NodePath("../MQTTBridge")
@export var reconciler_path: NodePath = NodePath("../TrainReconciler")
@export var default_train_path: NodePath = NodePath("../Train")

var _trains: Dictionary = {}
var _train_lines: Dictionary = {}
var _train_blocks: Dictionary = {}
var _crossovers_in_progress: Dictionary = {}

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

		# Tighten target speed with local safety reconciler if active
		if is_instance_valid(_reconciler) and _reconciler.get_local_wildlife_limit() >= 0.0:
			target_kmh = minf(target_kmh, _reconciler.get_local_wildlife_limit())

		var track_node: LTSTrack = null
		if _registry:
			track_node = _registry.track(line)
		elif line == "UP":
			track_node = get_node_or_null("../Track") as LTSTrack

		var dist_m := calculate_track_distance(line, block, offset_m)

		var train: LTSTrain = _trains.get(id, null)
		if not is_instance_valid(train):
			if id == "T1" and is_instance_valid(get_node_or_null(default_train_path)):
				train = get_node_or_null(default_train_path) as LTSTrain
			else:
				train = LTSTrain.new()
				train.name = "Train_%s" % id
				if is_instance_valid(track_node):
					train.set_track(track_node)
				train.set_remote_mode(true)
				train.set_track_position_m(dist_m)
				add_child(train)
			_trains[id] = train

		if is_instance_valid(track_node) and train.get_node_or_null(train.track_path) != track_node:
			train.set_track(track_node)

		train.set_remote_target(dist_m, speed_kmh, target_kmh)
		_train_lines[id] = line
		_train_blocks[id] = block

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


func calculate_track_distance(line: String, block_id: String, offset_m: float) -> float:
	var line_len := 753.9822
	if _registry:
		line_len = _registry.length_m(line)
	elif line == "DOWN":
		line_len = 728.8495

	var block_len := line_len / 5.0
	var block_index := 0
	if block_id.contains("-B"):
		var parts := block_id.split("-B")
		if parts.size() > 1:
			block_index = int(parts[1])

	var base_distance := block_index * block_len
	return fposmod(base_distance + offset_m, line_len)


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


func _process(delta: float) -> void:
	var done: Array[String] = []
	for train_id in _crossovers_in_progress:
		var info: Dictionary = _crossovers_in_progress[train_id]
		var train := get_train(train_id)
		if not is_instance_valid(train):
			done.append(train_id)
			continue

		info["progress"] += delta / float(info["duration"])
		var t: float = clampf(info["progress"], 0.0, 1.0)

		if info.has("target_track") and is_instance_valid(info["target_track"]):
			var target_track: LTSTrack = info["target_track"]
			var source_track: LTSTrack = train.get_node_or_null(train.track_path) as LTSTrack
			if is_instance_valid(source_track):
				var d_source := train.get_track_position_m()
				var d_target := d_source * target_track.length / source_track.length
				var p_source := source_track.get_global_transform_at_distance(d_source)
				var p_target := target_track.get_global_transform_at_distance(d_target)
				var blend_origin := p_source.origin.lerp(p_target.origin, t)
				train.global_position = blend_origin

		if t >= 1.0:
			var to_line: String = info["to_line"]
			_train_lines[train_id] = to_line
			if info.has("target_track") and is_instance_valid(info["target_track"]):
				train.set_track(info["target_track"])
			var scenery := get_node_or_null("../Scenery")
			var xover_name: String = info["crossover_name"]
			if scenery and scenery.has_method("set_crossover_active"):
				scenery.call("set_crossover_active", xover_name, false)
			done.append(train_id)

	for tid in done:
		_crossovers_in_progress.erase(tid)

