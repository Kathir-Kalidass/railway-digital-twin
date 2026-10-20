extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var bridge := MQTTBridge.new()
	bridge.name = "MQTTBridge"
	bridge.connect_on_ready = false
	bridge.reconnect_delay_base = 0.1
	bridge.reconnect_delay_max = 0.2
	root.add_child(bridge)

	a.ok(bridge.subscribe("railway/state"), "queues subscriptions before connecting")
	bridge.broker_url = "tcp://127.0.0.1:1"
	bridge.connect_broker()
	await create_timer(0.35).timeout
	a.ok(bridge.get("_reconnecting"), "schedules reconnect after connection failure")
	var reconnect_timer := bridge.get("_reconnect_timer") as Timer
	a.ok(is_instance_valid(reconnect_timer) and reconnect_timer.time_left > 0.0, "starts reconnect backoff timer")

	bridge.queue_free()
	await process_frame
	quit(a.report("test_mqtt_bridge"))
