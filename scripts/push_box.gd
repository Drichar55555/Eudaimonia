@tool
extends CharacterBody2D

const TERRAIN_LAYER := 1 << 0

@export_group("Push")
@export_range(0.05, 1.0, 0.05) var player_push_speed_multiplier := 0.55
@export_range(24.0, 520.0, 4.0) var max_push_speed := 150.0
@export_range(0.0, 48.0, 1.0) var skin_width := 2.0
@export var can_step_over_small_obstacles := true
@export_range(2.0, 36.0, 1.0) var max_step_height := 14.0
@export_range(1.0, 12.0, 1.0) var step_scan_increment := 2.0
@export_range(0.1, 1.0, 0.05) var step_push_speed_multiplier := 0.45

@export_group("Visual")
@export var fill_color := Color(0.47, 0.34, 0.22, 1.0):
	set(value):
		fill_color = value
		queue_redraw()
@export var edge_color := Color(0.12, 0.08, 0.05, 0.95):
	set(value):
		edge_color = value
		queue_redraw()
@export var band_color := Color(0.70, 0.54, 0.34, 0.85):
	set(value):
		band_color = value
		queue_redraw()
@export_range(0.0, 8.0, 0.25) var outline_width := 2.0:
	set(value):
		outline_width = value
		queue_redraw()

var _last_push_direction := 0.0
var _last_push_was_step := false

func _ready() -> void:
	z_index = 12
	z_as_relative = false
	add_to_group("pushable_boxes")
	add_to_group("saveable")
	collision_layer = TERRAIN_LAYER
	collision_mask = TERRAIN_LAYER
	set_physics_process(false)
	queue_redraw()

func push_from_player(push_direction: float, player_speed: float, delta: float, _player: Node = null) -> bool:
	if is_zero_approx(push_direction) or delta <= 0.0:
		return false
	var direction := signf(push_direction)
	var speed := clampf(maxf(player_speed, max_push_speed * 0.35), 0.0, max_push_speed)
	var motion := Vector2(direction * speed * delta, 0.0)
	if skin_width > 0.0:
		motion.x += direction * skin_width
	var collision := move_and_collide(motion)
	if collision != null:
		var recovery := direction * skin_width
		if not is_zero_approx(recovery):
			global_position.x -= recovery
		if can_step_over_small_obstacles and _try_step_over_small_obstacle(direction, speed, delta):
			_last_push_direction = direction
			_last_push_was_step = true
			queue_redraw()
			return true
		return false
	_last_push_direction = direction
	_last_push_was_step = false
	queue_redraw()
	return true

func _try_step_over_small_obstacle(push_direction: float, push_speed: float, delta: float) -> bool:
	if max_step_height <= 0.0 or step_scan_increment <= 0.0:
		return false
	var step_speed := clampf(push_speed * step_push_speed_multiplier, 0.0, max_push_speed)
	var horizontal_motion := Vector2(push_direction * step_speed * delta, 0.0)
	if skin_width > 0.0:
		horizontal_motion.x += push_direction * skin_width
	if is_zero_approx(horizontal_motion.x):
		return false
	var step_height := step_scan_increment
	while step_height <= max_step_height + 0.001:
		if _can_step_with_height(step_height, horizontal_motion):
			_apply_step_motion(step_height, horizontal_motion)
			return true
		step_height += step_scan_increment
	return false

func _can_step_with_height(step_height: float, horizontal_motion: Vector2) -> bool:
	var raised_transform := global_transform.translated(Vector2(0.0, -step_height))
	if test_move(global_transform, Vector2(0.0, -step_height)):
		return false
	if test_move(raised_transform, horizontal_motion):
		return false
	return true

func _apply_step_motion(step_height: float, horizontal_motion: Vector2) -> void:
	global_position.y -= step_height
	var collision := move_and_collide(horizontal_motion)
	if collision != null:
		var recovery := signf(horizontal_motion.x) * skin_width
		if not is_zero_approx(recovery):
			global_position.x -= recovery
		return
	_settle_after_step(step_height + 4.0)

func _settle_after_step(max_drop: float) -> void:
	if max_drop <= 0.0:
		return
	var collision := move_and_collide(Vector2(0.0, max_drop))
	if collision != null:
		return
	global_position.y -= max_drop

func get_push_speed_multiplier() -> float:
	if _last_push_was_step:
		return minf(player_push_speed_multiplier, player_push_speed_multiplier * step_push_speed_multiplier)
	return player_push_speed_multiplier

func get_save_state() -> Dictionary:
	return {
		"position": global_position,
		"last_push_direction": _last_push_direction,
		"last_push_was_step": _last_push_was_step,
	}

func apply_save_state(state: Dictionary) -> void:
	global_position = state.get("position", global_position)
	_last_push_direction = float(state.get("last_push_direction", 0.0))
	_last_push_was_step = bool(state.get("last_push_was_step", false))
	queue_redraw()

func _draw() -> void:
	for collision_polygon in _collision_polygons():
		var points := _transformed_polygon(collision_polygon)
		_draw_fill(points, fill_color)
		_draw_outline(points, edge_color, outline_width)
		_draw_box_bands(points)

func _collision_polygons() -> Array[CollisionPolygon2D]:
	var polygons: Array[CollisionPolygon2D] = []
	for child in get_children():
		var collision_polygon := child as CollisionPolygon2D
		if collision_polygon != null and collision_polygon.polygon.size() >= 3:
			polygons.append(collision_polygon)
	return polygons

func _transformed_polygon(collision_polygon: CollisionPolygon2D) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(collision_polygon.polygon.size())
	for index in collision_polygon.polygon.size():
		points[index] = collision_polygon.transform * collision_polygon.polygon[index]
	return points

func _draw_fill(points: PackedVector2Array, color: Color) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.size() >= 3:
		for index in range(0, indices.size(), 3):
			_draw_triangle(points[indices[index]], points[indices[index + 1]], points[indices[index + 2]], color)
		return
	var center := _polygon_center(points)
	for index in points.size():
		_draw_triangle(center, points[index], points[(index + 1) % points.size()], color)

func _draw_triangle(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	if absf((b - a).cross(c - a)) < 0.01:
		return
	draw_colored_polygon(PackedVector2Array([a, b, c]), color)

func _draw_outline(points: PackedVector2Array, color: Color, width: float) -> void:
	if width <= 0.0:
		return
	var closed := PackedVector2Array(points)
	closed.append(points[0])
	draw_polyline(closed, color, width, true)

func _draw_box_bands(points: PackedVector2Array) -> void:
	var bounds := _polygon_bounds(points)
	draw_line(bounds.position + Vector2(bounds.size.x * 0.22, 0.0), bounds.position + Vector2(bounds.size.x * 0.22, bounds.size.y), band_color, 3.0, true)
	draw_line(bounds.position + Vector2(bounds.size.x * 0.78, 0.0), bounds.position + Vector2(bounds.size.x * 0.78, bounds.size.y), band_color, 3.0, true)
	draw_line(bounds.position + Vector2(0.0, bounds.size.y * 0.22), bounds.position + Vector2(bounds.size.x, bounds.size.y * 0.22), band_color, 3.0, true)
	draw_line(bounds.position + Vector2(0.0, bounds.size.y * 0.78), bounds.position + Vector2(bounds.size.x, bounds.size.y * 0.78), band_color, 3.0, true)
	if not is_zero_approx(_last_push_direction):
		var center := bounds.get_center()
		draw_line(center, center + Vector2(_last_push_direction * 18.0, 0.0), band_color, 2.0, true)

func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds

func _polygon_center(points: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in points:
		center += point
	return center / float(points.size())
