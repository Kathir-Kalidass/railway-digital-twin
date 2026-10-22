extends CanvasLayer
class_name TwinHUD

@export var bridge_path: NodePath
@export var reconciler_path: NodePath
@export var train_path: NodePath
@export var camera_director_path: NodePath
@export var fleet_path: NodePath = NodePath("../FleetController")
@export_range(0.05, 2.0, 0.05) var refresh_sec := 0.25

var selected_train_id := "T1"

var _status: Label
var _metrics: Label
var _help: Label
var _elapsed := 0.0
var _meet: Dictionary = {}


func _ready() -> void:
	_status = _make_label(18, Color(0.92, 0.96, 1.0), Vector2(18, 14))
	_metrics = _make_label(16, Color(0.78, 0.88, 0.95), Vector2(18, 44))
	_help = _make_label(14, Color(0.65, 0.72, 0.78), Vector2(18, 108))
	_help.text = "TAB switch train   C camera   N day/night   B cinematic reel   SPACE wildlife   \u2191/\u2193 speed"
	var bridge := get_node_or_null(bridge_path) as MQTTBridge
	if bridge:
		bridge.message_received.connect(_on_message)
	refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= refresh_sec:
		_elapsed = 0.0
		refresh()


func get_selected_train_id() -> String:
	return selected_train_id


func select_train(id: String) -> void:
	selected_train_id = id
	var fleet := get_node_or_null(fleet_path) as FleetController
	var director := get_node_or_null(camera_director_path) as CameraDirector
	if fleet and is_instance_valid(fleet.get_train(id)):
		var target_train := fleet.get_train(id)
		if director:
			director.set_target_train(target_train)
	refresh()


func cycle_selected_train() -> void:
	var fleet := get_node_or_null(fleet_path) as FleetController
	if fleet and fleet.train_count() > 1:
		var ids: Array = fleet.train_ids()
		var idx := ids.find(selected_train_id)
		if idx < 0:
			idx = 0
		var next_idx := (idx + 1) % ids.size()
		select_train(str(ids[next_idx]))
	else:
		refresh()


func _on_message(topic: String, payload: Dictionary) -> void:
	if topic == "railway/state":
		apply_state(payload)


func apply_state(state: Dictionary) -> void:
	var meet_var: Variant = state.get("meets")
	if meet_var is Dictionary:
		_meet = meet_var
	refresh()


func _meet_text() -> String:
	if _meet.is_empty() or not bool(_meet.get("enabled", false)):
		return ""
	var phase := str(_meet.get("phase", "IDLE"))
	if phase == "IDLE":
		var seconds := int(ceil(float(_meet.get("nextMeetInSec", 0.0))))
		return "meet in %ds" % seconds
	var active_var: Variant = _meet.get("active")
	if active_var is Dictionary and not active_var.is_empty():
		var holder := str(active_var.get("holderId", "?"))
		var route := str(active_var.get("routeId", ""))
		var extra := ""
		if not route.is_empty():
			extra = " via %s" % route
		return "MEET %s %s%s" % [phase, holder, extra]
	return "MEET %s" % phase


func refresh() -> void:
	var bridge := get_node_or_null(bridge_path) as MQTTBridge
	var reconciler := get_node_or_null(reconciler_path) as TrainReconciler
	var train := get_node_or_null(train_path) as LTSTrain
	var director := get_node_or_null(camera_director_path) as CameraDirector
	var fleet := get_node_or_null(fleet_path) as FleetController

	var current_train := train
	var current_block := ""
	if fleet and fleet.train_count() > 0:
		var ft := fleet.get_train(selected_train_id)
		if is_instance_valid(ft):
			current_train = ft
			current_block = fleet.get_train_block(selected_train_id)

	var link := "MQTT online" if bridge and bridge.is_broker_connected() else "MQTT offline"
	var zone := reconciler.zone if reconciler else "zone?"
	var signal_aspect := reconciler.get_signal_aspect() if reconciler else "?"
	var wildlife := "WILDLIFE" if reconciler and reconciler.is_wildlife_active() else "clear"
	var sensor := "healthy" if reconciler == null or reconciler.is_sensor_healthy() else "FAULT"

	var cam_detector: SimulatedAnimalDetector = current_train.call("get_detector") if is_instance_valid(current_train) and current_train.has_method("get_detector") else null
	var cam_status := "CAM clear"
	if is_instance_valid(cam_detector) and cam_detector.is_detection_active():
		var last_det: Dictionary = cam_detector.get_last_detection()
		var conf := float(last_det.get("confidence", 0.0))
		cam_status = "CAM detect %.2f" % conf

	if fleet and fleet.train_count() > 1:
		var fleet_info := "fleet %d trains" % fleet.train_count()
		_status.text = "%s | %s | %s | %s | sensor %s | %s | %s" % [zone, signal_aspect, wildlife, cam_status, sensor, link, fleet_info]
	else:
		_status.text = "%s | %s | %s | %s | sensor %s | %s" % [zone, signal_aspect, wildlife, cam_status, sensor, link]

	_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if wildlife != "clear" or sensor == "FAULT" else Color(0.92, 0.96, 1.0))

	var speed := current_train.get_speed_kmh() if current_train else 0.0
	var target := current_train.get_target_speed_kmh() if current_train else 0.0
	var limit := reconciler.get_current_limit_kmh() if reconciler else 0.0
	var mode := director.mode_name() if director else "none"

	var meet_text := _meet_text()
	var meet_suffix := "" if meet_text.is_empty() else "   %s" % meet_text
	if fleet and fleet.train_count() > 1:
		_metrics.text = "train %s [%s] speed %.1f km/h (target %.1f, limit %.1f)   camera: %s%s" % [selected_train_id, current_block, speed, target, limit, mode, meet_suffix]
	else:
		_metrics.text = "speed %.1f km/h (target %.1f, limit %.1f)   camera: %s%s" % [speed, target, limit, mode, meet_suffix]


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
