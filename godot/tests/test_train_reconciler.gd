extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_minimal.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	var train := scene.get_node("Train") as LTSTrain
	var reconciler := scene.get_node("TrainReconciler") as TrainReconciler
	var subscriptions: Dictionary = scene.get_node("MQTTBridge").get("_subscriptions")
	a.ok(subscriptions.has("railway/zone1/signal"), "subscribes to the permitted zone signal topic")
	a.ok(subscriptions.has("railway/speed/zone1"), "subscribes to the permitted speed topic")
	a.ok(subscriptions.has("railway/commands/zone1"), "subscribes to the permitted command topic")
	a.ok(not subscriptions.has("railway/state"), "does not subscribe outside the Godot ACL")

	reconciler.call("_on_message", "railway/speed/zone1", {"speedKmh": 42.0})
	a.ok(is_equal_approx(train.get_target_speed_kmh(), 42.0), "uses backend speedKmh payload")
	reconciler.call("_on_message", "railway/zone1/signal", {"signal": "YELLOW"})
	a.ok(is_equal_approx(train.get_target_speed_kmh(), 30.0), "reduces speed for YELLOW signal")
	reconciler.call("_on_message", "railway/zone1/signal", {"signal": "RED"})
	a.ok(is_equal_approx(train.get_target_speed_kmh(), 0.0), "stops for RED signal")

	reconciler.call("_on_message", "railway/state", {
		"zones": {
			"zone1": {
				"signal": "GREEN",
				"targetSpeedKmh": 48.0,
				"wildlifeDetected": true,
				"sensorHealthy": true,
			},
		},
	})
	a.ok(is_equal_approx(train.get_target_speed_kmh(), 30.0), "reduces speed for active wildlife")
	reconciler.call("_on_message", "railway/state", {
		"zones": {
			"zone1": {
				"signal": "GREEN",
				"targetSpeedKmh": 48.0,
				"wildlifeDetected": false,
				"sensorHealthy": false,
			},
		},
	})
	a.ok(is_equal_approx(train.get_target_speed_kmh(), 0.0), "stops on sensor fault")
	reconciler.call("_on_message", "railway/state", {
		"zones": {
			"zone1": {
				"signal": "GREEN",
				"targetSpeedKmh": 48.0,
				"wildlifeDetected": false,
				"sensorHealthy": true,
			},
		},
	})
	a.ok(is_equal_approx(train.get_target_speed_kmh(), 48.0), "resumes to backend target after safe state")

	scene.queue_free()
	await process_frame
	quit(a.report("test_train_reconciler"))
