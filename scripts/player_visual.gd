extends Node2D

func _ready() -> void:
	z_index = 100
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2(-24, -42), Vector2(48, 56)), Color(0.36, 0.78, 1.0), true)
	draw_rect(Rect2(Vector2(-24, -42), Vector2(48, 56)), Color(0.02, 0.03, 0.04), false, 5.0)
	draw_polyline(PackedVector2Array([
		Vector2(0, -76),
		Vector2(0, -52),
		Vector2(-10, -62),
		Vector2(0, -52),
		Vector2(10, -62)
	]), Color(1.0, 0.86, 0.2), 5.0)
	draw_circle(Vector2(-9, -20), 4.0, Color(0.02, 0.03, 0.04))
	draw_circle(Vector2(9, -20), 4.0, Color(0.02, 0.03, 0.04))
	draw_arc(Vector2(0, -8), 12.0, 0.2, 2.94, 16, Color(0.02, 0.03, 0.04), 4.0)
