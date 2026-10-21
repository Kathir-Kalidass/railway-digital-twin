extends Node
class_name ESP32Integration

@export var bridge_path: NodePath
@export var zone := "zone1"
@export var safety_path: NodePath
@export var behaviour_path: NodePath
@export var animal_safety_path: NodePath
@export var telemetry_topic := "railway/telemetry/esp32"

var bridge: MQTTBridge
var safety
var behaviour
var animal_safety
var _external_active := false


func _ready() -> void:
	bridge = get_node_or_null(bridge_path) as MQTTBridge
	safety = get_node_or_null(safety_path)
	behaviour = get_node_or_null(behaviour_path)
	animal_safety = get_node_or_null(animal_safety_path)
	if bridge:
		bridge.message_received.connect(_on_message)
		bridge.connected.connect(_subscribe)


func _subscribe() -> void:
	if bridge:
		bridge.subscribe(telemetry_topic)


func _on_message(topic: String, payload: Dictionary) -> void:
	if topic == telemetry_topic:
		_process_telemetry(payload)


func _process_telemetry(data: Dictionary) -> void:
	var payload = data.get("payload", data)
	if not payload is Dictionary:
		return
	var wildlife_detected := bool(payload.get("wildlifeDetected", payload.get("animal_detected", false)))
	if wildlife_detected == _external_active:
		return

	_external_active = wildlife_detected
	var species := "deer"
	if safety and safety.has_method("set_external_hazard"):
		safety.call("set_external_hazard", wildlife_detected, species, 1)
	elif animal_safety:
		if wildlife_detected and animal_safety.has_method("trigger_wildlife_alert"):
			animal_safety.call("trigger_wildlife_alert", species, 1, true)
		elif not wildlife_detected and animal_safety.has_method("clear_alert"):
			animal_safety.call("clear_alert")

	if wildlife_detected and behaviour and behaviour.has_method("trigger_crossing"):
		behaviour.call("trigger_crossing", species)


func is_external_active() -> bool:
	return _external_active
