extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := Assert.new()
	var director_class := load("res://src/wildlife_director.gd")
	a.ok(director_class != null, "wildlife_director script loads")

	var director: Node = director_class.new()
	director.set("seed_value", 20261022)

	# 1. Determinism test (Requirement 9):
	# Sequence of 3 events with seed 20261022
	director.call("reset_seed", 20261022)
	var seq1: Array = []
	for i in 3:
		var ev: Dictionary = director.call("trigger_proximity_event", "T1", "UP", 100.0 * i)
		seq1.append(ev)

	# Reset seed to 20261022 and repeat
	director.call("reset_seed", 20261022)
	var seq2: Array = []
	for i in 3:
		var ev: Dictionary = director.call("trigger_proximity_event", "T1", "UP", 100.0 * i)
		seq2.append(ev)

	a.eq(seq1.size(), seq2.size(), "event sequence length matches")
	for i in seq1.size():
		var e1: Dictionary = seq1[i]
		var e2: Dictionary = seq2[i]
		a.eq(e1.get("trainId"), e2.get("trainId"), "event %d trainId matches" % i)
		a.eq(e1.get("line"), e2.get("line"), "event %d line matches" % i)
		a.eq(e1.get("species"), e2.get("species"), "event %d species matches" % i)
		a.eq(e1.get("count"), e2.get("count"), "event %d count matches" % i)
		a.ok(absf(float(e1.get("distanceM", 0.0)) - float(e2.get("distanceM", 0.0))) < 0.001,
			"event %d distanceM matches exactly" % i)

	# 2. Distance range check: 80m <= lead <= 280m
	var first_ev: Dictionary = seq1[0]
	var lead_dist := float(first_ev.get("distanceM", 0.0)) - 0.0 # train was at 0m
	a.ok(lead_dist >= 80.0 and lead_dist <= 280.0, "spawn point is within 80-280m ahead (got %.1fm)" % lead_dist)

	# 3. Cooldown check: 30s <= cooldown <= 60s
	var cd: float = float(director.get("_cooldown_remaining"))
	a.ok(cd >= 30.0 and cd <= 60.0, "cooldown is within 30-60s (got %.1fs)" % cd)

	# 4. HUD integration check: verify twin_hud shows CAM clear
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	await process_frame

	var hud := scene.get_node_or_null("HUD") as TwinHUD
	a.ok(hud != null, "TwinHUD exists in scene")
	if hud != null:
		hud.refresh()
		var status_text: String = hud._status.text
		a.ok(status_text.contains("CAM clear") or status_text.contains("CAM detect"),
			"HUD status line contains CAM indicator (got: '%s')" % status_text)

	scene.queue_free()
	director.queue_free()
	await process_frame

	quit(a.report("test_wildlife_director"))
