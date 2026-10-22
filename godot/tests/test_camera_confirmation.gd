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

	var fleet := scene.get_node("FleetController") as FleetController
	fleet.apply_state({
		"trains": [
			{"id": "T1", "line": "UP", "block": "UP-B0", "offsetM": 40.0, "physicalM": 40.0, "travelSign": 1, "speedKmh": 30.0, "targetSpeedKmh": 30.0}
		],
		"blocks": [
			{"id": "UP-B0", "line": "UP", "index": 0, "zone": "zone1", "lengthM": 250.7964, "hazard": {"stage": "SUSPECTED", "sources": ["trackside"]}}
		]
	})
	var t1 := fleet.get_train("T1") as LTSTrain
	var cam := t1.get_node_or_null("CameraConfirmation") as CameraConfirmation
	a.ok(cam != null, "CameraConfirmation exists on T1")
	if cam == null:
		quit(a.report("test_camera_confirmation"))
		return
	cam.enabled = true
	a.ok(cam.should_capture(), "capture starts on a nearby SUSPECTED hazard")
	cam.upload_override = func(_url: String, _headers: PackedStringArray, body: PackedByteArray) -> Dictionary:
		a.ok(body.size() > 0, "upload contains JPEG bytes")
		return {"ok": true, "confirmed": false, "degraded": false, "stage": "SUSPECTED"}
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	var bytes := cam.encode_frame(image)
	a.ok(bytes.size() > 0, "frame encodes to JPEG bytes")
	var headers := cam.headers("evt-1", "UP-B0")
	a.ok(headers.has("X-Camera-Token: test-token"), "headers include the token")
	a.ok(headers.has("X-Train-Id: T1"), "headers include the train id")
	var result := cam.handle_response({"ok": true, "confirmed": true, "stage": "CONFIRMED"}, 200)
	a.ok(result.get("confirmed", false), "confirmation response is recorded")
	a.ok(cam.get_last_result().get("confirmed", false), "latest result is exposed to the HUD")

	fleet.apply_state({
		"trains": [
			{"id": "T1", "line": "UP", "block": "UP-B0", "offsetM": 40.0, "physicalM": 40.0, "travelSign": 1, "speedKmh": 30.0, "targetSpeedKmh": 30.0}
		],
		"blocks": [
			{"id": "UP-B0", "line": "UP", "index": 0, "zone": "zone1", "lengthM": 250.7964, "hazard": null},
			{"id": "UP-B1", "line": "UP", "index": 1, "zone": "zone2", "lengthM": 250.7964, "hazard": {"stage": "SUSPECTED", "sources": ["trackside"]}}
		]
	})
	a.ok(cam.should_capture(), "capture starts for a hazard in the block ahead")
	var target := cam._hazard_for_train()
	a.eq(str(target.get("blockId", "")), "UP-B1", "camera targets the hazard block, not the train block")

	scene.queue_free()
	await process_frame
	quit(a.report("test_camera_confirmation"))
