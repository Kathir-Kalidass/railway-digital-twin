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

	var signal_director := scene.get_node_or_null("SignalDirector") as SignalDirector
	a.ok(signal_director != null, "SignalDirector exists in lts_full scene")

	if signal_director:
		var expected_blocks := [
			"UP-B0", "UP-B1", "UP-B2", "UP-B3", "UP-B4",
			"DOWN-B0", "DOWN-B1", "DOWN-B2", "DOWN-B3", "DOWN-B4"
		]
		for block_id in expected_blocks:
			var mast := signal_director.get_mast(block_id)
			a.ok(mast != null, "mast exists for %s" % block_id)
			if mast:
				a.eq(mast.block_id, block_id, "mast block_id matches %s" % block_id)
				a.ok(mast.get_aspect() != "", "mast has valid initial aspect")

		# Check mast placement
		var up_track := scene.get_node("Track") as LTSTrack
		var up_b0 := signal_director.get_mast("UP-B0")
		if up_b0 and up_track:
			var pose := up_track.get_global_transform_at_distance(0.0)
			a.ok(up_b0.global_position.distance_to(pose.origin) < 5.0,
				"UP-B0 mast is placed within 5m of block 0 boundary")

		# Test aspect switching
		signal_director.update_aspect("UP-B2", "RED")
		a.eq(signal_director.get_aspect("UP-B2"), "RED", "UP-B2 switches to RED")
		var mast_b2 := signal_director.get_mast("UP-B2")
		a.ok(mast_b2.is_lamp_active("RED"), "RED lamp is active on UP-B2")
		a.ok(not mast_b2.is_lamp_active("GREEN"), "GREEN lamp is off on UP-B2")

		signal_director.update_aspect("UP-B2", "YELLOW")
		a.eq(signal_director.get_aspect("UP-B2"), "YELLOW", "UP-B2 switches to YELLOW")
		a.ok(mast_b2.is_lamp_active("YELLOW"), "YELLOW lamp is active on UP-B2")
		a.ok(not mast_b2.is_lamp_active("RED"), "RED lamp is off on UP-B2")

		# Test MQTT bridge message handling
		bridge.message_received.emit("railway/signal/DOWN-B1", {"aspect": "YELLOW"})
		a.eq(signal_director.get_aspect("DOWN-B1"), "YELLOW", "DOWN-B1 reflects MQTT signal topic")

		bridge.message_received.emit("railway/state", {
			"blocks": [
				{"id": "UP-B3", "signal": "RED"}
			]
		})
		a.eq(signal_director.get_aspect("UP-B3"), "RED", "UP-B3 reflects state blocks snapshot")

	scene.queue_free()
	await process_frame
	quit(a.report("test_signal_masts"))
