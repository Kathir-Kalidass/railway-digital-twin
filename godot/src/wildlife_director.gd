class_name WildlifeDirector
extends Node

## Replaces fixed-crossing wildlife events with deterministic, randomized
## proximity triggers (80–280 m ahead of approaching trains) across both loops.

@export var seed_value := 20261022
@export var initial_delay_sec := 4.0
@export var spawn_lead_min_m := 80.0
@export var spawn_lead_max_m := 280.0
@export var cooldown_min_s := 30.0
@export var cooldown_max_s := 60.0
@export var enabled := true
@export var behaviour_path: NodePath = NodePath("../WildlifeBehaviour")
@export var track_registry_path: NodePath = NodePath("../../TrackRegistry")
@export var fleet_path: NodePath = NodePath("../../FleetController")
@export var train_path: NodePath = NodePath("../../Train")

var _behaviour: WildlifeBehaviour
var _registry: TrackRegistry
var _fleet: FleetController
var _train: LTSTrain

var _rng := RandomNumberGenerator.new()
var _delay_remaining := 4.0
var _cooldown_remaining := 0.0
var _events_history: Array[Dictionary] = []


func _ready() -> void:
	reset_seed(seed_value)
	_delay_remaining = initial_delay_sec
	_behaviour = get_node_or_null(behaviour_path) as WildlifeBehaviour
	_registry = get_node_or_null(track_registry_path) as TrackRegistry
	_fleet = get_node_or_null(fleet_path) as FleetController
	_train = get_node_or_null(train_path) as LTSTrain
	_load_config()


func _load_config() -> void:
	if not FileAccess.file_exists("res://config.cfg"):
		return
	var cfg := ConfigFile.new()
	if cfg.load("res://config.cfg") == OK:
		enabled = bool(cfg.get_value("simulation", "auto_wildlife", enabled))



func reset_seed(seed_val: int) -> void:
	seed_value = seed_val
	_rng.seed = seed_val
	_delay_remaining = 0.0
	_cooldown_remaining = 0.0


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if is_instance_valid(_behaviour) and not _behaviour.auto_crossing_enabled:
		return
	if _delay_remaining > 0.0:
		_delay_remaining -= delta
		return
	if _cooldown_remaining > 0.0:
		_cooldown_remaining -= delta
		return

	# Scan for running trains (speed > 1 km/h)
	if is_instance_valid(_fleet) and _fleet.train_count() > 0:
		for tid in _fleet.train_ids():
			var t := _fleet.get_train(str(tid))
			if is_instance_valid(t) and t.get_speed_kmh() > 2.0:
				var line_id := "UP" if str(tid) == "T1" else "DOWN"
				if is_instance_valid(_fleet):
					line_id = _fleet.get_train_line(str(tid))
				var sign_value := t.travel_sign if is_instance_valid(t) else (-1.0 if line_id == "DOWN" else 1.0)
				trigger_proximity_event(str(tid), line_id, t.get_track_position_m(), sign_value)
				return

	if is_instance_valid(_train) and _train.get_speed_kmh() > 2.0:
		trigger_proximity_event("T1", "UP", _train.get_track_position_m())


func trigger_proximity_event(train_id: String, line_id: String, train_pos: float, direction := 1.0, lead_override := -1.0, species_override := "", count_override := -1) -> Dictionary:
	var lead_m := lead_override if lead_override >= 0.0 else _rng.randf_range(spawn_lead_min_m, spawn_lead_max_m)
	var track_len := 1253.9822
	if is_instance_valid(_registry):
		var found := _registry.length_m(line_id)
		if found > 0.0:
			track_len = found
	var crossing_d := fposmod(train_pos + lead_m * direction, track_len)
	var species := species_override if not species_override.is_empty() else ("elephant" if _rng.randf() > 0.5 else "deer")
	var count := count_override if count_override >= 0 else (2 if _rng.randf() > 0.7 else 1)

	if is_instance_valid(_behaviour):
		for i in count:
			_behaviour.trigger_crossing_at(line_id, crossing_d + i * 2.0, species)

	_cooldown_remaining = _rng.randf_range(cooldown_min_s, cooldown_max_s)

	var ev := {
		"trainId": train_id,
		"line": line_id,
		"distanceM": crossing_d,
		"species": species,
		"count": count,
	}
	_events_history.append(ev)
	return ev


func get_events_history() -> Array[Dictionary]:
	return _events_history
