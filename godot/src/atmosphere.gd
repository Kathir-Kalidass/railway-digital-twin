extends Node
class_name Atmosphere

@export var env_path: NodePath
@export var sun_path: NodePath
@export_range(0.0, 1.0, 0.01) var time_of_day := 0.7


func _ready() -> void:
	apply()


func toggle() -> void:
	time_of_day = 0.15 if time_of_day >= 0.5 else 0.75
	apply()


func set_daynight(t: float) -> void:
	time_of_day = clampf(t, 0.0, 1.0)
	apply()


func apply() -> void:
	var world_environment := get_node_or_null(env_path) as WorldEnvironment
	if world_environment == null:
		world_environment = get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if world_environment and world_environment.environment:
		var environment := world_environment.environment
		environment.ambient_light_energy = lerpf(0.12, 0.24, time_of_day)
		environment.fog_light_color = Color(0.04, 0.06, 0.10).lerp(Color(0.58, 0.68, 0.78), time_of_day)
		environment.background_energy_multiplier = lerpf(0.15, 0.72, time_of_day)

	var sun := get_node_or_null(sun_path) as DirectionalLight3D
	if sun == null:
		sun = get_tree().root.find_child("Sunlight", true, false) as DirectionalLight3D
	if sun:
		sun.light_energy = lerpf(0.10, 1.12, time_of_day)
		sun.light_color = Color(0.55, 0.66, 0.95).lerp(Color(1.0, 0.96, 0.9), time_of_day)
