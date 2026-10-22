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
	a.ok(hud != null, "HUD exists in scene")

	if hud:
		hud.apply_state({
			"meets": {
				"enabled": true,
				"seed": 20261022,
				"phase": "HOLDING",
				"nextMeetInSec": 0,
				"active": {
					"holderId": "T3",
					"otherId": "T1",
					"crossover": true,
					"routeId": "X-DOWN-UP"
				}
			}
		})
		var metrics := (hud.get("_metrics") as Label).text
		a.ok(metrics.contains("MEET"), "HUD shows meet phase")
		a.ok(metrics.contains("T3"), "HUD shows the holding train")
		a.ok(metrics.contains("X-DOWN-UP"), "HUD shows the crossover route")

		hud.apply_state({
			"meets": {
				"enabled": true,
				"seed": 20261022,
				"phase": "IDLE",
				"nextMeetInSec": 42.0,
				"active": null
			}
		})
		metrics = (hud.get("_metrics") as Label).text
		a.ok(metrics.contains("meet in 42s"), "HUD counts down to the next meet")

		hud.apply_state({})
		a.ok(true, "HUD tolerates a snapshot without meets")

	scene.queue_free()
	await process_frame
	quit(a.report("test_meet_hud"))
