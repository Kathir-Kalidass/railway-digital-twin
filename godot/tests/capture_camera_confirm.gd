extends SceneTree

## Run: xvfb-run -a /home/kathir/apps/godot/Godot_v4.7.2-stable_linux.x86_64 \
##        --path godot --resolution 1440x900 --rendering-method gl_compatibility \
##        --script res://tests/capture_camera_confirm.gd
## Writes /tmp/opencode/camera_confirm.png with the confirmed HUD state.

var _scene: Node3D
var _fleet: FleetController
var _camera: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = load("res://scenes/lts_full.tscn").instantiate()
	_scene.get_node("MQTTBridge").connect_on_ready = false
	root.add_child(_scene)
	await process_frame
	await process_frame

	_fleet = _scene.get_node("FleetController") as FleetController
	_fleet.apply_state({
		"trains": [
			{"id": "T1", "line": "UP", "block": "UP-B1", "offsetM": 50.0, "physicalM": 300.0, "travelSign": 1, "speedKmh": 8.0, "targetSpeedKmh": 8.0}
		],
		"blocks": [
			{"id": "UP-B1", "line": "UP", "index": 1, "zone": "zone1", "lengthM": 250.7964, "hazard": {"stage": "SUSPECTED", "sources": ["trackside"]}}
		],
	})

	var spawner := _scene.get_node("WorldWildlife/WildlifeSpawner") as WildlifeSpawner
	var elephant := spawner.spawn("elephant")

	var t1 := _fleet.get_train("T1") as LTSTrain
	var loco := t1.get_node_or_null("Locomotive") as Node3D if is_instance_valid(t1) else null
	if loco:
		var forward := loco.global_transform.basis.x.normalized()
		elephant.global_position = loco.global_position + forward * 34.0
	var cam := t1.get_camera_confirmation() if is_instance_valid(t1) else null
	if cam != null:
		cam.enabled = true
		cam.upload_override = func(_url: String, _headers: PackedStringArray, body: PackedByteArray) -> Dictionary:
			return {"ok": true, "confirmed": body.size() > 0, "degraded": false, "stage": "CONFIRMED", "species": "elephant", "confidence": 0.92}
		await cam._capture_once()

	for frame in 8:
		await process_frame
	_setup_camera()
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/opencode/camera_confirm.png")
	quit()


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = 58.0
	_camera.far = 2000.0
	_scene.add_child(_camera)
	var t1 := _fleet.get_train("T1") as LTSTrain
	var loco := t1.get_node_or_null("Locomotive") as Node3D if is_instance_valid(t1) else null
	var center := loco.global_position if loco else Vector3(300.0, 0.0, 120.0)
	var forward := loco.global_transform.basis.x.normalized() if loco else Vector3.RIGHT
	var side := loco.global_transform.basis.z.normalized() if loco else Vector3.BACK
	_camera.global_position = center - forward * 24.0 + side * 18.0 + Vector3.UP * 9.0
	_camera.look_at(center + forward * 24.0 + Vector3.UP * 1.5, Vector3.UP)
	_camera.make_current()
