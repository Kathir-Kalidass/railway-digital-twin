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

	var hud := scene.get_node_or_null("HUD") as TwinHUD
	var director := scene.get_node_or_null("CameraDirector") as CameraDirector
	var fleet := scene.get_node_or_null("FleetController") as FleetController

	a.ok(hud != null, "HUD exists in scene")
	a.ok(director != null, "CameraDirector exists in scene")
	a.ok(fleet != null, "FleetController exists in scene")

	if hud and director and fleet:
		# Apply 2-train fleet state
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
					"block": "DOWN-B2",
					"offsetM": 15.0,
					"speedKmh": 42.0,
					"targetSpeedKmh": 42.0
				}
			]
		})

		hud.refresh()
		a.eq(hud.get_selected_train_id(), "T1", "Initial selected train is T1")
		var t1: LTSTrain = fleet.get_train("T1")
		var t3: LTSTrain = fleet.get_train("T3")
		a.eq(director.get_target_train(), t1, "Director initially targets T1")

		var status_text: String = (hud.get("_status") as Label).text
		var metrics_text: String = (hud.get("_metrics") as Label).text
		a.ok(status_text.contains("zone1"), "Status contains zone1")
		a.ok(status_text.contains("GREEN"), "Status contains GREEN")
		a.ok(metrics_text.contains("T1"), "Metrics display T1")
		a.ok(metrics_text.contains("UP-B0"), "Metrics display UP-B0")

		# Cycle to next train (T3)
		hud.cycle_selected_train()
		hud.refresh()
		a.eq(hud.get_selected_train_id(), "T3", "Selected train switches to T3")
		a.eq(director.get_target_train(), t3, "Director targets T3")

		metrics_text = (hud.get("_metrics") as Label).text
		a.ok(metrics_text.contains("T3"), "Metrics display T3")
		a.ok(metrics_text.contains("DOWN-B2"), "Metrics display DOWN-B2")

		# Cycle again to wrap back to T1
		hud.cycle_selected_train()
		hud.refresh()
		a.eq(hud.get_selected_train_id(), "T1", "Selected train wraps back to T1")
		a.eq(director.get_target_train(), t1, "Director targets T1 again")

	scene.queue_free()
	await process_frame
	quit(a.report("test_fleet_hud"))
