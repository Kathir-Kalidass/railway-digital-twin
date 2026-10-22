extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame

	var train := scene.get_node("Train") as LTSTrain
	a.ok(train != null, "Train exists in lts_full")

	var cam := train.call("get_forward_camera") as Camera3D
	a.ok(cam != null, "lead carriage has ForwardCamera")

	var detector := train.call("get_detector") as SimulatedAnimalDetector
	a.ok(detector != null, "lead carriage has SimulatedAnimalDetector")

	# Acceptance test 8: Forward alignment on straight sections and curves
	var track := scene.get_node("Track") as LTSTrack
	a.ok(track != null, "track exists")

	if train != null and cam != null and track != null:
		var test_distances := [0.0, 100.0, 188.0, 370.0, 560.0]
		for dist in test_distances:
			train.set_track_position_m(dist)
			await process_frame
			var carriage: Node3D = train._carriages[0]
			var carriage_forward: Vector3 = carriage.global_transform.basis.x.normalized()
			var cam_forward: Vector3 = -cam.global_transform.basis.z.normalized()
			var alignment: float = carriage_forward.dot(cam_forward)
			a.ok(alignment > 0.98, "camera aligns with carriage forward at dist %.1fm (dot: %.4f)" % [dist, alignment])

	scene.queue_free()
	await process_frame
	quit(a.report("test_onboard_camera"))
