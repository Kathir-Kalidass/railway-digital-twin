extends Node
class_name Atmosphere

@export var env_path: NodePath
@export var time_of_day := 0.5

func set_daynight(t: float) -> void:
	time_of_day = clamp(t, 0.0, 1.0)
	var env_node = get_node_or_null(env_path)
	if env_node and env_node.environment:
		env_node.environment.ambient_light_energy = lerp(0.2, 1.0, time_of_day)
