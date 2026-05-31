@tool
extends Area2D

@export var room_id := "Room":
	set(value):
		room_id = value
		queue_redraw()
@export_enum("custom", "horizontal", "vertical_shaft", "platforming", "boss", "cinematic") var camera_profile := "horizontal":
	set(value):
		camera_profile = value
		queue_redraw()
@export_enum("free_size", "horizontal_follow", "vertical_follow", "no_follow") var camera_view_mode := "free_size":
	set(value):
		camera_view_mode = value
		queue_redraw()
@export var manual_camera_rect := false:
	set(value):
		manual_camera_rect = value
		queue_redraw()
@export var camera_rect := Rect2(-180.0, -120.0, 1600.0, 900.0):
	set(value):
		camera_rect = value
		queue_redraw()
@export_range(320.0, 4096.0, 8.0) var camera_view_width := 1280.0:
	set(value):
		camera_view_width = value
		queue_redraw()
@export_enum("smooth", "fade_to_black") var transition_mode := "smooth":
	set(value):
		transition_mode = value
		queue_redraw()
@export var lookahead_distance: float = 96.0:
	set(value):
		lookahead_distance = value
		queue_redraw()
@export var vertical_offset: float = 0.0:
	set(value):
		vertical_offset = value
		queue_redraw()
@export var dead_zone := Vector2(42.0, 88.0):
	set(value):
		dead_zone = value
		queue_redraw()
@export var border_zone := Vector2(180.0, 140.0):
	set(value):
		border_zone = value
		queue_redraw()
@export var follow_damping := Vector2(7.5, 4.5):
	set(value):
		follow_damping = value
		queue_redraw()
@export var border_damping := Vector2(15.0, 10.0):
	set(value):
		border_damping = value
		queue_redraw()
@export var debug_color := Color(0.95, 0.78, 0.25, 0.5):
	set(value):
		debug_color = value
		queue_redraw()
@export var camera_view_color := Color(0.35, 1.0, 0.55, 0.9):
	set(value):
		camera_view_color = value
		queue_redraw()

func _ready() -> void:
	add_to_group("camera_rooms")
	monitoring = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	set_process(Engine.is_editor_hint())
	queue_redraw()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()

func get_camera_rect() -> Rect2:
	match camera_view_mode:
		"horizontal_follow", "vertical_follow":
			return _trigger_rect()
		"no_follow":
			return _screen_ratio_rect_for_trigger()
	if not manual_camera_rect:
		return _trigger_rect()
	return camera_rect

func get_camera_zoom() -> Vector2:
	return _zoom_for_view_size(get_camera_view_size())

func get_camera_view_size() -> Vector2:
	var rect := get_camera_rect()
	if camera_view_mode == "no_follow":
		return rect.size

	match camera_view_mode:
		"horizontal_follow":
			return _fit_aspect_size_inside(Vector2(rect.size.y * _screen_aspect_ratio(), rect.size.y), rect.size)
		"vertical_follow":
			return _fit_aspect_size_inside(Vector2(rect.size.x, rect.size.x / _screen_aspect_ratio()), rect.size)
		_:
			return _fit_aspect_size_inside(_screen_ratio_size_from_width(camera_view_width), rect.size)

func get_no_follow() -> bool:
	return camera_view_mode == "no_follow"

func get_camera_view_mode() -> String:
	return camera_view_mode

func get_transition_mode() -> String:
	return transition_mode

func get_camera_profile() -> String:
	return camera_profile

func get_lookahead_distance() -> float:
	if camera_profile != "custom":
		return _profile_lookahead_distance()
	return lookahead_distance

func get_vertical_offset() -> float:
	if camera_profile != "custom":
		return _profile_vertical_offset()
	return vertical_offset

func get_dead_zone() -> Vector2:
	if camera_profile != "custom":
		return _profile_dead_zone()
	return dead_zone

func get_border_zone() -> Vector2:
	if camera_profile != "custom":
		return _profile_border_zone()
	return border_zone

func get_follow_damping() -> Vector2:
	if camera_profile != "custom":
		return _profile_follow_damping()
	return follow_damping

func get_border_damping() -> Vector2:
	if camera_profile != "custom":
		return _profile_border_damping()
	return border_damping

func _profile_lookahead_distance() -> float:
	match camera_profile:
		"horizontal":
			return 120.0
		"vertical_shaft":
			return 32.0
		"platforming":
			return 72.0
		"boss":
			return 24.0
		"cinematic":
			return 100.0
		_:
			return lookahead_distance

func _profile_vertical_offset() -> float:
	match camera_profile:
		"vertical_shaft":
			return -24.0
		"boss":
			return -18.0
		"cinematic":
			return -48.0
		_:
			return 0.0

func _profile_dead_zone() -> Vector2:
	match camera_profile:
		"horizontal":
			return Vector2(90.0, 104.0)
		"vertical_shaft":
			return Vector2(150.0, 64.0)
		"platforming":
			return Vector2(72.0, 72.0)
		"boss":
			return Vector2(180.0, 130.0)
		"cinematic":
			return Vector2(120.0, 95.0)
		_:
			return dead_zone

func _profile_border_zone() -> Vector2:
	match camera_profile:
		"horizontal":
			return Vector2(220.0, 155.0)
		"vertical_shaft":
			return Vector2(230.0, 120.0)
		"platforming":
			return Vector2(180.0, 130.0)
		"boss":
			return Vector2(230.0, 180.0)
		"cinematic":
			return Vector2(210.0, 150.0)
		_:
			return border_zone

func _profile_follow_damping() -> Vector2:
	match camera_profile:
		"horizontal":
			return Vector2(7.0, 4.0)
		"vertical_shaft":
			return Vector2(4.0, 8.5)
		"platforming":
			return Vector2(8.0, 6.5)
		"boss":
			return Vector2(4.8, 4.2)
		"cinematic":
			return Vector2(3.8, 3.2)
		_:
			return follow_damping

func _profile_border_damping() -> Vector2:
	match camera_profile:
		"horizontal":
			return Vector2(16.0, 10.0)
		"vertical_shaft":
			return Vector2(9.0, 18.0)
		"platforming":
			return Vector2(17.0, 13.0)
		"boss":
			return Vector2(10.0, 9.0)
		"cinematic":
			return Vector2(8.0, 7.0)
		_:
			return border_damping

func contains_point(point: Vector2) -> bool:
	return _trigger_rect().has_point(point)

func get_trigger_rect() -> Rect2:
	return _trigger_rect()

func _on_body_entered(body: Node2D) -> void:
	if body.name != "Player":
		return
	get_tree().call_group("room_cameras", "request_room_refresh")

func _draw() -> void:
	var camera_rect_value := get_camera_rect()
	var local_rect := Rect2(to_local(camera_rect_value.position), camera_rect_value.size)
	draw_rect(local_rect, debug_color, false, 4.0)
	draw_rect(local_rect.grow(-8.0), Color(debug_color.r, debug_color.g, debug_color.b, 0.12), true)

	var view_size := get_camera_view_size()
	var view_center := _trigger_rect().get_center()
	var view_rect := Rect2(to_local(view_center - view_size * 0.5), view_size)
	draw_rect(view_rect, camera_view_color, false, 3.0)
	_draw_center_marker(to_local(view_center), camera_view_color)

func _draw_center_marker(center: Vector2, marker_color: Color) -> void:
	draw_line(center + Vector2(-10.0, 0.0), center + Vector2(10.0, 0.0), marker_color, 2.0)
	draw_line(center + Vector2(0.0, -10.0), center + Vector2(0.0, 10.0), marker_color, 2.0)

func _trigger_rect() -> Rect2:
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape == null or collision_shape.shape == null:
		return camera_rect

	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle == null:
		return camera_rect

	var shape_size := rectangle.size * collision_shape.scale.abs()
	var top_left := collision_shape.global_position - shape_size * 0.5
	return Rect2(top_left, shape_size)

func _screen_ratio_rect_for_trigger() -> Rect2:
	var rect := _trigger_rect()
	var target_ratio := _screen_aspect_ratio()
	var current_ratio := rect.size.x / rect.size.y

	if current_ratio > target_ratio:
		var target_height := rect.size.x / target_ratio
		var offset_y := (target_height - rect.size.y) * 0.5
		return Rect2(Vector2(rect.position.x, rect.position.y - offset_y), Vector2(rect.size.x, target_height))

	var target_width := rect.size.y * target_ratio
	var offset_x := (target_width - rect.size.x) * 0.5
	return Rect2(Vector2(rect.position.x - offset_x, rect.position.y), Vector2(target_width, rect.size.y))

func _zoom_to_fit_rect(rect: Rect2) -> Vector2:
	return _zoom_for_view_size(rect.size)

func _zoom_for_view_size(view_size: Vector2) -> Vector2:
	var viewport_size := Vector2(1280.0, 720.0)
	var zoom := minf(viewport_size.x / view_size.x, viewport_size.y / view_size.y)
	zoom = maxf(zoom, 0.1)
	return Vector2(zoom, zoom)

func _screen_ratio_size_from_width(width: float) -> Vector2:
	return Vector2(width, width / _screen_aspect_ratio())

func _fit_aspect_size_inside(view_size: Vector2, bounds_size: Vector2) -> Vector2:
	if view_size.x <= 0.0 or view_size.y <= 0.0 or bounds_size.x <= 0.0 or bounds_size.y <= 0.0:
		return Vector2.ZERO

	var scale := minf(bounds_size.x / view_size.x, bounds_size.y / view_size.y)
	scale = minf(scale, 1.0)
	return view_size * scale

func _screen_aspect_ratio() -> float:
	return 16.0 / 9.0
