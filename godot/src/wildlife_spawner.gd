extends Node3D
class_name WildlifeSpawner

@export var species := ["deer", "elephant"]
@export var use_procedural := true
@export var underpass_path: NodePath
@export var track_path: NodePath

var _animals: Array[Area3D] = []

func spawn(species_name: String) -> Area3D:
	if use_procedural:
		var animal := Area3D.new()
		animal.name = species_name
		animal.add_to_group("wildlife")
		animal.set_meta("species", species_name)
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.4
		mesh.height = 1.2
		var mat := StandardMaterial3D.new()
		if species_name == "elephant":
			mat.albedo_color = Color(0.6, 0.6, 0.6)
			mesh.radius = 0.8
			mesh.height = 2.0
		else:
			mat.albedo_color = Color(0.55, 0.4, 0.25)
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = mat
		visual.position.y = mesh.height * 0.5
		animal.add_child(visual)

		var collision := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = mesh.radius
		shape.height = mesh.height
		collision.shape = shape
		collision.position.y = mesh.height * 0.5
		animal.add_child(collision)

		add_child(animal)
		_animals.append(animal)
		return animal
	return null
