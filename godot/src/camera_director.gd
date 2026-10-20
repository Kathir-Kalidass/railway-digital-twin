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


func cycle() -> void:
	if _cameras.is_empty():
		return
	index = (index + 1) % _cameras.size()
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
		_:
			return "camera-%d" % index


func _process(delta: float) -> void:
	if not is_instance_valid(_train):
		return
	var forward := -_train.global_basis.z
	var up := _train.global_basis.y
	_drone_angle += delta * 0.15

	if _cab and _cab.current:
		_cab.global_position = _train.global_position + up * 3.1
		_cab.look_at(_train.global_position + forward * 30.0 + up * 2.2, up)

	if _drone and _drone.current:
		var offset := Vector3(sin(_drone_angle), 0.0, cos(_drone_angle)) * drone_radius
		_drone.global_position = _train.global_position + offset + Vector3.UP * drone_height
		_drone.look_at(_train.global_position + up * 2.0, Vector3.UP)
