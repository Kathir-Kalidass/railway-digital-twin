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

	var safety := scene.get_node_or_null("WorldWildlife/WildlifeSafety") as WildlifeSafety
	var fleet := scene.get_node_or_null("FleetController") as FleetController

	a.ok(safety != null, "WildlifeSafety exists")
	a.ok(fleet != null, "FleetController exists")

	if safety and fleet:
		# Set up 2 active trains on UP and DOWN
		fleet.apply_state({
			"trains": [
				{
					"id": "T1",
					"line": "UP",
					"block": "UP-B0",
					"offsetM": 40.0,
					"speedKmh": 48.0,
					"targetSpeedKmh": 48.0
				},
				{
					"id": "T3",
					"line": "DOWN",
					"block": "DOWN-B0",
					"offsetM": 20.0,
					"speedKmh": 45.0,
					"targetSpeedKmh": 45.0
				}
			]
		})

		var t1: LTSTrain = fleet.get_train("T1")
		var t3: LTSTrain = fleet.get_train("T3")
		a.ok(t1 != null and t3 != null, "Both T1 and T3 are initialized")
		a.ok(t1.get_target_speed_kmh() >= 40.0, "T1 starts at operational speed")
		a.ok(t3.get_target_speed_kmh() >= 40.0, "T3 starts at operational speed")

		# Trigger hazard on crossing corridor
		safety.set_external_hazard(true, "deer", 1)
		safety.refresh()
		await process_frame

		a.eq(safety.get_state(), "STOP", "WildlifeSafety enters STOP state")
		a.ok(absf(t1.get_target_speed_kmh()) < 0.01, "T1 target clamped to 0 km/h")
		a.ok(absf(t3.get_target_speed_kmh()) < 0.01, "T3 target clamped to 0 km/h")

		# Clear hazard
		safety.set_external_hazard(false)
		safety.refresh()
		await process_frame

		a.eq(safety.get_state(), "CLEAR", "WildlifeSafety returns to CLEAR state")

	scene.queue_free()
	await process_frame
	quit(a.report("test_wildlife_dual_track"))
