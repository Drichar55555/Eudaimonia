@tool
extends AnimatableBody2D

const TERRAIN_LAYER := 1 << 0

enum PlatformState { IDLE, RISING, WAITING, DESCENDING }

@export_group("Movement")
@export_range(16.0, 1200.0, 1.0) var rise_height := 180.0:
	set(value):
		rise_height = maxf(value, 16.0)
		queue_redraw()
@export_range(0.1, 8.0, 0.05) var rise_time := 1.2
@export_range(0.0, 10.0, 0.1) var top_wait_time := 1.5
@export_range(0.1, 8.0, 0.05) var descend_time := 1.4

@export_group("Platform")
@export var platform_size := Vector2(128.0, 24.0):
	set(value):
		platform_size = Vector2(maxf(value.x, 24.0), maxf(value.y, 8.0))
		_sync_shapes()
		queue_redraw()
@export var fill_color := Color(0.25, 0.31, 0.30, 1.0):
	set(value):
		fill_color = value
		queue_redraw()
@export var edge_color := Color(0.0, 0.86, 0.76, 0.95):
	set(value):
		edge_color = value
		queue_redraw()
@export_range(0.0, 8.0, 0.25) var edge_width := 2.0:
	set(value):
		edge_width = value
		queue_redraw()

@export_group("Editor Preview")
@export var show_height_preview := true:
	set(value):
		show_height_preview = value
		queue_redraw()
@export var preview_color := Color(0.0, 0.86, 0.76, 0.32):
	set(value):
		preview_color = value
		queue_redraw()

var _origin_position := Vector2.ZERO
var _target_position := Vector2.ZERO
var _move_from := Vector2.ZERO
var _move_to := Vector2.ZERO
var _move_elapsed := 0.0
var _wait_elapsed := 0.0
var _state := PlatformState.IDLE
var _armed := true
var _players_on_platform := 0
var _trigger_area: Area2D

func _ready() -> void:
	z_index = 1
	z_as_relative = false
	collision_layer = TERRAIN_LAYER
	collision_mask = 0
	_origin_position = global_position
	_target_position = _origin_position + Vector2.UP * rise_height
	_trigger_area = get_node_or_null("PlayerSensor") as Area2D
	_sync_shapes()
	if _trigger_area != null:
		_trigger_area.body_entered.connect(_on_sensor_body_entered)
		_trigger_area.body_exited.connect(_on_sensor_body_exited)
	set_physics_process(not Engine.is_editor_hint())
	queue_redraw()

func _physics_process(delta: float) -> void:
	match _state:
		PlatformState.RISING:
			_advance_motion(delta, rise_time, PlatformState.WAITING)
		PlatformState.WAITING:
			_wait_elapsed += delta
			if _wait_elapsed >= top_wait_time:
				_begin_motion(_origin_position, PlatformState.DESCENDING)
		PlatformState.DESCENDING:
			_advance_motion(delta, descend_time, PlatformState.IDLE)

func _draw() -> void:
	var body_rect := Rect2(-platform_size * 0.5, platform_size)
	draw_rect(body_rect, fill_color, true)
	if edge_width > 0.0:
		draw_rect(body_rect, edge_color, false, edge_width, true)
	var inner_color := edge_color
	inner_color.a *= 0.45
	draw_line(Vector2(-platform_size.x * 0.3, 0.0), Vector2(platform_size.x * 0.3, 0.0), inner_color, 2.0, true)
	if Engine.is_editor_hint() and show_height_preview:
		_draw_height_preview()

func set_rise_height_from_editor(local_target: Vector2) -> void:
	rise_height = maxf(-local_target.y, 16.0)
	queue_redraw()

func get_rise_target_point() -> Vector2:
	return Vector2(0.0, -rise_height)

func is_point_near_platform(local_point: Vector2, radius: float) -> bool:
	var body_rect := Rect2(-platform_size * 0.5, platform_size).grow(radius)
	return body_rect.has_point(local_point)

func _edit_is_selected_on_click(point: Vector2, tolerance: float) -> bool:
	return is_point_near_platform(point, tolerance)

func _on_sensor_body_entered(body: Node) -> void:
	if not body.is_in_group("players"):
		return
	_players_on_platform += 1
	if _state == PlatformState.IDLE and _armed and _is_player_above_platform(body as Node2D):
		_armed = false
		_target_position = _origin_position + Vector2.UP * rise_height
		_begin_motion(_target_position, PlatformState.RISING)

func _on_sensor_body_exited(body: Node) -> void:
	if not body.is_in_group("players"):
		return
	_players_on_platform = maxi(_players_on_platform - 1, 0)
	if _players_on_platform == 0:
		_armed = true

func _is_player_above_platform(body: Node2D) -> bool:
	return body != null and body.global_position.y < global_position.y + platform_size.y * 0.5

func _begin_motion(destination: Vector2, next_state: int) -> void:
	_move_from = global_position
	_move_to = destination
	_move_elapsed = 0.0
	_wait_elapsed = 0.0
	_state = next_state

func _advance_motion(delta: float, duration: float, finished_state: int) -> void:
	_move_elapsed += delta
	var raw_progress := clampf(_move_elapsed / maxf(duration, 0.001), 0.0, 1.0)
	var smooth_progress := raw_progress * raw_progress * (3.0 - 2.0 * raw_progress)
	global_position = _move_from.lerp(_move_to, smooth_progress)
	if raw_progress < 1.0:
		return
	global_position = _move_to
	_state = finished_state
	_move_elapsed = 0.0
	if finished_state == PlatformState.WAITING:
		_wait_elapsed = 0.0
	elif finished_state == PlatformState.IDLE:
		_origin_position = global_position

func _sync_shapes() -> void:
	if not is_inside_tree():
		return
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null:
		var body_rectangle := collision_shape.shape as RectangleShape2D
		if body_rectangle == null:
			body_rectangle = RectangleShape2D.new()
			collision_shape.shape = body_rectangle
		body_rectangle.size = platform_size
	var sensor_shape := get_node_or_null("PlayerSensor/CollisionShape2D") as CollisionShape2D
	if sensor_shape != null:
		var sensor_rectangle := sensor_shape.shape as RectangleShape2D
		if sensor_rectangle == null:
			sensor_rectangle = RectangleShape2D.new()
			sensor_shape.shape = sensor_rectangle
		sensor_rectangle.size = Vector2(maxf(platform_size.x - 12.0, 12.0), maxf(platform_size.y + 28.0, 32.0))
		sensor_shape.position = Vector2(0.0, -platform_size.y * 0.5 - sensor_rectangle.size.y * 0.5 + 4.0)

func _draw_height_preview() -> void:
	var target := get_rise_target_point()
	var half_width := platform_size.x * 0.5
	var target_rect := Rect2(target - platform_size * 0.5, platform_size)
	draw_rect(target_rect, preview_color, true)
	var outline := preview_color
	outline.a = minf(outline.a + 0.35, 1.0)
	draw_rect(target_rect, outline, false, 2.0, true)
	draw_dashed_line(Vector2(-half_width - 14.0, 0.0), Vector2(-half_width - 14.0, target.y), outline, 2.0, 8.0, true)
	var arrow_x := -half_width - 14.0
	draw_line(Vector2(arrow_x, target.y), Vector2(arrow_x - 6.0, target.y + 10.0), outline, 2.0, true)
	draw_line(Vector2(arrow_x, target.y), Vector2(arrow_x + 6.0, target.y + 10.0), outline, 2.0, true)
