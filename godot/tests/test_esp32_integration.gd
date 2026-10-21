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

	var integration := scene.get_node_or_null("ESP32Integration") as Node
	var behavior := scene.get_node("WorldWildlife/WildlifeBehaviour") as Node
	var safety := scene.get_node("WorldWildlife/WildlifeSafety") as Node
	var crossing := scene.get_node("WorldWildlife/LevelCrossing") as Node3D
	var train := scene.get_node("Train") as LTSTrain
	a.ok(integration != null, "ESP32 integration is wired in the demo scene")
	if integration == null:
		scene.queue_free()
		await process_frame
		quit(a.report("test_esp32_integration"))
		return

	behavior.set("auto_crossing_enabled", false)
	bridge.message_received.emit("railway/telemetry/esp32", {
		"event": "DEVICE_TELEMETRY",
		"zone": "zone1",
		"source": "esp32",
		"payload": {"device": "esp32", "sensorHealthy": true, "wildlifeDetected": true},
	})
	await physics_frame
	a.eq(str(safety.call("get_state")), "STOP", "ESP32 wildlife detection stops the animation")
	a.ok(train.get_target_speed_kmh() <= 0.01, "ESP32 detection stops the train")
	a.ok(behavior.call("get_active_animals").size() == 1, "ESP32 detection spawns one visible animal")
	a.ok(bool(crossing.call("is_alarm_active")), "ESP32 detection lowers the barriers")

	bridge.message_received.emit("railway/telemetry/esp32", {
		"event": "DEVICE_TELEMETRY",
		"zone": "zone1",
		"source": "esp32",
		"payload": {"device": "esp32", "sensorHealthy": true, "wildlifeDetected": false},
	})
	await physics_frame
	a.eq(str(safety.call("get_state")), "CLEAR", "ESP32 wildlife clear releases the animation hazard")
	a.ok(not bool(integration.call("is_external_active")), "ESP32 integration tracks the cleared state")

	scene.queue_free()
	await process_frame
	quit(a.report("test_esp32_integration"))
