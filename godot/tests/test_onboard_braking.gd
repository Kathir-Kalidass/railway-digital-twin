extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var braking := load("res://src/onboard_braking.gd")
	a.ok(braking != null, "onboard_braking script loads")

	# Test 1: Stopping distance at 0 km/h is exactly d_margin (25 m)
	var d0: float = braking.stopping_distance(0.0)
	a.ok(absf(d0 - 25.0) < 0.001, "stopping distance at 0 km/h is d_margin (25m)")

	# Test 2: Stopping distance at 36 km/h (10 m/s) with a=2.0, t=0.6, margin=25
	# v*t = 6, v^2/(2*a) = 25, margin = 25 -> total = 56m
	var d36: float = braking.stopping_distance(36.0, 2.0, 0.6, 25.0)
	a.ok(absf(d36 - 56.0) < 0.01, "stopping distance at 36 km/h is exactly 56m")

	# Test 3: Safe speed limit invertibility
	# At distance 56m, safe speed should be 36 km/h
	var v_safe: float = braking.safe_speed_limit(56.0, 2.0, 0.6, 25.0)
	a.ok(absf(v_safe - 36.0) < 0.05, "safe speed at 56m is 36 km/h")

	# Test 4: Distance within margin must yield 0 km/h
	var v_margin: float = braking.safe_speed_limit(20.0, 2.0, 0.6, 25.0)
	a.ok(absf(v_margin - 0.0) < 0.001, "distance <= d_margin forces 0 km/h limit")

	# Test 5: should_stop threshold check
	a.ok(braking.should_stop(50.0, 36.0, 2.0, 0.6, 25.0), "should stop when distance (50m) < d_stop (56m)")
	a.ok(not braking.should_stop(70.0, 36.0, 2.0, 0.6, 25.0), "should not stop when distance (70m) > d_stop (56m)")

	quit(a.report("test_onboard_braking"))
