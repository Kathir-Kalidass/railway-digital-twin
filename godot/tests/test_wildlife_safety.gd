extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame

	var behavior := scene.get_node("WorldWildlife/WildlifeBehaviour") as Node
	var safety := scene.get_node_or_null("WorldWildlife/WildlifeSafety") as Node
	var crossing := scene.get_node_or_null("WorldWildlife/LevelCrossing") as Node3D
	var train := scene.get_node("Train") as LTSTrain
	a.ok(safety != null, "wildlife safety controller is wired")
	a.ok(crossing != null, "level crossing is present")
	a.ok(behavior.has_method("get_active_animals"), "wildlife exposes active animals")
	a.ok(behavior.has_method("get_hazard_snapshot"), "wildlife exposes a hazard snapshot")
	if safety == null or crossing == null or not behavior.has_method("get_hazard_snapshot"):
		scene.queue_free()
		await process_frame
		quit(a.report("test_wildlife_safety"))
		return

	behavior.set("auto_crossing_enabled", false)
	behavior.call("trigger_crossing", "deer")
	await process_frame

	var animals: Array = behavior.call("get_active_animals")
	var initial_count: int = animals.size()
	a.eq(initial_count, 1, "manual crossing spawns one animal")
	if not animals.is_empty():
		var animal := animals[0] as Area3D
		a.ok(animal.visible, "animal is visible")
		a.ok(animal.global_position.y > -1.0, "animal walks on the surface, not under the terrain")

		var point: Vector3 = crossing.call("get_crossing_point")
		animal.global_position = Vector3(point.x, 0.0, point.z)
		safety.call("refresh")
		a.eq(str(safety.call("get_state")), "STOP", "animal on track is a stop hazard")
		a.ok(train.get_target_speed_kmh() <= 0.01, "on-track animal forces the local target to zero")
		a.ok(bool(crossing.call("is_alarm_active")), "crossing alarm activates")
		crossing.call("_process", 1.0)
		a.ok(bool(crossing.call("is_barrier_down")), "crossing barrier lowers")

		animal.global_position = point + Vector3(0.0, 0.0, 40.0)
		safety.call("refresh")
		a.eq(str(safety.call("get_state")), "CLEAR", "animal away from the track clears the hazard")
		a.ok(train.get_target_speed_kmh() > 0.0, "train target resumes after the animal clears")

		a.ok(safety.has_method("set_external_hazard"), "safety supports an external hazard input")
		if safety.has_method("set_external_hazard"):
			safety.call("set_external_hazard", true, "esp32", 2)
			safety.call("refresh")
			a.eq(str(safety.call("get_state")), "STOP", "external ESP32 hazard holds a stop")
			a.ok(train.get_target_speed_kmh() <= 0.01, "external hazard forces the local target to zero")
			a.ok(bool(crossing.call("is_alarm_active")), "external hazard activates the crossing alarm")

			safety.call("set_external_hazard", false)
			safety.call("refresh")
			a.eq(str(safety.call("get_state")), "CLEAR", "external hazard clear releases the stop")
			a.ok(train.get_target_speed_kmh() > 0.0, "train target resumes after external clear")

	behavior.set("auto_crossing_enabled", true)
	behavior.set("_delay_remaining", 0.0)
	behavior.set("_cooldown_remaining", 0.0)
	behavior.call("_physics_process", 0.05)
	a.ok(behavior.call("get_active_animals").size() > initial_count, "automatic wildlife crossings spawn animals")

	scene.queue_free()
	await process_frame
	quit(a.report("test_wildlife_safety"))
