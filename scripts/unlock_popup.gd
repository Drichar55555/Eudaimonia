extends Control

@export var title_path: NodePath
@export var description_path: NodePath

var _title_label: Label
var _description_label: Label
var _can_close := false

func _ready() -> void:
	add_to_group("unlock_popups")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label = get_node_or_null(title_path) as Label
	_description_label = get_node_or_null(description_path) as Label

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _can_close:
		return
	if event is InputEventKey and event.pressed:
		_close()
	elif event is InputEventMouseButton and event.pressed:
		_close()

func show_unlock(mask_name: String) -> void:
	var readable_name := _readable_mask_name(mask_name)
	if _title_label != null:
		_title_label.text = "Unlocked: %s" % readable_name
	if _description_label != null:
		_description_label.text = "%s is now available. Press any key to close." % readable_name
	visible = true
	_can_close = false
	call_deferred("_enable_close")

func _enable_close() -> void:
	_can_close = true

func _close() -> void:
	visible = false
	_can_close = false
	get_viewport().set_input_as_handled()

func _readable_mask_name(mask_name: String) -> String:
	match mask_name:
		"euda_mask":
			return "Euda Mask"
		"ghost_mask":
			return "Ghost Mask"
		_:
			return "No Mask"
