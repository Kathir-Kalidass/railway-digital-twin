extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame

	var up := scene.get_node("Track") as LTSTrack
	var down := scene.get_node("InnerTrack") as LTSTrack
	a.ok(up != null and down != null, "both tracks exist")
	if up == null or down == null:
		quit(a.report("test_stadium_track"))
		return

	if not ("curve_radius_m" in up) or not up.has_method("map_to_parallel"):
		a.ok(false, "stadium sampler exports and map_to_parallel exist")
		scene.queue_free()
		quit(a.report("test_stadium_track"))
		return

	a.ok(absf(up.length - 1253.9822) < 0.01, "UP length is 2S + 2πR")
	a.ok(absf(down.length - 1228.8495) < 0.01, "DOWN length is 2S + 2πR")
	a.ok(absf(up.curve_radius_m - 120.0) < 0.001, "UP curve radius is 120 m")
	a.ok(absf(down.curve_radius_m - 116.0) < 0.001, "DOWN curve radius is 116 m")

	var up_points := {
		0.0: Vector3(-125.0, 0.0, 120.0),
		125.0: Vector3(0.0, 0.0, 120.0),
		250.0: Vector3(125.0, 0.0, 120.0),
		250.0 + PI * 120.0 * 0.5: Vector3(245.0, 0.0, 0.0),
		250.0 + PI * 120.0: Vector3(125.0, 0.0, -120.0),
		500.0 + PI * 120.0: Vector3(-125.0, 0.0, -120.0),
		500.0 + PI * 120.0 * 1.5: Vector3(-245.0, 0.0, 0.0),
	}
	for distance in up_points:
		var pose := up.get_global_transform_at_distance(distance)
		a.ok(pose.origin.distance_to(up_points[distance]) < 0.02,
			"UP pose at %.3f m is correct" % distance)

	a.ok(up.get_global_transform_at_distance(0.0).origin.distance_to(
		up.get_global_transform_at_distance(up.length).origin) < 0.02,
		"UP seam is continuous")
	a.ok(down.get_global_transform_at_distance(0.0).origin.distance_to(
		down.get_global_transform_at_distance(down.length).origin) < 0.02,
		"DOWN seam is continuous")

	for distance in [0.0, 125.0, 250.0, 344.2478, 438.4956, 626.9911, 751.2389, 876.9911, 1000.0]:
		var up_pose := up.get_global_transform_at_distance(distance)
		var down_pose := down.get_global_transform_at_distance(down.map_to_parallel(distance))
		a.ok(absf(up_pose.origin.distance_to(down_pose.origin) - 4.0) < 0.03,
			"parallel mapping keeps 4 m spacing at UP %.1f m" % distance)

	for distance in [0.0, 125.0, 250.0, 344.2478, 626.9911, 876.9911]:
		var round_trip: float = up.map_to_parallel(down.map_to_parallel(distance))
		a.ok(absf(round_trip - distance) < 0.02, "parallel mapping round-trips at %.1f m" % distance)

	var south_shifted := up.get_shifted_global_pos_at_distance(0.0, 12.0)
	a.ok(south_shifted.distance_to(Vector3(-125.0, 0.0, 132.0)) < 0.02,
		"positive shift is outside the UP rail on the south straight")

	scene.queue_free()
	await process_frame
	quit(a.report("test_stadium_track"))
