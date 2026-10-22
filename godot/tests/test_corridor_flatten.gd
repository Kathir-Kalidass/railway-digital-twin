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

	for distance in [0.0, 125.0, 250.0, 344.2478, 438.4956, 626.9911, 751.2389, 876.9911, 1000.0, 1125.0]:
		var up_point: Vector3 = up.get_global_transform_at_distance(distance).origin
		a.ok(terrain.height_at(up_point.x, up_point.z) < 0.2,
			"corridor flattened under UP at %.0f m" % distance)
		var down_point: Vector3 = down.get_global_transform_at_distance(down.map_to_parallel(distance)).origin
		a.ok(terrain.height_at(down_point.x, down_point.z) < 0.2,
			"corridor flattened under DOWN at %.0f m" % distance)
		a.ok(terrain.is_flattened(up_point.x, up_point.z), "UP centre line is a flatten source at %.0f m" % distance)
		a.ok(terrain.is_flattened(down_point.x, down_point.z), "DOWN centre line is a flatten source at %.0f m" % distance)
		var mid_point := (up_point + down_point) * 0.5
		a.ok(terrain.is_flattened(mid_point.x, mid_point.z), "mid-corridor is flat at %.0f m" % distance)
		var outer_point: Vector3 = up.get_shifted_global_pos_at_distance(distance, 12.0)
		a.ok(not terrain.is_flattened(outer_point.x, outer_point.z),
			"corridor stops before 12 m outside the outer rail at %.0f m" % distance)

	var river_y := terrain.height_at(0.0, 0.0)
	a.ok(river_y < -2.0, "river channel is carved through the infield")

	var river := scene.get_node("WorldWildlife/TerrainGenerator/RiverWater") as MeshInstance3D
	a.ok(river != null and absf(river.global_position.z) < 0.01, "river water lies at z = 0")

	scene.queue_free()
	await process_frame
	quit(a.report("test_corridor_flatten"))
