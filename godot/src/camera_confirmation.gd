class_name CameraConfirmation
extends Node

@export var enabled := true
@export var capture_fps := 2.0
@export var frame_width := 640
@export var frame_height := 360
@export var jpeg_quality := 70
@export var camera_range_m := 200.0
@export var api_url := "http://127.0.0.1:3001"
@export var camera_token := "test-token"

var train: LTSTrain
var upload_override: Callable
var _state: Dictionary = {}
var _viewport: SubViewport
var _camera: Camera3D
var _http: HTTPRequest
var _pending := false
var _accum := 0.0
var _event_seq := 0
var _last_result: Dictionary = {}


func _ready() -> void:
	train = get_parent() as LTSTrain
	if not OS.get_environment("BACKEND_HTTP_URL").is_empty():
		api_url = OS.get_environment("BACKEND_HTTP_URL")
	if not OS.get_environment("CAMERA_INGEST_TOKEN").is_empty():
		camera_token = OS.get_environment("CAMERA_INGEST_TOKEN")
	_viewport = SubViewport.new()
	_viewport.name = "CaptureViewport"
	_viewport.size = Vector2i(frame_width, frame_height)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.world_3d = get_viewport().find_world_3d()
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.near = 0.1
	_camera.far = 400.0
	_camera.current = true
	_viewport.add_child(_camera)
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func apply_state(state: Dictionary) -> void:
	_state = state


func _hazard_for_train() -> Dictionary:
	if not is_instance_valid(train):
		return {}
	var blocks: Array = _state.get("blocks", [])
	for block in blocks:
		if not (block is Dictionary):
			continue
		if str(block.get("line", "")) != train.line_id:
			continue
		var hazard: Variant = block.get("hazard")
		if hazard is Dictionary and str(hazard.get("stage", "NONE")) in ["SUSPECTED", "CONFIRMED"]:
			return {"blockId": str(block.get("id", "")), "hazard": hazard}
	return {}


func should_capture() -> bool:
	if not enabled or _pending:
		return false
	if not is_instance_valid(train) or not is_instance_valid(_camera):
		return false
	if train.get_speed_kmh() <= 0.1:
		return false
	var target := _hazard_for_train()
	if target.is_empty():
		return false
	var hazard: Dictionary = target.get("hazard", {})
	return str(hazard.get("stage", "")) != "CONFIRMED"


func headers(event_id: String, block_id: String) -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: image/jpeg",
		"X-Camera-Token: %s" % camera_token,
		"X-Train-Id: %s" % train.train_id,
		"X-Line: %s" % train.line_id,
		"X-Block: %s" % block_id,
		"X-Event-Id: %s" % event_id,
		"X-Captured-At: %s" % Time.get_datetime_string_from_system(true),
	])


func encode_frame(image: Image) -> PackedByteArray:
	return image.save_jpg_to_buffer(clampf(jpeg_quality / 100.0, 0.01, 1.0))


func _physics_process(delta: float) -> void:
	if not is_instance_valid(train) or not is_instance_valid(_camera):
		return
	var source := train.get_forward_camera()
	if is_instance_valid(source):
		_camera.global_transform = source.global_transform
	_accum += delta
	if _accum < 1.0 / capture_fps:
		return
	_accum = 0.0
	if should_capture():
		_capture_once()


func _capture_once() -> void:
	_pending = true
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	var bytes := encode_frame(image)
	var target := _hazard_for_train()
	var block_id := str(target.get("blockId", train.block_id))
	_event_seq += 1
	var event_id := "cam-%s-%d-%d" % [train.train_id, int(Time.get_unix_time_from_system()), _event_seq]
	if upload_override.is_valid():
		var result: Dictionary = upload_override.call(api_url + "/api/wildlife/camera/frame", headers(event_id, block_id), bytes)
		handle_response(result, 200)
		_pending = false
		return
	var err := _http.request_raw(api_url + "/api/wildlife/camera/frame", headers(event_id, block_id), HTTPClient.METHOD_POST, bytes)
	if err != OK:
		_pending = false


func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_pending = false
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		handle_response(parsed, response_code)


func handle_response(result: Dictionary, status: int) -> Dictionary:
	var merged := result.duplicate()
	merged["status"] = status
	merged["at"] = Time.get_unix_time_from_system()
	_last_result = merged
	return _last_result


func get_last_result() -> Dictionary:
	return _last_result
