extends Node3D
class_name TerrainGenerator

@export var size := 500.0
@export var height := 10.0
@export var stream_width := 30.0
@export var seed := 42
@export var track_path: NodePath
@export var flatten_radius := 15.0

var _noise := FastNoiseLite.new()
var _track_samples := PackedVector3Array()


func _ready() -> void:
	_noise.seed = seed
	_collect_track_samples()
	generate()


func height_at(x: float, z: float) -> float:
	var value := _noise.get_noise_2d(x, z) * height
	if z > -stream_width / 2.0 and z < stream_width / 2.0 and x > -size * 0.5 and x < size * 0.5:
		value = minf(value, -0.5)
	if _track_samples.is_empty():
		return value
	var distance := _track_distance(x, z)
	if distance >= flatten_radius:
		return value
	var factor := 1.0 - smoothstep(flatten_radius * 0.35, flatten_radius, distance)
	return lerpf(value, -0.18, factor)


func _collect_track_samples() -> void:
	var track := get_node_or_null(track_path) as LTSTrack
	if track == null:
		track = get_node_or_null("../../Track") as LTSTrack
	if track == null:
		return
	var distance := 0.0
	while distance <= track.length:
		_track_samples.append(track.get_global_transform_at_distance(distance).origin)
		distance += 4.0


func _grass_texture() -> ImageTexture:
	var image := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = seed + 11
	noise.frequency = 0.045
	for y in 256:
		for x in 256:
			var value := 0.78 + noise.get_noise_2d(x, y) * 0.22
			image.set_pixel(x, y, Color(value, value, value))
	return ImageTexture.create_from_image(image)


func _track_distance(x: float, z: float) -> float:
	var best := INF
	for point in _track_samples:
		var dx := x - point.x
		var dz := z - point.z
		var candidate := dx * dx + dz * dz
		if candidate < best:
			best = candidate
	return sqrt(best)


func generate() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	mesh.subdivide_width = 64
	mesh.subdivide_depth = 64
	var surf := SurfaceTool.new()
	surf.create_from(mesh, 0)
	var data = surf.commit_to_arrays()
	var verts = data[ArrayMesh.ARRAY_VERTEX]
	for i in verts.size():
		var v: Vector3 = verts[i]
		v.y = height_at(v.x, v.z)
		verts[i] = v
	data[ArrayMesh.ARRAY_VERTEX] = verts
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = ArrayMesh.new()
	mi.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.12, 0.24, 0.10)
	ground_material.roughness = 0.96
	ground_material.albedo_texture = _grass_texture()
	ground_material.uv1_triplanar = true
	ground_material.uv1_scale = Vector3(0.18, 0.18, 0.18)
	mi.material_override = ground_material
	add_child(mi)
