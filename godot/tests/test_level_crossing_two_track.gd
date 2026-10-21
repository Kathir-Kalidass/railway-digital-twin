extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame

	var crossing := scene.get_node("WorldWildlife/LevelCrossing") as Node3D
	var up := scene.get_node("Track") as LTSTrack
	var down := scene.get_node("InnerTrack") as LTSTrack
	var points: Array = crossing.call("get_crossing_points")
	a.eq(points.size(), 2, "crossing reports both track points")

	var distance_m: float = crossing.get("distance_m")
	var up_point: Vector3 = up.get_global_transform_at_distance(distance_m).origin
	var down_point: Vector3 = down.get_global_transform_at_distance(distance_m * down.length / up.length).origin
	a.ok(points[0].distance_to(up_point) < 0.5, "first point is the UP crossing")
	a.ok(points[1].distance_to(down_point) < 0.5, "second point is the DOWN crossing")
	a.ok(Vector3(points[0].x, 0.0, points[0].z).distance_to(
		crossing.call("get_crossing_point")) < 0.01, "legacy get_crossing_point still returns UP")

	var pad := crossing.get_node_or_null("Pad") as MeshInstance3D
	a.ok(pad != null, "crossing has a named road pad")
	if pad:
		var pad_box := _world_aabb(pad)
		a.ok(pad_box.has_point(up_point + Vector3(0.0, -0.02, 0.0)), "pad covers the UP track")
		a.ok(pad_box.has_point(down_point + Vector3(0.0, -0.02, 0.0)), "pad covers the DOWN track")

	var pivots := crossing.find_children("BarrierPivot", "Node3D", true, false)
	a.ok(pivots.size() >= 2, "barrier sets frame both approach sides")
	crossing.call("set_alarm", true)
	crossing.call("_process", 1.0)
	a.ok(bool(crossing.call("is_barrier_down")), "alarm lowers the barriers")
	for pivot in pivots:
		a.ok(absf((pivot as Node3D).rotation.z) < 0.05, "every barrier lowers with the alarm")
		var local: Vector3 = crossing.to_local((pivot as Node3D).global_position)
		a.ok(local.z > 3.0 or local.z < -7.0, "barrier stand is clear of both tracks")

	scene.queue_free()
	await process_frame
	quit(a.report("test_level_crossing_two_track"))


func _world_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	var items: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D and not items.has(root):
		items.push_front(root)
	for item in items:
		var mesh_instance := item as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var box := mesh_instance.get_aabb()
		for index in 8:
			var point := mesh_instance.global_transform * box.get_endpoint(index)
			if not found:
				result = AABB(point, Vector3.ZERO)
				found = true
			else:
				result = result.expand(point)
	return result
