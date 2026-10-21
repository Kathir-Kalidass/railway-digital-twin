extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame

	var scenery := scene.get_node("Scenery") as SceneryDirector
	var up := scene.get_node("Track") as LTSTrack
	var down := scene.get_node("InnerTrack") as LTSTrack

	for entry in [["CrossoverA", scenery.crossover_a_up_distance], ["CrossoverB", scenery.crossover_b_up_distance]]:
		var node_name: String = entry[0]
		var d_up: float = entry[1]
		var d_down: float = d_up * down.length / up.length
		a.ok(d_up > 301.5929 and d_up < 452.3893, "%s is inside UP-B2" % node_name)
		a.ok(d_down > 291.5398 and d_down < 437.3097, "%s is inside DOWN-B2" % node_name)

		var node := scenery.get_node_or_null(node_name) as Node3D
		a.ok(node != null, "%s exists" % node_name)
		if node == null:
			continue
		a.ok(absf(float(node.get_meta("up_distance")) - d_up) < 0.001, "%s records its UP distance" % node_name)
		a.ok(absf(float(node.get_meta("down_distance")) - d_down) < 0.001, "%s records its DOWN distance" % node_name)

		var up_point: Vector3 = up.get_global_transform_at_distance(d_up).origin
		var down_point: Vector3 = down.get_global_transform_at_distance(d_down).origin
		var mid := (up_point + down_point) * 0.5
		a.ok(node.global_position.distance_to(mid) < 0.3, "%s is centred between the rails" % node_name)
		var up_end := node.to_global(Vector3(0.0, 0.0, 2.0))
		var down_end := node.to_global(Vector3(0.0, 0.0, -2.0))
		a.ok(up_end.distance_to(up_point) < 0.3, "%s starts on the UP centre line" % node_name)
		a.ok(down_end.distance_to(down_point) < 0.3, "%s ends on the DOWN centre line" % node_name)

		var blades := node.get_node_or_null("Blades") as Node3D
		a.ok(blades != null, "%s has switch blades" % node_name)
		if blades:
			a.ok(blades.find_children("*", "MeshInstance3D", true, false).size() >= 2,
				"%s has two switch blades" % node_name)

		var platform0 := scenery.get_node_or_null("Platform0") as Node3D
		if platform0:
			a.ok(node.global_position.distance_to(platform0.global_position) > 5.0,
				"%s clears the island platform" % node_name)

	scene.queue_free()
	await process_frame
	quit(a.report("test_station_crossovers"))
