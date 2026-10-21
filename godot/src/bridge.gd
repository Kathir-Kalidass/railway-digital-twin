extends Node3D
class_name Bridge

## Road bridge over the river. The deck spans the channel; abutments, piers,
## guard rails, and approach slabs keep it structurally legible.

@export var span := 44.0
@export var road_width := 8.0
@export var deck_height := 0.55


func _ready() -> void:
	build()


func build() -> void:
	var concrete := _material(Color(0.48, 0.49, 0.47), 0.9)
	var steel := _material(Color(0.28, 0.31, 0.33), 0.45, 0.55)
	var asphalt := _material(Color(0.13, 0.14, 0.15), 0.96)

	_box("Deck", Vector3(road_width, 0.45, span), Vector3(0.0, deck_height, 0.0), concrete)
	_box("RoadSurface", Vector3(road_width - 0.8, 0.08, span - 1.0), Vector3(0.0, deck_height + 0.27, 0.0), asphalt)

	for side in [-1.0, 1.0]:
		_box("Abutment", Vector3(road_width + 3.0, 3.2, 2.2),
			Vector3(0.0, deck_height - 1.5, side * (span * 0.5 - 1.1)), concrete)
		for z in [-8.0, 8.0]:
			for x in [-2.8, 2.8]:
				_box("Pier", Vector3(1.0, 4.2, 1.0), Vector3(x, -2.05, z), concrete)

		for z in range(-18, 19, 4):
			_box("RailingPost", Vector3(0.12, 1.1, 0.12),
				Vector3(side * (road_width * 0.5 - 0.12), deck_height + 0.9, float(z)), steel)
		for rail_y in [0.95, 1.35]:
			_box("Railing", Vector3(0.08, 0.08, span - 1.0),
				Vector3(side * (road_width * 0.5 - 0.12), deck_height + rail_y, 0.0), steel)

	for side in [-1.0, 1.0]:
		_box("Approach", Vector3(road_width, 0.12, 12.0),
			Vector3(0.0, 0.08, side * (span * 0.5 + 5.0)), asphalt)


func _box(node_name: String, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	add_child(instance)
	return instance


func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result
