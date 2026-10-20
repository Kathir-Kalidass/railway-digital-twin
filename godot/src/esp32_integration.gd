extends Node
class_name ESP32Integration

@export var bridge_path: NodePath
@export var zone := "zone1"
@export var animal_safety_path: NodePath
@export var telemetry_topic := "railway/telemetry/esp32"
@export var command_topic := "railway/commands/esp32"

var bridge: MQTTBridge
var safety

func _ready() -> void:
	bridge = get_node_or_null(bridge_path) as MQTTBridge
	safety = get_node_or_null(animal_safety_path)
	if bridge:
		bridge.message_received.connect(_on_message)
		bridge.connected.connect(_subscribe)

func _subscribe() -> void:
	if bridge:
		bridge.subscribe(telemetry_topic)
		bridge.subscribe(command_topic)

func _on_message(topic: String, payload: Dictionary) -> void:
	if topic == telemetry_topic:
		_process_telemetry(payload)
	elif topic == command_topic:
		_process_command(payload)

func _process_telemetry(data: Dictionary) -> void:
	var payload = data.get("payload", data)
	var wildlife_detected = bool(payload.get("wildlifeDetected", payload.get("animal_detected", false)))
	var sensor_healthy = bool(payload.get("sensorHealthy", true))
	var device = str(payload.get("device", ""))
	if safety and wildlife_detected:
		safety.trigger_wildlife_alert("animal", 1, true)
		bridge.publish("railway/%s/wildlife" % zone, {
			"zone": zone,
			"wildlifeDetected": true,
			"species": "animal",
			"count": 1,
			"onTrack": true,
			"source": "esp32",
			"device": device,
			"sensorHealthy": sensor_healthy,
			"timestamp": Time.get_unix_time_from_system()
		})

func _process_command(data: Dictionary) -> void:
	pass

func send_command(cmd: Dictionary) -> void:
	if bridge:
		cmd["timestamp"] = Time.get_unix_time_from_system()
		bridge.publish(command_topic, cmd)
