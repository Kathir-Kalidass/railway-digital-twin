class_name LTSTrain
extends Node3D

@export var track_path: NodePath = NodePath("../Track")
@export var initial_position_m := 40.0
@export var acceleration_mps2 := 0.45
@export var service_brake_mps2 := 0.7
@export var emergency_brake_mps2 := 1.1

var _target_speed_mps := 0.0
var _speed_mps := 0.0
var _track_position_m := 0.0
var _carriages: Array[Node3D] = []
var _wheels: Array[MeshInstance3D] = []
var _track: LTSTrack
var _lts_math: Node

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
	_lts_math = load("res://Data/Scripts/Singletons/Math.gd").new()
	_track = get_node_or_null(track_path) as LTSTrack
	if not is_instance_valid(_track):
		push_error("LTSTrain requires an LTSTrack at %s" % track_path)
		set_physics_process(false)
		return

	_track_position_m = clampf(initial_position_m, 0.0, _track.length)
	_build_train()
	_update_train_pose()


func _exit_tree() -> void:
	if is_instance_valid(_lts_math):
		_lts_math.free()


func _physics_process(delta: float) -> void:
	var target_speed := _target_speed_mps
	if _target_speed_mps < _speed_mps:
		var braking := emergency_brake_mps2 if _target_speed_mps == 0.0 else service_brake_mps2
		_speed_mps = move_toward(_speed_mps, target_speed, braking * delta)
	else:
		_speed_mps = move_toward(_speed_mps, target_speed, acceleration_mps2 * delta)

	_track_position_m += _speed_mps * delta
	if _track_position_m >= _track.length:
		_track_position_m = _track.length
		_target_speed_mps = 0.0

	_update_train_pose()
	var rotation_delta := (_speed_mps * delta) / 0.48
	for wheel in _wheels:
		wheel.rotate_object_local(Vector3.UP, rotation_delta)


func _update_train_pose() -> void:
	for index in _carriages.size():
		var carriage_distance := maxf(0.0, _track_position_m - index * 18.0)
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
		_build_carriage(carriage, colors[index], index == 0)


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
