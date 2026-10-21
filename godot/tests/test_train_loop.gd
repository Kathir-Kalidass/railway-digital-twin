extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame

	var track := scene.get_node("Track") as LTSTrack
	var train := scene.get_node("Train") as LTSTrain
	var start := track.get_global_transform_at_distance(0.0).origin
	var end := track.get_global_transform_at_distance(track.length).origin
	a.ok(track.length > 600.0, "track is extended into a full loop")
	a.ok(start.distance_to(end) < 0.1, "track start and end meet at the loop seam")

	train.set_target_speed_kmh(36.0)
	train.set("_track_position_m", track.length - 0.5)
	train.set("_speed_mps", 10.0)
	train.call("_physics_process", 0.2)

	var wrapped := train.get_track_position_m()
	a.ok(wrapped >= 0.0 and wrapped < 5.0, "train wraps past the end instead of stopping")
	a.ok(train.get_target_speed_kmh() > 30.0, "loop seam does not cancel the target speed")

	for index in 3:
		var carriage := train.get_child(index) as Node3D
		var expected := fposmod(wrapped - index * 18.0, track.length)
		var expected_origin := track.get_global_transform_at_distance(expected).origin
		a.ok(carriage.global_position.distance_to(expected_origin) < 0.25,
			"carriage %d wraps with the locomotive" % index)

	scene.queue_free()
	await process_frame
	quit(a.report("test_train_loop"))
