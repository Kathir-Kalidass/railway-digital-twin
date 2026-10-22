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

	var fleet := scene.get_node("FleetController") as FleetController
	var scenery := scene.get_node("Scenery") as SceneryDirector

	fleet.apply_state({
		"trains": [
			{"id": "T1", "line": "UP", "block": "UP-B0", "offsetM": 120.0, "physicalM": 120.0, "travelSign": 1, "speedKmh": 8.3, "targetSpeedKmh": 8.3},
			{"id": "T3", "line": "DOWN", "block": "DOWN-B3", "offsetM": 0.0, "physicalM": 320.0, "travelSign": -1, "speedKmh": 0.0, "targetSpeedKmh": 0.0}
		]
	})
	var t1 := fleet.get_train("T1") as LTSTrain
	var t3 := fleet.get_train("T3") as LTSTrain
	var carriage := t1.get_node_or_null("Locomotive") as Node3D if t1 else null
	var t3_carriage := t3.get_node_or_null("Locomotive") as Node3D if t3 else null
	a.ok(carriage != null, "T1 has a visible locomotive")
	a.ok(t3_carriage != null, "T3 is present and visible while T1 is routed")
	var up_pos := carriage.global_position if carriage else Vector3.ZERO

	fleet.apply_state({
		"trains": [
			{"id": "T1", "line": "DOWN", "block": "DOWN-B0", "offsetM": 120.0, "physicalM": 120.0, "travelSign": 1, "speedKmh": 8.3, "targetSpeedKmh": 8.3, "routePhase": "CROSS_ENTRY", "crossingProgress": 0.0, "crossoverId": "X-A", "targetLine": "DOWN"},
			{"id": "T3", "line": "DOWN", "block": "DOWN-B3", "offsetM": 0.0, "physicalM": 320.0, "travelSign": -1, "speedKmh": 0.0, "targetSpeedKmh": 0.0}
		],
		"routes": {"wrongLine": {"active": {"trainId": "T1", "phase": "CROSS_ENTRY", "entryCrossover": "X-A", "exitCrossover": "X-B", "progress": 0.2, "crossingProgress": 0.0, "heldTrainId": "T3"}}}
	})
	a.ok(fleet.is_train_crossing_over("T1"), "route entry starts a blend")
	a.ok(scenery.is_crossover_active("CrossoverA"), "entry blade is active")
	a.eq(fleet.get_train_line("T1"), "UP", "visual line stays on the source during the entry blend")
	a.ok(carriage.global_position.distance_to(up_pos) < 0.05, "route entry does not snap the consist")
	a.ok(t3_carriage != null and fleet.get_train_line("T3") == "DOWN", "T3 remains visible on DOWN")

	fleet.apply_state({
		"trains": [
			{"id": "T1", "line": "DOWN", "block": "DOWN-B0", "offsetM": 130.0, "physicalM": 130.0, "travelSign": 1, "speedKmh": 8.3, "targetSpeedKmh": 8.3, "routePhase": "CROSS_ENTRY", "crossingProgress": 0.5, "crossoverId": "X-A", "targetLine": "DOWN"},
			{"id": "T3", "line": "DOWN", "block": "DOWN-B3", "offsetM": 0.0, "physicalM": 320.0, "travelSign": -1, "speedKmh": 0.0, "targetSpeedKmh": 0.0}
		],
		"routes": {"wrongLine": {"active": {"trainId": "T1", "phase": "CROSS_ENTRY", "entryCrossover": "X-A", "exitCrossover": "X-B", "progress": 0.3, "crossingProgress": 0.5, "heldTrainId": "T3"}}}
	})
	fleet._process(0.25)
	var mid_shift := carriage.global_position.distance_to(up_pos) if carriage else 0.0
	a.ok(mid_shift > 0.2, "consist moves smoothly toward the destination track")
	a.ok(fleet.is_train_crossing_over("T1"), "crossover still in progress at midpoint")
	a.ok(scenery.is_crossover_active("CrossoverA"), "entry blade stays active through entry")

	fleet.apply_state({
		"trains": [
			{"id": "T1", "line": "DOWN", "block": "DOWN-B0", "offsetM": 140.0, "physicalM": 140.0, "travelSign": 1, "speedKmh": 8.3, "targetSpeedKmh": 8.3, "routePhase": "WRONG_LINE", "crossingProgress": 1.0},
			{"id": "T3", "line": "DOWN", "block": "DOWN-B3", "offsetM": 0.0, "physicalM": 320.0, "travelSign": -1, "speedKmh": 0.0, "targetSpeedKmh": 0.0}
		],
		"routes": {"wrongLine": {"active": {"trainId": "T1", "phase": "WRONG_LINE", "entryCrossover": "X-A", "exitCrossover": "X-B", "progress": 0.45, "crossingProgress": 1.0, "heldTrainId": "T3"}}}
	})
	a.ok(not fleet.is_train_crossing_over("T1"), "entry blend ends on WRONG_LINE")
	a.eq(fleet.get_train_line("T1"), "DOWN", "T1 is on DOWN during the wrong-line phase")
	a.ok(not scenery.is_crossover_active("CrossoverA"), "entry blade returns to normal")
	await process_frame
	a.ok(carriage.global_position.distance_to(up_pos) > mid_shift + 0.2, "consist settles onto the destination track")

	fleet.apply_state({
		"trains": [
			{"id": "T1", "line": "DOWN", "block": "DOWN-B3", "offsetM": 125.77, "physicalM": 220.0, "travelSign": 1, "speedKmh": 8.3, "targetSpeedKmh": 8.3, "routePhase": "CROSS_EXIT", "crossingProgress": 0.5, "crossoverId": "X-B", "targetLine": "UP"},
			{"id": "T3", "line": "DOWN", "block": "DOWN-B3", "offsetM": 0.0, "physicalM": 320.0, "travelSign": -1, "speedKmh": 0.0, "targetSpeedKmh": 0.0}
		],
		"routes": {"wrongLine": {"active": {"trainId": "T1", "phase": "CROSS_EXIT", "entryCrossover": "X-A", "exitCrossover": "X-B", "progress": 0.8, "crossingProgress": 0.5, "heldTrainId": "T3"}}}
	})
	a.ok(fleet.is_train_crossing_over("T1"), "exit starts a blend")
	a.ok(scenery.is_crossover_active("CrossoverB"), "exit blade is active")

	fleet.apply_state({
		"trains": [
			{"id": "T1", "line": "UP", "block": "UP-B0", "offsetM": 240.0, "physicalM": 240.0, "travelSign": 1, "speedKmh": 8.3, "targetSpeedKmh": 8.3, "routePhase": "CLEARANCE", "crossingProgress": 1.0},
			{"id": "T3", "line": "DOWN", "block": "DOWN-B3", "offsetM": 0.0, "physicalM": 320.0, "travelSign": -1, "speedKmh": 0.0, "targetSpeedKmh": 0.0}
		],
		"routes": {"wrongLine": {"active": {"trainId": "T1", "phase": "CLEARANCE", "entryCrossover": "X-A", "exitCrossover": "X-B", "progress": 0.95, "crossingProgress": 1.0, "heldTrainId": "T3"}}}
	})
	a.ok(not fleet.is_train_crossing_over("T1"), "exit blend ends on the original line")
	a.eq(fleet.get_train_line("T1"), "UP", "T1 is back on UP during clearance")
	a.ok(not scenery.is_crossover_active("CrossoverB"), "exit blade returns to normal")

	scene.queue_free()
	await process_frame
	quit(a.report("test_wrong_line_visual"))
