@tool
extends "res://scripts/stair.gd"

const GHOST_BLOCK_LAYER := 1 << 3

@export_group("Ghost Material")
@export var ghost_fill_color := Color(0.30, 0.34, 0.32, 0.9):
	set(value):
		ghost_fill_color = value
		queue_redraw()
@export var ghost_edge_color := Color(0.08, 0.10, 0.10, 0.78):
	set(value):
		ghost_edge_color = value
		queue_redraw()
@export var ghost_stripe_color := Color(0.20, 0.24, 0.22, 0.4):
	set(value):
		ghost_stripe_color = value
		queue_redraw()
@export_range(6.0, 48.0, 1.0) var stripe_spacing := 18.0:
	set(value):
		stripe_spacing = maxf(value, 6.0)
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
@export_range(0.0, 16.0, 0.5) var euda_blur_offset := 5.0:
	set(value):
		euda_blur_offset = maxf(value, 0.0)
		queue_redraw()
@export_range(0.1, 30.0, 0.1) var euda_flicker_speed := 9.5:
	set(value):
		euda_flicker_speed = maxf(value, 0.1)
		queue_redraw()

var _euda_mask_active := false

func _ready() -> void:
	super._ready()
	add_to_group("ghost_blocks")
	_configure_ghost_collision()
	set_process(Engine.is_editor_hint() or _euda_mask_active)

func _process(delta: float) -> void:
	super._process(delta)
	if Engine.is_editor_hint() or _euda_mask_active:
		queue_redraw()

func _draw() -> void:
	var stair_polygon := get_stair_polygon()
	if stair_polygon.size() < 3:
		return
	_draw_polygon_fill(stair_polygon, ghost_fill_color)
	_draw_clipped_stripes(stair_polygon, ghost_stripe_color)
	_draw_polygon_outline(stair_polygon, ghost_edge_color, outline_width)
	if _euda_mask_active:
		_draw_euda_distortion(stair_polygon)

func set_revealed_by_euda_mask(is_revealed: bool) -> void:
	if _euda_mask_active == is_revealed:
		return
	_euda_mask_active = is_revealed
	set_process(Engine.is_editor_hint() or _euda_mask_active)
	queue_redraw()

func is_revealed_by_euda_mask() -> bool:
	return _euda_mask_active

func _configure_ghost_collision() -> void:
	var collision_body := get_node_or_null(collision_body_path) as StaticBody2D
	if collision_body == null:
		return
	collision_body.collision_layer = GHOST_BLOCK_LAYER
	collision_body.collision_mask = 0
	collision_body.add_to_group("ghost_block_collision_bodies")

func _draw_euda_distortion(points: PackedVector2Array) -> void:
	var flicker := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * euda_flicker_speed)
	var blur := euda_blur_color
	blur.a *= 0.65 + flicker * 0.45
	for offset in [
		Vector2(-euda_blur_offset, 0.0),
		Vector2(euda_blur_offset, 0.0),
		Vector2(0.0, -euda_blur_offset * 0.65),
		Vector2(0.0, euda_blur_offset * 0.65),
	]:
		_draw_polygon_fill(_offset_points(points, offset), blur)
	var pulse_edge := euda_edge_color
	pulse_edge.a *= 0.65 + flicker * 0.35
	_draw_polygon_outline(points, pulse_edge, outline_width + 1.0 + flicker * 1.5)
	var flash := euda_flicker_color
	flash.a *= 0.35 + flicker * 0.65
	_draw_clipped_stripes(points, flash, 1.0 + flicker * 1.5)

func _draw_polygon_fill(points: PackedVector2Array, color_value: Color) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	for index in range(0, indices.size(), 3):
		if index + 2 >= indices.size():
			break
		var a := points[indices[index]]
		var b := points[indices[index + 1]]
		var c := points[indices[index + 2]]
		if absf((b - a).cross(c - a)) < 0.01:
			continue
		draw_colored_polygon(PackedVector2Array([a, b, c]), color_value)

func _draw_polygon_outline(points: PackedVector2Array, color_value: Color, width: float) -> void:
	if width <= 0.0:
		return
	var closed := PackedVector2Array(points)
	closed.append(points[0])
	draw_polyline(closed, color_value, width, true)

func _draw_clipped_stripes(points: PackedVector2Array, color_value: Color, width := 1.0) -> void:
	var bounds := _points_bounds(points)
	var stripe_x := bounds.position.x - bounds.size.y
	var stripe_extent := bounds.size.y + maxf(width, 1.0) * 2.0
	while stripe_x < bounds.end.x + bounds.size.y:
		var stripe_polygon := PackedVector2Array([
			Vector2(stripe_x - width, bounds.end.y + width),
			Vector2(stripe_x + width, bounds.end.y + width),
			Vector2(stripe_x + stripe_extent + width, bounds.position.y - width),
			Vector2(stripe_x + stripe_extent - width, bounds.position.y - width),
		])
		for clipped_polygon in Geometry2D.intersect_polygons(stripe_polygon, points):
			if clipped_polygon.size() >= 3:
				draw_colored_polygon(clipped_polygon, color_value)
		stripe_x += stripe_spacing

func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var shifted := PackedVector2Array()
	for point in points:
		shifted.append(point + offset)
	return shifted

func _points_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds
