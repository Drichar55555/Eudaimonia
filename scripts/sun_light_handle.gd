@tool
extends Sprite2D

@export var handle_color := Color(1.0, 0.78, 0.24, 0.92):
	set(value):
		handle_color = value
		_update_handle_visual()
@export var runtime_hidden := true
@export var draw_arrow := false:
	set(value):
		draw_arrow = value
		queue_redraw()

func _ready() -> void:
	centered = true
	z_index = 1025
	z_as_relative = false
	_update_handle_visual()
	queue_redraw()

func _process(_delta: float) -> void:
	z_index = 1025
	z_as_relative = false
	_update_handle_visual()
	if Engine.is_editor_hint():
		queue_redraw()

func _update_handle_visual() -> void:
	modulate = handle_color
	visible = true if Engine.is_editor_hint() else not runtime_hidden

func _draw() -> void:
	if not Engine.is_editor_hint() or not draw_arrow:
		return
	var arrow_color := Color(1.0, 0.94, 0.45, 0.95)
	draw_line(Vector2.ZERO, Vector2(0.0, 150.0), arrow_color, 7.0, true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0.0, 190.0),
		Vector2(-42.0, 132.0),
		Vector2(42.0, 132.0),
	]), arrow_color)
