extends Control

@export var camera_path: NodePath

var game_camera: Camera2D

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_camera = get_node_or_null(camera_path) as Camera2D

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if game_camera == null:
		return
	if not bool(game_camera.get("show_camera_zone_overlay")):
		return

	var viewport_size := get_viewport_rect().size
	var center := viewport_size * 0.5
	var dead_zone_value: Variant = game_camera.get("active_dead_zone")
	var border_zone_value: Variant = game_camera.get("active_border_zone")
	var dead_zone := dead_zone_value as Vector2 if dead_zone_value is Vector2 else Vector2(42.0, 88.0)
	var border_zone := border_zone_value as Vector2 if border_zone_value is Vector2 else Vector2(180.0, 140.0)
	var zoom: Vector2 = game_camera.zoom
	var dead_screen := dead_zone * zoom
	var border_screen := border_zone * zoom

	_draw_centered_rect(center, border_screen, Color(1.0, 0.58, 0.18, 0.9), 2.0)
	_draw_centered_rect(center, dead_screen, Color(0.28, 0.82, 1.0, 0.95), 2.0)

func _draw_centered_rect(center: Vector2, half_size: Vector2, color_value: Color, width: float) -> void:
	var rect := Rect2(center - half_size, half_size * 2.0)
	draw_rect(rect, color_value, false, width)
