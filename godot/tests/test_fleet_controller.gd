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

	var fleet := scene.get_node_or_null("FleetController") as FleetController
	a.ok(fleet != null, "FleetController exists in lts_full scene")

	if fleet:
		# 1. Test track distance calculation
		var d_up_b0: float = fleet.calculate_track_distance("UP", "UP-B0", 40.0)
		a.ok(absf(d_up_b0 - 40.0) < 0.05, "UP-B0 offset 40m is 40m")

		var d_up_b1: float = fleet.calculate_track_distance("UP", "UP-B1", 10.0)
		var expected_up_b1: float = (753.9822 / 5.0) + 10.0
		a.ok(absf(d_up_b1 - expected_up_b1) < 0.1, "UP-B1 offset 10m maps to ~160.8m")

		var d_down_b2: float = fleet.calculate_track_distance("DOWN", "DOWN-B2", 0.0)
		var expected_down_b2: float = (728.8495 / 5.0) * 2.0
		a.ok(absf(d_down_b2 - expected_down_b2) < 0.1, "DOWN-B2 offset 0m maps to ~291.5m")

		# 2. Test applying state snapshot
		fleet.apply_state({
			"trains": [
				{
					"id": "T1",
					"line": "UP",
					"block": "UP-B0",
					"offsetM": 40.0,
					"speedKmh": 48.0,
					"targetSpeedKmh": 48.0,
					"lengthM": 60.0
				},
				{
					"id": "T3",
					"line": "DOWN",
					"block": "DOWN-B0",
					"offsetM": 20.0,
					"speedKmh": 45.0,
					"targetSpeedKmh": 45.0,
					"lengthM": 60.0
				}
			]
		})

		a.eq(fleet.train_count(), 2, "FleetController manages 2 trains")
		var t1: LTSTrain = fleet.get_train("T1")
		var t3: LTSTrain = fleet.get_train("T3")
		a.ok(t1 != null, "T1 exists")
		a.ok(t3 != null, "T3 exists")

		if t1 and t3:
			a.eq(fleet.get_train_line("T1"), "UP", "T1 is on UP line")
			a.eq(fleet.get_train_line("T3"), "DOWN", "T3 is on DOWN line")
			a.ok(absf(t1.get_track_position_m() - 40.0) < 1.0, "T1 initial track position ~40m")
			a.ok(absf(t3.get_track_position_m() - 20.0) < 1.0, "T3 initial track position ~20m")

		# 3. Simulate process frames to verify smooth movement without snapping
		var initial_t1_pos: float = t1.get_track_position_m() if t1 else 0.0
		for frame in 10:
			await process_frame
		var later_t1_pos: float = t1.get_track_position_m() if t1 else 0.0
		a.ok(later_t1_pos > initial_t1_pos, "T1 moves forward across frames")

		# 4. Test MQTT bridge railway/state message handling
		bridge.message_received.emit("railway/state", {
			"trains": [
				{
					"id": "T1",
					"line": "UP",
					"block": "UP-B1",
					"offsetM": 5.0,
					"speedKmh": 48.0,
					"targetSpeedKmh": 48.0
				},
				{
					"id": "T3",
					"line": "DOWN",
					"block": "DOWN-B1",
					"offsetM": 8.0,
					"speedKmh": 45.0,
					"targetSpeedKmh": 45.0
				}
			]
		})

		a.eq(fleet.get_train_block("T1"), "UP-B1", "T1 block updated to UP-B1")
		a.eq(fleet.get_train_block("T3"), "DOWN-B1", "T3 block updated to DOWN-B1")

	scene.queue_free()
	await process_frame
	quit(a.report("test_fleet_controller"))
