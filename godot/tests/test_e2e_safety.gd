extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_minimal.tscn").instantiate()
	var bridge := scene.get_node("MQTTBridge") as MQTTBridge
	bridge.connect_on_ready = false
	root.add_child(scene)
	await process_frame

	var train := scene.get_node("Train") as LTSTrain
	var reconciler := scene.get_node("TrainReconciler") as TrainReconciler
	a.ok(is_instance_valid(reconciler), "reconciler is wired in the demo scene")

	# Hazard path: a backend wildlife command followed by a RED aspect. The
	# signal is emitted on the bridge so the reconciler's own handler is used.
	bridge.message_received.emit("railway/commands/zone1", {"event": "WILDLIFE_DETECTED"})
	bridge.message_received.emit("railway/zone1/signal", {"signal": "RED"})
	a.ok(is_equal_approx(train.get_target_speed_kmh(), 0.0), "hazard stops the train")

	# Clear path: wildlife cleared and the signal returns to GREEN.
	bridge.message_received.emit("railway/commands/zone1", {"event": "WILDLIFE_CLEARED"})
	bridge.message_received.emit("railway/zone1/signal", {"signal": "GREEN"})
	a.ok(train.get_target_speed_kmh() > 0.0, "clear resumes movement")

	scene.queue_free()
	await process_frame
	quit(a.report("test_e2e_safety"))
