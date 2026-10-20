extends Node
class_name AnimalSafetySystem

@export var bridge_path: NodePath
@export var zone := "zone1"
@export var safety_signals_path: NodePath
@export var reconciler_path: NodePath
@export var alert_duration := 10.0

var bridge: MQTTBridge
var signals
var reconciler
var _active := false
var _timer := 0.0

func _ready() -> void:
	bridge = get_node_or_null(bridge_path)
	signals = get_node_or_null(safety_signals_path)
	reconciler = get_node_or_null(reconciler_path)

func _process(delta: float) -> void:
	if _active:
		_timer += delta
		if _timer >= alert_duration:
			clear_alert()

func trigger_wildlife_alert(species: String, count: int, on_track: bool) -> void:
	_active = true
	_timer = 0.0
	if signals and signals.has_method("set_state"):
		signals.set_state(false)
	if reconciler:
		reconciler.set("_wildlife_active", true)
		if reconciler.has_method("_recompute"):
			reconciler._recompute()
	bridge.publish("railway/%s/wildlife" % zone, {
		"zone": zone, "wildlifeDetected": true, "species": species, "count": count, "onTrack": on_track,
		"timestamp": Time.get_unix_time_from_system()
	})

func clear_alert() -> void:
	_active = false
	_timer = 0.0
	if signals and signals.has_method("set_state"):
		signals.set_state(true)
	if reconciler:
		reconciler.set("_wildlife_active", false)
		if reconciler.has_method("_recompute"):
			reconciler._recompute()
