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

	var hud := scene.get_node("HUD") as TwinHUD
	var director := scene.get_node("CameraDirector") as CameraDirector
	a.ok(hud != null, "HUD is part of the demo scene")

	hud.refresh()
	var status := (hud.get("_status") as Label).text
	var metrics := (hud.get("_metrics") as Label).text
	a.ok(status.contains("zone1"), "HUD shows the zone")
	a.ok(status.contains("GREEN"), "HUD shows the signal aspect")
	a.ok(status.contains("clear"), "HUD shows wildlife clear")
	a.ok(status.contains("MQTT offline"), "HUD shows link state")
	a.ok(metrics.contains("camera: follow"), "HUD shows camera mode")

	bridge.message_received.emit("railway/zone1/signal", {"signal": "RED"})
	hud.refresh()
	status = (hud.get("_status") as Label).text
	a.ok(status.contains("RED"), "HUD reflects a red signal")

	director.cycle()
	hud.refresh()
	metrics = (hud.get("_metrics") as Label).text
	a.ok(metrics.contains("camera: cab"), "HUD reflects the active camera")

	scene.queue_free()
	await process_frame
	quit(a.report("test_hud"))
