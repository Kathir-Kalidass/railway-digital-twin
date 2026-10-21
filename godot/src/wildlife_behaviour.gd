extends Node
class_name WildlifeBehaviour

@export var spawner_path: NodePath
@export var underpass_path: NodePath
@export var track_path: NodePath
@export var prefer_underpass := 0.8
@export var speed_mps := 1.0
@export var crossing_zone_distance := 30.0

var _active_animals := []

func _ready() -> void:
	pass

func _physics_process(delta: float) -> void:
	for animal in _active_animals:
		if is_instance_valid(animal):
			var dir := Vector3(0, 0, 1)
			animal.global_transform.origin += dir * speed_mps * delta
			if animal.global_transform.origin.z > crossing_zone_distance:
				animal.queue_free()
				_active_animals.erase(animal)

func trigger_crossing(species_name: String) -> void:
	var spawner: WildlifeSpawner = get_node_or_null(spawner_path)
	if not spawner:
		return
	var animal = spawner.spawn(species_name)
	if not animal:
		return
	animal.visible = true
	if randf() < prefer_underpass and underpass_path:
		var up = get_node_or_null(underpass_path)
		if up:
			animal.global_transform.origin = up.global_transform.origin + Vector3(0, 0.0, -10)
			animal.look_at(up.global_transform.origin + Vector3(0, 0.5, 0))
			_active_animals.append(animal)
		return
	animal.global_transform.origin = Vector3(randf_range(-10, 10), 0.0, -crossing_zone_distance/2)
	animal.rotation.y = deg_to_rad(180)
	_active_animals.append(animal)
