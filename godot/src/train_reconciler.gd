extends Node
class_name TrainReconciler

@export var train_path: NodePath
@export var bridge_path: NodePath
@export var zone := "zone1"
@export var max_safe_speed_kmh := 60.0
@export var wildlife_reduced_speed_kmh := 30.0
@export var blocked_speed_kmh := 0.0

var _train: LTSTrain
var _bridge: MQTTBridge
var _wildlife_active := false
var _signal_aspect := "CLEAR"
var _current_limit_kmh := 60.0

func _ready() -> void:
	_train = get_node_or_null(train_path)
	_bridge = get_node_or_null(bridge_path)
	if _bridge:
		_bridge.message_received.connect(_on_message)
		_bridge.connected.connect(_subscribe)
	if _bridge and _bridge.is_inside_tree():
		_subscribe()

func _subscribe() -> void:
	if not _bridge:
		return
	_bridge.subscribe("railway/%s/signal" % zone)
	_bridge.subscribe("railway/speed/%s" % zone)
	_bridge.subscribe("railway/zoneN/signal")
	_bridge.subscribe("railway/commands/%s" % zone)
	_bridge.subscribe("railway/state")

func _on_message(topic: String, payload: Dictionary) -> void:
	if topic == "railway/%s/signal" % zone or topic == "railway/zoneN/signal":
		if payload.has("aspect"):
			_signal_aspect = str(payload["aspect"])
		_recompute()
	elif topic == "railway/speed/%s" % zone:
		if payload.has("limitKmh"):
			_current_limit_kmh = float(payload["limitKmh"])
		_recompute()
	elif topic == "railway/commands/%s" % zone:
		if payload.has("wildlife") and payload["wildlife"] is Dictionary:
			var w = payload["wildlife"]
			_wildlife_active = bool(w.get("active", w.get("detected", false)))
		elif payload.has("wildlifeActive"):
			_wildlife_active = bool(payload["wildlifeActive"])
		_recompute()
	elif topic == "railway/state":
		if payload.has("zones") and payload["zones"] is Dictionary and payload["zones"].has(zone):
			var z = payload["zones"][zone]
			if z.has("signalAspect"):
				_signal_aspect = str(z["signalAspect"])
			if z.has("speedLimitKmh"):
				_current_limit_kmh = float(z["speedLimitKmh"])
			if z.has("wildlifeActive"):
				_wildlife_active = bool(z["wildlifeActive"])
		_recompute()

func _recompute() -> void:
	var v := min(_current_limit_kmh, max_safe_speed_kmh)
	if _signal_aspect == "STOP":
		v = min(v, blocked_speed_kmh)
	elif _signal_aspect == "CAUTION":
		v = min(v, max_safe_speed_kmh * 0.5)
	if _wildlife_active:
		v = min(v, wildlife_reduced_speed_kmh)
	if _train and _train.has_method("set_target_speed_kmh"):
		_train.set_target_speed_kmh(v)
