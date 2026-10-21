extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame

	var registry := scene.get_node_or_null("TrackRegistry") as TrackRegistry
	a.ok(registry != null, "track registry is part of the scene")
	var up: LTSTrack = registry.track("UP") if registry else null
	var down: LTSTrack = registry.track("DOWN") if registry else null
	a.ok(up != null, "UP resolves to the outer track")
	a.ok(down != null, "DOWN resolves to the inner track")
	if down:
		a.ok(absf(down.radius - 116.0) < 0.001, "inner radius is 116 m")
		a.ok(absf(down.length - 728.8495) < 0.01, "inner length is the inner circumference")
		a.ok(absf(down.global_position.z + 4.0) < 0.01, "inner loop starts 4 m inside")
		a.ok(down.get_node_or_null("Rails") != null, "inner track builds rail visuals")
	if registry:
		a.eq(registry.line_ids(), PackedStringArray(["UP", "DOWN"]), "registry reports both lines")
		a.ok(absf(registry.length_m("UP") - 753.9822) < 0.01, "UP length exposed")
		a.ok(registry.first() == scene.get_node("Track"), "first() returns UP")

	for distance in [0.0, 188.4956, 376.9911, 565.4867]:
		var up_pose: Transform3D = up.get_global_transform_at_distance(distance)
		var down_pose: Transform3D = down.get_global_transform_at_distance(distance * 116.0 / 120.0)
		a.ok(absf(up_pose.origin.distance_to(down_pose.origin) - 4.0) < 0.05,
			"4 m spacing at UP %.1f m" % distance)

	scene.queue_free()
	await process_frame
	quit(a.report("test_track_registry"))
