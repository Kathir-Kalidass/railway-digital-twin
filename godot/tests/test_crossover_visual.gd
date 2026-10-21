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

		# 2. Test train crossover transition on FleetController
		fleet.apply_state({
			"trains": [
				{
					"id": "T1",
					"line": "UP",
					"block": "UP-B2",
					"offsetM": 10.0,
					"speedKmh": 30.0,
					"targetSpeedKmh": 30.0
				}
			]
		})

		var t1 := fleet.get_train("T1")
		a.ok(t1 != null, "T1 initialized")
		var init_pos := t1.global_position

		# Request crossover transition from UP to DOWN
		fleet.transition_train_line("T1", "DOWN", 0.5)
		a.ok(fleet.is_train_crossing_over("T1"), "T1 is marked crossing over")
		a.ok(scenery.is_crossover_active("CrossoverA"), "CrossoverA blades active during transition")

		# Advance halfway through transition
		fleet._process(0.25)
		await process_frame
		var mid_pos := t1.global_position
		# Midpoint should be between the UP position and DOWN rail
		a.ok(mid_pos.distance_to(init_pos) > 0.2, "T1 smoothly shifts away from start")

		# Advance past transition end
		fleet._process(0.35)
		await process_frame
		a.ok(not fleet.is_train_crossing_over("T1"), "T1 finished crossover transition")
		a.eq(fleet.get_train_line("T1"), "DOWN", "T1 line is now DOWN")
		a.ok(not scenery.is_crossover_active("CrossoverA"), "CrossoverA blades returned to normal")

	scene.queue_free()
	await process_frame
	quit(a.report("test_crossover_visual"))
