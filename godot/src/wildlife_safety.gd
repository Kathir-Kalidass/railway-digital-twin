extends Node
class_name WildlifeSafety

## Local fail-safe for the wildlife loop. It can only tighten the target
## speed; backend commands remain authoritative when the broker is online.

@export var behaviour_path: NodePath
@export var reconciler_path: NodePath
@export var publisher_path: NodePath
@export var crossing_path: NodePath
@export var fleet_path: NodePath = NodePath("../../FleetController")
@export var warning_distance_m := 10.0
@export var stop_distance_m := 4.0
@export var caution_speed_kmh := 30.0
@export var sensor_lookahead_m := 150.0

var _behaviour: WildlifeBehaviour
var _reconciler: TrainReconciler
var _publisher: WildlifePublisher
var _crossing: Node3D
var _state := "CLEAR"
var _last_species := "deer"
var _external_active := false
var _external_species := "wildlife"
var _external_count := 1


func _ready() -> void:
	_behaviour = get_node_or_null(behaviour_path) as WildlifeBehaviour
	_reconciler = get_node_or_null(reconciler_path) as TrainReconciler
	_publisher = get_node_or_null(publisher_path) as WildlifePublisher
	_crossing = get_node_or_null(crossing_path)


func _physics_process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	if not is_instance_valid(_behaviour) or not is_instance_valid(_reconciler):
		return

	var snapshot := _behaviour.get_hazard_snapshot(warning_distance_m, stop_distance_m)
	var next_state := str(snapshot.get("state", "CLEAR"))
	if _external_active:
		next_state = "STOP"
	_apply_train_limits()

	if is_instance_valid(_crossing) and _crossing.has_method("set_alarm"):
		_crossing.call("set_alarm", next_state != "CLEAR")

	if is_instance_valid(_publisher):
		var species := str(snapshot.get("species", "deer"))
		var count := int(snapshot.get("count", 0))
		if _external_active:
			species = _external_species
			count = _external_count
		if next_state == "STOP" and _state != "STOP":
			_last_species = species if not species.is_empty() else "wildlife"
			_publisher.report(_last_species, count, true)
		elif next_state == "CLEAR" and _state == "STOP":
			_publisher.report(_last_species, 0, false)

	_state = next_state


func _apply_train_limits() -> void:
	var trains: Array[LTSTrain] = []
	var fleet := get_node_or_null(fleet_path) as FleetController
	if is_instance_valid(fleet):
		for tid in fleet.train_ids():
			var tr := fleet.get_train(str(tid))
			if is_instance_valid(tr):
				trains.append(tr)
	elif is_instance_valid(_reconciler):
		var tr := _reconciler.get_node_or_null(_reconciler.train_path) as LTSTrain
		if is_instance_valid(tr):
			trains.append(tr)

	for tr in trains:
		if _external_active:
			tr.set_local_speed_limit(0.0)
			continue
		var hazard := _behaviour.get_train_hazard_snapshot(
			tr.line_id,
			tr.get_track_position_m(),
			tr.travel_sign,
			warning_distance_m,
			stop_distance_m,
			sensor_lookahead_m,
			tr.get_speed_kmh()
		)
		match str(hazard.get("state", "CLEAR")):
			"STOP":
				tr.set_local_speed_limit(0.0)
			"WARN":
				tr.set_local_speed_limit(caution_speed_kmh)
			_:
				tr.set_local_speed_limit(-1.0)


func set_external_hazard(active: bool, species := "wildlife", count := 1) -> void:
	_external_active = active
	if active:
		_external_species = species if not species.is_empty() else "wildlife"
		_external_count = maxi(1, count)
	refresh()


func is_external_active() -> bool:
	return _external_active


func get_state() -> String:
	return _state
