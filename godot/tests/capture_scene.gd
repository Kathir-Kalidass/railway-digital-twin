extends SceneTree

## Developer screenshot helper (not part of the test glob).
## Run: xvfb-run -a godot --path godot --resolution 1280x720 \
##        --rendering-method gl_compatibility --script res://tests/capture_scene.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	for frame in 10:
		await process_frame
	var camera := scene.get_node_or_null("FollowCamera") as Camera3D
	if camera:
		camera.make_current()
	await _shot("/tmp/opencode/scene_follow.png")

	var scenario := scene.get_node_or_null("ScenarioDirector") as ScenarioDirector
	if scenario:
		scenario.run_reel()
		await create_timer(2.5).timeout
		await _shot("/tmp/opencode/scene_reel.png")
		await create_timer(6.0).timeout

	var director := scene.get_node_or_null("CameraDirector") as CameraDirector
	if director:
		director.set_mode("drone")
		for frame in 5:
			await process_frame
		await _shot("/tmp/opencode/scene_drone.png")
		director.set_mode("cab")
		for frame in 5:
			await process_frame
		await _shot("/tmp/opencode/scene_cab.png")
		director.set_mode("follow")
		var atmosphere := scene.get_node_or_null("WorldWildlife/Atmosphere") as Atmosphere
		if atmosphere:
			atmosphere.toggle()
			for frame in 12:
				await process_frame
			await _shot("/tmp/opencode/scene_night.png")
			atmosphere.set_daynight(0.75)
			for frame in 5:
				await process_frame
	var world := scene.get_node_or_null("World")
	if world:
		world.set_process(false)
	var train := scene.get_node_or_null("Train") as Node3D
	if train and camera:
		var locomotive := train.get_node_or_null("Locomotive") as Node3D
		var center := locomotive.global_position if locomotive else train.global_position
		camera.global_position = center + Vector3(0.0, 35.0, 0.0)
		camera.look_at(center, Vector3.FORWARD)
		camera.make_current()
		for frame in 3:
			await process_frame
		await _shot("/tmp/opencode/scene_overhead.png")

	var wildlife := scene.get_node_or_null("WorldWildlife/WildlifeBehaviour") as WildlifeBehaviour
	var crossing := scene.get_node_or_null("WorldWildlife/LevelCrossing") as Node3D
	if wildlife and crossing:
		wildlife.set("auto_crossing_enabled", false)
		wildlife.call("trigger_crossing", "deer")
		await create_timer(5.2).timeout
		var point: Vector3 = crossing.call("get_crossing_point")
		var wildlife_camera := Camera3D.new()
		wildlife_camera.fov = 55.0
		scene.add_child(wildlife_camera)
		wildlife_camera.global_position = point + crossing.global_basis.z * 15.0 + crossing.global_basis.x * 4.0 + Vector3(0.0, 4.5, 0.0)
		wildlife_camera.look_at(point + Vector3(0.0, 0.8, 0.0), Vector3.UP)
		wildlife_camera.make_current()
		for frame in 3:
			await process_frame
		await _shot("/tmp/opencode/scene_wildlife.png")
	quit()


func _shot(path: String) -> void:
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
