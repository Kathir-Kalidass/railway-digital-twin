extends Node
class_name MQTTBridge

signal connected
signal disconnected
signal message_received(topic: String, payload: Dictionary)

@export var broker_url := "tcp://127.0.0.1:1883"
@export var client_id := "godot-digital-twin"
@export var username := ""
@export var password := ""
@export_range(1, 65535) var keepalive_sec := 60
@export_range(0.1, 30.0, 0.1) var reconnect_delay_base := 1.0
@export_range(0.1, 30.0, 0.1) var reconnect_delay_max := 30.0
@export var connect_on_ready := true

var _client: MQTTClient
var _reconnect_timer: Timer
var _reconnect_delay := 1.0
var _connecting := false
var _connected := false
var _reconnecting := false
var _shutting_down := false
var _subscriptions: Dictionary[String, int] = {}


func _ready() -> void:
	if not _load_local_config():
		return
	_reconnect_delay = reconnect_delay_base
	_reconnect_timer = Timer.new()
	_reconnect_timer.name = "ReconnectTimer"
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect(_on_reconnect_timeout)
	add_child(_reconnect_timer)

	_client = MQTTClient.new()
	_client.client_id = client_id
	_client.keepalive = keepalive_sec
	_client.verbose_level = 0
	_client.broker_connected.connect(_on_connected)
	_client.broker_disconnected.connect(_on_disconnected)
	_client.broker_connection_failed.connect(_on_connection_failed)
	_client.received_message.connect(_on_message)
	add_child(_client)
	if connect_on_ready:
		connect_broker()


func connect_broker() -> void:
	if _shutting_down or _connected or _connecting:
		return
	if not is_instance_valid(_client):
		push_error("MQTT bridge is not initialized; check its local configuration.")
		return
	if broker_url.strip_edges().is_empty():
		push_error("MQTT broker URL must not be empty.")
		return
	_connecting = true
	if not username.is_empty():
		_client.set_user_pass(username, password)
	if not _client.connect_to_broker(broker_url):
		_connecting = false
		_schedule_reconnect()


func subscribe(topic: String, qos: int = 0) -> bool:
	if topic.strip_edges().is_empty():
		push_error("MQTT subscription topic must not be empty.")
		return false
	if qos < 0 or qos > 1:
		push_error("MQTT QoS %d is unsupported; use QoS 0 or 1." % qos)
		return false
	_subscriptions[topic] = qos
	if _connected:
		_client.subscribe(topic, qos)
	return true


func publish(topic: String, payload: Variant, retain: bool = false, qos: int = 0) -> bool:
	if topic.strip_edges().is_empty():
		push_error("MQTT publish topic must not be empty.")
		return false
	if qos < 0 or qos > 1:
		push_error("MQTT QoS %d is unsupported; use QoS 0 or 1." % qos)
		return false
	if not _connected or not is_instance_valid(_client):
		push_warning("MQTT publish skipped while disconnected: %s" % topic)
		return false
	var message_text := JSON.stringify(payload) if payload is Dictionary or payload is Array else str(payload)
	_client.publish(topic, message_text, retain, qos)
	return true


func _load_local_config() -> bool:
	if not FileAccess.file_exists("res://config.cfg"):
		return true
	var config := ConfigFile.new()
	var error := config.load("res://config.cfg")
	if error != OK:
		push_error("Could not read res://config.cfg: %s" % error_string(error))
		return false
	broker_url = str(config.get_value("mqtt", "broker_url", broker_url))
	username = str(config.get_value("mqtt", "username", username))
	password = str(config.get_value("mqtt", "password", password))
	if config.has_section_key("mqtt", "host"):
		var host := str(config.get_value("mqtt", "host"))
		var port := int(config.get_value("mqtt", "port", 1883))
		broker_url = "tcp://%s:%d" % [host, port]
	return true


func _on_connected() -> void:
	_connecting = false
	_connected = true
	_reconnecting = false
	_reconnect_delay = reconnect_delay_base
	for topic in _subscriptions:
		_client.subscribe(topic, _subscriptions[topic])
	connected.emit()


func _on_disconnected() -> void:
	var was_connected := _connected
	_connected = false
	_connecting = false
	if was_connected:
		disconnected.emit()
	_schedule_reconnect()


func _on_connection_failed() -> void:
	_connecting = false
	_schedule_reconnect()


func _on_message(topic: String, raw_message: Variant) -> void:
	var message_text: String = raw_message.get_string_from_utf8() if raw_message is PackedByteArray else str(raw_message)
	var parsed: Variant = JSON.parse_string(message_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Ignoring invalid MQTT JSON object on topic %s." % topic)
		return
	message_received.emit(topic, parsed)


func _schedule_reconnect() -> void:
	if _shutting_down or _reconnecting or not is_instance_valid(_reconnect_timer):
		return
	_reconnecting = true
	_reconnect_timer.start(_reconnect_delay)
	_reconnect_delay = minf(_reconnect_delay * 2.0, reconnect_delay_max)


func _on_reconnect_timeout() -> void:
	_reconnecting = false
	connect_broker()


func _exit_tree() -> void:
	_shutting_down = true
	if is_instance_valid(_reconnect_timer):
		_reconnect_timer.stop()
	if is_instance_valid(_client):
		_client.disconnect_from_server()
