@tool
extends StaticBody2D

@export var show_temporary_visual := true:
	set(value):
		show_temporary_visual = value
		queue_redraw()

@export var ground_color := Color(0.24, 0.28, 0.26, 1.0):
	set(value):
		ground_color = value
		queue_redraw()

@export var wall_color := Color(0.32, 0.34, 0.32, 1.0):
	set(value):
		wall_color = value
		queue_redraw()

@export var floating_color := Color(0.28, 0.31, 0.29, 1.0):
	set(value):
		floating_color = value
		queue_redraw()

@export var fallback_color := Color(0.3, 0.34, 0.32, 1.0):
	set(value):
		fallback_color = value
		queue_redraw()

@export var outline_color := Color(0.08, 0.1, 0.1, 0.65):
	set(value):
		outline_color = value
		queue_redraw()

@export var outline_width := 2.0:
	set(value):
		outline_width = value
		queue_redraw()

func _ready() -> void:
	set_process(Engine.is_editor_hint())
	queue_redraw()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()

func _draw() -> void:
	if not show_temporary_visual:
		return

	for child in get_children():
		var collision_polygon := child as CollisionPolygon2D
		if collision_polygon == null:
			continue
		if collision_polygon.polygon.size() < 3:
			continue

		var points := _transformed_polygon(collision_polygon)
		var fill_color := _color_for_collision(collision_polygon.name)
		_draw_temporary_fill(points, fill_color)
		_draw_outline(points)

func _draw_temporary_fill(points: PackedVector2Array, fill_color: Color) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.size() >= 3:
		for index in range(0, indices.size(), 3):
			_draw_triangle(points[indices[index]], points[indices[index + 1]], points[indices[index + 2]], fill_color)
		return

	var center := _polygon_center(points)
	for index in points.size():
		var next_index := (index + 1) % points.size()
		_draw_triangle(center, points[index], points[next_index], fill_color)

func _draw_triangle(a: Vector2, b: Vector2, c: Vector2, fill_color: Color) -> void:
	if absf((b - a).cross(c - a)) < 0.01:
		return
	draw_colored_polygon(PackedVector2Array([a, b, c]), fill_color)

func _polygon_center(points: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in points:
		center += point
	return center / float(points.size())

func _transformed_polygon(collision_polygon: CollisionPolygon2D) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(collision_polygon.polygon.size())

	for index in collision_polygon.polygon.size():
		points[index] = collision_polygon.transform * collision_polygon.polygon[index]

	return points

func _color_for_collision(collision_name: StringName) -> Color:
	var name_text := String(collision_name).to_lower()
	if name_text.contains("ground"):
		return ground_color
	if name_text.contains("wall"):
		return wall_color
	if name_text.contains("floating") or name_text.contains("rock"):
		return floating_color
	return fallback_color

func _draw_outline(points: PackedVector2Array) -> void:
	if outline_width <= 0.0:
		return

	var closed_points := PackedVector2Array(points)
	closed_points.append(points[0])
	draw_polyline(closed_points, outline_color, outline_width)
