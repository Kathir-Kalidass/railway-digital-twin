extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	var bridge := scene.get_node("MQTTBridge") as MQTTBridge
	bridge.connect_on_ready = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var scenario := scene.get_node_or_null("ScenarioDirector") as ScenarioDirector
	var director := scene.get_node_or_null("CameraDirector") as CameraDirector
	var fleet := scene.get_node_or_null("FleetController") as FleetController

	a.ok(scenario != null, "ScenarioDirector exists")
	a.ok(director != null, "CameraDirector exists")
	a.ok(fleet != null, "FleetController exists")

	if scenario and director and fleet:
		# Test station camera mode
		director.set_mode("station")
		a.eq(director.mode_name(), "station", "Station camera mode active")
		var st_cam := director.current_camera()
		a.ok(st_cam != null and st_cam.current, "Station camera is active")

		# Initialize 2 trains
		fleet.apply_state({
			"trains": [
				{
					"id": "T1",
					"line": "UP",
					"block": "UP-B1",
					"offsetM": 140.0,
					"speedKmh": 40.0,
					"targetSpeedKmh": 40.0
				},
				{
					"id": "T3",
					"line": "DOWN",
					"block": "DOWN-B1",
					"offsetM": 135.0,
					"speedKmh": 40.0,
					"targetSpeedKmh": 40.0
				}
			]
		})

		# Run meet scenario with fast step duration
		scenario.run_meet_scenario(0.15)
		await process_frame
		a.ok(scenario.running, "Meet scenario is running")
		a.eq(director.mode_name(), "station", "Camera frames station during meet")

		# Wait for scenario steps to finish
		await create_timer(0.9).timeout
		a.ok(not scenario.running, "Meet scenario finished")
		a.eq(director.mode_name(), "follow", "Camera returned to follow mode")

	scene.queue_free()
	await process_frame
	quit(a.report("test_meet_scenario"))
