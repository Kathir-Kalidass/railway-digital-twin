extends Node
class_name TrainReconciler

@export var train_path: NodePath
@export var bridge_path: NodePath
@export var zone := "zone1"
@export var max_safe_speed_kmh := 60.0
@export var wildlife_reduced_speed_kmh := 30.0

var _train: LTSTrain
var _bridge: MQTTBridge
var _wildlife_active := false
var _sensor_healthy := true
var _signal_aspect := "GREEN"
var _current_limit_kmh := 60.0


func _ready() -> void:
	_train = get_node_or_null(train_path) as LTSTrain
	_bridge = get_node_or_null(bridge_path) as MQTTBridge
	if _bridge:
		_bridge.message_received.connect(_on_message)
		_bridge.connected.connect(_subscribe)
		_subscribe()


func _subscribe() -> void:
	if not _bridge:
		return
	_bridge.subscribe("railway/%s/signal" % zone)
	_bridge.subscribe("railway/speed/%s" % zone)
	_bridge.subscribe("railway/commands/%s" % zone)


func _on_message(topic: String, payload: Dictionary) -> void:
	if topic == "railway/%s/signal" % zone:
		if payload.has("signal"):
			_signal_aspect = str(payload["signal"]).to_upper()
		elif payload.has("aspect"):
			_signal_aspect = str(payload["aspect"]).to_upper()
		_recompute()
	elif topic == "railway/speed/%s" % zone:
		if payload.has("speedKmh"):
			_current_limit_kmh = maxf(0.0, float(payload["speedKmh"]))
		elif payload.has("limitKmh"):
			_current_limit_kmh = maxf(0.0, float(payload["limitKmh"]))
		_recompute()
	elif topic == "railway/commands/%s" % zone:
		match str(payload.get("event", "")):
			"WILDLIFE_DETECTED":
				_wildlife_active = true
			"WILDLIFE_CLEARED":
				_wildlife_active = false
			"SENSOR_FAULT":
				_sensor_healthy = false
			"SENSOR_RESTORED":
				_sensor_healthy = true
		if payload.has("wildlifeActive"):
			_wildlife_active = bool(payload["wildlifeActive"])
		_recompute()
	elif topic == "railway/state":
		var zones: Variant = payload.get("zones", {})
		if not zones is Dictionary or not zones.has(zone):
			return
		var zone_state: Variant = zones[zone]
		if not zone_state is Dictionary:
			return
		if zone_state.has("signal"):
			_signal_aspect = str(zone_state["signal"]).to_upper()
		elif zone_state.has("signalAspect"):
			_signal_aspect = str(zone_state["signalAspect"]).to_upper()
		if zone_state.has("targetSpeedKmh"):
			_current_limit_kmh = maxf(0.0, float(zone_state["targetSpeedKmh"]))
		elif zone_state.has("speedLimitKmh"):
			_current_limit_kmh = maxf(0.0, float(zone_state["speedLimitKmh"]))
		if zone_state.has("wildlifeDetected"):
			_wildlife_active = bool(zone_state["wildlifeDetected"])
		elif zone_state.has("wildlifeActive"):
			_wildlife_active = bool(zone_state["wildlifeActive"])
		if zone_state.has("sensorHealthy"):
			_sensor_healthy = bool(zone_state["sensorHealthy"])
		_recompute()


func _recompute() -> void:
	var target_speed := minf(_current_limit_kmh, max_safe_speed_kmh)
	if _signal_aspect == "RED" or _signal_aspect == "STOP" or not _sensor_healthy:
		target_speed = 0.0
	elif _signal_aspect == "YELLOW" or _signal_aspect == "CAUTION":
		target_speed = minf(target_speed, max_safe_speed_kmh * 0.5)
	if _wildlife_active:
		target_speed = minf(target_speed, wildlife_reduced_speed_kmh)
	if is_instance_valid(_train):
		_train.set_target_speed_kmh(target_speed)
