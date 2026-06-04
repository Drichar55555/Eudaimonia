@tool
extends "res://scripts/save_point.gd"

@export_group("Soul Lamp Visual")
@export var lamp_color := Color(0.22, 0.28, 0.26, 1.0):
	set(value):
		lamp_color = value
		queue_redraw()
@export var lamp_edge_color := Color(0.07, 0.09, 0.08, 0.9):
	set(value):
		lamp_edge_color = value
		queue_redraw()
@export var flame_color := Color(0.56, 0.92, 1.0, 0.9):
	set(value):
		flame_color = value
		queue_redraw()
@export var glow_color := Color(0.42, 0.82, 1.0, 0.18):
	set(value):
		glow_color = value
		queue_redraw()
@export var base_height := 88.0:
	set(value):
		base_height = maxf(value, 24.0)
		queue_redraw()
@export var lamp_width := 36.0:
	set(value):
		lamp_width = maxf(value, 14.0)
		queue_redraw()

func _draw() -> void:
	_draw_lamp()
	_draw_save_radius()

func _draw_lamp() -> void:
	var post_top := Vector2(0.0, -base_height)
	var post_bottom := Vector2(0.0, 0.0)
	draw_line(post_bottom, post_top, lamp_edge_color, 6.0, true)
	draw_line(post_bottom + Vector2(-16.0, 0.0), post_bottom + Vector2(16.0, 0.0), lamp_edge_color, 5.0, true)
	draw_line(post_bottom + Vector2(-10.0, -10.0), post_bottom + Vector2(10.0, -10.0), lamp_color, 7.0, true)

	var head_center := post_top + Vector2(0.0, -12.0)
	var half_width := lamp_width * 0.5
	var lamp_points := PackedVector2Array([
		head_center + Vector2(-half_width, -10.0),
		head_center + Vector2(half_width, -10.0),
		head_center + Vector2(half_width * 0.72, 16.0),
		head_center + Vector2(-half_width * 0.72, 16.0),
	])
	draw_colored_polygon(lamp_points, lamp_color)
	var closed := PackedVector2Array(lamp_points)
	closed.append(lamp_points[0])
	draw_polyline(closed, lamp_edge_color, 3.0, true)

	draw_circle(head_center + Vector2(0.0, 4.0), half_width * 1.6, glow_color)
	draw_circle(head_center + Vector2(0.0, 4.0), half_width * 0.42, flame_color)
	draw_circle(head_center + Vector2(0.0, 4.0), half_width * 0.16, Color(1.0, 1.0, 1.0, 0.82))

func _draw_save_radius() -> void:
	if Engine.is_editor_hint():
		if not show_editor_visual:
			return
	elif not show_runtime_visual:
		return
	var outline := debug_color
	outline.a = minf(debug_color.a + 0.45, 1.0)
	draw_circle(Vector2.ZERO, debug_radius, debug_color)
	draw_arc(Vector2.ZERO, debug_radius, 0.0, TAU, 48, outline, 3.0, true)
