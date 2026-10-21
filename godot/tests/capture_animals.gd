extends SceneTree

## Developer screenshot helper for the Blender animal models.
## Run: xvfb-run -a godot --path godot --resolution 1280x720 \
##        --rendering-method gl_compatibility --script res://tests/capture_animals.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	var sky := ProceduralSkyMaterial.new()
	sky.sky_top_color = Color(0.18, 0.36, 0.62)
	sky.sky_horizon_color = Color(0.58, 0.70, 0.82)
	sky.ground_bottom_color = Color(0.16, 0.20, 0.17)
	sky.ground_horizon_color = Color(0.55, 0.64, 0.70)
	environment.sky.sky_material = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.66, 0.82)
	environment.ambient_light_energy = 0.24
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.58, 0.68, 0.78)
	environment.fog_density = 0.0005
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	sun.light_energy = 1.1
	root.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.28, 0.12)
	ground.material_override = material
	root.add_child(ground)

	var deer: Node3D = load("res://assets/models/animals/deer.glb").instantiate()
	deer.position = Vector3(-2.0, 0.0, 0.0)
	deer.rotation.y = PI / 2.0
	root.add_child(deer)
	var elephant: Node3D = load("res://assets/models/animals/elephant.glb").instantiate()
	elephant.position = Vector3(2.5, 0.0, 0.0)
	elephant.rotation.y = PI / 2.0
	root.add_child(elephant)

	var camera := Camera3D.new()
	camera.position = Vector3(2.0, 5.0, -11.0)
	camera.fov = 46.0
	root.add_child(camera)
	camera.look_at(Vector3(0.5, 1.2, 0.0))
	camera.current = true

	for frame in 10:
		await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/opencode/animals_scene.png")
	quit()
