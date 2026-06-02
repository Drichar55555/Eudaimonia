@tool
extends StaticBody2D

const GHOST_BLOCK_LAYER := 1 << 3

@export var show_temporary_visual := true:
	set(value):
		show_temporary_visual = value
		queue_redraw()

@export_group("Normal Material")
@export var normal_fill_color := Color(0.30, 0.34, 0.32, 1.0):
	set(value):
		normal_fill_color = value
		queue_redraw()

@export var normal_edge_color := Color(0.08, 0.10, 0.10, 0.72):
	set(value):
		normal_edge_color = value
		queue_redraw()

@export var normal_stripe_color := Color(0.20, 0.24, 0.22, 0.35):
	set(value):
		normal_stripe_color = value
		queue_redraw()

@export_group("Euda Mask Effect")
@export var euda_blur_color := Color(0.68, 1.0, 0.86, 0.22):
	set(value):
		euda_blur_color = value
		queue_redraw()

@export var euda_edge_color := Color(0.78, 1.0, 0.92, 0.86):
	set(value):
		euda_edge_color = value
		queue_redraw()

@export var euda_flicker_color := Color(1.0, 1.0, 1.0, 0.34):
	set(value):
		euda_flicker_color = value
		queue_redraw()

@export var euda_blur_offset := 5.0:
	set(value):
		euda_blur_offset = maxf(value, 0.0)
		queue_redraw()

@export var euda_flicker_speed := 9.5:
	set(value):
		euda_flicker_speed = maxf(value, 0.1)
		queue_redraw()

@export_group("Geometry Style")

@export var edge_width := 2.0:
	set(value):
		edge_width = value
		queue_redraw()

@export var stripe_spacing := 18.0:
	set(value):
		stripe_spacing = maxf(value, 6.0)
		queue_redraw()

var _euda_mask_active := false

func _ready() -> void:
	add_to_group("ghost_blocks")
	set_process(Engine.is_editor_hint())
	_configure_collision()
	queue_redraw()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _euda_mask_active:
		queue_redraw()

func _draw() -> void:
	if not show_temporary_visual:
		return

	for child in get_children():
		var collision_polygon := child as CollisionPolygon2D
		if collision_polygon == null or collision_polygon.polygon.size() < 3:
			continue

		var points := _transformed_polygon(collision_polygon)
		_draw_fill(points, normal_fill_color)
		_draw_stripes(points, normal_stripe_color, 1.0)
		_draw_outline(points, normal_edge_color, edge_width)
		if _euda_mask_active:
			_draw_euda_distortion(points)

func set_revealed_by_euda_mask(is_revealed: bool) -> void:
	set_euda_mask_active(is_revealed)

func is_revealed_by_euda_mask() -> bool:
	return _euda_mask_active

func set_euda_mask_active(is_active: bool) -> void:
	if _euda_mask_active == is_active:
		return
	_euda_mask_active = is_active
	set_process(Engine.is_editor_hint() or _euda_mask_active)
	queue_redraw()

func is_euda_mask_active() -> bool:
	return _euda_mask_active

func get_visual_mode() -> String:
	return "euda_distortion" if _euda_mask_active else "normal_material"

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

func _draw_fill(points: PackedVector2Array, fill_color: Color) -> void:
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

func _draw_outline(points: PackedVector2Array, color: Color, width: float) -> void:
	var closed_points := PackedVector2Array(points)
	closed_points.append(points[0])
	draw_polyline(closed_points, color, width)

func _draw_stripes(points: PackedVector2Array, color: Color, width: float) -> void:
	var rect := _bounds_for_points(points)
	var start_x := rect.position.x - rect.size.y
	var end_x := rect.end.x + rect.size.y
	var x := start_x
	while x < end_x:
		draw_line(Vector2(x, rect.end.y), Vector2(x + rect.size.y, rect.position.y), color, width)
		x += stripe_spacing

func _draw_euda_distortion(points: PackedVector2Array) -> void:
	var flicker := _euda_flicker_amount()
	var blur_color := euda_blur_color
	blur_color.a *= 0.65 + flicker * 0.45
	for offset in [Vector2(-euda_blur_offset, 0.0), Vector2(euda_blur_offset, 0.0), Vector2(0.0, -euda_blur_offset * 0.65), Vector2(0.0, euda_blur_offset * 0.65)]:
		_draw_fill(_offset_points(points, offset), blur_color)

	var pulse_edge := euda_edge_color
	pulse_edge.a *= 0.65 + flicker * 0.35
	_draw_outline(points, pulse_edge, edge_width + 1.0 + flicker * 1.5)

	var flash_color := euda_flicker_color
	flash_color.a *= 0.35 + flicker * 0.65
	_draw_stripes(points, flash_color, 1.0 + flicker * 1.5)
	_draw_flicker_slices(points, flash_color, flicker)

func _draw_flicker_slices(points: PackedVector2Array, color: Color, flicker: float) -> void:
	var rect := _bounds_for_points(points)
	var slice_count := 4
	for index in slice_count:
		var y := lerpf(rect.position.y, rect.end.y, (float(index) + 0.5) / float(slice_count))
		var offset := sin(Time.get_ticks_msec() * 0.008 + index * 1.7) * euda_blur_offset * (0.5 + flicker)
		var slice_color := color
		slice_color.a *= 0.45
		draw_line(Vector2(rect.position.x + offset, y), Vector2(rect.end.x + offset, y), slice_color, 2.0)

func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var shifted := PackedVector2Array()
	shifted.resize(points.size())
	for index in points.size():
		shifted[index] = points[index] + offset
	return shifted

func _euda_flicker_amount() -> float:
	var time := Time.get_ticks_msec() / 1000.0
	return 0.5 + 0.5 * sin(time * euda_flicker_speed)

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
