extends CanvasLayer
class_name TwinHUD

@export var bridge_path: NodePath
@export var reconciler_path: NodePath
@export var train_path: NodePath
@export var camera_director_path: NodePath
@export_range(0.05, 2.0, 0.05) var refresh_sec := 0.25

var _status: Label
var _metrics: Label
var _help: Label
var _elapsed := 0.0


func _ready() -> void:
	_status = _make_label(18, Color(0.92, 0.96, 1.0), Vector2(18, 14))
	_metrics = _make_label(16, Color(0.78, 0.88, 0.95), Vector2(18, 44))
	_help = _make_label(14, Color(0.65, 0.72, 0.78), Vector2(18, 108))
	_help.text = "C camera   N day/night   SPACE wildlife   \u2191/\u2193 speed"
	refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= refresh_sec:
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	var bridge := get_node_or_null(bridge_path) as MQTTBridge
	var reconciler := get_node_or_null(reconciler_path) as TrainReconciler
	var train := get_node_or_null(train_path) as LTSTrain
	var director := get_node_or_null(camera_director_path) as CameraDirector

	var link := "MQTT online" if bridge and bridge.is_broker_connected() else "MQTT offline"
	var zone := reconciler.zone if reconciler else "zone?"
	var signal_aspect := reconciler.get_signal_aspect() if reconciler else "?"
	var wildlife := "WILDLIFE" if reconciler and reconciler.is_wildlife_active() else "clear"
	var sensor := "healthy" if reconciler == null or reconciler.is_sensor_healthy() else "FAULT"
	_status.text = "%s | %s | %s | sensor %s | %s" % [zone, signal_aspect, wildlife, sensor, link]
	_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if wildlife != "clear" or sensor == "FAULT" else Color(0.92, 0.96, 1.0))

	var speed := train.get_speed_kmh() if train else 0.0
	var target := train.get_target_speed_kmh() if train else 0.0
	var limit := reconciler.get_current_limit_kmh() if reconciler else 0.0
	var mode := director.mode_name() if director else "none"
	_metrics.text = "speed %.1f km/h (target %.1f, limit %.1f)   camera: %s" % [speed, target, limit, mode]


func _make_label(size: int, color: Color, position: Vector2) -> Label:
	var label := Label.new()
	label.position = position
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)
	return label
