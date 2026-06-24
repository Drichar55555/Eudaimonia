extends Label

@export var save_manager_path: NodePath
@export var saving_text := "Saving..."
@export var finished_text := "Saved"
@export var finished_visible_time := 0.9

var save_manager: Node
var _finished_timer := 0.0

func _ready() -> void:
	save_manager = get_node_or_null(save_manager_path)
	visible = false
	if save_manager != null:
		if save_manager.has_signal("save_started"):
			save_manager.save_started.connect(_on_save_started)
		if save_manager.has_signal("save_finished"):
			save_manager.save_finished.connect(_on_save_finished)

func _process(delta: float) -> void:
	if save_manager != null and bool(save_manager.get("is_saving")):
		text = saving_text
		visible = true
		return

	if _finished_timer > 0.0:
		_finished_timer = maxf(_finished_timer - delta, 0.0)
		text = finished_text
		visible = true
		return

	visible = false

func _on_save_started(_checkpoint_position: Vector2) -> void:
	_finished_timer = 0.0
	text = saving_text
	visible = true

func _on_save_finished(_checkpoint_position: Vector2) -> void:
	_finished_timer = finished_visible_time
	text = finished_text
	visible = true
