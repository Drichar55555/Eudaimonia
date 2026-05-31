extends ColorRect

@export var camera_path: NodePath
@export var fade_speed: float = 8.0

var camera: Node

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0.02, 0.025, 0.035, 0.0)
	camera = get_node_or_null(camera_path)

func _process(delta: float) -> void:
	var target_alpha := 0.0
	if camera != null:
		target_alpha = float(camera.get("transition_mask_alpha"))

	var next_alpha := move_toward(color.a, target_alpha, fade_speed * delta)
	color = Color(color.r, color.g, color.b, next_alpha)
	visible = color.a > 0.001
