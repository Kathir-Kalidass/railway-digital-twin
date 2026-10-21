extends SceneTree

## Run: xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 \
##        --path godot --resolution 1280x720 --rendering-method gl_compatibility \
##        --script res://tests/capture_double_track.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	for frame in 12:
		await process_frame
	var camera := Camera3D.new()
	camera.fov = 58.0
	camera.far = 2000.0
	scene.add_child(camera)
	camera.global_position = Vector3(0.0, 175.0, 95.0)
	camera.look_at(Vector3(0.0, 0.0, -120.0), Vector3.UP)
	camera.make_current()
	for frame in 3:
		await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/opencode/double_track_overview.png")
	quit()
