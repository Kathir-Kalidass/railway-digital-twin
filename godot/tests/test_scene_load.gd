extends SceneTree

func _initialize() -> void:
	var a := Assert.new()
	var packed: PackedScene = load("res://scenes/lts_full.tscn")
	a.ok(packed != null, "minimal LTS scene loads")
	if packed == null:
		quit(a.report("test_scene_load"))
		return

	var world := packed.instantiate()
	world.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(world)
	await process_frame

	var train: LTSTrain = world.get_node("Train")
	var track: LTSTrack = world.get_node("Track")
	a.ok(track.get_track_info_at(100.0)["position"] != Vector3.ZERO, "LTS rail geometry returns a track position")
	a.ok(world.get_node("Track/Rails").multimesh.instance_count > 100, "procedural rail mesh is built")
	a.ok(world.get_node_or_null("FollowCamera") is Camera3D, "follow camera is present")
	a.ok(world.get_node("WorldEnvironment").environment.ambient_light_energy > 0.0, "world has visible ambient lighting")
	var locomotive := train.get_node("Locomotive") as Node3D
	var camera := world.get_node("FollowCamera") as Camera3D
	var camera_to_train := (locomotive.global_position - camera.global_position).normalized()
	a.ok((-camera.global_basis.z).dot(camera_to_train) > 0.99, "follow camera is aimed at the locomotive")
	a.ok(world.get_node("TrainReconciler") is TrainReconciler, "safety controller is part of the LTS scene")
	a.ok(world.get_node("WorldWildlife/WildlifePublisher") is WildlifePublisher, "wildlife publisher is part of the LTS scene")
	var detection_band := world.get_node("WorldWildlife/DetectionBand") as DetectionBand
	a.ok(detection_band.get_child_count() > 0, "wildlife detector has a trigger volume")
	a.ok(world.get_node("WorldWildlife/WildlifeUnderpass") is WildlifeUnderpass, "wildlife underpass is part of the scene")
	var bridge := world.get_node("WorldWildlife/Bridge") as Bridge
	a.ok(bridge.get_child_count() > 0, "bridge builds an LTS model or procedural fallback")
	a.ok(train.get_node("Locomotive") != null, "locomotive model is built")
	a.ok(train.get_node("PassengerCoach1") != null and train.get_node("PassengerCoach2") != null, "two passenger coaches are built")

	var initial_position := train.get_track_position_m()
	train.set_target_speed_kmh(36.0)
	await create_timer(1.5).timeout
	a.ok(train.get_speed_kmh() > 0.0, "train accelerates toward its target speed")
	a.ok(train.get_track_position_m() > initial_position, "train advances along the curved LTS rail")

	var speed_before_braking := train.get_speed_kmh()
	train.set_target_speed_kmh(0.0)
	await create_timer(1.0).timeout
	a.ok(train.get_speed_kmh() < speed_before_braking, "train brakes when target speed drops to zero")
	world.queue_free()
	await process_frame
	quit(a.report("test_scene_load"))
