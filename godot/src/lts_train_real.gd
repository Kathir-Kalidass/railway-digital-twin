extends Node3D
class_name LTSTrainReal

@export var track_path: NodePath
@export var initial_position_m := 0.0
@export var max_accel := 0.8
@export var brake_accel := 1.2

var _track: Node3D
var _speed_mps := 0.0
var _target_speed_mps := 0.0
var _position_m := 0.0
var _follow_cam: Camera3D

func _ready() -> void:
	_track = get_node_or_null(track_path)
	_position_m = initial_position_m
	_follow_cam = get_node_or_null("../FollowCamera")
	build()

func build() -> void:
	var loco := load("res://Trains/JFR1/JFR1_Red.tscn")
	if loco:
		var l = loco.instantiate()
		l.scale = Vector3(1, 1, 1)
		add_child(l)
	var wag1 := load("res://Trains/JFR1/JFR1_Grey.tscn")
	if wag1:
		var w1 = wag1.instantiate()
		w1.transform.origin = Vector3(0, 0, -18)
		add_child(w1)
	var wag2 := load("res://Trains/JFR1/JFR1_Grey.tscn")
	if wag2:
		var w2 = wag2.instantiate()
		w2.transform.origin = Vector3(0, 0, -36)
		add_child(w2)

func set_target_speed_kmh(v: float) -> void:
	_target_speed_mps = clamp(v, 0.0, 100.0) / 3.6

func get_speed_kmh() -> float:
	return _speed_mps * 3.6

func get_track_position_m() -> float:
	return _position_m

func _physics_process(delta: float) -> void:
	if _speed_mps < _target_speed_mps:
		_speed_mps = min(_target_speed_mps, _speed_mps + max_accel * delta)
	elif _speed_mps > _target_speed_mps:
		_speed_mps = max(_target_speed_mps, _speed_mps - brake_accel * delta)
	_position_m += _speed_mps * delta
	var pos := Vector3(0, 0, 0)
	var dir := Vector3(1, 0, 0)
	if _track and _track.has_method("get_track_info_at"):
		var info = _track.get_track_info_at(_position_m)
		pos = info.get("position", pos)
		dir = info.get("forward", dir)
	global_transform.origin = pos + Vector3(0, 1.2, 0)
	look_at(pos + dir * 2.0 + Vector3(0, 1.2, 0))
	if _follow_cam:
		_follow_cam.global_transform.origin = global_transform.origin + dir * -12.0 + Vector3(0, 4.0, 0)
		_follow_cam.look_at(global_transform.origin + Vector3(0, 2.0, 0))
