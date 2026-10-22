extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _make_detector() -> Dictionary:
	var detector: Node = load("res://src/simulated_animal_detector.gd").new()
	var reconciler := TrainReconciler.new()
	detector.set("reconciler", reconciler)
	var published: Array[Dictionary] = []
	detector.set("publish_override", func(payload: Dictionary) -> void: published.append(payload))
	return {"detector": detector, "reconciler": reconciler, "published": published}


func _snap(speed: float = 36.0) -> Dictionary:
	return {
		"camera_transform": Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)),
		"speed_kmh": speed,
		"animals": [{"position": Vector3(0.0, 1.5, -30.0), "species": "deer"}],
	}


func _run() -> void:
	var a := Assert.new()
	var braking := load("res://src/onboard_braking.gd")
	a.ok(absf(braking.stopping_distance(80.0) - 161.79) < 0.05, "80 km/h stopping distance is 161.79 m")
	a.ok(braking.near_distance(80.0, 180.0) >= braking.stopping_distance(80.0), "near warning distance covers a full stop")
	a.ok(braking.near_distance(36.0, 180.0) >= braking.stopping_distance(36.0), "near distance never undercuts the stop distance")

	var fixture := _make_detector()
	var detector: Node = fixture.detector
	var reconciler: TrainReconciler = fixture.reconciler
	var published: Array = fixture.published
	a.eq(str(detector.get("source")), "onboard-camera", "ML detections identify as the onboard camera")

	detector.call("process_detections", _snap(), 0.1)
	a.eq(reconciler.get_local_wildlife_limit(), 30.0, "first detection warns at 30 km/h")
	a.ok(not bool(detector.call("is_confirmed")), "first detection never confirms")
	a.eq(published.size(), 1, "first detection publishes one near observation")
	if published.size() == 1:
		a.eq(bool(published[0].get("nearAnimal")), true, "near observation is flagged nearAnimal")
		a.eq(bool(published[0].get("confirmed")), false, "near observation is not confirmed")
		a.eq(bool(published[0].get("wildlifeDetected")), true, "near observation reports wildlife")

	detector.call("process_detections", _snap(), 0.1)
	a.eq(reconciler.get_local_wildlife_limit(), 0.0, "second consecutive detection stops")
	a.ok(bool(detector.call("is_confirmed")), "second detection confirms")
	a.eq(published.size(), 2, "confirmation publishes one observation")
	if published.size() == 2:
		a.eq(bool(published[1].get("confirmed")), true, "confirmed observation is flagged")
		a.eq(bool(published[1].get("nearAnimal")), true, "confirmed observation keeps the near flag")

	var before_duplicate := published.size()
	detector.call("process_detections", _snap(), 0.1)
	a.eq(published.size(), before_duplicate, "duplicate detections do not republish near or confirmed events")

	detector.call("process_detections", {"camera_transform": Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), "speed_kmh": 36.0, "animals": []}, 3.1)
	a.eq(reconciler.get_local_wildlife_limit(), -1.0, "clear restores the local limit")
	a.eq(published.size(), before_duplicate + 1, "clear publishes once")
	if published.size() > before_duplicate:
		a.eq(bool(published[-1].get("confirmed")), false, "clear is not a confirmation")
		a.eq(bool(published[-1].get("wildlifeDetected")), false, "clear reports no wildlife")

	var near_only := _make_detector()
	var near_detector: Node = near_only.detector
	var near_reconciler: TrainReconciler = near_only.reconciler
	var near_published: Array = near_only.published
	near_detector.call("process_detections", _snap(), 0.1)
	near_detector.call("process_detections", {"camera_transform": Transform3D(Basis.IDENTITY, Vector3(0.0, 2.0, 0.0)), "speed_kmh": 36.0, "animals": []}, 3.1)
	a.eq(near_published.size(), 2, "near then clear publish two observations")
	a.eq(near_reconciler.get_local_wildlife_limit(), -1.0, "near-only clear lifts the warning")
	for observation in near_published:
		a.eq(bool(observation.get("confirmed")), false, "near-only sequence never publishes confirmation")

	detector.queue_free()
	reconciler.queue_free()
	near_detector.queue_free()
	near_reconciler.queue_free()
	quit(a.report("test_near_animal_warning"))
