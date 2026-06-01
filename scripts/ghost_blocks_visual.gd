@tool
extends StaticBody2D

const GHOST_BLOCK_LAYER := 1 << 3

@export var show_temporary_visual := true:
	set(value):
		show_temporary_visual = value
		queue_redraw()

@export var visual_color := Color(0.42, 0.78, 1.0, 0.23):
	set(value):
		visual_color = value
		queue_redraw()

@export var edge_color := Color(0.62, 0.92, 1.0, 0.8):
	set(value):
		edge_color = value
		queue_redraw()

@export var stripe_color := Color(0.9, 1.0, 1.0, 0.24):
	set(value):
		stripe_color = value
		queue_redraw()

@export var edge_width := 2.0:
	set(value):
		edge_width = value
		queue_redraw()

@export var stripe_spacing := 18.0:
	set(value):
		stripe_spacing = maxf(value, 6.0)
		queue_redraw()

func _ready() -> void:
	set_process(Engine.is_editor_hint())
	_configure_collision()
	queue_redraw()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()

func _draw() -> void:
	if not show_temporary_visual:
		return

	for child in get_children():
		var collision_polygon := child as CollisionPolygon2D
		if collision_polygon == null or collision_polygon.polygon.size() < 3:
			continue

		var points := _transformed_polygon(collision_polygon)
		_draw_fill(points)
		_draw_outline(points)
		_draw_stripes(points)

func _configure_collision() -> void:
	collision_layer = GHOST_BLOCK_LAYER
	collision_mask = 0
	for child in get_children():
		var collision_polygon := child as CollisionPolygon2D
		if collision_polygon != null:
			collision_polygon.disabled = false

func _transformed_polygon(collision_polygon: CollisionPolygon2D) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(collision_polygon.polygon.size())
	for index in collision_polygon.polygon.size():
		points[index] = collision_polygon.transform * collision_polygon.polygon[index]
	return points

func _draw_fill(points: PackedVector2Array) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.size() >= 3:
		for index in range(0, indices.size(), 3):
			_draw_triangle(points[indices[index]], points[indices[index + 1]], points[indices[index + 2]])
		return

	var center := _polygon_center(points)
	for index in points.size():
		var next_index := (index + 1) % points.size()
		_draw_triangle(center, points[index], points[next_index])

func _draw_triangle(a: Vector2, b: Vector2, c: Vector2) -> void:
	if absf((b - a).cross(c - a)) < 0.01:
		return
	draw_colored_polygon(PackedVector2Array([a, b, c]), visual_color)

func _draw_outline(points: PackedVector2Array) -> void:
	var closed_points := PackedVector2Array(points)
	closed_points.append(points[0])
	draw_polyline(closed_points, edge_color, edge_width)

func _draw_stripes(points: PackedVector2Array) -> void:
	var rect := _bounds_for_points(points)
	var start_x := rect.position.x - rect.size.y
	var end_x := rect.end.x + rect.size.y
	var x := start_x
	while x < end_x:
		draw_line(Vector2(x, rect.end.y), Vector2(x + rect.size.y, rect.position.y), stripe_color, 1.0)
		x += stripe_spacing

func _polygon_center(points: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in points:
		center += point
	return center / float(points.size())

func _bounds_for_points(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds
