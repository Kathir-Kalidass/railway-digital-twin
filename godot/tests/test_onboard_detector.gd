extends SceneTree


class MockTerrain:
	var peak_x: float = 0.0
	var peak_z: float = -50.0
	var peak_h: float = 15.0

	func height_at(x: float, z: float) -> float:
		var d := Vector2(x - peak_x, z - peak_z).length()
		return maxf(0.0, peak_h - d * 0.5)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var detector_class := load("res://src/simulated_animal_detector.gd")
	a.ok(detector_class != null, "simulated_animal_detector script loads")

	var detector: Node = detector_class.new()
	detector.set("train_id", "T1")
	detector.set("line", "UP")

	# Camera at (0, 2, 0), looking down -Z axis
	# Basis: X right, Y up, -Z forward
	var cam_trans := Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0))

	# 1. Animal directly ahead at 40m (0, 1.5, -40)
	var snap1 := {
		"camera_transform": cam_trans,
		"speed_kmh": 36.0,
		"animals": [
			{ "position": Vector3(0.0, 1.5, -40.0), "species": "deer" }
		]
	}
	var res1: Array = detector.call("detect", snap1)
	a.eq(res1.size(), 1, "animal directly ahead is detected")
	if not res1.is_empty():
		var det: Dictionary = res1[0]
		a.eq(det.get("species"), "deer", "detected species matches")
		# confidence = (1 - 40/180) * 0.9 = (140/180) * 0.9 = 0.70
		var conf: float = det.get("confidence", 0.0)
		a.ok(conf >= 0.69 and conf <= 0.71, "confidence calculation is accurate (~0.70)")
		a.ok(absf(float(det.get("distance_m", 0.0)) - 40.0) < 0.1, "distance is ~40m")

	# 2. Animal behind camera at (0, 1.5, +30)
	var snap_behind := {
		"camera_transform": cam_trans,
		"speed_kmh": 36.0,
		"animals": [
			{ "position": Vector3(0.0, 1.5, 30.0), "species": "deer" }
		]
	}
	var res_behind: Array = detector.call("detect", snap_behind)
	a.eq(res_behind.size(), 0, "animal behind camera is ignored")

	# 3. Animal outside horizontal cone (cone is +-25 deg)
	# At 50m ahead, 35 deg lateral is tan(35)*50 = 35m
	var snap_wide := {
		"camera_transform": cam_trans,
		"speed_kmh": 36.0,
		"animals": [
			{ "position": Vector3(35.0, 1.5, -50.0), "species": "deer" }
		]
	}
	var res_wide: Array = detector.call("detect", snap_wide)
	a.eq(res_wide.size(), 0, "animal outside horizontal cone is ignored")

	# 4. Animal beyond range (200m > 180m range)
	var snap_far := {
		"camera_transform": cam_trans,
		"speed_kmh": 36.0,
		"animals": [
			{ "position": Vector3(0.0, 1.5, -200.0), "species": "deer" }
		]
	}
	var res_far: Array = detector.call("detect", snap_far)
	a.eq(res_far.size(), 0, "animal beyond 180m range is ignored")

	# 5. Occlusion test: terrain hill between camera and animal
	var mock_terrain := MockTerrain.new()
	var snap_terrain := {
		"camera_transform": cam_trans,
		"speed_kmh": 36.0,
		"terrain": mock_terrain,
		"animals": [
			{ "position": Vector3(0.0, 1.5, -100.0), "species": "deer" }
		]
	}
	var res_terrain: Array = detector.call("detect", snap_terrain)
	a.eq(res_terrain.size(), 0, "terrain hill occludes animal")

	# 6. Occlusion test: tree trunk between camera and animal
	var tree_node := Node3D.new()
	tree_node.position = Vector3(0.2, 0.0, -30.0)
	var snap_tree := {
		"camera_transform": cam_trans,
		"speed_kmh": 36.0,
		"trees": [tree_node],
		"animals": [
			{ "position": Vector3(0.0, 1.5, -60.0), "species": "deer" }
		]
	}
	var res_tree: Array = detector.call("detect", snap_tree)
	a.eq(res_tree.size(), 0, "tree trunk occludes animal")

	# 7. Bridge AABB occlusion test
	var snap_bridge := {
		"camera_transform": cam_trans,
		"speed_kmh": 36.0,
		"bridge_aabbs": [AABB(Vector3(-5.0, -1.0, -45.0), Vector3(10.0, 6.0, 10.0))],
		"animals": [
			{ "position": Vector3(0.0, 1.5, -80.0), "species": "deer" }
		]
	}
	var res_bridge: Array = detector.call("detect", snap_bridge)
	a.eq(res_bridge.size(), 0, "bridge structure occludes animal")

	# 8. Immediate local stop test with MQTT disconnected (Safety Principle 2)
	var reconciler := TrainReconciler.new()
	detector.set("reconciler", reconciler)
	# Critical detection (animal at 30m with speed 36kmh where d_stop is 56m)
	var snap_crit := {
		"camera_transform": cam_trans,
		"speed_kmh": 36.0,
		"animals": [
			{ "position": Vector3(0.0, 1.5, -30.0), "species": "deer" }
		]
	}
	detector.call("process_detections", snap_crit, 0.1)
	a.ok(reconciler.is_local_wildlife_active(), "critical detection immediately activates local stop")
	a.eq(reconciler.get_local_wildlife_limit(), 0.0, "local wildlife limit forced to 0 km/h with no MQTT")

	detector.queue_free()
	reconciler.queue_free()
	tree_node.queue_free()

	quit(a.report("test_onboard_detector"))
