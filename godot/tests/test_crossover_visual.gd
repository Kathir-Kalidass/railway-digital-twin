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

	var scenery := scene.get_node_or_null("Scenery") as SceneryDirector
	var fleet := scene.get_node_or_null("FleetController") as FleetController

	a.ok(scenery != null, "SceneryDirector exists")
	a.ok(fleet != null, "FleetController exists")

	if scenery and fleet:
		# 1. Test switch blade animation on SceneryDirector
		a.ok(not scenery.is_crossover_active("CrossoverA"), "CrossoverA initially normal")
		scenery.set_crossover_active("CrossoverA", true)
		a.ok(scenery.is_crossover_active("CrossoverA"), "CrossoverA active/reversed")
		scenery.set_crossover_active("CrossoverA", false)
		a.ok(not scenery.is_crossover_active("CrossoverA"), "CrossoverA returns to normal")

		# 2. Backend-driven crossover animates the visible consist
		fleet.apply_state({
			"trains": [
				{
					"id": "T1",
					"line": "UP",
					"block": "UP-B2",
					"offsetM": 10.0,
					"speedKmh": 0.0,
					"targetSpeedKmh": 0.0
				}
			]
		})

		var t1 := fleet.get_train("T1")
		a.ok(t1 != null, "T1 initialized")
		var carriage := t1.get_node_or_null("Locomotive") as Node3D
		a.ok(carriage != null, "T1 has a visible locomotive")
		if carriage:
			var up_pos := carriage.global_position

			fleet.apply_state({
				"trains": [
					{
						"id": "T1",
						"line": "DOWN",
						"block": "DOWN-B2",
						"offsetM": 10.0,
						"speedKmh": 0.0,
						"targetSpeedKmh": 0.0
					}
				]
			})
			a.ok(fleet.is_train_crossing_over("T1"), "backend line change starts a visible crossover")
			a.eq(fleet.get_train_line("T1"), "UP", "visual line stays on the source during the crossover")
			a.ok(carriage.global_position.distance_to(up_pos) < 0.05, "backend line change does not snap the consist")
			a.ok(scenery.is_crossover_active("CrossoverA"), "CrossoverA blades active during backend crossover")

			fleet._process(fleet.crossover_duration_sec * 0.5)
			var mid_pos := carriage.global_position
			var mid_shift := mid_pos.distance_to(up_pos)
			a.ok(mid_shift > 0.2, "consist moves smoothly toward the target track")
			a.ok(fleet.is_train_crossing_over("T1"), "crossover still in progress at midpoint")

			fleet._process(fleet.crossover_duration_sec * 0.6)
			a.ok(not fleet.is_train_crossing_over("T1"), "backend crossover finished")
			a.eq(fleet.get_train_line("T1"), "DOWN", "T1 line is now DOWN")
			a.ok(not scenery.is_crossover_active("CrossoverA"), "CrossoverA blades returned to normal")
			a.ok(carriage.global_position.distance_to(up_pos) > mid_shift + 0.2, "consist continues across the track spacing")

		# 3. Manual transition also moves the visible consist
		var down_pos := carriage.global_position if carriage else Vector3.ZERO
		fleet.transition_train_line("T1", "UP", 0.4)
		a.ok(fleet.is_train_crossing_over("T1"), "T1 is marked crossing over")
		a.ok(scenery.is_crossover_active("CrossoverB"), "CrossoverB blades active during transition")

		fleet._process(0.2)
		if carriage:
			a.ok(carriage.global_position.distance_to(down_pos) > 0.2, "consist shifts back toward UP")

		fleet._process(0.25)
		a.ok(not fleet.is_train_crossing_over("T1"), "T1 finished crossover transition")
		a.eq(fleet.get_train_line("T1"), "UP", "T1 line is now UP")
		a.ok(not scenery.is_crossover_active("CrossoverB"), "CrossoverB blades returned to normal")

	scene.queue_free()
	await process_frame
	quit(a.report("test_crossover_visual"))
