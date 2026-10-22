extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var train := scene.get_node("Train") as Node3D
	var locomotive := train.get_child(0) as Node3D
	var director := scene.get_node("CameraDirector") as CameraDirector
	var follow := scene.get_node("FollowCamera") as Camera3D
	a.ok(director != null, "camera director is part of the scene")
	a.ok(follow.current, "follow camera starts active")
	a.eq(director.mode_name(), "follow", "starts in follow mode")

	director.cycle()
	await process_frame
	var cab := director.current_camera()
	a.eq(director.mode_name(), "cab", "cycles to the cab camera")
	a.ok(cab.current, "cab camera becomes active")
	a.ok(cab.global_position.distance_to(locomotive.global_position) < 12.0,
		"cab camera rides with the train")

	director.cycle()
	await process_frame
	await process_frame
	var drone := director.current_camera()
	a.eq(director.mode_name(), "drone", "cycles to the drone camera")
	a.ok(drone.current, "drone camera becomes active")
	a.ok(drone.global_position.distance_to(locomotive.global_position) > 10.0,
		"drone camera orbits away from the train")

	director.cycle()
	a.eq(director.mode_name(), "follow", "cycles back to follow")

	director.set_mode("station")
	await process_frame
	a.ok(director.current_camera().global_position.z > 40.0, "station camera looks at the south straight")

	var atmosphere := scene.get_node("WorldWildlife/Atmosphere") as Atmosphere
	var world_environment := scene.get_node("WorldEnvironment") as WorldEnvironment
	var environment: Environment = world_environment.environment
	var day_energy: float = environment.ambient_light_energy
	atmosphere.toggle()
	a.ok(not is_equal_approx(environment.ambient_light_energy, day_energy),
		"day/night toggle changes ambient light")
	a.eq(atmosphere.time_of_day, 0.15, "toggles to night")
	atmosphere.toggle()
	a.eq(atmosphere.time_of_day, 0.75, "toggles back to day")

	scene.queue_free()
	await process_frame
	quit(a.report("test_camera_director"))
