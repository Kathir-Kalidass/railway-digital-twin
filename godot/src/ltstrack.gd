class_name LTSTrack
extends Rail

@export var max_speed_kmh := 80.0
@export var sleeper_spacing_m := 2.5
@export var track_gauge_m := 1.435
@export var straight_length_m := 250.0
@export var curve_radius_m := 120.0
@export var parallel_curve_radius_m := 116.0

func _ready() -> void:
	length = 2.0 * straight_length_m + TAU * curve_radius_m
	radius = curve_radius_m
	_build_track_visuals()


func map_to_parallel(distance_m: float) -> float:
	var s := straight_length_m
	var r := curve_radius_m
	var pr := parallel_curve_radius_m if parallel_curve_radius_m > 0.0 else r
	var parallel_length := 2.0 * s + TAU * pr
	var d := fposmod(distance_m, parallel_length)
	if d <= s:
		return d
	if d <= s + PI * pr:
		return s + (d - s) * r / pr
	if d <= 2.0 * s + PI * pr:
		return d - PI * (pr - r)
	var west_offset := d - (2.0 * s + PI * pr)
	return fposmod(2.0 * s + PI * r + west_offset * r / pr, length)


func get_local_transform_at_distance(distance_m: float) -> Transform3D:
	var s := straight_length_m
	var r := curve_radius_m
	var d := fposmod(distance_m, length)
	var origin := Vector3.ZERO
	var forward := Vector3.RIGHT
	if d <= s:
		origin = Vector3(-s * 0.5 + d, 0.0, r)
		forward = Vector3.RIGHT
	elif d <= s + PI * r:
		var theta := PI * 0.5 - (d - s) / r
		origin = Vector3(s * 0.5 + r * cos(theta), 0.0, r * sin(theta))
		forward = Vector3(sin(theta), 0.0, -cos(theta))
	elif d <= 2.0 * s + PI * r:
		var along := d - (s + PI * r)
		origin = Vector3(s * 0.5 - along, 0.0, -r)
		forward = Vector3.LEFT
	else:
		var theta := -PI * 0.5 - (d - (2.0 * s + PI * r)) / r
		origin = Vector3(-s * 0.5 + r * cos(theta), 0.0, r * sin(theta))
		forward = Vector3(sin(theta), 0.0, -cos(theta))
	var basis := Basis(forward.normalized(), Vector3.UP, forward.cross(Vector3.UP).normalized())
	return Transform3D(basis, origin)


func get_shifted_local_pos_at_distance(distance_m: float, shift: float) -> Vector3:
	var pose := get_local_transform_at_distance(distance_m)
	return pose.origin + pose.basis.z * shift


func get_track_info_at(distance_m: float) -> Dictionary:
	var pose := get_global_transform_at_distance(clampf(distance_m, 0.0, length))
	return {
		"position": pose.origin,
		"forward": pose.basis.x.normalized(),
		"up": pose.basis.y.normalized(),
		"side": pose.basis.z.normalized(),
		"max_speed_kmh": max_speed_kmh,
	}


func _build_track_visuals() -> void:
	var sleeper_mesh := BoxMesh.new()
	sleeper_mesh.size = Vector3(0.18, 0.16, track_gauge_m + 1.1)
	sleeper_mesh.material = _material(Color(0.22, 0.13, 0.08), 0.9)

	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(1.1, 0.16, 0.13)
	rail_mesh.material = _material(Color(0.38, 0.42, 0.44), 0.28, 0.72)

	var sleeper_transforms: Array[Transform3D] = []
	var rail_transforms: Array[Transform3D] = []
	var distance := 0.0
	while distance <= length:
		var pose := get_local_transform_at_distance(distance)
		var sleeper_pose := pose
		sleeper_pose.origin.y -= 0.12
		sleeper_transforms.append(sleeper_pose)

		for side in [-1.0, 1.0]:
			var rail_pose := pose
			rail_pose.origin += pose.basis.z * side * track_gauge_m * 0.5
			rail_pose.origin.y += 0.02
			rail_transforms.append(rail_pose)
		distance += sleeper_spacing_m

	_add_multimesh("Sleepers", sleeper_mesh, sleeper_transforms)
	_add_multimesh("Rails", rail_mesh, rail_transforms)


func _add_multimesh(node_name: String, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = mesh
	instances.instance_count = transforms.size()
	for index in transforms.size():
		instances.set_instance_transform(index, transforms[index])

	var visual := MultiMeshInstance3D.new()
	visual.name = node_name
	visual.multimesh = instances
	add_child(visual)


func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result
