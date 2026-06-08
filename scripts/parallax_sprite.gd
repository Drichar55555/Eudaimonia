extends Sprite2D

@export var parallax_speed := Vector2.ONE
@export var max_parallax_offset := Vector2(140.0, 80.0)
@export var camera_reset_distance := 420.0
@export var camera_group := "room_cameras"

var _start_position := Vector2.ZERO
var _last_camera_position := Vector2.ZERO
var _parallax_offset := Vector2.ZERO
var _has_start := false

func _ready() -> void:
	var camera := _current_camera()
	if camera != null:
		_capture_start(camera)
	set_process(not Engine.is_editor_hint())

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var camera := _current_camera()
	if camera == null:
		return
	if not _has_start:
		_capture_start(camera)
		return

	var camera_delta := camera.global_position - _last_camera_position
	_last_camera_position = camera.global_position
	if camera_delta.length() > camera_reset_distance:
		_capture_start(camera)
		return

	_parallax_offset += camera_delta * (Vector2.ONE - parallax_speed)
	_parallax_offset.x = clampf(_parallax_offset.x, -max_parallax_offset.x, max_parallax_offset.x)
	_parallax_offset.y = clampf(_parallax_offset.y, -max_parallax_offset.y, max_parallax_offset.y)
	global_position = _start_position + _parallax_offset

func _capture_start(camera: Camera2D) -> void:
	_start_position = global_position
	_last_camera_position = camera.global_position
	_parallax_offset = Vector2.ZERO
	_has_start = true

func _current_camera() -> Camera2D:
	for camera in get_tree().get_nodes_in_group(camera_group):
		if camera is Camera2D and (camera as Camera2D).is_current():
			return camera as Camera2D
	var viewport_camera := get_viewport().get_camera_2d()
	if viewport_camera != null:
		return viewport_camera
	for camera in get_tree().get_nodes_in_group(camera_group):
		if camera is Camera2D:
			return camera as Camera2D
	return null
