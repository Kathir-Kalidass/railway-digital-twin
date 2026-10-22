extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame

	var network_class := load("res://src/wildlife_sensor_network.gd")
	a.ok(network_class != null, "wildlife_sensor_network script loads")

	var network := scene.get_node_or_null("WorldWildlife/SensorHuts") as Node3D
	if network == null:
		# If not yet wired into the tscn, instantiate dynamically to test
		network = network_class.new()
		network.name = "SensorHuts"
		network.set("track_registry_path", scene.get_node("TrackRegistry").get_path())
		network.set("bridge_path", scene.get_node("MQTTBridge").get_path())
		scene.get_node("WorldWildlife").add_child(network)
		await process_frame

	a.ok(network != null, "SensorHuts network exists")

	# 1. Total huts must be 10 (5 UP, 5 DOWN)
	var huts: Array = network.call("get_huts")
	a.eq(huts.size(), 10, "exactly 10 sensor huts spawned (5 UP, 5 DOWN)")

	# 2. Check hut IDs: UP-S0..UP-S4, DOWN-S0..DOWN-S4
	var hut_ids := []
	for h in huts:
		var hut_node := h as Node3D
		hut_ids.append(str(hut_node.get("sensor_id")))
	a.ok(hut_ids.has("UP-S0") and hut_ids.has("UP-S4"), "contains UP-S0 and UP-S4")
	a.ok(hut_ids.has("DOWN-S0") and hut_ids.has("DOWN-S4"), "contains DOWN-S0 and DOWN-S4")

	# 3. Check visuals on hut UP-S2
	var s2 := network.call("get_hut", "UP-S2") as Node3D
	a.ok(s2 != null, "UP-S2 hut exists")
	if s2 != null:
		a.ok(s2.get_node_or_null("HutBody") != null, "hut has equipment body")
		a.ok(s2.get_node_or_null("Mast") != null, "hut has sensor mast")
		a.ok(s2.get_node_or_null("Lamp") != null, "hut has status lamp")

		# 4. Animal detection: place mock animal at UP-S2 position
		var mock_animal := Area3D.new()
		mock_animal.add_to_group("wildlife")
		mock_animal.set_meta("species", "deer")
		mock_animal.set_meta("track_distance_m", float(s2.get("boundary_distance_m")))
		mock_animal.position = s2.global_position + Vector3(0.0, 0.0, 10.0) # 10m away (well within 75m)
		scene.add_child(mock_animal)
		await process_frame

		network.call("scan_now")
		a.ok(bool(s2.call("is_detecting")), "UP-S2 detects animal within 75m")

		var obs: Dictionary = s2.call("get_last_observation")
		a.eq(str(obs.get("source")), "trackside", "observation source is trackside")
		a.eq(str(obs.get("sensorId")), "UP-S2", "observation sensorId matches")
		a.eq(str(obs.get("line")), "UP", "observation line matches")
		a.eq(bool(obs.get("wildlifeDetected")), true, "wildlifeDetected is true")
		a.eq(int(obs.get("count")), 1, "count is 1")

		# 5. Move animal far away (> 75m)
		mock_animal.position = s2.global_position + Vector3(0.0, 0.0, 200.0)
		await process_frame
		network.call("scan_now")
		a.ok(not bool(s2.call("is_detecting")), "UP-S2 clears when animal moves beyond 75m")

		var clear_obs: Dictionary = s2.call("get_last_observation")
		a.eq(bool(clear_obs.get("wildlifeDetected")), false, "clear observation has wildlifeDetected=false")
		a.eq(int(clear_obs.get("count")), 0, "clear observation count is 0")

		mock_animal.queue_free()

	var down_hut := network.call("get_hut", "DOWN-S0") as Node3D
	a.ok(down_hut != null, "DOWN-S0 exists")
	if down_hut != null:
		var down := scene.get_node("InnerTrack") as LTSTrack
		a.ok(absf(float(down_hut.get("line_length_m")) - down.length) < 0.01, "DOWN hut knows its line length")
		a.ok(absf(float(down_hut.call("physical_to_operational", 240.0)) - fposmod(down.length - 240.0, down.length)) < 0.01,
			"DOWN physical 240 maps to operational L-240")
		var down_animal := Area3D.new()
		down_animal.add_to_group("wildlife")
		down_animal.set_meta("species", "deer")
		down_animal.set_meta("track_distance_m", 240.0)
		down_animal.position = down_hut.global_position + Vector3(0.0, 0.0, 10.0)
		scene.add_child(down_animal)
		await process_frame
		network.call("scan_now")
		var down_obs: Dictionary = down_hut.call("get_last_observation")
		a.eq(str(down_obs.get("line")), "DOWN", "DOWN observation line is DOWN")
		a.ok(float(down_obs.get("distanceM", 0.0)) <= down.length, "DOWN distance is operational")
		down_animal.queue_free()

	scene.queue_free()
	await process_frame
	quit(a.report("test_sensor_huts"))
