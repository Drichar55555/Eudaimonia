extends Node2D

@export var camera_group := "room_cameras"
@export var fog_color := Color(0.72, 0.78, 0.74, 0.08)
@export_range(0.0, 120.0, 1.0) var drift_speed := 10.0
@export_range(0.2, 3.0, 0.05) var fog_scale := 1.0
@export var cover_margin := Vector2(180.0, 120.0)

var _time := 0.0
var _bands := [
	{"y": -0.32, "height": 64.0, "phase": 0.2, "alpha": 0.70},
	{"y": -0.06, "height": 92.0, "phase": 1.8, "alpha": 0.48},
	{"y": 0.24, "height": 72.0, "phase": 3.4, "alpha": 0.58},
]

func _ready() -> void:
	z_index = -12
	z_as_relative = false
	set_process(not Engine.is_editor_hint())
	queue_redraw()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += delta
	var camera := _current_camera()
	if camera != null:
		global_position = camera.global_position
	queue_redraw()

func _draw() -> void:
	var camera := _current_camera()
	if camera == null:
		return
	var viewport_size := get_viewport_rect().size
	var view_size := Vector2(
		viewport_size.x / maxf(camera.zoom.x, 0.001),
		viewport_size.y / maxf(camera.zoom.y, 0.001)
	) + cover_margin * 2.0
	for band in _bands:
		var phase := float(band["phase"])
		var y := float(band["y"]) * view_size.y + sin(_time * 0.16 + phase) * drift_speed
		var x := cos(_time * 0.11 + phase) * drift_speed * 1.8
		var height := float(band["height"]) * fog_scale
		var color := fog_color
		color.a *= float(band["alpha"])
		_draw_fog_band(Vector2(-view_size.x * 0.5 + x, y), Vector2(view_size.x, height), color)

func _draw_fog_band(top_left: Vector2, size: Vector2, color: Color) -> void:
	var steps := 8
	for index in steps:
		var progress := float(index) / float(maxi(steps - 1, 1))
		var fade := sin(progress * PI)
		var row_color := color
		row_color.a *= fade * 0.42
		var row_height := size.y / float(steps)
		draw_rect(Rect2(top_left + Vector2(0.0, row_height * index), Vector2(size.x, row_height + 1.0)), row_color, true)

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
