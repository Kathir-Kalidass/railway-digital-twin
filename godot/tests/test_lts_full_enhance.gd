extends SceneTree

func _initialize() -> void:
	var a := Assert.new()
	var packed: PackedScene = load("res://scenes/lts_full.tscn")
	a.ok(packed != null, "lts_full loads")
	var world := packed.instantiate()
	world.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(world)
	await process_frame
	a.ok(world.get_node("Track/Rails").multimesh.instance_count > 50, "rails built")
	a.ok(world.get_node_or_null("FollowCamera") is Camera3D, "follow cam")
	a.ok(world.get_node("Train").get_track_position_m() >= 0, "train positioned")
	a.ok(world.get_node("WorldWildlife/WildlifeUnderpass") != null, "underpass")
	a.ok(world.get_node("WorldWildlife/DetectionBand") != null, "detector")
	world.queue_free()
	await process_frame
	quit(a.report("test_lts_full_enhance"))
