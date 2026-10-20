extends Node3D
class_name SafetySignals

@export var barrier_path: NodePath
@export var led_red_path: NodePath
@export var led_green_path: NodePath

func set_state(safe: bool) -> void:
	var b = get_node_or_null(barrier_path)
	if b and b.has_method("set_down"):
		b.set_down(not safe)
	var lr = get_node_or_null(led_red_path)
	var lg = get_node_or_null(led_green_path)
	if lr:
		lr.visible = not safe
	if lg:
		lg.visible = safe
