extends Node
class_name WildlifeBehaviour

## Direct, visible wildlife crossings. Animals walk from one side of the
## fixed level crossing, pause on the track, then continue. The safety
## controller turns that movement into warning/stop limits.

@export var spawner_path: NodePath
@export var underpass_path: NodePath
@export var track_path: NodePath
@export var train_path: NodePath
@export var crossing_path: NodePath
@export var auto_crossing_enabled := true
@export var initial_delay_sec := 4.0
@export var cooldown_sec := 30.0
@export var crossing_distance_m := 260.0
@export var crossing_lead_distance_m := 280.0
@export var crossing_min_distance_m := 80.0
@export var crossing_side_offset_m := 12.0
@export var speed_mps := 2.5
@export var dwell_on_track_sec := 8.0
@export var species_cycle := ["deer", "elephant"]

var _spawner: WildlifeSpawner
var _track: LTSTrack
var _train: LTSTrain
var _crossing: Node3D
var _active_animals: Array[Area3D] = []
var _delay_remaining := 0.0
var _cooldown_remaining := 0.0
var _species_index := 0


func _ready() -> void:
	_spawner = get_node_or_null(spawner_path) as WildlifeSpawner
	_track = get_node_or_null(track_path) as LTSTrack
	_train = get_node_or_null(train_path) as LTSTrain
	_crossing = get_node_or_null(crossing_path)
	_delay_remaining = initial_delay_sec


func _physics_process(delta: float) -> void:
	if auto_crossing_enabled:
		_delay_remaining = maxf(0.0, _delay_remaining - delta)
		_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
		if _delay_remaining <= 0.0 and _cooldown_remaining <= 0.0 and _train_is_approaching():
			var species: String = species_cycle[_species_index % species_cycle.size()]
			_species_index += 1
			_trigger_automatic(species)

	_advance_animals(delta)


func trigger_crossing(species_name: String) -> Area3D:
	if not is_instance_valid(_spawner):
		return null
	var point := get_crossing_point()
	var pose := get_crossing_pose()
	var side := pose.basis.z.normalized()
	if side.length_squared() < 0.1:
		side = Vector3.FORWARD

	var start := point - side * crossing_side_offset_m
	var finish := point + side * crossing_side_offset_m
	start.y = point.y
	finish.y = point.y

	var animal := _spawner.spawn(species_name)
	if animal == null:
		return null
	animal.visible = true
	animal.global_position = start
	animal.set_meta("crossing_point", point)
	animal.set_meta("ground_y", point.y)
	animal.set_meta("target_position", point)
	animal.set_meta("end_position", finish)
	animal.set_meta("dwell_remaining", dwell_on_track_sec)
	animal.set_meta("dwelled", false)
	_face(animal, point - start)
	_active_animals.append(animal)
	return animal


func get_active_animals() -> Array[Area3D]:
	return _active_animals


func get_crossing_point() -> Vector3:
	if is_instance_valid(_crossing) and _crossing.has_method("get_crossing_point"):
		return _crossing.call("get_crossing_point")
	if is_instance_valid(_track):
		return _track.get_global_transform_at_distance(crossing_distance_m).origin
	if get_parent() is Node3D:
		return (get_parent() as Node3D).global_position
	return Vector3.ZERO


func get_crossing_pose() -> Transform3D:
	if is_instance_valid(_crossing) and _crossing.has_method("get_crossing_pose"):
		return _crossing.call("get_crossing_pose")
	if is_instance_valid(_track):
		return _track.get_global_transform_at_distance(crossing_distance_m)
	if get_parent() is Node3D:
		return (get_parent() as Node3D).global_transform
	return Transform3D(Basis(), get_crossing_point())


func get_hazard_snapshot(warning_distance_m: float, stop_distance_m: float) -> Dictionary:
	var nearest := INF
	var nearest_species := "deer"
	var count := 0
	var on_track := false

	for animal in _active_animals:
		if not is_instance_valid(animal):
			continue
		count += 1
		if not animal.has_meta("crossing_point"):
			continue
		var point: Vector3 = animal.get_meta("crossing_point")
		var distance := Vector2(animal.global_position.x - point.x, animal.global_position.z - point.z).length()
		if distance < nearest:
			nearest = distance
			nearest_species = str(animal.get_meta("species", "deer"))
		if distance <= stop_distance_m:
			on_track = true

	var state := "CLEAR"
	if on_track:
		state = "STOP"
	elif nearest <= warning_distance_m:
		state = "WARN"

	return {
		"state": state,
		"species": nearest_species,
		"count": count,
		"on_track": on_track,
		"nearest_m": nearest,
	}


func _trigger_automatic(species_name: String) -> void:
	trigger_crossing(species_name)
	_cooldown_remaining = cooldown_sec


func _train_is_approaching() -> bool:
	if not is_instance_valid(_train) or not is_instance_valid(_track) or _track.length <= 0.0:
		return false
	var distance_to_crossing := fposmod(crossing_distance_m - _train.get_track_position_m(), _track.length)
	return distance_to_crossing >= crossing_min_distance_m and distance_to_crossing <= crossing_lead_distance_m


func _advance_animals(delta: float) -> void:
	for animal in _active_animals.duplicate():
		if not is_instance_valid(animal):
			_active_animals.erase(animal)
			continue

		var target: Vector3 = animal.get_meta("target_position", animal.global_position)
		var current: Vector3 = animal.global_position
		var offset: Vector3 = target - current
		offset.y = 0.0
		var distance: float = offset.length()

		if not bool(animal.get_meta("dwelled", false)) and distance < 0.75:
			var remaining := float(animal.get_meta("dwell_remaining", 0.0)) - delta
			animal.set_meta("dwell_remaining", remaining)
			if remaining <= 0.0:
				animal.set_meta("dwelled", true)
				animal.set_meta("target_position", animal.get_meta("end_position", current))
			continue

		if distance > 0.001:
			current += offset / distance * minf(speed_mps * delta, distance)
			current.y = float(animal.get_meta("ground_y", current.y))
			animal.global_position = current
			_face(animal, offset)

		if bool(animal.get_meta("dwelled", false)) and distance < 0.5:
			_active_animals.erase(animal)
			animal.queue_free()


func _face(animal: Area3D, direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return
	animal.look_at(animal.global_position + direction, Vector3.UP)
