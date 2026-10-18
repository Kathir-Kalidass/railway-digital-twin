extends Node3D

# Educational digital twin only. This is not railway signalling software.
const API_BASE := "http://127.0.0.1:3001"
const TRACK_WIDTH := 2.15
const MAX_SPEED := 80.0

var track_path: Path3D
var train_follow: PathFollow3D
var train_root: Node3D
var elephant: Node3D
var signal_lamp: MeshInstance3D
var signal_red_mat: StandardMaterial3D
var signal_green_mat: StandardMaterial3D
var hud: Label
var wildlife_active := false
var sensor_fault := false
var target_speed := 48.0
var current_speed := 48.0
var last_reported_hazard := false
var last_reported_fault := false
var report_timer := 0.0
var event_queue: Array[String] = []

func _ready() -> void:
	_build_world()
	_build_hud()
	_send_event("RESET")

func _process(delta: float) -> void:
	var safe_target := 0.0 if wildlife_active or sensor_fault else target_speed
	current_speed = move_toward(current_speed, safe_target, (18.0 if safe_target < current_speed else 7.0) * delta)
	if train_follow:
		var path_length := track_path.curve.get_baked_length()
		if path_length > 0.0:
			train_follow.progress = fposmod(train_follow.progress + (current_speed / 3.6) * delta * 0.42, path_length)
	if elephant:
		elephant.visible = wildlife_active
		if wildlife_active:
			elephant.rotation.y = sin(Time.get_ticks_msec() * 0.001) * 0.04
	if signal_lamp:
		var mat := signal_red_mat if wildlife_active or sensor_fault else signal_green_mat
		signal_lamp.set_surface_override_material(0, mat)
	report_timer += delta
	if report_timer >= 1.5:
		report_timer = 0.0
		_post_state()
	_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				wildlife_active = not wildlife_active
				_send_event("WILDLIFE_DETECTED" if wildlife_active else "WILDLIFE_CLEARED")
			KEY_F:
				sensor_fault = not sensor_fault
				_send_event("SENSOR_FAULT" if sensor_fault else "SENSOR_RESTORED")
			KEY_R:
				if not wildlife_active and not sensor_fault:
					target_speed = 48.0
					_send_event("RESET")
			KEY_UP:
				target_speed = min(MAX_SPEED, target_speed + 8.0)
				_send_speed()
			KEY_DOWN:
				target_speed = max(0.0, target_speed - 8.0)
				_send_speed()

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("203f55")
	sky_mat.sky_horizon_color = Color("b1c7b1")
	sky_mat.ground_bottom_color = Color("172d27")
	sky_mat.ground_horizon_color = Color("7d9c82")
	environment.sky.sky_material = sky_mat
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a9c4b1")
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(180, 180)
	ground.mesh = ground_mesh
	ground.position.y = -0.45
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color("294a37")
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	add_child(ground)

	track_path = Path3D.new()
	track_path.name = "CurvedRailwayPath"
	track_path.curve = Curve3D.new()
	track_path.curve.add_point(Vector3(-25, 0, 16), Vector3.ZERO, Vector3(0, 0, -10))
	track_path.curve.add_point(Vector3(-20, 0, 2), Vector3(0, 0, 8), Vector3(8, 0, -7))
	track_path.curve.add_point(Vector3(-7, 0, -8), Vector3(-7, 0, -3), Vector3(10, 0, -3))
	track_path.curve.add_point(Vector3(9, 0, -12), Vector3(-10, 0, 0), Vector3(9, 0, 7))
	track_path.curve.add_point(Vector3(22, 0, -2), Vector3(0, 0, -8), Vector3(4, 0, 10))
	track_path.curve.add_point(Vector3(18, 0, 15), Vector3(0, 0, -8), Vector3(-8, 0, 4))
	track_path.curve.add_point(Vector3(4, 0, 21), Vector3(9, 0, 0), Vector3(-10, 0, 0))
	track_path.curve.bake_interval = 0.5
	add_child(track_path)
	_build_tracks()
	_build_forest()
	_build_train()
	_build_elephant()
	_build_signal()
	_build_camera()

func _build_tracks() -> void:
	var rail_mat := _material(Color("8b9697"), 0.28, 0.65)
	var sleeper_mat := _material(Color("514b3e"), 0.95)
	var length := track_path.curve.get_baked_length()
	var previous_left := Vector3.ZERO
	var previous_right := Vector3.ZERO
	var previous_center := Vector3.ZERO
	var have_previous := false
	var d := 0.0
	while d <= length:
		var center := track_path.curve.sample_baked(d)
		var ahead := track_path.curve.sample_baked(min(length, d + 0.15))
		var forward := (ahead - center).normalized()
		var side := Vector3.UP.cross(forward).normalized()
		var left := center + side * TRACK_WIDTH * 0.5
		var right := center - side * TRACK_WIDTH * 0.5
		if have_previous:
			_add_beam(previous_left, left, 0.14, 0.17, rail_mat, "RailLeft")
			_add_beam(previous_right, right, 0.14, 0.17, rail_mat, "RailRight")
			if int(d * 1.2) % 2 == 0:
				_add_beam(previous_center - side * 1.45, previous_center + side * 1.45, 0.24, 0.13, sleeper_mat, "Sleeper")
		previous_left = left
		previous_right = right
		previous_center = center
		have_previous = true
		d += 0.7

func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	for i in range(110):
		var x := rng.randf_range(-42, 42)
		var z := rng.randf_range(-28, 35)
		var p := Vector3(x, 0, z)
		var nearest := 999.0
		for j in range(0, 101, 5):
			var sample := track_path.curve.sample_baked(track_path.curve.get_baked_length() * float(j) / 101.0)
			nearest = min(nearest, Vector2(p.x - sample.x, p.z - sample.z).length())
		if nearest < 4.2:
			continue
		var tree := Node3D.new()
		tree.position = p
		var trunk := MeshInstance3D.new()
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.18
		trunk_mesh.bottom_radius = 0.32
		trunk_mesh.height = rng.randf_range(2.2, 3.8)
		trunk.mesh = trunk_mesh
		trunk.position.y = trunk_mesh.height * 0.5
		trunk.material_override = _material(Color("604b36"))
		tree.add_child(trunk)
		var crown := MeshInstance3D.new()
		var crown_mesh := SphereMesh.new()
		crown_mesh.radius = rng.randf_range(1.0, 1.7)
		crown_mesh.height = crown_mesh.radius * 2.2
		crown.mesh = crown_mesh
		crown.position.y = trunk_mesh.height + 0.8
		crown.material_override = _material([Color("28513b"), Color("315d43"), Color("3d6746")][rng.randi_range(0, 2)], 1.0)
		tree.add_child(crown)
		add_child(tree)

func _build_train() -> void:
	train_follow = PathFollow3D.new()
	train_follow.name = "AnimatedTrainFollow"
	train_follow.loop = true
	train_follow.rotates = true
	train_follow.progress = 0.0
	track_path.add_child(train_follow)
	train_root = Node3D.new()
	train_root.name = "Train"
	train_follow.add_child(train_root)
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(2.15, 1.45, 5.4)
	body.mesh = body_mesh
	body.position.y = 1.2
	body.material_override = _material(Color("d7e2dd"), 0.32, 0.2)
	train_root.add_child(body)
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(1.95, 0.8, 1.25)
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 0.95, -2.8)
	nose.material_override = _material(Color("4e9c91"), 0.28)
	train_root.add_child(nose)
	var window_mat := _material(Color("183b4b"), 0.18, 0.1)
	for side in [-1.0, 1.0]:
		for i in range(4):
			var window := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(0.035, 0.42, 0.7)
			window.mesh = wm
			window.position = Vector3(side * 1.09, 1.42, -1.55 + i * 0.9)
			window.material_override = window_mat
			train_root.add_child(window)
		for z in [-1.8, 1.7]:
			var wheel := MeshInstance3D.new()
			var wheel_mesh := CylinderMesh.new()
			wheel_mesh.top_radius = 0.38
			wheel_mesh.bottom_radius = 0.38
			wheel_mesh.height = 0.2
			wheel.mesh = wheel_mesh
			wheel.rotation_degrees.z = 90
			wheel.position = Vector3(side * 1.08, 0.42, z)
			wheel.material_override = _material(Color("202a30"), 0.5)
			train_root.add_child(wheel)

func _build_elephant() -> void:
	elephant = Node3D.new()
	elephant.name = "WildlifeIntrusionModel"
	elephant.position = Vector3(-3.5, 0, -7.1)
	elephant.visible = false
	add_child(elephant)
	var skin := _material(Color("777e7b"), 0.9)
	_add_ellipsoid(elephant, Vector3(0, 1.15, 0), Vector3(1.45, 1.05, 2.05), skin)
	_add_ellipsoid(elephant, Vector3(0, 1.8, -1.45), Vector3(0.95, 0.9, 0.95), skin)
	_add_ellipsoid(elephant, Vector3(-0.95, 1.65, -1.35), Vector3(0.65, 0.75, 0.2), skin)
	_add_ellipsoid(elephant, Vector3(0.95, 1.65, -1.35), Vector3(0.65, 0.75, 0.2), skin)
	_add_ellipsoid(elephant, Vector3(0, 1.2, -2.15), Vector3(0.24, 0.65, 0.28), skin)
	for x in [-0.82, 0.82]:
		for z in [-0.8, 0.8]:
			_add_ellipsoid(elephant, Vector3(x, 0.48, z), Vector3(0.34, 0.62, 0.35), skin)
	var tusk_mat := _material(Color("e6dfc8"))
	_add_ellipsoid(elephant, Vector3(-0.45, 1.25, -2.05), Vector3(0.12, 0.12, 0.48), tusk_mat)
	_add_ellipsoid(elephant, Vector3(0.45, 1.25, -2.05), Vector3(0.12, 0.12, 0.48), tusk_mat)

func _build_signal() -> void:
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.11
	pm.height = 3.8
	pole.mesh = pm
	pole.position = Vector3(2.5, 1.9, -10.0)
	pole.material_override = _material(Color("343e40"))
	add_child(pole)
	var housing := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.55, 1.1, 0.35)
	housing.mesh = hm
	housing.position = Vector3(2.5, 3.35, -10.0)
	housing.material_override = _material(Color("1b292b"))
	add_child(housing)
	signal_red_mat = _material(Color("ff343e"), 0.2, 0.1)
	signal_green_mat = _material(Color("32f58c"), 0.2, 0.1)
	signal_lamp = MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.19
	lm.height = 0.38
	signal_lamp.mesh = lm
	signal_lamp.position = Vector3(2.5, 3.58, -9.78)
	signal_lamp.material_override = signal_green_mat
	add_child(signal_lamp)

func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0, 24, 34)
	camera.rotation_degrees = Vector3(-29, -9, 0)
	camera.current = true
	camera.fov = 58
	add_child(camera)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(22, 20)
	panel.custom_minimum_size = Vector2(365, 158)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.07, 0.1, 0.88)
	style.border_color = Color(0.24, 0.56, 0.53, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var title := Label.new()
	title.text = "RAILWAY DIGITAL TWIN  /  ZONE 01"
	title.add_theme_color_override("font_color", Color("79e4c1"))
	title.add_theme_font_size_override("font_size", 13)
	col.add_child(title)
	hud = Label.new()
	hud.add_theme_color_override("font_color", Color("e2edf2"))
	hud.add_theme_font_size_override("font_size", 14)
	col.add_child(hud)
	var keys := Label.new()
	keys.text = "SPACE Wildlife  ·  F Sensor fault  ·  R Reset  ·  ↑/↓ Speed"
	keys.add_theme_color_override("font_color", Color("9ab2bd"))
	keys.add_theme_font_size_override("font_size", 11)
	col.add_child(keys)
	var note := Label.new()
	note.text = "Simulation only — not certified railway control"
	note.add_theme_color_override("font_color", Color("f2c77a"))
	note.add_theme_font_size_override("font_size", 10)
	col.add_child(note)

func _update_hud() -> void:
	if not hud:
		return
	var aspect := "RED / RESTRICTIVE" if wildlife_active or sensor_fault else "GREEN / NORMAL"
	var health := "FAULT" if sensor_fault else "HEALTHY"
	hud.text = "Train speed: %02d km/h   Target: %02d km/h\nSignal: %s\nWildlife: %s   Sensor: %s" % [roundi(current_speed), roundi(target_speed), aspect, "DETECTED" if wildlife_active else "CLEAR", health]

func _send_speed() -> void:
	var req := {"type":"SPEED", "speedKmh":target_speed, "source":"godot"}
	_request("/api/event", req)

func _send_event(kind: String) -> void:
	_request("/api/event", {"type":kind, "source":"godot", "zone":"ZONE_1"})

func _post_state() -> void:
	# Send periodic simulated speed/zone telemetry as an auditable event.
	_request("/api/event", {"type":"SIMULATION_TELEMETRY", "source":"godot", "zone":"ZONE_1", "speedKmh":roundi(current_speed), "wildlifeDetected":wildlife_active, "sensorHealthy":not sensor_fault})

func _request(path: String, payload: Dictionary) -> void:
	var request := HTTPRequest.new()
	request.timeout = 2.0
	add_child(request)
	request.request_completed.connect(func(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray): request.queue_free())
	var err := request.request(API_BASE + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		request.queue_free()

func _add_beam(a: Vector3, b: Vector3, width: float, height: float, mat: Material, node_name: String) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height, a.distance_to(b))
	mesh_instance.mesh = mesh
	mesh_instance.position = (a + b) * 0.5
	mesh_instance.look_at_from_position(mesh_instance.position, b, Vector3.UP)
	mesh_instance.material_override = mat
	add_child(mesh_instance)

func _add_ellipsoid(parent: Node3D, pos: Vector3, scale_value: Vector3, mat: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	part.mesh = mesh
	part.position = pos
	part.scale = scale_value
	part.material_override = mat
	parent.add_child(part)

func _material(color: Color, roughness: float = 0.8, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat
