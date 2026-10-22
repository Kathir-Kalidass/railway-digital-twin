extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame
	var hud := scene.get_node("HUD") as TwinHUD
	hud.apply_state({
		"routes": {"wrongLine": {"active": {"trainId": "T1", "phase": "WRONG_LINE", "entryCrossover": "X-A", "exitCrossover": "X-B", "progress": 0.42, "crossingProgress": 0.0, "heldTrainId": "T3"}}},
		"meets": {"enabled": false, "phase": "IDLE", "nextMeetInSec": 0}
	})
	hud.refresh()
	a.ok(hud._status.text.contains("WRONG-LINE"), "HUD shows wrong-line status")
	a.ok(hud._metrics.text.contains("T1") and hud._metrics.text.contains("42%"), "HUD shows route progress")
	a.ok(hud._metrics.text.contains("T3 HOLD"), "HUD shows the held train")

	scene.queue_free()
	await process_frame
	quit(a.report("test_wrong_line_hud"))
