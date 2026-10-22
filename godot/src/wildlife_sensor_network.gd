class_name WildlifeSensorNetwork
extends Node3D

## Distributed network of 10 trackside sensor huts placed at block boundaries
## (5 UP, 5 DOWN) providing overlapping 75m detection coverage along both lines.

@export var track_registry_path: NodePath = NodePath("../TrackRegistry")
@export var bridge_path: NodePath = NodePath("../MQTTBridge")
@export var sensor_coverage_m := 75.0

var _huts: Dictionary = {}
var _registry: TrackRegistry
var _bridge: MQTTBridge
var _tick_count := 0


func _ready() -> void:
	_registry = get_node_or_null(track_registry_path) as TrackRegistry
	_bridge = get_node_or_null(bridge_path) as MQTTBridge
	_build_huts()


func _build_huts() -> void:
	var lines := ["UP", "DOWN"]
	for line in lines:
		var track: LTSTrack = null
		if _registry:
			track = _registry.track(line)
		elif line == "UP":
			track = get_node_or_null("../../Track") as LTSTrack

		if not is_instance_valid(track):
			continue

		var track_len := track.length
		var block_len := track_len / 5.0
		var side_offset := 3.2 if line == "UP" else -3.2

		for index in 5:
			var sensor_id := "%s-S%d" % [line, index]
			var dist := fposmod(index * block_len, track_len)
			var pose := track.get_global_transform_at_distance(dist)

			var hut := TracksideSensorHut.new()
			hut.name = "Hut_%s_S%d" % [line, index]
			hut.sensor_id = sensor_id
			hut.line = line
			hut.boundary_distance_m = dist
			hut.coverage_radius_m = sensor_coverage_m
			hut.bridge = _bridge

			var hut_pos := pose.origin + pose.basis.z * side_offset
			hut.transform = Transform3D(pose.basis, hut_pos)
			add_child(hut)
			_huts[sensor_id] = hut


func _physics_process(_delta: float) -> void:
	_tick_count += 1
	if _tick_count % 5 == 0:
		scan_now()


func scan_now() -> void:
	var animals := get_tree().get_nodes_in_group("wildlife") if get_tree() else []
	for hut in _huts.values():
		var h := hut as TracksideSensorHut
		if is_instance_valid(h):
			h.scan_animals(animals)


func get_huts() -> Array:
	return _huts.values()


func get_hut(sensor_id: String) -> TracksideSensorHut:
	return _huts.get(sensor_id, null) as TracksideSensorHut
