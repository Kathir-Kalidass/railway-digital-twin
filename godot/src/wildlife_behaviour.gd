extends Node
class_name WildlifeBehaviour

@export var spawner_path: NodePath
@export var underpass_path: NodePath
@export var prefer_underpass := 0.8

func _ready() -> void:
	pass

func trigger_crossing(species_name: String) -> void:
	var spawner: WildlifeSpawner = get_node_or_null(spawner_path)
	if not spawner:
		return
	var animal = spawner.spawn(species_name)
	if not animal:
		return
	if randf() < prefer_underpass and underpass_path:
		var up = get_node_or_null(underpass_path)
		if up:
			animal.global_transform.origin = up.global_transform.origin + Vector3(0, 0.5, -10)
		return
	animal.global_transform.origin = Vector3(randf_range(-20, 20), 0.5, randf_range(-5, 5))
