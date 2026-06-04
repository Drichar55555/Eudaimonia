extends Control

signal dialogue_finished

@export var speaker_label_path: NodePath
@export var body_label_path: NodePath
@export var continue_label_path: NodePath

var _speaker_label: Label
var _body_label: Label
var _continue_label: Label
var _speaker := ""
var _lines: Array[String] = []
var _line_index := 0
var _active := false
var _advance_was_down := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_speaker_label = get_node_or_null(speaker_label_path) as Label
	_body_label = get_node_or_null(body_label_path) as Label
	_continue_label = get_node_or_null(continue_label_path) as Label
	visible = false
	set_process(true)

func show_dialogue(speaker: String, lines: Array[String]) -> void:
	_speaker = speaker
	_lines = lines.duplicate()
	_line_index = 0
	_active = not _lines.is_empty()
	visible = _active
	_advance_was_down = true
	_update_text()

func is_dialogue_active() -> bool:
	return _active

func _process(_delta: float) -> void:
	if not _active:
		return
	var advance_down := Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if advance_down and not _advance_was_down:
		_advance()
	_advance_was_down = advance_down

func _advance() -> void:
	_line_index += 1
	if _line_index >= _lines.size():
		_active = false
		visible = false
		dialogue_finished.emit()
		return
	_update_text()

func _update_text() -> void:
	if _speaker_label != null:
		_speaker_label.text = _speaker
	if _body_label != null:
		_body_label.text = _lines[_line_index] if _line_index < _lines.size() else ""
	if _continue_label != null:
		_continue_label.text = "E / Space"
