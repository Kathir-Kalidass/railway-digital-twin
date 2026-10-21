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

	for module in 5:
		var d_up: float = scenery.station_distance + module * scenery.station_module_spacing
		var up_pose: Transform3D = up.get_global_transform_at_distance(d_up)
		var down_pose: Transform3D = down.get_global_transform_at_distance(d_up * down.length / up.length)
		var mid := (up_pose.origin + down_pose.origin) * 0.5
		a.ok(d_up > 301.5929 and d_up < 452.3893, "module %d is inside UP-B2" % module)
		var d_down: float = d_up * down.length / up.length
		a.ok(d_down > 291.5398 and d_down < 437.3097, "module %d is inside DOWN-B2" % module)

		var platform := scenery.get_node_or_null("Platform%d" % module) as Node3D
		a.ok(platform != null, "island platform module %d exists" % module)
		if platform == null:
			continue
		var box := _world_aabb(platform)
		var centre := box.get_center()
		a.ok(Vector2(centre.x - mid.x, centre.z - mid.z).length() < 0.8,
			"module %d is centred between the tracks" % module)
		for corner in 8:
			var point := box.get_endpoint(corner)
			var lateral := absf((point - mid).dot(up_pose.basis.z))
			a.ok(lateral <= 1.15, "module %d stays inside the 4 m gap" % module)

	scene.queue_free()
	await process_frame
	quit(a.report("test_station_island"))


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
