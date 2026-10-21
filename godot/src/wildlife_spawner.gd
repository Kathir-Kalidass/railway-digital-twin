extends Node3D
class_name WildlifeSpawner

@export var species := ["deer", "elephant"]
@export var use_procedural := true
@export var use_lts_models := true
@export var underpass_path: NodePath
@export var track_path: NodePath

const ANIMAL_MODELS := {
	"deer": "res://assets/models/animals/deer.glb",
	"elephant": "res://assets/models/animals/elephant.glb",
}
const ANIMAL_VISUAL := preload("res://src/animal_visual.gd")

var _animals: Array[Area3D] = []


func spawn(species_name: String) -> Area3D:
	var animal := Area3D.new()
	animal.name = species_name
	animal.add_to_group("wildlife")
	animal.set_meta("species", species_name)

	var has_model := _attach_lts_model(animal, species_name)
	if not has_model and use_procedural:
		_attach_capsule(animal, species_name)

	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	if species_name == "elephant":
		shape.radius = 1.0
		shape.height = 2.4
	else:
		shape.radius = 0.45
		shape.height = 1.6
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	animal.add_child(collision)

	add_child(animal)
	_animals.append(animal)
	return animal


func _attach_lts_model(animal: Area3D, species_name: String) -> bool:
	if not use_lts_models:
		return false
	var path: String = ANIMAL_MODELS.get(species_name, "")
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		return false
	model.rotation.y = PI / 2.0
	var visual := Node3D.new()
	visual.name = "AnimalModel"
	visual.set_script(ANIMAL_VISUAL)
	visual.add_child(model)
	animal.add_child(visual)
	animal.set_meta("model", "lts")
	return true


func _attach_capsule(animal: Area3D, species_name: String) -> void:
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
	visual.name = "CapsuleFallback"
	visual.mesh = mesh
	visual.material_override = mat
	visual.position.y = mesh.height * 0.5
	animal.add_child(visual)
