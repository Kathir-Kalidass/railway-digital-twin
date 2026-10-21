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
	var track := scene.get_node("Track") as LTSTrack
	var river_y := terrain.height_at(0.0, -120.0)
	var bank_y := terrain.height_at(0.0, -90.0)
	a.ok(river_y < -2.0, "river channel is carved below the water line")
	a.ok(bank_y > river_y + 1.5, "river banks rise above the channel")
	a.ok(terrain.get_node_or_null("RiverWater") is MeshInstance3D, "river has a visible water surface")

	var road_bridge := scene.get_node_or_null("WorldWildlife/Bridge") as Node3D
	a.ok(road_bridge != null, "road bridge is present")
	if road_bridge:
		a.ok(absf(road_bridge.global_position.z + 120.0) < 10.0, "road bridge spans the river")
		a.ok(road_bridge.find_children("*", "MeshInstance3D", true, false).size() > 2,
			"road bridge has deck, supports, and railings")

	var railway_a := scene.get_node_or_null("WorldWildlife/RailwayBridgeA") as Node3D
	var railway_b := scene.get_node_or_null("WorldWildlife/RailwayBridgeB") as Node3D
	a.ok(railway_a != null, "first railway bridge is present")
	a.ok(railway_b != null, "second railway bridge is present")
	if railway_a and railway_a.has_method("get_bridge_pose"):
		var pose_a: Transform3D = railway_a.call("get_bridge_pose")
		a.ok(absf(pose_a.origin.z + 120.0) < 10.0, "first railway bridge sits on the river crossing")
	if railway_b and railway_b.has_method("get_bridge_pose"):
		var pose_b: Transform3D = railway_b.call("get_bridge_pose")
		a.ok(absf(pose_b.origin.z + 120.0) < 10.0, "second railway bridge sits on the river crossing")

	var crossing := scene.get_node_or_null("WorldWildlife/LevelCrossing") as Node3D
	a.ok(crossing != null, "level crossing is present")
	if crossing and crossing.has_method("get_crossing_point"):
		var crossing_point: Vector3 = crossing.call("get_crossing_point")
		var track_point := track.get_global_transform_at_distance(float(crossing.get("distance_m"))).origin
		a.ok(crossing_point.distance_to(track_point) < 1.0, "level crossing is aligned to the track")

	var down := scene.get_node("InnerTrack") as LTSTrack
	for bridge in [railway_a, railway_b]:
		if bridge == null:
			continue
		var fraction: float = bridge.get("distance_fraction")
		var up_point: Vector3 = track.get_global_transform_at_distance(track.length * fraction).origin
		var down_point: Vector3 = down.get_global_transform_at_distance(down.length * fraction).origin
		var deck := bridge.get_node_or_null("Deck") as MeshInstance3D
		a.ok(deck != null, "bridge has a named deck")
		if deck:
			var deck_box := _world_aabb(deck)
			a.ok(deck_box.has_point(up_point + Vector3(0.0, -0.5, 0.0)), "deck supports the UP rails")
			a.ok(deck_box.has_point(down_point + Vector3(0.0, -0.5, 0.0)), "deck supports the DOWN rails")
			var deck_mesh := deck.mesh as BoxMesh
			a.ok(deck_mesh != null and deck_mesh.size.z > 10.0, "deck is wide enough for both tracks")
		for pier in bridge.find_children("Pier*", "MeshInstance3D", true, false):
			var pier_centre: Vector3 = (pier as MeshInstance3D).global_position
			a.ok(_horizontal_distance(pier_centre, track) > 1.25, "pier clears the UP centre line")
			a.ok(_horizontal_distance(pier_centre, down) > 1.25, "pier clears the DOWN centre line")

	scene.queue_free()
	await process_frame
	quit(a.report("test_river_bridges"))


func _horizontal_distance(point: Vector3, track: LTSTrack) -> float:
	var best := INF
	var distance := 0.0
	while distance <= track.length:
		var sample := track.get_global_transform_at_distance(distance).origin
		best = minf(best, Vector2(point.x - sample.x, point.z - sample.z).length())
		distance += 1.0
	return best


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
