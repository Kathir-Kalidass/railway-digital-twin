extends Node
class_name MQTTBridge

signal connected
signal disconnected
signal message_received(topic: String, payload: Dictionary)

@export var broker_url := "tcp://127.0.0.1:1883"
@export var client_id := "godot-digital-twin"
@export var username := "godot"
@export var password := "godot-dev-pass"
@export var keepalive_sec := 60
@export var reconnect_delay_base := 0.5
@export var reconnect_delay_max := 30.0

var _client: MQTTClient
var _reconnect_delay := 0.5
var _reconnecting := false

func _ready() -> void:
	_client = MQTTClient.new()
	add_child(_client)
	_client.broker_connected.connect(_on_connected)
	_client.broker_disconnected.connect(_on_disconnected)
	_client.broker_connection_failed.connect(_on_failed)
	_client.received_message.connect(_on_message)
	_connect()

func _connect() -> void:
	_reconnecting = true
	_client.set_user_pass(username, password)
	_client.connect_to_broker(broker_url)

func _on_connected() -> void:
	_reconnecting = false
	_reconnect_delay = reconnect_delay_base
	connected.emit()

func _on_disconnected() -> void:
	disconnected.emit()
	_schedule_reconnect()

func _on_failed() -> void:
	_schedule_reconnect()

func _schedule_reconnect() -> void:
	if _reconnecting:
		return
	_reconnecting = true
	get_tree().create_timer(_reconnect_delay).timeout.connect(_connect)
	_reconnect_delay = clamp(_reconnect_delay * 2.0, reconnect_delay_base, reconnect_delay_max)

func _on_message(topic: String, message) -> void:
	var data: Dictionary = {}
	if message is String:
		var json := JSON.new()
		if json.parse(message) == OK and json.data is Dictionary:
			data = json.data
	elif message is Dictionary:
		data = message
	message_received.emit(topic, data)

func subscribe(topic: String, qos: int = 0) -> void:
	if _client:
		_client.subscribe(topic, qos)

func publish(topic: String, payload: Variant, retain: bool = false, qos: int = 0) -> void:
	if not _client:
		return
	var s := payload
	if payload is Dictionary or payload is Array:
		s = JSON.stringify(payload)
	_client.publish(topic, s, retain, qos)
