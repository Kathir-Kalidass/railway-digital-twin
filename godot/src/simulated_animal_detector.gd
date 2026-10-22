class_name SimulatedAnimalDetector
extends Node

## Deterministic simulated ML animal detector with forward cone vision,
## analytic occlusion (terrain, trees, bridges), confidence scoring,
## immediate local fail-safe braking, and MQTT observation publishing.

@export var train_id := "T1"
@export var line := "UP"
@export var source := "onboard-camera"
@export var reconciler_path: NodePath
@export var bridge_path: NodePath
@export var camera_path: NodePath
@export var camera_range_m := 180.0
@export var camera_cone_deg := 25.0
@export var camera_vertical_cone_deg := 10.0
@export var min_confidence := 0.65
@export var detection_persistence := 2
@export var detection_clear_hold_s := 3.0
@export var camera_interval_ticks := 3

var reconciler: TrainReconciler
var _bridge: MQTTBridge
var _camera: Camera3D
var _scenery: Node
var _terrain: Object
var _consecutive_detections := 0
var _clear_timer := 0.0
var _active_detection := false
var _near_active := false
var _confirmed := false
var publish_override: Callable
var _last_detection: Dictionary = {}
var _tick_count := 0
var _event_seq := 0
var _chainage_m := 0.0


func _ready() -> void:
	if reconciler == null and not reconciler_path.is_empty():
		reconciler = get_node_or_null(reconciler_path) as TrainReconciler
	if not bridge_path.is_empty():
		_bridge = get_node_or_null(bridge_path) as MQTTBridge
	if not camera_path.is_empty():
		_camera = get_node_or_null(camera_path) as Camera3D

	var world := get_tree().current_scene if get_tree() else null
	if world != null:
		_scenery = world.get_node_or_null("SceneryDirector")
		_terrain = world.get_node_or_null("TerrainGenerator")


func _owner_train() -> LTSTrain:
	var node := get_parent()
	while node != null:
		if node is LTSTrain:
			return node as LTSTrain
		node = node.get_parent()
	return null


func _to_operational(physical_m: float, train: LTSTrain) -> float:
	var line_len := train.get_track_length_m()
	if line_len <= 0.0:
		return physical_m
	if train.line_id == "DOWN":
		return fposmod(line_len - physical_m, line_len)
	return fposmod(physical_m, line_len)


func _physics_process(delta: float) -> void:
	_tick_count += 1
	if _tick_count % camera_interval_ticks != 0:
		if _active_detection:
			_tick_clear_timer(delta)
		return

	var train := _owner_train()
	var cam_trans := _camera.global_transform if is_instance_valid(_camera) else (get_parent() as Node3D).global_transform if get_parent() is Node3D else Transform3D.IDENTITY
	var speed_kmh := 0.0
	if is_instance_valid(train):
		train_id = train.train_id
		line = train.line_id
		_chainage_m = _to_operational(train.get_track_position_m(), train)
		speed_kmh = train.get_speed_kmh()

	var animals_list: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("wildlife"):
		var n3d := node as Node3D
		if n3d != null and n3d.visible:
			var species := str(n3d.get_meta("species", "deer")) if n3d.has_meta("species") else "deer"
			animals_list.append({
				"position": n3d.global_position,
				"species": species,
				"track_distance_m": float(n3d.get_meta("track_distance_m", 0.0)) if n3d.has_meta("track_distance_m") else 0.0,
			})

	var snapshot := {
		"camera_transform": cam_trans,
		"speed_kmh": speed_kmh,
		"animals": animals_list,
		"terrain": _terrain,
		"trees": _scenery.call("tree_roots") if is_instance_valid(_scenery) and _scenery.has_method("tree_roots") else [],
	}

	process_detections(snapshot, delta * float(camera_interval_ticks))


func detect(snapshot: Dictionary) -> Array[Dictionary]:
	var cam_trans: Transform3D = snapshot.get("camera_transform", Transform3D.IDENTITY)
	var speed_kmh: float = float(snapshot.get("speed_kmh", 0.0))
	var animals: Array = snapshot.get("animals", [])
	var terrain: Object = snapshot.get("terrain", null)
	var trees: Array = snapshot.get("trees", [])
	var bridge_aabbs: Array = snapshot.get("bridge_aabbs", [])

	var results: Array[Dictionary] = []

	for item in animals:
		if not item is Dictionary:
			continue
		var anim_dict: Dictionary = item
		var anim_pos: Vector3 = anim_dict.get("position", Vector3.ZERO)
		var species: String = str(anim_dict.get("species", "deer"))

		# Camera local coordinate system:
		# Godot camera looks down -Z axis, +X is right, +Y is up.
		var local_pos := cam_trans.affine_inverse() * anim_pos
		var depth := -local_pos.z
		if depth <= 0.1 or depth > camera_range_m:
			continue

		var lateral_angle := rad_to_deg(atan2(absf(local_pos.x), depth))
		var vertical_angle := rad_to_deg(atan2(absf(local_pos.y), depth))
		if lateral_angle > camera_cone_deg or vertical_angle > camera_vertical_cone_deg:
			continue

		var distance_3d := (anim_pos - cam_trans.origin).length()
		if distance_3d > camera_range_m:
			continue

		# Occlusion test
		if _is_occluded(cam_trans.origin, anim_pos, terrain, trees, bridge_aabbs):
			continue

		# Confidence calculation
		var mult := 0.9 if species == "deer" else (1.1 if species == "elephant" else 1.0)
		var conf := clampf((1.0 - distance_3d / camera_range_m) * mult, 0.0, 1.0)
		if conf < min_confidence:
			continue

		# Screen position in 0..1 viewport space
		var h_tan := tan(deg_to_rad(camera_cone_deg))
		var v_tan := tan(deg_to_rad(camera_vertical_cone_deg))
		var sx := clampf(0.5 + 0.5 * (local_pos.x / (depth * h_tan)), 0.0, 1.0)
		var sy := clampf(0.5 - 0.5 * (local_pos.y / (depth * v_tan)), 0.0, 1.0)

		var critical := OnboardBraking.should_stop(distance_3d, speed_kmh)

		results.append({
			"species": species,
			"confidence": conf,
			"distance_m": distance_3d,
			"screen_position": Vector2(sx, sy),
			"critical": critical,
			"position": anim_pos,
		})

	# Sort nearest first
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance_m", 0.0)) < float(b.get("distance_m", 0.0))
	)
	return results


func process_detections(snapshot: Dictionary, delta: float) -> void:
	var detections := detect(snapshot)
	if not detections.is_empty():
		var best: Dictionary = detections[0]
		_last_detection = best
		_consecutive_detections += 1
		_clear_timer = detection_clear_hold_s
		if not _near_active:
			_active_detection = true
			_near_active = true
			_apply_near()
			_publish_observation(true, best, true, false)
		if not _confirmed and _consecutive_detections >= detection_persistence:
			_confirmed = true
			_apply_stop()
			_publish_observation(true, best, true, true)
	else:
		_consecutive_detections = 0
		_tick_clear_timer(delta)


func _tick_clear_timer(delta: float) -> void:
	if _active_detection:
		_clear_timer -= delta
		if _clear_timer <= 0.0:
			_active_detection = false
			_near_active = false
			_confirmed = false
			_lift_stop()
			_publish_observation(false, _last_detection, false, false)


func _apply_near() -> void:
	if is_instance_valid(reconciler):
		reconciler.set_local_wildlife_limit(30.0)


func _apply_stop() -> void:
	if is_instance_valid(reconciler):
		reconciler.set_local_wildlife_limit(0.0)


func _lift_stop() -> void:
	if is_instance_valid(reconciler):
		reconciler.set_local_wildlife_limit(-1.0)


func _publish_observation(detected: bool, det_info: Dictionary, near := false, confirmed := false) -> void:
	_event_seq += 1
	var event_id := "onboard-%s-%d-%d" % [train_id, int(Time.get_unix_time_from_system()), _event_seq]
	var payload := {
		"eventId": event_id,
		"source": source,
		"line": line,
		"distanceM": _chainage_m,
		"distanceToAnimalM": float(det_info.get("distance_m", 0.0)) if detected else 0.0,
		"wildlifeDetected": detected,
		"nearAnimal": near if detected else false,
		"confirmed": confirmed if detected else false,
		"species": str(det_info.get("species", "deer")),
		"count": 1 if detected else 0,
		"onTrack": detected,
		"trainId": train_id,
		"confidence": float(det_info.get("confidence", 0.0)) if detected else 0.0,
		"timestamp": Time.get_unix_time_from_system(),
	}
	if publish_override.is_valid():
		publish_override.call(payload)
	if is_instance_valid(_bridge) and _bridge.is_broker_connected():
		_bridge.publish("railway/wildlife", payload)


func is_detection_active() -> bool:
	return _active_detection


func is_near_active() -> bool:
	return _near_active


func is_confirmed() -> bool:
	return _confirmed


func get_last_detection() -> Dictionary:
	return _last_detection


func _is_occluded(cam_pos: Vector3, target_pos: Vector3, terrain: Object, trees: Array, bridge_aabbs: Array) -> bool:
	var dir := target_pos - cam_pos
	var dist := dir.length()
	if dist < 0.1:
		return false
	var ray := dir / dist

	# 1. Terrain occlusion
	if terrain != null and terrain.has_method("height_at"):
		var step_m := 5.0
		var t := step_m
		while t < dist - 2.0:
			var p := cam_pos + ray * t
			var h := float(terrain.call("height_at", p.x, p.z))
			if h > p.y + 0.15:
				return true
			t += step_m

	# 2. Tree trunks
	for tree in trees:
		var tree_node := tree as Node3D
		if tree_node == null:
			continue
		var tpos := tree_node.global_position if tree_node.is_inside_tree() else tree_node.position
		var v_seg := Vector2(target_pos.x - cam_pos.x, target_pos.z - cam_pos.z)
		var seg_len_sq := v_seg.length_squared()
		if seg_len_sq < 0.01:
			continue
		var v_tree := Vector2(tpos.x - cam_pos.x, tpos.z - cam_pos.z)
		var u := clampf(v_tree.dot(v_seg) / seg_len_sq, 0.0, 1.0)
		var closest := Vector2(cam_pos.x, cam_pos.z) + v_seg * u
		var dist_to_axis := (Vector2(tpos.x, tpos.z) - closest).length()
		if dist_to_axis <= 1.2:
			var ray_y := cam_pos.y + (target_pos.y - cam_pos.y) * u
			if ray_y >= tpos.y and ray_y <= tpos.y + 8.0:
				return true

	# 3. Bridge AABBs
	for box in bridge_aabbs:
		if box is AABB and _ray_intersects_aabb(cam_pos, ray, dist, box):
			return true

	return false


func _ray_intersects_aabb(origin: Vector3, dir: Vector3, max_dist: float, box: AABB) -> bool:
	var tmin := 0.0
	var tmax := max_dist
	for i in 3:
		var inv_d := 1.0 / dir[i] if absf(dir[i]) > 0.00001 else 100000.0
		var t0 := (box.position[i] - origin[i]) * inv_d
		var t1 := (box.position[i] + box.size[i] - origin[i]) * inv_d
		if inv_d < 0.0:
			var tmp := t0
			t0 = t1
			t1 = tmp
		tmin = maxf(tmin, t0)
		tmax = minf(tmax, t1)
		if tmax <= tmin:
			return false
	return tmin < max_dist and tmax > 0.0
