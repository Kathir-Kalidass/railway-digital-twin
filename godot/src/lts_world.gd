extends Node3D

@onready var track: LTSTrack = $Track
@onready var train: LTSTrain = $Train
@export var initial_target_speed_kmh := 54.0

var follow_camera: Camera3D

func _ready() -> void:
	train.set_target_speed_kmh(initial_target_speed_kmh)
	follow_camera = Camera3D.new()
	follow_camera.name = "FollowCamera"
	follow_camera.current = true
	add_child(follow_camera)
	_update_camera(1.0)


func _process(delta: float) -> void:
	_update_camera(clampf(delta * 4.0, 0.0, 1.0))


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		train.set_target_speed_kmh(train.get_target_speed_kmh() + 10.0)
	elif event.is_action_pressed("ui_down"):
		train.set_target_speed_kmh(train.get_target_speed_kmh() - 10.0)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		var wildlife_behaviour := get_node_or_null("WorldWildlife/WildlifeBehaviour") as WildlifeBehaviour
		if wildlife_behaviour:
			wildlife_behaviour.trigger_crossing("deer")


func _update_camera(weight: float) -> void:
	var track_info := track.get_track_info_at(train.get_track_position_m())
	var forward: Vector3 = track_info["forward"]
	var up: Vector3 = track_info["up"]
	var side: Vector3 = track_info["side"]
	var target_position: Vector3 = train.global_position - forward * 30.0 + up * 11.0 + side * 12.0
	follow_camera.global_position = follow_camera.global_position.lerp(target_position, weight)
	follow_camera.look_at(train.global_position + up * 2.0, up)
