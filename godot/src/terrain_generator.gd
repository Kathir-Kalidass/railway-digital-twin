extends Node3D
class_name TerrainGenerator

@export var size := 500.0
@export var height := 10.0
@export var stream_width := 30.0
@export var seed := 42

func _ready() -> void:
	generate()

func generate() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	mesh.subdivide_width = 32
	mesh.subdivide_depth = 32
	var surf := SurfaceTool.new()
	surf.create_from(mesh, 0)
	var data = surf.commit_to_arrays()
	var verts = data[ArrayMesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed
	for i in verts.size():
		var v: Vector3 = verts[i]
		var h = noise.get_noise_2d(v.x, v.z) * height
		if v.z > -stream_width/2 and v.z < stream_width/2 and v.x > size*-0.5 and v.x < size*0.5:
			h = min(h, -0.5)
		v.y = h
		verts[i] = v
	data[ArrayMesh.ARRAY_VERTEX] = verts
	var mi := MeshInstance3D.new()
	mi.mesh = ArrayMesh.new()
	mi.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
	mi.material_override = StandardMaterial3D.new()
	add_child(mi)
