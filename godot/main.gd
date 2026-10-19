extends Node3D

# ==============================================================================
# RAILWAY DIGITAL TWIN - TWO-ZONE PROCEDURAL 3D SIMULATION (GODOT 4)
# ==============================================================================
# Features:
# - Full two-zone system: Zone 1 (Forest Corridor) & Zone 2 (Mountain Tunnel)
# - Articulated 3-car train: Locomotive + 2 Passenger Coaches on curved rails
# - Speed-synchronized rotating wheels on all bogies
# - Locomotive high-beam spotlight & braking indicator tail lights
# - Procedural smoke / exhaust particle plume from locomotive
# - Dynamic 3-aspect signals for both Zone 1 & Zone 2 (Red / Yellow / Green)
# - Level crossing with animated boom barrier & alternating red hazard flashers
# - Procedural walking elephant: animated 4-leg cycle, flapping ears, trunk sway
# - Day / Night dynamic sky & lighting cycle (Press N to toggle)
# - Multi-angle cinematic camera director (Press C to cycle 4 cameras)
# - Dual-stack communication: HTTP REST + Telemetry stream to backend
# ==============================================================================

const CONFIG_PATH := "res://config.cfg"
const TRACK_WIDTH := 2.2
const MAX_SPEED := 80.0
const BRAKING_DECEL := 1.2 # m/s^2

# Configuration
var api_base := "http://127.0.0.1:3001"
var active_zone := "zone1"

# State & Controls
var target_speed := 48.0
var current_speed := 48.0
var wildlife_zone1 := false
var sensor_fault_zone1 := false
var wildlife_zone2 := false
var sensor_fault_zone2 := false

# Simulation variables
var train_progress := 0.0
var wheel_rotation_angle := 0.0
var barrier_position := 1.0 # 1.0 = open, 0.0 = closed
var elephant_anim_time := 0.0
var elephant_track_t := 0.0 # 0.0 = forest, 1.0 = on track
var day_time := 0.28 # 0.0 - 1.0
var auto_day_night := false
var backend_connected := false
var backend_ping_timer := 0.0
var telemetry_timer := 0.0
var camera_mode := 0 # 0: Overview, 1: Chase, 2: Driver Cab, 3: Wildlife Crossing

# Visual Nodes
var track_path: Path3D
var train_follow: PathFollow3D
var coach1_follow: PathFollow3D
var coach2_follow: PathFollow3D
var locomotive_mesh: Node3D
var wheels: Array[MeshInstance3D] = []
var smoke_particles: Array[MeshInstance3D] = []
var smoke_data: Array[Dictionary] = []
var headlight: SpotLight3D
var brake_light_mat: StandardMaterial3D

# Signals & Barriers
var signal1_lamps: Array[MeshInstance3D] = [] # 0: Red, 1: Yellow, 2: Green
var signal2_lamps: Array[MeshInstance3D] = []
var barrier_arm: Node3D
var barrier_lights: Array[MeshInstance3D] = []
var danger_ring: MeshInstance3D

# Wildlife
var elephant_root: Node3D
var elephant_legs: Array[Node3D] = []
var elephant_ears: Array[Node3D] = []
var elephant_trunk: Node3D
var elephant_tail: Node3D

# Cameras & Environment
var main_camera: Camera3D
var sun_light: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var trees_list: Array[Node3D] = []

# HUD
var hud_panel: PanelContainer
var hud_speed_label: Label
var hud_zone1_label: Label
var hud_zone2_label: Label
var hud_cam_label: Label
var hud_conn_label: Label
var hud_conn_dot: ColorRect
var hud_stopping_bar: ProgressBar

func _ready() -> void:
	_load_config()
	_build_environment()
	_build_track_and_terrain()
	_build_signals_and_crossing()
	_build_train()
	_build_elephant()
	_build_cameras()
	_build_hud()
	_ping_backend()
	_send_event("RESET", "zone1")

func _process(delta: float) -> void:
	_update_speeds_and_physics(delta)
	_update_train_movement(delta)
	_update_wheels_and_particles(delta)
	_update_wildlife_animation(delta)
	_update_signals_and_barriers(delta)
	_update_day_night(delta)
	_update_cameras(delta)
	_update_hud()

	# Periodic networking
	telemetry_timer += delta
	if telemetry_timer >= 1.0:
		telemetry_timer = 0.0
		_send_telemetry()

	backend_ping_timer += delta
	if backend_ping_timer >= 5.0:
		backend_ping_timer = 0.0
		_ping_backend()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	match event.keycode:
		KEY_SPACE:
			wildlife_zone1 = not wildlife_zone1
			_send_event("WILDLIFE_DETECTED" if wildlife_zone1 else "WILDLIFE_CLEARED", "zone1")
		KEY_F:
			sensor_fault_zone1 = not sensor_fault_zone1
			_send_event("SENSOR_FAULT" if sensor_fault_zone1 else "SENSOR_RESTORED", "zone1")
		KEY_2:
			wildlife_zone2 = not wildlife_zone2
			_send_event("WILDLIFE_DETECTED" if wildlife_zone2 else "WILDLIFE_CLEARED", "zone2")
		KEY_R:
			if not wildlife_zone1 and not sensor_fault_zone1 and not wildlife_zone2 and not sensor_fault_zone2:
				target_speed = 48.0
				_send_event("RESET", "zone1")
				_send_event("RESET", "zone2")
		KEY_UP:
			target_speed = min(MAX_SPEED, target_speed + 8.0)
			_send_speed()
		KEY_DOWN:
			target_speed = max(0.0, target_speed - 8.0)
			_send_speed()
		KEY_C:
			camera_mode = (camera_mode + 1) % 4
		KEY_N:
			auto_day_night = not auto_day_night
			if not auto_day_night:
				day_time = 0.85 if day_time < 0.5 else 0.28 # Quick toggle Day / Sunset / Night

# ------------------------------------------------------------------------------
# PHYSICS & SPEED
# ------------------------------------------------------------------------------
func _update_speeds_and_physics(delta: float) -> void:
	var hazard_active := wildlife_zone1 or sensor_fault_zone1 or wildlife_zone2 or sensor_fault_zone2
	var safe_target := 0.0 if hazard_active else target_speed
	var accel_rate := 22.0 if safe_target < current_speed else 8.5
	current_speed = move_toward(current_speed, safe_target, accel_rate * delta)

	# Tail brake light glows bright red on deceleration
	if brake_light_mat:
		var is_braking := current_speed > safe_target + 1.0 and safe_target == 0.0
		brake_light_mat.emission_energy_multiplier = 4.0 if is_braking else 0.8

func _update_train_movement(delta: float) -> void:
	if not track_path or not track_path.curve:
		return
	var curve_len := track_path.curve.get_baked_length()
	if curve_len <= 0.0:
		return

	var speed_ms := current_speed / 3.6
	train_progress = fposmod(train_progress + speed_ms * delta * 0.45, curve_len)

	if train_follow:
		train_follow.progress = train_progress
	if coach1_follow:
		coach1_follow.progress = fposmod(train_progress - 6.4, curve_len)
	if coach2_follow:
		coach2_follow.progress = fposmod(train_progress - 12.8, curve_len)

	# Update active zone based on position along curve
	var half_len := curve_len * 0.5
	var new_zone := "zone1" if train_progress < half_len else "zone2"
	if new_zone != active_zone:
		active_zone = new_zone
		_send_event("TRAIN_ENTERED_ZONE", active_zone)

func _update_wheels_and_particles(delta: float) -> void:
	# Synchronized wheel rotation
	var wheel_radius := 0.42
	var angular_vel := (current_speed / 3.6) / wheel_radius
	wheel_rotation_angle += angular_vel * delta
	for w in wheels:
		w.rotation.x = wheel_rotation_angle

	# Procedural exhaust steam particles
	for i in range(smoke_particles.size()):
		var p := smoke_particles[i]
		var data := smoke_data[i]
		data.life += delta * (1.2 + current_speed * 0.03)
		if data.life > 1.0:
			data.life = 0.0
			p.position = Vector3(0, 1.85, -2.1) # Exhaust pipe
			p.scale = Vector3.ONE * 0.12
		else:
			p.position.y += delta * 1.8
			p.position.z += delta * (current_speed * 0.08) # Trails behind train
			var s: float = lerp(0.12, 0.65, data.life)
			p.scale = Vector3.ONE * s

# ------------------------------------------------------------------------------
# WILDLIFE ANIMATION
# ------------------------------------------------------------------------------
func _update_wildlife_animation(delta: float) -> void:
	if not elephant_root:
		return

	var target_t := 1.0 if wildlife_zone1 else 0.0
	elephant_track_t = move_toward(elephant_track_t, target_t, delta * 0.45)
	elephant_root.visible = elephant_track_t > 0.01

	if elephant_root.visible:
		# Interpolate between forest edge and track center
		var forest_pos := Vector3(-14.0, 0, -6.5)
		var track_pos := Vector3(-2.8, 0, -7.2)
		elephant_root.position = forest_pos.lerp(track_pos, elephant_track_t)

		# Walking cycle when moving
		var is_walking := abs(elephant_track_t - target_t) > 0.02
		if is_walking:
			elephant_anim_time += delta * 4.5
		else:
			elephant_anim_time += delta * 1.2 # Idle sway

		# 4-Leg alternating swing
		if elephant_legs.size() >= 4:
			var swing1 := sin(elephant_anim_time) * 0.35
			var swing2 := sin(elephant_anim_time + PI) * 0.35
			elephant_legs[0].rotation.x = swing1 if is_walking else 0.0
			elephant_legs[1].rotation.x = swing2 if is_walking else 0.0
			elephant_legs[2].rotation.x = swing2 if is_walking else 0.0
			elephant_legs[3].rotation.x = swing1 if is_walking else 0.0

		# Ear flapping & trunk sway
		if elephant_ears.size() >= 2:
			var ear_flap := sin(Time.get_ticks_msec() * 0.003) * 0.18
			elephant_ears[0].rotation.y = ear_flap
			elephant_ears[1].rotation.y = -ear_flap
		if elephant_trunk:
			elephant_trunk.rotation.x = -0.25 + sin(Time.get_ticks_msec() * 0.002) * 0.15
		if elephant_tail:
			elephant_tail.rotation.z = sin(Time.get_ticks_msec() * 0.004) * 0.25

		# Danger ring pulsing on ground
		if danger_ring:
			danger_ring.visible = elephant_track_t > 0.5
			var pulse: float = 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.12
			danger_ring.scale = Vector3(pulse, 1.0, pulse)

# ------------------------------------------------------------------------------
# SIGNALS & CROSSING BARRIERS
# ------------------------------------------------------------------------------
func _update_signals_and_barriers(delta: float) -> void:
	# Zone 1 Signal logic: RED if hazard, else GREEN
	var z1_red := wildlife_zone1 or sensor_fault_zone1
	_set_signal_aspect(signal1_lamps, "RED" if z1_red else "GREEN")

	# Zone 2 Signal logic: RED if z2 hazard, YELLOW if z1 hazard (caution!), else GREEN
	var z2_red := wildlife_zone2 or sensor_fault_zone2
	var z2_aspect := "RED" if z2_red else ("YELLOW" if z1_red else "GREEN")
	_set_signal_aspect(signal2_lamps, z2_aspect)

	# Motorized Boom Barrier Gate
	var barrier_target := 0.0 if (wildlife_zone1 or sensor_fault_zone1) else 1.0
	barrier_position = move_toward(barrier_position, barrier_target, delta * 1.5)
	if barrier_arm:
		barrier_arm.rotation.z = lerp(0.0, deg_to_rad(82.0), barrier_position)

	# Flashing red crossing lights
	var flash_on := int(Time.get_ticks_msec() * 0.003) % 2 == 0 and barrier_position < 0.95
	for i in range(barrier_lights.size()):
		var light := barrier_lights[i]
		var lit := flash_on if i == 0 else (not flash_on and barrier_position < 0.95)
		light.visible = lit

func _set_signal_aspect(lamps: Array[MeshInstance3D], aspect: String) -> void:
	if lamps.size() < 3:
		return
	# 0: RED, 1: YELLOW, 2: GREEN
	lamps[0].visible = aspect == "RED"
	lamps[1].visible = aspect == "YELLOW"
	lamps[2].visible = aspect == "GREEN"

# ------------------------------------------------------------------------------
# DAY / NIGHT CYCLE & ATMOSPHERE
# ------------------------------------------------------------------------------
func _update_day_night(delta: float) -> void:
	if auto_day_night:
		day_time = fmod(day_time + delta * 0.02, 1.0)

	if sun_light:
		var sun_angle: float = (day_time - 0.25) * TAU
		sun_light.rotation_degrees = Vector3(rad_to_deg(sin(sun_angle)) * 60.0, rad_to_deg(sun_angle), 0)
		var is_night := day_time > 0.5 and day_time < 0.95
		sun_light.light_energy = 0.15 if is_night else 1.3

	if headlight:
		headlight.light_energy = 2.5 if (day_time > 0.45 and day_time < 0.98) else 0.8

# ------------------------------------------------------------------------------
# CINEMATIC CAMERA DIRECTOR
# ------------------------------------------------------------------------------
func _update_cameras(delta: float) -> void:
	if not main_camera or not train_root:
		return

	var target_transform: Transform3D
	match camera_mode:
		0: # OVERVIEW
			target_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-30), deg_to_rad(-8), 0)), Vector3(0, 28, 38))
		1: # CHASE CAM (Follows behind train)
			var train_pos := train_follow.global_position
			var forward := -train_follow.global_transform.basis.z.normalized()
			var cam_pos := train_pos - forward * 11.0 + Vector3(0, 4.2, 0)
			target_transform = Transform3D().looking_at(forward, Vector3.UP)
			target_transform.origin = cam_pos
			target_transform = target_transform.looking_at(train_pos + Vector3(0, 1.5, 0), Vector3.UP)
		2: # DRIVER CAB CAM (Inside train looking forward)
			var cab_pos := train_follow.global_position + Vector3(0, 1.65, 0)
			var forward := -train_follow.global_transform.basis.z.normalized()
			target_transform = Transform3D().looking_at(forward, Vector3.UP)
			target_transform.origin = cab_pos
		3: # WILDLIFE CROSSING CAM
			var look_target := Vector3(-3.5, 1.2, -7.0)
			var cam_pos := Vector3(6.5, 3.2, -1.0)
			target_transform = Transform3D().looking_at(look_target - cam_pos, Vector3.UP)
			target_transform.origin = cam_pos

	main_camera.global_transform = main_camera.global_transform.interpolate_with(target_transform, delta * 4.0)

# ------------------------------------------------------------------------------
# WORLD & PROCEDURAL ASSET BUILDERS
# ------------------------------------------------------------------------------
func _build_environment() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("1e3d59")
	sky_material.sky_horizon_color = Color("a7c5b6")
	sky_material.ground_bottom_color = Color("142823")
	sky_material.ground_horizon_color = Color("688970")
	env.sky.sky_material = sky_material
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b4d2be")
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.15
	env_node.environment = env
	add_child(env_node)

	sun_light = DirectionalLight3D.new()
	sun_light.rotation_degrees = Vector3(-45, -30, 0)
	sun_light.light_energy = 1.3
	sun_light.shadow_enabled = true
	add_child(sun_light)

	# Ground terrain
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(240, 240)
	ground.mesh = gm
	ground.position.y = -0.48
	var ground_mat := _material(Color("264634"), 0.95)
	ground.material_override = ground_mat
	add_child(ground)

func _build_track_and_terrain() -> void:
	track_path = Path3D.new()
	track_path.name = "TwinLoopPath"
	track_path.curve = Curve3D.new()

	# Zone 1 (Forest Section) & Zone 2 (Mountain Tunnel Loop)
	track_path.curve.add_point(Vector3(-30, 0, 18), Vector3.ZERO, Vector3(0, 0, -12))
	track_path.curve.add_point(Vector3(-22, 0, 2), Vector3(0, 0, 8), Vector3(10, 0, -8))
	track_path.curve.add_point(Vector3(-6, 0, -9), Vector3(-8, 0, -3), Vector3(12, 0, -3)) # Wildlife crossing
	track_path.curve.add_point(Vector3(12, 0, -14), Vector3(-10, 0, 0), Vector3(10, 0, 8)) # Mountain entry
	track_path.curve.add_point(Vector3(26, 0, -2), Vector3(0, 0, -10), Vector3(4, 0, 12)) # Tunnel
	track_path.curve.add_point(Vector3(20, 0, 18), Vector3(0, 0, -10), Vector3(-10, 0, 5)) # Bridge
	track_path.curve.add_point(Vector3(4, 0, 24), Vector3(12, 0, 0), Vector3(-12, 0, 0))
	track_path.curve.bake_interval = 0.4
	add_child(track_path)

	# Build Rails, Sleepers, Ballast
	var rail_mat := _material(Color("8e999b"), 0.2, 0.7)
	var sleeper_mat := _material(Color("4a3c31"), 0.9)
	var ballast_mat := _material(Color("3b3833"), 0.98)
	var length := track_path.curve.get_baked_length()
	var d := 0.0

	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_c := Vector3.ZERO
	var first := true

	while d <= length:
		var center := track_path.curve.sample_baked(d)
		var ahead := track_path.curve.sample_baked(min(length, d + 0.2))
		var forward := (ahead - center).normalized()
		var side := Vector3.UP.cross(forward).normalized()
		var left := center + side * TRACK_WIDTH * 0.5
		var right := center - side * TRACK_WIDTH * 0.5

		if not first:
			_add_beam(prev_l, left, 0.16, 0.18, rail_mat, "RailL")
			_add_beam(prev_r, right, 0.16, 0.18, rail_mat, "RailR")
			_add_beam(prev_c, center, 3.2, 0.12, ballast_mat, "Ballast")
			if int(d * 1.5) % 2 == 0:
				_add_beam(prev_c - side * 1.55, prev_c + side * 1.55, 0.26, 0.14, sleeper_mat, "Sleeper")
		prev_l = left
		prev_r = right
		prev_c = center
		first = false
		d += 0.65

	_build_forest()
	_build_mountain_tunnel()
	_build_zone_boundary_gantries()

func _build_forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	for i in range(120):
		var x := rng.randf_range(-48, 48)
		var z := rng.randf_range(-32, 40)
		var p := Vector3(x, 0, z)
		# Don't place on tracks
		var nearest := 999.0
		for j in range(0, 101, 4):
			var sample := track_path.curve.sample_baked(track_path.curve.get_baked_length() * float(j) / 100.0)
			nearest = min(nearest, Vector2(p.x - sample.x, p.z - sample.z).length())
		if nearest < 4.8:
			continue

		var tree := Node3D.new()
		tree.position = p
		var trunk := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.18
		tm.bottom_radius = 0.35
		tm.height = rng.randf_range(2.4, 4.0)
		trunk.mesh = tm
		trunk.position.y = tm.height * 0.5
		trunk.material_override = _material(Color("513e2e"))
		tree.add_child(trunk)

		var crown := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = rng.randf_range(1.1, 1.8)
		cm.height = cm.radius * 2.2
		crown.mesh = cm
		crown.position.y = tm.height + 0.8
		var foliage_colors := [Color("284e3a"), Color("1e4231"), Color("355d44"), Color("244b35")]
		crown.material_override = _material(foliage_colors[rng.randi() % foliage_colors.size()], 0.95)
		tree.add_child(crown)
		add_child(tree)
		trees_list.append(crown)

func _build_mountain_tunnel() -> void:
	# Mountain tunnel portal at x=25, z=-2
	var portal := Node3D.new()
	portal.position = Vector3(25, 0, -2)
	var rock_mat := _material(Color("4d4a45"), 0.95)

	# Mountain bulk
	var mountain := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(14, 10, 16)
	mountain.mesh = mm
	mountain.position = Vector3(0, 4.8, 0)
	mountain.material_override = rock_mat
	portal.add_child(mountain)

	# Tunnel arch entrance
	var arch_mat := _material(Color("2a2826"), 0.9)
	var arch_l := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(1.2, 5.5, 4.0)
	arch_l.mesh = am
	arch_l.position = Vector3(-2.8, 2.5, -7.5)
	arch_l.material_override = arch_mat
	portal.add_child(arch_l)

	var arch_r := MeshInstance3D.new()
	arch_r.mesh = am
	arch_r.position = Vector3(2.8, 2.5, -7.5)
	arch_r.material_override = arch_mat
	portal.add_child(arch_r)

	var arch_top := MeshInstance3D.new()
	var atm := BoxMesh.new()
	atm.size = Vector3(6.8, 1.4, 4.0)
	arch_top.mesh = atm
	arch_top.position = Vector3(0, 5.2, -7.5)
	arch_top.material_override = arch_mat
	portal.add_child(arch_top)

	# Interior tunnel warm light
	var tunnel_light := OmniLight3D.new()
	tunnel_light.position = Vector3(0, 3.8, 0)
	tunnel_light.light_color = Color("ffba66")
	tunnel_light.light_energy = 2.0
	tunnel_light.omni_range = 10.0
	portal.add_child(tunnel_light)
	add_child(portal)

func _build_zone_boundary_gantries() -> void:
	# Overhead Arch marking Zone 1 -> Zone 2
	var gantry := Node3D.new()
	gantry.position = Vector3(12, 0, -14)
	gantry.look_at(gantry.position + Vector3(1, 0, 0.8), Vector3.UP)
	var steel_mat := _material(Color("323d42"), 0.4, 0.5)

	var post_l := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.08
	pm.bottom_radius = 0.12
	pm.height = 4.8
	post_l.mesh = pm
	post_l.position = Vector3(-2.5, 2.4, 0)
	post_l.material_override = steel_mat
	gantry.add_child(post_l)

	var post_r := MeshInstance3D.new()
	post_r.mesh = pm
	post_r.position = Vector3(2.5, 2.4, 0)
	post_r.material_override = steel_mat
	gantry.add_child(post_r)

	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(5.4, 0.45, 0.4)
	beam.mesh = bm
	beam.position = Vector3(0, 4.6, 0)
	beam.material_override = steel_mat
	gantry.add_child(beam)

	# Illuminated boundary sign
	var sign_mesh := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(2.8, 0.7, 0.1)
	sign_mesh.mesh = sm
	sign_mesh.position = Vector3(0, 4.6, 0.25)
	var sign_mat := _material(Color("0f2d26"), 0.3)
	sign_mat.emission_enabled = true
	sign_mat.emission = Color("4fe3be")
	sign_mat.emission_energy_multiplier = 1.2
	sign_mesh.material_override = sign_mat
	gantry.add_child(sign_mesh)
	add_child(gantry)

# ------------------------------------------------------------------------------
# MULTI-CAR TRAIN WITH ROTATING WHEELS & LIGHTS
# ------------------------------------------------------------------------------
func _build_train() -> void:
	train_follow = PathFollow3D.new()
	train_follow.loop = true
	train_follow.rotates = true
	track_path.add_child(train_follow)

	coach1_follow = PathFollow3D.new()
	coach1_follow.loop = true
	coach1_follow.rotates = true
	track_path.add_child(coach1_follow)

	coach2_follow = PathFollow3D.new()
	coach2_follow.loop = true
	coach2_follow.rotates = true
	track_path.add_child(coach2_follow)

	# Locomotive
	train_root = Node3D.new()
	train_root.name = "Locomotive"
	train_follow.add_child(train_root)
	_build_locomotive_body(train_root)

	# Coach 1
	var coach1 := Node3D.new()
	coach1.name = "Coach1"
	coach1_follow.add_child(coach1)
	_build_coach_body(coach1, Color("dce5e7"))

	# Coach 2
	var coach2 := Node3D.new()
	coach2.name = "Coach2"
	coach2_follow.add_child(coach2)
	_build_coach_body(coach2, Color("dce5e7"), true) # has rear brake lights

func _build_locomotive_body(parent: Node3D) -> void:
	var body_mat := _material(Color("e0ece8"), 0.3, 0.15)
	var accent_mat := _material(Color("288075"), 0.3, 0.1)
	var dark_mat := _material(Color("162428"), 0.5)

	# Main chassis
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.2, 1.45, 5.6)
	body.mesh = bm
	body.position.y = 1.22
	body.material_override = body_mat
	parent.add_child(body)

	# Aerodynamic cab nose
	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(2.0, 0.9, 1.4)
	nose.mesh = nm
	nose.position = Vector3(0, 0.98, -3.0)
	nose.material_override = accent_mat
	parent.add_child(nose)

	# Wraparound windscreen
	var glass_mat := _material(Color("13303d"), 0.1, 0.3)
	var glass := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(1.85, 0.55, 0.1)
	glass.mesh = gm
	glass.position = Vector3(0, 1.55, -2.85)
	glass.rotation_degrees.x = -25
	glass.material_override = glass_mat
	parent.add_child(glass)

	# Side windows
	for side in [-1.0, 1.0]:
		for i in range(4):
			var win := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(0.04, 0.45, 0.72)
			win.mesh = wm
			win.position = Vector3(side * 1.11, 1.45, -1.6 + i * 0.95)
			win.material_override = glass_mat
			parent.add_child(win)

	# Rotating Wheels (Locomotive Bogies: Front & Rear)
	for side in [-1.0, 1.0]:
		for z in [-2.1, -1.1, 1.1, 2.1]:
			var wheel := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.42
			wm.bottom_radius = 0.42
			wm.height = 0.18
			wheel.mesh = wm
			wheel.rotation_degrees.z = 90
			wheel.position = Vector3(side * 1.08, 0.42, z)
			wheel.material_override = dark_mat
			parent.add_child(wheel)
			wheels.append(wheel)

	# Headlight spotlight & glowing bulb
	headlight = SpotLight3D.new()
	headlight.position = Vector3(0, 1.1, -3.6)
	headlight.rotation_degrees = Vector3(-4, 180, 0)
	headlight.spot_angle = 38.0
	headlight.spot_range = 35.0
	headlight.light_color = Color("fff2d1")
	headlight.light_energy = 2.0
	parent.add_child(headlight)

	var bulb := MeshInstance3D.new()
	var bmesh := SphereMesh.new()
	bmesh.radius = 0.12
	bmesh.height = 0.24
	bulb.mesh = bmesh
	bulb.position = Vector3(0, 1.1, -3.65)
	var bulb_mat := _material(Color("ffffff"), 0.1)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color("fff6d6")
	bulb_mat.emission_energy_multiplier = 3.0
	bulb.material_override = bulb_mat
	parent.add_child(bulb)

	# Procedural exhaust particles
	for i in range(5):
		var puff := MeshInstance3D.new()
		var pmesh := SphereMesh.new()
		pmesh.radius = 0.2
		pmesh.height = 0.4
		puff.mesh = pmesh
		var pmat := _material(Color(0.85, 0.88, 0.9, 0.4), 0.9)
		pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material_override = pmat
		parent.add_child(puff)
		smoke_particles.append(puff)
		smoke_data.append({"life": float(i) / 5.0})

func _build_coach_body(parent: Node3D, col: Color, is_rear: bool = false) -> void:
	var body_mat := _material(col, 0.35, 0.1)
	var dark_mat := _material(Color("162428"), 0.5)
	var glass_mat := _material(Color("13303d"), 0.1, 0.3)

	var coach := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(2.15, 1.45, 5.4)
	coach.mesh = cm
	coach.position.y = 1.22
	coach.material_override = body_mat
	parent.add_child(coach)

	# Passenger windows
	for side in [-1.0, 1.0]:
		for i in range(5):
			var win := MeshInstance3D.new()
			var wm := BoxMesh.new()
			wm.size = Vector3(0.04, 0.45, 0.68)
			win.mesh = wm
			win.position = Vector3(side * 1.09, 1.45, -1.8 + i * 0.9)
			win.material_override = glass_mat
			parent.add_child(win)

	# Coach Wheels
	for side in [-1.0, 1.0]:
		for z in [-1.8, -0.9, 0.9, 1.8]:
			var wheel := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.42
			wm.bottom_radius = 0.42
			wm.height = 0.18
			wheel.mesh = wm
			wheel.rotation_degrees.z = 90
			wheel.position = Vector3(side * 1.08, 0.42, z)
			wheel.material_override = dark_mat
			parent.add_child(wheel)
			wheels.append(wheel)

	# Rear Tail / Brake lights on the last coach
	if is_rear:
		brake_light_mat = _material(Color("ff1520"), 0.1)
		brake_light_mat.emission_enabled = true
		brake_light_mat.emission = Color("ff1520")
		brake_light_mat.emission_energy_multiplier = 1.0

		for side in [-0.8, 0.8]:
			var lamp := MeshInstance3D.new()
			var lm := SphereMesh.new()
			lm.radius = 0.1
			lm.height = 0.2
			lamp.mesh = lm
			lamp.position = Vector3(side, 1.1, 2.72)
			lamp.material_override = brake_light_mat
			parent.add_child(lamp)

# ------------------------------------------------------------------------------
# PROCEDURAL ELEPHANT WITH 4-LEG RIG
# ------------------------------------------------------------------------------
func _build_elephant() -> void:
	elephant_root = Node3D.new()
	elephant_root.name = "Elephant"
	elephant_root.position = Vector3(-14, 0, -6.5)
	elephant_root.visible = false
	add_child(elephant_root)

	var skin := _material(Color("6a7170"), 0.9)

	# Body torso
	var body := Node3D.new()
	_add_ellipsoid(body, Vector3(0, 1.4, 0), Vector3(1.5, 1.2, 2.2), skin)
	elephant_root.add_child(body)

	# Head
	var head := Node3D.new()
	head.position = Vector3(0, 1.95, -1.6)
	_add_ellipsoid(head, Vector3.ZERO, Vector3(0.95, 0.95, 1.0), skin)
	elephant_root.add_child(head)

	# Flapping Ears
	for side in [-1.0, 1.0]:
		var ear := Node3D.new()
		ear.position = Vector3(side * 0.9, 0.1, 0.1)
		_add_ellipsoid(ear, Vector3(side * 0.35, 0, 0), Vector3(0.75, 0.85, 0.14), skin)
		head.add_child(ear)
		elephant_ears.append(ear)

	# Trunk
	elephant_trunk = Node3D.new()
	elephant_trunk.position = Vector3(0, -0.4, -0.85)
	_add_ellipsoid(elephant_trunk, Vector3(0, -0.6, 0), Vector3(0.24, 0.85, 0.28), skin)
	head.add_child(elephant_trunk)

	# Tusks
	var tusk_mat := _material(Color("f2ebd9"), 0.3)
	for side in [-0.45, 0.45]:
		var tusk := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.04
		tm.bottom_radius = 0.11
		tm.height = 0.75
		tusk.mesh = tm
		tusk.position = Vector3(side, -0.35, -0.65)
		tusk.rotation_degrees = Vector3(-45, side * 15, 0)
		tusk.material_override = tusk_mat
		head.add_child(tusk)

	# 4 Articulated Legs for walking
	for x in [-0.85, 0.85]:
		for z in [-0.9, 0.9]:
			var leg_pivot := Node3D.new()
			leg_pivot.position = Vector3(x, 1.1, z)
			_add_ellipsoid(leg_pivot, Vector3(0, -0.55, 0), Vector3(0.35, 0.65, 0.38), skin)
			elephant_root.add_child(leg_pivot)
			elephant_legs.append(leg_pivot)

	# Tail
	elephant_tail = Node3D.new()
	elephant_tail.position = Vector3(0, 1.5, 2.15)
	_add_ellipsoid(elephant_tail, Vector3(0, -0.4, 0.1), Vector3(0.08, 0.5, 0.08), skin)
	elephant_root.add_child(elephant_tail)

	# Pulsing Ground Danger Zone Ring
	danger_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.4
	tm.outer_radius = 2.7
	danger_ring.mesh = tm
	danger_ring.position = Vector3(-2.8, 0.05, -7.2)
	danger_ring.rotation_degrees.x = 90
	var ring_mat := _material(Color("ff2233"), 0.2)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color("ff2233")
	ring_mat.emission_energy_multiplier = 2.5
	danger_ring.material_override = ring_mat
	add_child(danger_ring)

# ------------------------------------------------------------------------------
# SIGNALS & CROSSING
# ------------------------------------------------------------------------------
func _build_signals_and_crossing() -> void:
	# Zone 1 Signal Mast
	signal1_lamps = _build_3aspect_signal(Vector3(3.2, 0, -11.0), "Signal_Zone1")

	# Zone 2 Signal Mast
	signal2_lamps = _build_3aspect_signal(Vector3(18.0, 0, 15.0), "Signal_Zone2")

	# Level Crossing & Motorized Boom Barrier
	var crossing_base := Node3D.new()
	crossing_base.position = Vector3(3.5, 0, -5.5)
	var post_mat := _material(Color("323a3d"), 0.5)

	var stanchion := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.4, 1.2, 0.4)
	stanchion.mesh = sm
	stanchion.position.y = 0.6
	stanchion.material_override = post_mat
	crossing_base.add_child(stanchion)

	# Animated Boom Barrier Arm
	barrier_arm = Node3D.new()
	barrier_arm.position = Vector3(0, 1.05, 0)
	var arm_mesh := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(6.2, 0.16, 0.12)
	arm_mesh.mesh = am
	arm_mesh.position = Vector3(-3.1, 0, 0)
	var arm_mat := _material(Color("f2f6f8"), 0.3)
	arm_mesh.material_override = arm_mat
	barrier_arm.add_child(arm_mesh)
	crossing_base.add_child(barrier_arm)

	# Twin Alternating Flasher Lights
	var red_flasher_mat := _material(Color("ff1a26"), 0.1)
	red_flasher_mat.emission_enabled = true
	red_flasher_mat.emission = Color("ff1a26")
	red_flasher_mat.emission_energy_multiplier = 4.0

	for side in [-0.28, 0.28]:
		var light := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.12
		lm.height = 0.24
		light.mesh = lm
		light.position = Vector3(side, 1.5, 0.1)
		light.material_override = red_flasher_mat
		crossing_base.add_child(light)
		barrier_lights.append(light)

	add_child(crossing_base)

func _build_3aspect_signal(pos: Vector3, node_name: String) -> Array[MeshInstance3D]:
	var mast := Node3D.new()
	mast.name = node_name
	mast.position = pos
	var metal := _material(Color("262f33"), 0.4)

	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.08
	pm.bottom_radius = 0.12
	pm.height = 4.2
	pole.mesh = pm
	pole.position.y = 2.1
	pole.material_override = metal
	mast.add_child(pole)

	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.55, 1.45, 0.42)
	head.mesh = hm
	head.position.y = 3.6
	head.material_override = metal
	mast.add_child(head)

	var lamps: Array[MeshInstance3D] = []
	var colors := [Color("ff2233"), Color("ffcc22"), Color("22ff77")]
	var heights := [4.05, 3.6, 3.15]

	for i in range(3):
		var lamp := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.15
		lm.height = 0.3
		lamp.mesh = lm
		lamp.position = Vector3(0, heights[i], 0.22)
		var mat := _material(colors[i], 0.1)
		mat.emission_enabled = true
		mat.emission = colors[i]
		mat.emission_energy_multiplier = 3.5
		lamp.material_override = mat
		lamp.visible = (i == 2) # Start green
		mast.add_child(lamp)
		lamps.append(lamp)

	add_child(mast)
	return lamps

# ------------------------------------------------------------------------------
# CAMERAS
# ------------------------------------------------------------------------------
func _build_cameras() -> void:
	main_camera = Camera3D.new()
	main_camera.name = "MainDirectorCamera"
	main_camera.current = true
	main_camera.fov = 54.0
	main_camera.position = Vector3(0, 28, 38)
	main_camera.rotation_degrees = Vector3(-30, -8, 0)
	add_child(main_camera)

# ------------------------------------------------------------------------------
# HUD (GLASSMORPHISM UI)
# ------------------------------------------------------------------------------
func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	hud_panel = PanelContainer.new()
	hud_panel.position = Vector2(24, 24)
	hud_panel.custom_minimum_size = Vector2(420, 230)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.1, 0.14, 0.88)
	style.border_color = Color(0.25, 0.65, 0.58, 0.85)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	hud_panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(hud_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	hud_panel.add_child(vbox)

	# Header with status indicator
	var hbox_head := HBoxContainer.new()
	var title := Label.new()
	title.text = "RAILWAY DIGITAL TWIN // LIVE CONTROL"
	title.add_theme_color_override("font_color", Color("6ee7b7"))
	title.add_theme_font_size_override("font_size", 13)
	hbox_head.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox_head.add_child(spacer)

	hud_conn_dot = ColorRect.new()
	hud_conn_dot.custom_minimum_size = Vector2(8, 8)
	hud_conn_dot.color = Color("ff5555")
	hbox_head.add_child(hud_conn_dot)

	hud_conn_label = Label.new()
	hud_conn_label.text = "CONNECTING"
	hud_conn_label.add_theme_color_override("font_color", Color("94a3b8"))
	hud_conn_label.add_theme_font_size_override("font_size", 11)
	hbox_head.add_child(hud_conn_label)
	vbox.add_child(hbox_head)

	# Speed readout
	hud_speed_label = Label.new()
	hud_speed_label.add_theme_font_size_override("font_size", 16)
	hud_speed_label.add_theme_color_override("font_color", Color("f8fafc"))
	vbox.add_child(hud_speed_label)

	# Stopping distance bar
	hud_stopping_bar = ProgressBar.new()
	hud_stopping_bar.max_value = 80.0
	hud_stopping_bar.show_percentage = false
	hud_stopping_bar.custom_minimum_size.y = 8
	vbox.add_child(hud_stopping_bar)

	# Zone 1 & Zone 2 Status
	hud_zone1_label = Label.new()
	hud_zone1_label.add_theme_font_size_override("font_size", 12)
	hud_zone1_label.add_theme_color_override("font_color", Color("cbd5e1"))
	vbox.add_child(hud_zone1_label)

	hud_zone2_label = Label.new()
	hud_zone2_label.add_theme_font_size_override("font_size", 12)
	hud_zone2_label.add_theme_color_override("font_color", Color("cbd5e1"))
	vbox.add_child(hud_zone2_label)

	# Camera & mode
	hud_cam_label = Label.new()
	hud_cam_label.add_theme_font_size_override("font_size", 11)
	hud_cam_label.add_theme_color_override("font_color", Color("7dd3fc"))
	vbox.add_child(hud_cam_label)

	# Controls cheat sheet
	var help := Label.new()
	help.text = "SPACE Wildlife  ·  F Sensor Fault  ·  R Reset  ·  ↑/↓ Speed  ·  C Camera  ·  N Day/Night"
	help.add_theme_font_size_override("font_size", 10)
	help.add_theme_color_override("font_color", Color("94a3b8"))
	vbox.add_child(help)

func _update_hud() -> void:
	if not hud_speed_label:
		return

	var stopping_dist := int((current_speed / 3.6) ** 2 / (2.0 * BRAKING_DECEL))
	hud_speed_label.text = "SPEED: %02d km/h  (Target: %02d km/h)  ·  Est. Braking: %d m" % [roundi(current_speed), roundi(target_speed), stopping_dist]
	hud_stopping_bar.value = current_speed

	var z1_sig := "RED" if (wildlife_zone1 or sensor_fault_zone1) else "GREEN"
	var z1_wild := "DETECTED" if wildlife_zone1 else "CLEAR"
	var z1_sens := "FAULT" if sensor_fault_zone1 else "OK"
	hud_zone1_label.text = "ZONE 1 (Forest): Signal %s  |  Wildlife %s  |  Sensor %s" % [z1_sig, z1_wild, z1_sens]

	var z2_sig := "RED" if (wildlife_zone2 or sensor_fault_zone2) else ("YELLOW" if (wildlife_zone1 or sensor_fault_zone1) else "GREEN")
	var z2_wild := "DETECTED" if wildlife_zone2 else "CLEAR"
	hud_zone2_label.text = "ZONE 2 (Tunnel): Signal %s  |  Wildlife %s  |  Current Zone: %s" % [z2_sig, z2_wild, active_zone.to_upper()]

	var cam_names := ["Overview 3D", "Chase Cam", "Driver Cab Front", "Wildlife Crossing"]
	hud_cam_label.text = "CAMERA [C]: %s   ·   TIME [N]: %s" % [cam_names[camera_mode], "NIGHT" if (day_time > 0.5 and day_time < 0.95) else "DAY"]

	hud_conn_dot.color = Color("22c55e") if backend_connected else Color("ef4444")
	hud_conn_label.text = "BACKEND ONLINE" if backend_connected else ("DISCONNECTED: " + api_base)

# ------------------------------------------------------------------------------
# NETWORKING & CONFIG
# ------------------------------------------------------------------------------
func _load_config() -> void:
	var cf := ConfigFile.new()
	var err := cf.load(CONFIG_PATH)
	if err == OK:
		api_base = cf.get_value("network", "api_base", "http://127.0.0.1:3001")
		active_zone = cf.get_value("simulation", "zone", "zone1")
		target_speed = float(cf.get_value("simulation", "default_speed", 48.0))
		current_speed = target_speed

func _send_event(kind: String, zone: String) -> void:
	var payload := {
		"type": kind,
		"zone": zone,
		"source": "godot-twin"
	}
	_http_post("/api/event", payload)

func _send_speed() -> void:
	var payload := {
		"type": "SPEED",
		"zone": active_zone,
		"speedKmh": target_speed,
		"source": "godot-twin"
	}
	_http_post("/api/event", payload)

func _send_telemetry() -> void:
	var payload := {
		"type": "SIMULATION_TELEMETRY",
		"zone": active_zone,
		"speedKmh": roundi(current_speed),
		"trainPresent": true,
		"wildlifeDetected": (wildlife_zone1 if active_zone == "zone1" else wildlife_zone2),
		"sensorHealthy": (not sensor_fault_zone1 if active_zone == "zone1" else not sensor_fault_zone2),
		"source": "godot-twin"
	}
	_http_post("/api/event", payload)

func _ping_backend() -> void:
	var req := HTTPRequest.new()
	req.timeout = 2.0
	add_child(req)
	req.request_completed.connect(func(_res: int, code: int, _h: PackedStringArray, _b: PackedByteArray):
		backend_connected = (code == 200)
		req.queue_free()
	)
	var err := req.request(api_base + "/api/health")
	if err != OK:
		backend_connected = false
		req.queue_free()

func _http_post(endpoint: String, payload: Dictionary) -> void:
	var req := HTTPRequest.new()
	req.timeout = 2.0
	add_child(req)
	req.request_completed.connect(func(_res: int, code: int, _h: PackedStringArray, _b: PackedByteArray):
		if code == 200:
			backend_connected = true
		req.queue_free()
	)
	var headers := ["Content-Type: application/json"]
	var err := req.request(api_base + endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		req.queue_free()

# ------------------------------------------------------------------------------
# UTILITIES
# ------------------------------------------------------------------------------
func _add_beam(a: Vector3, b: Vector3, width: float, height: float, mat: Material, node_name: String) -> void:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	var bm := BoxMesh.new()
	bm.size = Vector3(width, height, a.distance_to(b))
	inst.mesh = bm
	inst.position = (a + b) * 0.5
	inst.look_at_from_position(inst.position, b, Vector3.UP)
	inst.material_override = mat
	add_child(inst)

func _add_ellipsoid(parent: Node3D, pos: Vector3, scale_val: Vector3, mat: Material) -> void:
	var inst := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	inst.mesh = sm
	inst.position = pos
	inst.scale = scale_val
	inst.material_override = mat
	parent.add_child(inst)

func _material(col: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = rough
	mat.metallic = metal
	return mat
