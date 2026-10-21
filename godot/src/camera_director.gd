extends Node
class_name CameraDirector

@export var train_path: NodePath
@export var follow_camera_path: NodePath
@export var drone_radius := 26.0
@export var drone_height := 16.0

var index := 0

var _train: Node3D
var _cameras: Array[Camera3D] = []
var _cab: Camera3D
var _drone: Camera3D
var _station: Camera3D
var _drone_angle := 0.0


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	_train = get_node_or_null(train_path)
	var follow := get_node_or_null(follow_camera_path) as Camera3D
	if follow:
		_cameras.append(follow)

	_cab = Camera3D.new()
	_cab.name = "CabCamera"
	_cab.fov = 74.0
	_cab.near = 0.1
	_cab.far = 1200.0
	_cab.current = false
	add_child(_cab)
	_cameras.append(_cab)

	_drone = Camera3D.new()
	_drone.name = "DroneCamera"
	_drone.fov = 58.0
	_drone.near = 0.5
	_drone.far = 2000.0
	_drone.current = false
	add_child(_drone)
	_cameras.append(_drone)

	_station = Camera3D.new()
	_station.name = "StationCamera"
	_station.fov = 58.0
	_station.near = 0.5
	_station.far = 2000.0
	_station.current = false
	_station.position = Vector3(0.0, 22.0, 28.0)
	add_child(_station)
	_station.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	_cameras.append(_station)


func set_target_train(train_node: Node3D) -> void:
	_train = train_node
	var world := get_parent()
	if world and world.has_method("set_target_train"):
		world.call("set_target_train", train_node)


func get_target_train() -> Node3D:
	if not is_instance_valid(_train):
		_train = get_node_or_null(train_path)
	return _train


func cycle() -> void:
	if _cameras.is_empty():
		return
	var tracking_modes := mini(3, _cameras.size())
	_activate((index + 1) % tracking_modes)


func set_mode(mode: String) -> void:
	var modes := ["follow", "cab", "drone", "station"]
	var wanted := modes.find(mode)
	if wanted >= 0 and wanted < _cameras.size():
		_activate(wanted)


func _activate(target: int) -> void:
	index = target
	for i in _cameras.size():
		_cameras[i].current = i == index


func current_camera() -> Camera3D:
	if _cameras.is_empty():
		return null
	return _cameras[index]


func mode_name() -> String:
	if _cameras.is_empty():
		return "none"
	match index:
		0:
			return "follow"
		1:
			return "cab"
		2:
			return "drone"
		3:
			return "station"
		_:
			return "camera-%d" % index


func _front_carriage() -> Node3D:
	if not is_instance_valid(_train):
		return null
	if _train.get_child_count() > 0:
		return _train.get_child(0) as Node3D
	return _train as Node3D


func _process(delta: float) -> void:
	var carriage := _front_carriage()
	if carriage == null:
		return
	var forward := carriage.global_basis.x.normalized()
	var up := carriage.global_basis.y.normalized()
	var center := carriage.global_position
	_drone_angle += delta * 0.15

	if _cab and _cab.current:
		_cab.global_position = center + forward * 9.6 + up * 2.6
		_cab.look_at(center + forward * 80.0 + up * 1.9, up)

	if _drone and _drone.current:
		var offset := Vector3(sin(_drone_angle), 0.0, cos(_drone_angle)) * drone_radius
		_drone.global_position = center + offset + Vector3.UP * drone_height
		_drone.look_at(center + up * 2.0, Vector3.UP)
