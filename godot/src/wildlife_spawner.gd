extends Node3D
class_name WildlifeSpawner

@export var species := ["deer", "elephant"]
@export var use_procedural := true
@export var underpass_path: NodePath
@export var track_path: NodePath

var _animals := []

func spawn(species_name: String) -> Node3D:
	if use_procedural:
		var body := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.4
		mesh.height = 1.2
		body.mesh = mesh
		var mat := StandardMaterial3D.new()
		if species_name == "elephant":
			mat.albedo_color = Color(0.6, 0.6, 0.6)
			mesh.radius = 0.8
			mesh.height = 2.0
		else:
			mat.albedo_color = Color(0.55, 0.4, 0.25)
		body.material_override = mat
		body.name = species_name
		add_child(body)
		_animals.append(body)
		return body
	return null
