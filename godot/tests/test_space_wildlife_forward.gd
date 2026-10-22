extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	var bridge := scene.get_node("MQTTBridge") as MQTTBridge
	bridge.connect_on_ready = false
	root.add_child(scene)
	await process_frame
	await process_frame

	var world := scene
	var fleet := scene.get_node("FleetController") as FleetController
	var behaviour := scene.get_node("WorldWildlife/WildlifeBehaviour") as WildlifeBehaviour
	var safety := scene.get_node("WorldWildlife/WildlifeSafety") as WildlifeSafety
	var director := scene.get_node("WorldWildlife/WildlifeDirector") as WildlifeDirector
	var track := scene.get_node("Track") as LTSTrack
	var down_track := scene.get_node("InnerTrack") as LTSTrack

	director.enabled = false
	behaviour.auto_crossing_enabled = false
	fleet.apply_state({"trains": [
		{"id": "T1", "line": "UP", "block": "UP-B0", "offsetM": 40.0, "physicalM": 40.0, "travelSign": 1, "speedKmh": 54.0, "targetSpeedKmh": 54.0},
		{"id": "T3", "line": "DOWN", "block": "DOWN-B0", "offsetM": 200.0, "physicalM": 200.0, "travelSign": -1, "speedKmh": 54.0, "targetSpeedKmh": 54.0}
	]})
	await process_frame
	var t1 := fleet.get_train("T1") as LTSTrain
	var t3 := fleet.get_train("T3") as LTSTrain
	a.ok(t1 != null and t3 != null, "both trains exist")

	var animal: Area3D = behaviour.trigger_crossing_at("UP", 260.0, "deer")
	_place_on_track(animal, track, 260.0)
	safety.refresh()
	a.ok(t1.get_target_speed_kmh() > 40.0, "far animal on own line does not stop T1")
	a.ok(t3.get_target_speed_kmh() > 40.0, "animal on UP does not stop DOWN train T3")

	_place_on_track(animal, track, 60.0)
	safety.refresh()
	a.ok(t1.get_target_speed_kmh() <= 0.01, "animal in T1 forward path stops T1")
	a.ok(t3.get_target_speed_kmh() > 40.0, "T1 forward-path stop does not affect T3")
	var held_position := t1.get_track_position_m()
	await create_timer(0.5).timeout
	a.ok(absf(t1.get_track_position_m() - held_position) < 1.0, "remote train holds position at a local stop")

	_place_on_track(animal, track, 20.0)
	safety.refresh()
	a.ok(t1.get_target_speed_kmh() > 40.0, "animal behind T1 is not a forward hazard")
	a.ok(t3.get_target_speed_kmh() > 40.0, "animal behind T1 does not affect T3")

	_place_on_track(animal, track, 1000.0)
	safety.refresh()
	world.set_target_train(t1)
	a.ok(world.has_method("spawn_wildlife_ahead"), "Space handler exposes a forward spawn")
	if world.has_method("spawn_wildlife_ahead"):
		var before := behaviour.get_active_animals().size()
		world.call("spawn_wildlife_ahead")
		var animals: Array = behaviour.get_active_animals()
		a.eq(animals.size(), before + 1, "Space spawns one animal")
		if not animals.is_empty():
			var spawned := animals[animals.size() - 1] as Area3D
			a.eq(str(spawned.get_meta("line", "")), "UP", "Space spawns on the selected train's line")
			var forward := fposmod(float(spawned.get_meta("track_distance_m", 0.0)) - t1.get_track_position_m(), track.length)
			a.ok(forward > 50.0 and forward < 180.0, "Space spawns ahead of the selected train")

	world.set_target_train(t3)
	if world.has_method("spawn_wildlife_ahead"):
		world.call("spawn_wildlife_ahead")
		var animals: Array = behaviour.get_active_animals()
		if not animals.is_empty():
			var spawned := animals[animals.size() - 1] as Area3D
			a.eq(str(spawned.get_meta("line", "")), "DOWN", "Space follows the selected DOWN train")
			var forward := fposmod((float(spawned.get_meta("track_distance_m", 0.0)) - t3.get_track_position_m()) * t3.travel_sign, down_track.length)
			a.ok(forward > 50.0 and forward < 180.0, "Space spawns ahead in the selected train's travel direction")

	scene.queue_free()
	await process_frame
	quit(a.report("test_space_wildlife_forward"))


func _place_on_track(animal: Area3D, track: LTSTrack, distance_m: float) -> void:
	var pose := track.get_global_transform_at_distance(distance_m)
	var point := Vector3(pose.origin.x, 0.0, pose.origin.z)
	animal.global_position = point
	animal.set_meta("track_distance_m", distance_m)
	animal.set_meta("crossing_point", point)
	animal.set_meta("target_position", point)
