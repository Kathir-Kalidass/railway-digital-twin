extends Node
class_name WildlifePublisher

@export var bridge_path: NodePath
@export var zone := "zone1"

var bridge: MQTTBridge
var _last := ""
var _pending_key := ""
var _pending_payload: Dictionary = {}


func _ready() -> void:
	bridge = get_node_or_null(bridge_path) as MQTTBridge
	if bridge:
		bridge.connected.connect(_flush_pending)


func report(species: String, count: int, on_track: bool) -> void:
	var payload := {
		"zone": zone,
		"wildlifeDetected": count > 0,
		"species": species,
		"count": count,
		"onTrack": on_track,
		"timestamp": Time.get_unix_time_from_system(),
	}
	var observation_key := JSON.stringify({
		"zone": zone,
		"species": species,
		"count": count,
		"onTrack": on_track,
	})
	if observation_key == _last:
		return
	if bridge and bridge.is_broker_connected() and bridge.publish("railway/%s/wildlife" % zone, payload):
		_last = observation_key
		_pending_key = ""
		_pending_payload = {}
		return
	_pending_key = observation_key
	_pending_payload = payload


func _flush_pending() -> void:
	if not bridge or _pending_key.is_empty() or not bridge.is_broker_connected():
		return
	if bridge.publish("railway/%s/wildlife" % zone, _pending_payload):
		_last = _pending_key
		_pending_key = ""
		_pending_payload = {}
