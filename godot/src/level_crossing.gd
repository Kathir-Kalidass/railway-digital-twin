extends Node3D
class_name LevelCrossing

## Road level crossing on the loop. The alarm closes a boom barrier across
## the track and flashes two red lamps while wildlife is near or on the rails.

@export var track_path: NodePath
@export var track_paths: Array[NodePath] = []
@export var track_registry_path: NodePath = NodePath("../../TrackRegistry")
@export var distance_m := 260.0
@export var track_gauge_m := 1.435
@export var road_width_m := 8.0

var _track_poses: Array[Transform3D] = []

var _alarm := false
var _down := 0.0
var _pivots: Array[Node3D] = []
var _lamps: Array[MeshInstance3D] = []
var _flash_time := 0.0

const RED := Color(0.78, 0.04, 0.03)
const WHITE := Color(0.94, 0.94, 0.9)
const STEEL := Color(0.34, 0.36, 0.38)
const CONCRETE := Color(0.48, 0.49, 0.48)


func _ready() -> void:
	_place()
	_build()


func _place() -> void:
	_track_poses.clear()
	var tracks := _resolve_tracks()
	if tracks.is_empty():
		return
	var base := tracks[0]
	for track in tracks:
		var track_distance := distance_m if track == base else track.map_to_parallel(distance_m)
		_track_poses.append(track.get_global_transform_at_distance(track_distance))
	global_transform = _track_poses[0]


func _resolve_tracks() -> Array[LTSTrack]:
	var result: Array[LTSTrack] = []
	for path in track_paths:
		var track := get_node_or_null(path) as LTSTrack
		if track != null:
			result.append(track)
	if result.is_empty():
		var registry := get_node_or_null(track_registry_path) as TrackRegistry
		if registry != null:
			result = registry.tracks()
	if result.is_empty():
		var fallback := get_node_or_null(track_path) as LTSTrack
		if fallback != null:
			result.append(fallback)
	return result


func _build() -> void:
	var asphalt := _material(Color(0.13, 0.14, 0.15), 0.96)
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(10.0, 0.12, 13.0)
	pad.mesh = pad_mesh
	pad.material_override = asphalt
	pad.position = _pad_local_position()
	add_child(pad)
	_build_barrier_set(pad.position.z, -1.0)
	_build_barrier_set(pad.position.z, 1.0)


func _pad_local_position() -> Vector3:
	var local := Vector3(0.0, -0.06, 0.0)
	if _track_poses.size() > 1:
		var centre := Vector3.ZERO
		for pose in _track_poses:
			centre += global_transform.affine_inverse() * pose.origin
		centre /= float(_track_poses.size())
		local.z = centre.z
	return local


func _build_barrier_set(corridor_centre_z: float, side: float) -> void:
	var steel := _material(STEEL, 0.45, 0.5)
	var concrete := _material(CONCRETE, 0.9)
	var red := _material(RED, 0.55)
	var white := _material(WHITE, 0.55)
	var root := Node3D.new()
	root.name = "BarrierSet%d" % (0 if side < 0.0 else 1)
	add_child(root)
	var post_z := corridor_centre_z + side * 4.6
	var pillar_z := corridor_centre_z + side * 6.0

	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.11
	post_mesh.bottom_radius = 0.13
	post_mesh.height = 3.2
	post.mesh = post_mesh
	post.material_override = steel
	post.position = Vector3(0.0, 1.6, post_z)
	root.add_child(post)

	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.55, 0.18, 0.55)
	base.mesh = base_mesh
	base.material_override = concrete
	base.position = Vector3(0.0, 0.09, post_z)
	root.add_child(base)

	var housing := MeshInstance3D.new()
	var housing_mesh := BoxMesh.new()
	housing_mesh.size = Vector3(0.72, 0.62, 0.3)
	housing.mesh = housing_mesh
	housing.material_override = steel
	housing.position = Vector3(0.0, 3.35, post_z)
	root.add_child(housing)

	for lamp_x in [-0.2, 0.2]:
		var lamp := MeshInstance3D.new()
		var lamp_mesh := SphereMesh.new()
		lamp_mesh.radius = 0.13
		lamp_mesh.height = 0.26
		lamp.mesh = lamp_mesh
		lamp.material_override = red
		lamp.position = Vector3(lamp_x, 3.35, post_z + (0.18 if side > 0.0 else -0.18))
		lamp.visible = false
		root.add_child(lamp)
		_lamps.append(lamp)

	var sign_root := Node3D.new()
	sign_root.position = Vector3(0.0, 2.65, post_z + (0.08 if side > 0.0 else -0.08))
	root.add_child(sign_root)
	for angle in [-PI / 4.0, PI / 4.0]:
		var board := MeshInstance3D.new()
		var board_mesh := BoxMesh.new()
		board_mesh.size = Vector3(0.9, 0.12, 0.05)
		board.mesh = board_mesh
		board.material_override = red
		board.rotation.z = angle
		sign_root.add_child(board)

	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(0.55, 0.06, 0.04)
	stripe.mesh = stripe_mesh
	stripe.material_override = white
	stripe.position = Vector3(0.0, -0.7, post_z + (0.05 if side > 0.0 else -0.05))
	root.add_child(stripe)

	var pillar := MeshInstance3D.new()
	var pillar_mesh := BoxMesh.new()
	pillar_mesh.size = Vector3(0.5, 1.2, 0.5)
	pillar.mesh = pillar_mesh
	pillar.material_override = concrete
	pillar.position = Vector3(-4.6, 0.6, pillar_z)
	root.add_child(pillar)

	var pivot := Node3D.new()
	pivot.name = "BarrierPivot"
	pivot.position = Vector3(-4.6, 1.05, pillar_z)
	root.add_child(pivot)
	_pivots.append(pivot)

	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(8.2, 0.2, 0.2)
	arm.mesh = arm_mesh
	arm.material_override = red
	arm.position = Vector3(4.1, 0.0, 0.0)
	pivot.add_child(arm)

	for stripe_x in [1.4, 3.4, 5.4]:
		var band := MeshInstance3D.new()
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(0.8, 0.22, 0.22)
		band.mesh = band_mesh
		band.material_override = white
		band.position = Vector3(float(stripe_x), 0.0, 0.0)
		pivot.add_child(band)

	var tip := MeshInstance3D.new()
	var tip_mesh := BoxMesh.new()
	tip_mesh.size = Vector3(0.7, 0.18, 0.18)
	tip.mesh = tip_mesh
	tip.material_override = white
	tip.position = Vector3(8.2, 0.0, 0.0)
	pivot.add_child(tip)

	pivot.rotation.z = deg_to_rad(82.0)


func _process(delta: float) -> void:
	var target := 1.0 if _alarm else 0.0
	_down = move_toward(_down, target, delta * 1.8)
	for pivot in _pivots:
		pivot.rotation.z = deg_to_rad(82.0) * (1.0 - _down)

	_flash_time += delta
	var flash_on := _alarm and int(_flash_time * 3.0) % 2 == 0
	for lamp in _lamps:
		lamp.visible = flash_on


func set_alarm(active: bool) -> void:
	_alarm = active


func is_alarm_active() -> bool:
	return _alarm


func is_barrier_down() -> bool:
	return _down > 0.9


func get_crossing_point() -> Vector3:
	return global_position


func get_crossing_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for pose in _track_poses:
		result.append(pose.origin)
	return result


func get_crossing_pose() -> Transform3D:
	return global_transform


func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result
