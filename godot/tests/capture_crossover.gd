extends SceneTree

## Run: xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 \
##        --path godot --resolution 1280x720 --rendering-method gl_compatibility \
##        --script res://tests/capture_crossover.gd
## Writes crossover_before/mid/after.png plus numbered frames under /tmp/opencode.

const FRAME_COUNT := 30
const FRAME_STEP_SEC := 0.1

var _scene: Node3D
var _camera: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = load("res://scenes/lts_full.tscn").instantiate()
	_scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(_scene)

	var fleet := _scene.get_node_or_null("FleetController") as FleetController
	if fleet:
		fleet.crossover_duration_sec = FRAME_COUNT * FRAME_STEP_SEC
		fleet.apply_state({
			"trains": [
				{"id": "T1", "line": "UP", "block": "UP-B2", "offsetM": 20.0, "speedKmh": 0.0, "targetSpeedKmh": 0.0},
				{"id": "T3", "line": "DOWN", "block": "DOWN-B4", "offsetM": 30.0, "speedKmh": 45.0, "targetSpeedKmh": 45.0}
			]
		})

	_setup_camera()
	_apply_hud()
	for frame in 6:
		await process_frame
	await _snapshot("crossover_before.png")

	if fleet:
		fleet.apply_state({
			"trains": [
				{"id": "T1", "line": "DOWN", "block": "DOWN-B2", "offsetM": 0.0, "speedKmh": 0.0, "targetSpeedKmh": 0.0},
				{"id": "T3", "line": "DOWN", "block": "DOWN-B4", "offsetM": 30.0, "speedKmh": 45.0, "targetSpeedKmh": 45.0}
			]
		})

	for frame in FRAME_COUNT:
		await create_timer(FRAME_STEP_SEC).timeout
		await _snapshot("crossover_frame_%02d.png" % frame)
		if frame == FRAME_COUNT / 2 - 1:
			await _snapshot("crossover_midway.png")
	await _snapshot("crossover_after.png")
	quit()


func _setup_camera() -> void:
	var carriage := _scene.get_node_or_null("Train/Locomotive") as Node3D
	var center := Vector3(60.0, 1.0, -232.0)
	if carriage:
		center = carriage.global_position + Vector3(12.0, 1.0, 8.0)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.far = 2000.0
	_scene.add_child(_camera)
	_camera.global_position = center + Vector3(42.0, 20.0, -12.0)
	_camera.look_at(center, Vector3.UP)
	_camera.make_current()


func _apply_hud() -> void:
	var hud := _scene.get_node_or_null("HUD") as TwinHUD
	if hud:
		hud.apply_state({
			"meets": {
				"enabled": true,
				"seed": 20261022,
				"phase": "HOLDING",
				"nextMeetInSec": 0,
				"active": {
					"holderId": "T1",
					"otherId": "T3",
					"holdRemainingSec": 8.0,
					"crossover": true,
					"routeId": "X-UP-DOWN"
				},
				"last": null
			}
		})


func _snapshot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/opencode/%s" % file_name)
