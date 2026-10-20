extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_minimal.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var scenario := scene.get_node("ScenarioDirector") as ScenarioDirector
	var director := scene.get_node("CameraDirector") as CameraDirector
	var atmosphere := scene.get_node("WorldWildlife/Atmosphere") as Atmosphere
	a.ok(scenario != null, "scenario director is part of the scene")

	scenario.cinematic_seconds = 0.2
	scenario.run_reel()
	await process_frame
	a.ok(scenario.running, "cinematic reel starts")
	a.eq(director.mode_name(), "drone", "reel switches to the drone camera")
	a.eq(atmosphere.time_of_day, 0.25, "reel sets dusk")

	await create_timer(0.5).timeout
	a.ok(not scenario.running, "reel finishes")
	a.eq(director.mode_name(), "follow", "reel restores the follow camera")
	a.eq(atmosphere.time_of_day, 0.75, "reel restores daylight")

	scene.queue_free()
	await process_frame
	quit(a.report("test_scenario_director"))
