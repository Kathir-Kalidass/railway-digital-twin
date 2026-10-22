extends Node3D

@onready var track: LTSTrack = $Track
@onready var train: Node3D = $Train
@export var initial_target_speed_kmh := 54.0
@export var space_wildlife_lead_m := 120.0

var follow_camera: Camera3D

func _ready() -> void:
	train.set_target_speed_kmh(initial_target_speed_kmh)
	_configure_lighting()
	follow_camera = Camera3D.new()
	follow_camera.name = "FollowCamera"
	follow_camera.current = true
	follow_camera.fov = 62.0
	follow_camera.near = 0.1
	follow_camera.far = 1200.0
	add_child(follow_camera)
	_update_camera(1.0)


func _process(delta: float) -> void:
	_update_camera(clampf(delta * 4.0, 0.0, 1.0))


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		train.set_target_speed_kmh(train.get_target_speed_kmh() + 10.0)
	elif event.is_action_pressed("ui_down"):
		train.set_target_speed_kmh(train.get_target_speed_kmh() - 10.0)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		spawn_wildlife_ahead()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		var director := get_node_or_null("CameraDirector") as CameraDirector
		if director:
			director.cycle()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_N:
		var atmosphere := get_node_or_null("WorldWildlife/Atmosphere") as Atmosphere
		if atmosphere:
			atmosphere.toggle()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		var scenario := get_node_or_null("ScenarioDirector") as ScenarioDirector
		if scenario:
			scenario.run_reel()
	elif event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_TAB or event.keycode == KEY_T):
		var hud := get_node_or_null("HUD") as TwinHUD
		if hud:
			hud.cycle_selected_train()


func spawn_wildlife_ahead() -> Dictionary:
	var selected := train as LTSTrain
	if not is_instance_valid(selected):
		return {}
	var director := get_node_or_null("WorldWildlife/WildlifeDirector") as WildlifeDirector
	if is_instance_valid(director):
		return director.trigger_proximity_event(
			selected.train_id,
			selected.line_id,
			selected.get_track_position_m(),
			selected.travel_sign,
			space_wildlife_lead_m,
			"deer",
			1
		)
	var behaviour := get_node_or_null("WorldWildlife/WildlifeBehaviour") as WildlifeBehaviour
	if is_instance_valid(behaviour):
		var track_len := selected.get_track_length_m()
		var distance := fposmod(selected.get_track_position_m() + space_wildlife_lead_m * selected.travel_sign, track_len)
		behaviour.trigger_crossing_at(selected.line_id, distance, "deer")
	return {}


func set_target_train(target_train: Node3D) -> void:
	if not is_instance_valid(target_train):
		return
	train = target_train
	if train.get("track_path") != null:
		var t_node := train.get_node_or_null(train.get("track_path")) as LTSTrack
		if is_instance_valid(t_node):
			track = t_node


func _update_camera(weight: float) -> void:
	var track_info := track.get_track_info_at(train.get_track_position_m())
	var forward: Vector3 = track_info["forward"]
	var up: Vector3 = track_info["up"]
	var side: Vector3 = track_info["side"]
	var locomotive := train.get_node_or_null("Locomotive") as Node3D
	var train_position := train.global_position
	if locomotive:
		train_position = locomotive.global_position
	var target_position: Vector3 = train_position - forward * 30.0 + up * 11.0 + side * 12.0
	follow_camera.global_position = follow_camera.global_position.lerp(target_position, weight)
	follow_camera.look_at(train_position + up * 2.0, up)


func _configure_lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.18, 0.36, 0.62)
	sky_material.sky_horizon_color = Color(0.58, 0.70, 0.82)
	sky_material.ground_bottom_color = Color(0.16, 0.20, 0.17)
	sky_material.ground_horizon_color = Color(0.55, 0.64, 0.70)
	sky_material.sun_angle_max = 20.0
	environment.sky.sky_material = sky_material
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.66, 0.82)
	environment.ambient_light_energy = 0.24
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.08
	environment.adjustment_contrast = 1.03
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.58, 0.68, 0.78)
	environment.fog_density = 0.0005
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	var sunlight := DirectionalLight3D.new()
	sunlight.name = "Sunlight"
	sunlight.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sunlight.light_energy = 1.12
	sunlight.light_color = Color(1.0, 0.96, 0.9)
	sunlight.shadow_enabled = true
	add_child(sunlight)
