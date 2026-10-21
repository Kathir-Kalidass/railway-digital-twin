extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var train := scene.get_node("Train") as LTSTrain
	if FileAccess.file_exists("res://assets/models/lts/wagon_passenger.glb"):
		a.ok(train.uses_lts_models, "train uses the exported LTS wagon models")
		for index in 3:
			var carriage := train.get_child(index) as Node3D
			a.ok(carriage.get_node_or_null("LTSModel") != null, "carriage %d has an LTS model" % index)
		var bounds := _bounds(train.get_child(1) as Node3D)
		a.ok(bounds.size.x > 10.0, "passenger coach is full length")
		a.ok(bounds.size.y > 3.0, "passenger coach has body height")
	else:
		a.ok(not train.uses_lts_models, "train falls back without GLB assets")

	var spawner := scene.get_node("WorldWildlife/WildlifeSpawner") as WildlifeSpawner
	var deer := spawner.spawn("deer")
	a.ok(deer != null and deer.get_meta("model", "") == "lts", "deer uses the Blender GLB")
	a.ok(deer.get_node_or_null("AnimalModel") != null, "deer visual is attached")
	var visual := deer.get_node_or_null("AnimalModel")
	if visual:
		a.ok(visual.get_script() != null, "deer has the gait script")
		a.ok(visual.find_child("LegFL", true, false) != null, "deer has articulated legs")
		a.ok(visual.find_child("DeerBody", true, false) != null, "deer body mesh is joined")
	var elephant := spawner.spawn("elephant")
	a.ok(elephant.get_meta("model", "") == "lts", "elephant uses the Blender GLB")
	a.ok(elephant.get_node_or_null("AnimalModel") != null, "elephant visual is attached")
	if elephant.get_node_or_null("AnimalModel"):
		a.ok(elephant.get_node("AnimalModel").find_child("Trunk", true, false) != null, "elephant has a trunk")

	var scenery := scene.get_node_or_null("Scenery") as SceneryDirector
	a.ok(scenery != null, "scenery director is present")
	a.ok(scenery.get_child_count() > 80, "full-scale scenery is populated")
	a.ok(scenery.get_node_or_null("Ground") == null, "terrain remains under WorldWildlife")

	var terrain := scene.get_node("WorldWildlife/TerrainGenerator") as TerrainGenerator
	a.ok(terrain.get_node_or_null("Ground") != null, "terrain mesh generated")
	a.ok(terrain.height_at(0.0, 0.0) < 1.0, "terrain height query works")

	deer.queue_free()
	elephant.queue_free()
	scene.queue_free()
	await process_frame
	quit(a.report("test_real_assets"))


func _bounds(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for item in root.find_children("*", "MeshInstance3D", true, false):
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
