class_name SignalDirector
extends Node3D

@export var track_registry_path: NodePath = NodePath("../TrackRegistry")
@export var bridge_path: NodePath = NodePath("../MQTTBridge")

var _masts: Dictionary = {}
var _registry: TrackRegistry
var _bridge: MQTTBridge


func _ready() -> void:
	_registry = get_node_or_null(track_registry_path) as TrackRegistry
	_bridge = get_node_or_null(bridge_path) as MQTTBridge

	_build_masts()

	if _bridge:
		_bridge.message_received.connect(_on_message)
		_bridge.connected.connect(_subscribe)
		if _bridge.is_broker_connected():
			_subscribe()


func _subscribe() -> void:
	if not _bridge:
		return
	_bridge.subscribe("railway/signal/+")
	_bridge.subscribe("railway/state")


func _build_masts() -> void:
	var lines := ["UP", "DOWN"]
	for line in lines:
		var track: LTSTrack = null
		if _registry:
			track = _registry.track(line)
		elif line == "UP":
			track = get_node_or_null("../Track") as LTSTrack

		if not is_instance_valid(track):
			continue

		var track_len := track.length
		var block_len := track_len / 5.0
		var side_offset := 2.6 if line == "UP" else -2.6

		for index in 5:
			var block_id := "%s-B%d" % [line, index]
			var distance := fposmod(index * block_len, track_len)
			var pose := track.get_global_transform_at_distance(distance)

			var mast := BlockSignalMast.new()
			mast.name = "Signal_%s_B%d" % [line, index]
			mast.block_id = block_id
			mast.line_id = line

			# Place mast beside track facing oncoming traffic
			var mast_pos := pose.origin + pose.basis.z * side_offset
			mast.transform = Transform3D(pose.basis, mast_pos)
			# Point signal face toward oncoming train (facing -basis.x)
			mast.rotate_object_local(Vector3.UP, PI * 0.5)

			add_child(mast)
			_masts[block_id] = mast


func _on_message(topic: String, payload: Dictionary) -> void:
	if topic.begins_with("railway/signal/"):
		var block_id := topic.trim_prefix("railway/signal/")
		var aspect := str(payload.get("aspect", payload.get("signal", "GREEN")))
		update_aspect(block_id, aspect)
	elif topic == "railway/state":
		var blocks_var: Variant = payload.get("blocks", [])
		if blocks_var is Array:
			for item in blocks_var:
				if item is Dictionary:
					var b_id := str(item.get("id", ""))
					var b_aspect := str(item.get("signal", item.get("aspect", "GREEN")))
					if not b_id.is_empty():
						update_aspect(b_id, b_aspect)


func get_mast(block_id: String) -> BlockSignalMast:
	return _masts.get(block_id, null) as BlockSignalMast


func get_aspect(block_id: String) -> String:
	var mast: BlockSignalMast = get_mast(block_id)
	if mast:
		return mast.get_aspect()
	return ""


func update_aspect(block_id: String, aspect: String) -> void:
	var mast: BlockSignalMast = get_mast(block_id)
	if mast:
		mast.set_aspect(aspect)


func masts() -> Array:
	return _masts.values()
