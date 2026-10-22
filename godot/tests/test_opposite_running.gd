extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var fleet := scene.get_node("FleetController") as FleetController
	fleet.apply_state({
		"trains": [
			{"id": "T1", "line": "UP", "block": "UP-B0", "offsetM": 40.0, "physicalM": 40.0, "travelSign": 1, "speedKmh": 36.0, "targetSpeedKmh": 36.0},
			{"id": "T3", "line": "DOWN", "block": "DOWN-B0", "offsetM": 0.0, "physicalM": 0.0, "travelSign": -1, "speedKmh": 36.0, "targetSpeedKmh": 36.0}
		]
	})

	var t1 := fleet.get_train("T1") as LTSTrain
	var t3 := fleet.get_train("T3") as LTSTrain
	a.ok(t1 != null and t3 != null, "both trains exist")
	if t1 == null or t3 == null:
		quit(a.report("test_opposite_running"))
		return

	a.ok(absf(t1.travel_sign - 1.0) < 0.001, "T1 travels clockwise")
	a.ok(absf(t3.travel_sign + 1.0) < 0.001, "T3 travels anticlockwise")
	a.ok(absf(t3.get_track_position_m()) < 0.1, "T3 starts at DOWN physical 0")

	var t3_locomotive := t3.get_node("Locomotive") as Node3D
	var t3_forward := t3_locomotive.global_basis.x.normalized()
	a.ok(t3_forward.dot(Vector3.RIGHT) < -0.9, "T3 faces west at the south straight")

	var t3_p1 := t3.get_track_position_m()
	t3.call("_physics_process", 0.2)
	var t3_p2 := t3.get_track_position_m()
	a.ok(t3_p2 < t3_p1 or t3_p2 > t3._track.length - 5.0, "T3 moves anticlockwise")

	var t1_start := t1.get_track_position_m()
	t1.call("_physics_process", 0.2)
	a.ok(t1.get_track_position_m() > t1_start, "T1 moves clockwise")

	var camera := t3.get_forward_camera()
	a.ok(camera != null, "T3 has a forward camera")
	if camera:
		var to_camera := (camera.global_position - t3_locomotive.global_position).normalized()
		a.ok(to_camera.dot(t3_forward) > 0.5, "T3 camera faces the direction of travel")

	scene.queue_free()
	await process_frame
	quit(a.report("test_opposite_running"))
