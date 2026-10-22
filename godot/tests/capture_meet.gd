extends SceneTree

## Run: xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 \
##        --path godot --resolution 1280x720 --rendering-method gl_compatibility \
##        --script res://tests/capture_meet.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node3D = load("res://scenes/lts_full.tscn").instantiate()
	scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(scene)
	for frame in 12:
		await process_frame

	var fleet := scene.get_node_or_null("FleetController") as FleetController
	if fleet:
		fleet.apply_state({
			"trains": [
				{"id": "T1", "line": "UP", "block": "UP-B2", "offsetM": 20.0, "speedKmh": 0.0, "targetSpeedKmh": 0.0},
				{"id": "T3", "line": "DOWN", "block": "DOWN-B2", "offsetM": 30.0, "speedKmh": 45.0, "targetSpeedKmh": 45.0}
			]
		})

	var hud := scene.get_node_or_null("HUD") as TwinHUD
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

	var camera := Camera3D.new()
	camera.fov = 55.0
	camera.far = 2000.0
	scene.add_child(camera)
	camera.global_position = Vector3(70.0, 26.0, -268.0)
	camera.look_at(Vector3(32.0, 1.0, -231.0), Vector3.UP)
	camera.make_current()
	for frame in 4:
		await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/opencode/meet_randomized.png")
	quit()
