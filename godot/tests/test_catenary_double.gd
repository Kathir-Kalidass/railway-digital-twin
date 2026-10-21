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
	var down := scene.get_node("InnerTrack") as LTSTrack
	var up := scene.get_node("Track") as LTSTrack

	for node_name in ["CatenaryWiresUP", "CatenaryWiresDOWN"]:
		var wires := scenery.get_node_or_null(node_name) as MeshInstance3D
		a.ok(wires != null, "%s exists" % node_name)
		if wires:
			a.ok(wires.mesh != null and wires.mesh.get_surface_count() >= 1, "%s has wire geometry" % node_name)

	var down_wires := scenery.get_node_or_null("CatenaryWiresDOWN") as MeshInstance3D
	if down_wires:
		for distance in [60.0, 300.0, 600.0]:
			var target: Vector3 = down.get_global_transform_at_distance(distance).origin + Vector3(0.0, 5.55, 0.0)
			a.ok(_mesh_has_vertex_near(down_wires.mesh, target, 0.35),
				"DOWN catenary passes above the track at %.0f m" % distance)

	for tree in scenery.tree_roots():
		var position: Vector3 = tree.global_position
		var direction := 0.0
		while direction <= up.length:
			var up_sample := up.get_global_transform_at_distance(direction).origin
			a.ok(Vector2(position.x - up_sample.x, position.z - up_sample.z).length() > 5.0,
				"no tree within 5 m of the UP centre line")
			var down_sample := down.get_global_transform_at_distance(direction * down.length / up.length).origin
			a.ok(Vector2(position.x - down_sample.x, position.z - down_sample.z).length() > 5.0,
				"no tree within 5 m of the DOWN centre line")
			direction += 8.0

	scene.queue_free()
	await process_frame
	quit(a.report("test_catenary_double"))


func _mesh_has_vertex_near(mesh: Mesh, target: Vector3, tolerance: float) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		if vertex.distance_to(target) < tolerance:
			return true
	return false
