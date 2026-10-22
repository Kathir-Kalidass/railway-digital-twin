extends SceneTree

## Run: xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 \
##        --path godot --resolution 1440x900 --rendering-method gl_compatibility \
##        --script res://tests/capture_crossover.gd
## Writes wrong_line_before/mid/after.png plus numbered frames under /tmp/opencode.

const ENTRY_FRAMES := 10
const RUN_FRAMES := 16
const EXIT_FRAMES := 10
const FRAME_COUNT := ENTRY_FRAMES + RUN_FRAMES + EXIT_FRAMES
const FRAME_STEP_SEC := 0.1

var _scene: Node3D
var _camera: Camera3D
var _fleet: FleetController


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = load("res://scenes/lts_full.tscn").instantiate()
	_scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(_scene)
	await process_frame
	await process_frame

	_fleet = _scene.get_node_or_null("FleetController") as FleetController
	_apply(120.0, null)
	for frame in 6:
		await process_frame
	_setup_camera()
	await _snapshot("wrong_line_before.png")

	for frame in FRAME_COUNT:
		var t := float(frame) / float(FRAME_COUNT - 1)
		var phase := "CROSS_ENTRY"
		var crossing := 0.0
		var physical := 120.0
		var route_progress := 0.2
		if frame < ENTRY_FRAMES:
			crossing = float(frame) / float(ENTRY_FRAMES - 1)
			physical = 120.0 + 20.0 * crossing
			route_progress = 0.2 + 0.1 * crossing
		elif frame < ENTRY_FRAMES + RUN_FRAMES:
			phase = "WRONG_LINE"
			crossing = 1.0
			var run_frac := float(frame - ENTRY_FRAMES) / float(RUN_FRAMES - 1)
			physical = 140.0 + 80.0 * run_frac
			route_progress = 0.3 + 0.4 * run_frac
		else:
			phase = "CROSS_EXIT"
			var exit_frac := float(frame - ENTRY_FRAMES - RUN_FRAMES) / float(EXIT_FRAMES - 1)
			crossing = exit_frac
			physical = 220.0 + 20.0 * exit_frac
			route_progress = 0.7 + 0.1 * exit_frac

		_apply(physical, {
			"trainId": "T1",
			"phase": phase,
			"entryCrossover": "X-A",
			"exitCrossover": "X-B",
			"progress": route_progress,
			"crossingProgress": crossing,
			"heldTrainId": "T3",
			"holdPhysicalM": 320.0,
			"elapsedSec": t * FRAME_COUNT * FRAME_STEP_SEC,
		})
		await create_timer(FRAME_STEP_SEC).timeout
		await _snapshot("wrong_line_frame_%02d.png" % frame)
		if frame == ENTRY_FRAMES + RUN_FRAMES / 2 - 1:
			await _snapshot("wrong_line_midway.png")

	_apply(242.0, {
		"trainId": "T1",
		"phase": "CLEARANCE",
		"entryCrossover": "X-A",
		"exitCrossover": "X-B",
		"progress": 0.95,
		"crossingProgress": 1.0,
		"heldTrainId": "T3",
		"holdPhysicalM": 320.0,
	})
	await create_timer(FRAME_STEP_SEC).timeout
	await _snapshot("wrong_line_after.png")
	quit()


func _apply(t1_physical: float, wrong_line: Variant) -> void:
	if not _fleet:
		return
	var t1_down := t1_physical >= 140.0 and t1_physical < 240.0
	var route_phase := ""
	var crossing := 0.0
	var crossover_id := ""
	var target_line := ""
	if wrong_line is Dictionary:
		route_phase = str(wrong_line.get("phase", ""))
		crossing = float(wrong_line.get("crossingProgress", 0.0))
		if route_phase == "CROSS_ENTRY":
			crossover_id = "X-A"
			target_line = "DOWN"
			t1_down = false
		elif route_phase == "CROSS_EXIT":
			crossover_id = "X-B"
			target_line = "UP"
			t1_down = true
	var t1 := {
		"id": "T1",
		"line": "DOWN" if t1_down else "UP",
		"block": "DOWN-B3" if t1_physical >= 220.0 else ("DOWN-B0" if t1_down else "UP-B0"),
		"offsetM": t1_physical - (737.3097 if t1_physical >= 220.0 else 0.0),
		"physicalM": t1_physical,
		"travelSign": 1.0,
		"speedKmh": 8.3,
		"targetSpeedKmh": 8.3,
	}
	if not route_phase.is_empty():
		t1["routePhase"] = route_phase
		t1["crossingProgress"] = crossing
		t1["crossoverId"] = crossover_id
		t1["targetLine"] = target_line
	_fleet.apply_state({
		"trains": [
			t1,
			{"id": "T3", "line": "DOWN", "block": "DOWN-B3", "offsetM": 171.5398, "physicalM": 320.0, "travelSign": -1, "speedKmh": 0.0, "targetSpeedKmh": 0.0}
		],
		"routes": {"wrongLine": {"active": wrong_line}},
	})
	var hud := _scene.get_node_or_null("HUD") as TwinHUD
	if hud:
		hud.apply_state({"routes": {"wrongLine": {"active": wrong_line}}})


func _setup_camera() -> void:
	var center := Vector3(90.0, 1.0, 110.0)
	if _fleet:
		var t1 := _fleet.get_train("T1")
		var t3 := _fleet.get_train("T3")
		var t1_loco := t1.get_node_or_null("Locomotive") as Node3D if is_instance_valid(t1) else null
		var t3_loco := t3.get_node_or_null("Locomotive") as Node3D if is_instance_valid(t3) else null
		if t1_loco and t3_loco:
			center = (t1_loco.global_position + t3_loco.global_position) * 0.5
	_camera = Camera3D.new()
	_camera.fov = 75.0
	_camera.far = 2000.0
	_scene.add_child(_camera)
	_camera.global_position = center + Vector3(20.0, 120.0, 150.0)
	_camera.look_at(center, Vector3.UP)
	_camera.make_current()


func _snapshot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/opencode/%s" % file_name)
