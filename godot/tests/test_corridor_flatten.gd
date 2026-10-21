extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame

	var terrain := scene.get_node("WorldWildlife/TerrainGenerator") as TerrainGenerator
	var up := scene.get_node("Track") as LTSTrack
	var down := scene.get_node("InnerTrack") as LTSTrack

	for distance in [0.0, 188.4956, 305.0, 376.9911, 500.0, 660.0]:
		var up_point: Vector3 = up.get_global_transform_at_distance(distance).origin
		a.ok(terrain.height_at(up_point.x, up_point.z) < 0.2,
			"corridor flattened under UP at %.0f m" % distance)
		var down_point: Vector3 = down.get_global_transform_at_distance(distance * 116.0 / 120.0).origin
		a.ok(terrain.height_at(down_point.x, down_point.z) < 0.2,
			"corridor flattened under DOWN at %.0f m" % distance)
		a.ok(terrain.is_flattened(up_point.x, up_point.z), "UP centre line is a flatten source at %.0f m" % distance)
		a.ok(terrain.is_flattened(down_point.x, down_point.z), "DOWN centre line is a flatten source at %.0f m" % distance)
		var mid_point := (up_point + down_point) * 0.5
		a.ok(terrain.is_flattened(mid_point.x, mid_point.z), "mid-corridor is flat at %.0f m" % distance)
		var outer_point: Vector3 = up.get_shifted_global_pos_at_distance(distance, 12.0)
		a.ok(not terrain.is_flattened(outer_point.x, outer_point.z),
			"corridor stops before 12 m outside the outer rail at %.0f m" % distance)

	var river_y := terrain.height_at(0.0, -120.0)
	a.ok(river_y < -2.0, "river channel is still carved")

	scene.queue_free()
	await process_frame
	quit(a.report("test_corridor_flatten"))
