extends Area2D

@export var room_id := "Room"
@export var camera_rect := Rect2(-180.0, -120.0, 1080.0, 720.0)
@export var debug_color := Color(0.95, 0.78, 0.25, 0.5)

func _ready() -> void:
	add_to_group("camera_rooms")
	monitoring = true
	body_entered.connect(_on_body_entered)
	queue_redraw()

func get_camera_rect() -> Rect2:
	return camera_rect

func contains_point(point: Vector2) -> bool:
	return camera_rect.has_point(point)

func _on_body_entered(body: Node2D) -> void:
	if body.name != "Player":
		return
	get_tree().call_group("room_cameras", "set_room", self)

func _draw() -> void:
	var local_rect := Rect2(to_local(camera_rect.position), camera_rect.size)
	draw_rect(local_rect, debug_color, false, 4.0)
	draw_rect(local_rect.grow(-8.0), Color(debug_color.r, debug_color.g, debug_color.b, 0.12), true)
