extends ColorRect

@export var camera_path: NodePath
@export var fade_speed: float = 8.0

var camera: Node
var target_alpha := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0.02, 0.025, 0.035, 0.0)
	camera = get_node_or_null(camera_path)

func _process(delta: float) -> void:
	if camera != null:
		target_alpha = 0.38 if camera.get("is_room_transitioning") else 0.0

	var next_alpha := move_toward(color.a, target_alpha, fade_speed * delta)
	color = Color(color.r, color.g, color.b, next_alpha)
	visible = color.a > 0.001
