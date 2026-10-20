extends Node
class_name WildlifePublisher

@export var bridge_path: NodePath
@export var zone := "zone1"

var bridge: MQTTBridge
var _last := ""

func _ready() -> void:
	bridge = get_node_or_null(bridge_path) as MQTTBridge

func report(species: String, count: int, on_track: bool) -> void:
	var payload := {
		"zone": zone,
		"wildlifeDetected": count > 0,
		"species": species,
		"count": count,
		"onTrack": on_track,
		"timestamp": Time.get_unix_time_from_system(),
	}
	var key := JSON.stringify(payload)
	if key == _last:
		return
	_last = key
	if bridge and bridge.has_method("publish"):
		bridge.publish("railway/%s/wildlife" % zone, payload)
