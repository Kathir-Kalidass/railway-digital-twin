class_name LTSTrack
extends Rail

@export var max_speed_kmh := 80.0
@export var sleeper_spacing_m := 2.5
@export var track_gauge_m := 1.435

func _ready() -> void:
	_build_track_visuals()


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
