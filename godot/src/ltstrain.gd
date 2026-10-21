class_name LTSTrain
extends Node3D

@export var track_path: NodePath = NodePath("../Track")
@export var initial_position_m := 40.0
@export var initial_speed_kmh := 54.0
@export var acceleration_mps2 := 0.45
@export var service_brake_mps2 := 0.7
@export var emergency_brake_mps2 := 1.1
@export var use_lts_models := true

const LTS_LOCOMOTIVE := "res://assets/models/lts/wagon_locomotive.glb"
const LTS_PASSENGER := "res://assets/models/lts/wagon_passenger.glb"

var _target_speed_mps := 0.0
var _speed_mps := 0.0
var _track_position_m := 0.0
var _target_distance_m := 0.0
var remote_mode := false
var _carriages: Array[Node3D] = []
var _wheels: Array[MeshInstance3D] = []
var _track: LTSTrack
var _lts_math: Node
var uses_lts_models := false


func set_remote_mode(enabled: bool) -> void:
	remote_mode = enabled


func set_track(new_track: LTSTrack) -> void:
	_track = new_track
	if is_instance_valid(_track):
		track_path = _track.get_path()


func set_track_position_m(distance_m: float) -> void:
	if not is_instance_valid(_lts_math):
		_lts_math = load("res://Data/Scripts/Singletons/Math.gd").new()
	if is_instance_valid(_track):
		_track_position_m = fposmod(distance_m, _track.length)
		_target_distance_m = _track_position_m
		_update_train_pose()


func set_remote_target(distance_m: float, speed_kmh: float, target_kmh: float) -> void:
	if not is_instance_valid(_lts_math):
		_lts_math = load("res://Data/Scripts/Singletons/Math.gd").new()
	if not is_instance_valid(_track):
		return
	var track_len := _track.length
	_target_distance_m = fposmod(distance_m, track_len)
	_target_speed_mps = float(_lts_math.call("kmh_to_speed", target_kmh))
	_speed_mps = float(_lts_math.call("kmh_to_speed", speed_kmh))

	if not remote_mode:
		remote_mode = true
		_track_position_m = _target_distance_m
		_update_train_pose()
		return

	var err := fposmod(_target_distance_m - _track_position_m, track_len)
	if err > track_len * 0.5:
		err -= track_len
	if absf(err) > 15.0:
		_track_position_m = _target_distance_m
		_update_train_pose()


func set_target_speed_kmh(speed_kmh: float) -> void:
	var limit := 120.0
	if is_instance_valid(_track):
		limit = minf(limit, _track.max_speed_kmh)
	var clamped_speed := clampf(speed_kmh, 0.0, limit)
	_target_speed_mps = float(_lts_math.call("kmh_to_speed", clamped_speed))


func get_target_speed_kmh() -> float:
	return float(_lts_math.call("speed_to_kmh", _target_speed_mps))


func get_speed_kmh() -> float:
	return float(_lts_math.call("speed_to_kmh", _speed_mps))


func get_track_position_m() -> float:
	return _track_position_m


func _ready() -> void:
	if not is_instance_valid(_lts_math):
		_lts_math = load("res://Data/Scripts/Singletons/Math.gd").new()
	if not is_instance_valid(_track):
		_track = get_node_or_null(track_path) as LTSTrack
	if not is_instance_valid(_track):
		push_error("LTSTrain requires an LTSTrack at %s" % track_path)
		set_physics_process(false)
		return

	_track_position_m = fposmod(initial_position_m, _track.length)
	_target_speed_mps = float(_lts_math.call("kmh_to_speed", initial_speed_kmh))
	_speed_mps = _target_speed_mps
	_build_train()
	_update_train_pose()
	_fit_lts_models()


func _exit_tree() -> void:
	if is_instance_valid(_lts_math):
		_lts_math.free()


func _physics_process(delta: float) -> void:
	if remote_mode:
		if is_instance_valid(_track):
			var track_len := _track.length
			_track_position_m = fposmod(_track_position_m + _speed_mps * delta, track_len)
			var err := fposmod(_target_distance_m - _track_position_m, track_len)
			if err > track_len * 0.5:
				err -= track_len
			_track_position_m = fposmod(_track_position_m + err * minf(1.0, 3.0 * delta), track_len)
			_update_train_pose()
			var rot_delta := (_speed_mps * delta) / 0.48
			for wheel in _wheels:
				wheel.rotate_object_local(Vector3.UP, rot_delta)
		return

	var target_speed := _target_speed_mps
	if _target_speed_mps < _speed_mps:
		var braking := emergency_brake_mps2 if _target_speed_mps == 0.0 else service_brake_mps2
		_speed_mps = move_toward(_speed_mps, target_speed, braking * delta)
	else:
		_speed_mps = move_toward(_speed_mps, target_speed, acceleration_mps2 * delta)

	_track_position_m = fposmod(_track_position_m + _speed_mps * delta, _track.length)

	_update_train_pose()
	var rotation_delta := (_speed_mps * delta) / 0.48
	for wheel in _wheels:
		wheel.rotate_object_local(Vector3.UP, rotation_delta)


func _update_train_pose() -> void:
	for index in _carriages.size():
		var carriage_distance := fposmod(_track_position_m - index * 18.0, _track.length)
		_carriages[index].global_transform = _track.get_global_transform_at_distance(carriage_distance)


func _build_train() -> void:
	var colors := [
		Color(0.72, 0.16, 0.08),
		Color(0.84, 0.86, 0.82),
		Color(0.84, 0.86, 0.82),
	]
	for index in 3:
		var carriage := Node3D.new()
		carriage.name = ["Locomotive", "PassengerCoach1", "PassengerCoach2"][index]
		add_child(carriage)
		_carriages.append(carriage)
		if not _build_lts_carriage(carriage, index == 0):
			_build_carriage(carriage, colors[index], index == 0)


func _build_lts_carriage(parent: Node3D, locomotive: bool) -> bool:
	if not use_lts_models:
		return false
	var path := LTS_LOCOMOTIVE if locomotive else LTS_PASSENGER
	if not FileAccess.file_exists(path):
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		return false
	model.name = "LTSModel"
	parent.add_child(model)
	if locomotive:
		for side in [-0.85, 0.85]:
			var headlight := SpotLight3D.new()
			headlight.position = Vector3(8.1, 1.6, side)
			headlight.rotation.y = -PI * 0.5
			headlight.spot_range = 60.0
			headlight.spot_angle = 26.0
			headlight.light_energy = 2.2
			headlight.light_color = Color(1.0, 0.93, 0.8)
			headlight.shadow_enabled = false
			parent.add_child(headlight)
	for offset in [-4.0, 4.0]:
		var cabin := OmniLight3D.new()
		cabin.position = Vector3(offset, 2.6, 0.0)
		cabin.omni_range = 5.5
		cabin.light_energy = 0.35
		cabin.light_color = Color(1.0, 0.86, 0.64)
		cabin.shadow_enabled = false
		parent.add_child(cabin)
	uses_lts_models = true
	return true


func _fit_lts_models() -> void:
	for carriage in _carriages:
		var model := carriage.get_node_or_null("LTSModel") as Node3D
		if model == null:
			continue
		var box := _local_aabb(carriage, model)
		if box.size == Vector3.ZERO:
			continue
		model.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)


func _local_aabb(parent: Node3D, model: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var relative := parent.global_transform.affine_inverse() * mesh_instance.global_transform
		var box := mesh_instance.get_aabb()
		for index in 8:
			var point := relative * box.get_endpoint(index)
			if not found:
				result = AABB(point, Vector3.ZERO)
				found = true
			else:
				result = result.expand(point)
	return result


func _build_carriage(parent: Node3D, body_color: Color, locomotive: bool) -> void:
	var body := BoxMesh.new()
	body.size = Vector3(13.0, 2.7, 2.8)
	body.material = _material(body_color, 0.56)
	_add_box(parent, "CarBody", body, Vector3(0.0, 2.0, 0.0))

	var roof := BoxMesh.new()
	roof.size = Vector3(12.6, 0.22, 2.9)
	roof.material = _material(Color(0.18, 0.2, 0.21), 0.7)
	_add_box(parent, "Roof", roof, Vector3(0.0, 3.4, 0.0))

	var window_mesh := BoxMesh.new()
	window_mesh.size = Vector3(7.5, 0.85, 0.04)
	window_mesh.material = _material(Color(0.13, 0.26, 0.31), 0.19, 0.35)
	_add_box(parent, "Windows", window_mesh, Vector3(0.0, 2.72, 1.42))
	_add_box(parent, "WindowsOtherSide", window_mesh, Vector3(0.0, 2.72, -1.42))

	if locomotive:
		var cab_mesh := BoxMesh.new()
		cab_mesh.size = Vector3(3.4, 1.5, 2.65)
		cab_mesh.material = _material(Color(0.75, 0.18, 0.09), 0.48)
		_add_box(parent, "Cab", cab_mesh, Vector3(3.6, 4.0, 0.0))
		_add_headlight(parent, 6.6, 1.5, 0.55)
		_add_headlight(parent, 6.6, 1.5, -0.55)

	for axle_offset in [-4.5, 4.5]:
		var bogie := Node3D.new()
		bogie.position = Vector3(axle_offset, 0.75, 0.0)
		parent.add_child(bogie)
		var bogie_mesh := BoxMesh.new()
		bogie_mesh.size = Vector3(3.2, 0.35, 2.0)
		bogie_mesh.material = _material(Color(0.12, 0.13, 0.14), 0.82)
		_add_box(bogie, "BogieFrame", bogie_mesh, Vector3.ZERO)
		for side in [-1.0, 1.0]:
			var wheel := MeshInstance3D.new()
			wheel.name = "Wheel"
			var wheel_mesh := CylinderMesh.new()
			wheel_mesh.top_radius = 0.48
			wheel_mesh.bottom_radius = 0.48
			wheel_mesh.height = 0.24
			wheel_mesh.material = _material(Color(0.08, 0.09, 0.1), 0.84, 0.12)
			wheel.mesh = wheel_mesh
			wheel.position = Vector3(0.0, -0.28, side * 1.08)
			wheel.rotation.x = PI / 2.0
			bogie.add_child(wheel)
			_wheels.append(wheel)


func _add_headlight(parent: Node3D, x: float, y: float, z: float) -> void:
	var lamp := SphereMesh.new()
	lamp.radius = 0.18
	lamp.height = 0.36
	lamp.material = _material(Color(1.0, 0.83, 0.38), 0.2, 0.0)
	_add_box(parent, "Headlight", lamp, Vector3(x, y, z))


func _add_box(parent: Node3D, node_name: String, mesh: Mesh, position: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)


func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result
