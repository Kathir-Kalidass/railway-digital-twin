extends Node3D
class_name EnvironmentEnhance

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.85, 0.9)
	env.fog_density = 0.001
	var wenv := WorldEnvironment.new()
	wenv.environment = env
	add_child(wenv)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.9)
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
