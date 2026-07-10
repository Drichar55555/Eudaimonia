extends Control

signal dialogue_finished
signal choice_selected(index: int)

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
var _use_single_advance_key := false
var _advance_keycode: Key = KEY_NONE
var _continue_text := "E / Space"
var _choice_mode := false
var _choice_prompt := ""
var _choices: Array[String] = []
var _choice_index := 0
var _choice_nav_was_down := false
var _choice_direct_was_down := false

func _ready() -> void:
	add_to_group("dialogue_boxes")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_speaker_label = get_node_or_null(speaker_label_path) as Label
	_body_label = get_node_or_null(body_label_path) as Label
	_continue_label = get_node_or_null(continue_label_path) as Label
	visible = false
	set_process(true)

func show_dialogue(speaker: String, lines: Array[String]) -> void:
	_choice_mode = false
	_choices.clear()
	_use_single_advance_key = false
	_advance_keycode = KEY_NONE
	_continue_text = "E / Space"
	_start_dialogue(speaker, lines)

func show_key_dialogue(speaker: String, lines: Array[String], continue_text: String, advance_keycode: Key) -> void:
	_choice_mode = false
	_choices.clear()
	_use_single_advance_key = true
	_advance_keycode = advance_keycode
	_continue_text = continue_text
	_start_dialogue(speaker, lines)

func show_choice_dialogue(speaker: String, prompt: String, choices: Array[String], continue_text: String = "方向键 / 1-3 / E") -> void:
	_speaker = speaker
	_choice_prompt = prompt
	_choices = choices.duplicate()
	_choice_index = 0
	_choice_mode = true
	_use_single_advance_key = false
	_advance_keycode = KEY_NONE
	_continue_text = continue_text
	_active = not _choices.is_empty()
	visible = _active
	_advance_was_down = true
	_choice_nav_was_down = true
	_choice_direct_was_down = true
	_update_text()

func _start_dialogue(speaker: String, lines: Array[String]) -> void:
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
	if _choice_mode:
		_process_choice_input()
		return
	var advance_down := _advance_is_down()
	if advance_down and not _advance_was_down:
		_advance()
	_advance_was_down = advance_down

func _process_choice_input() -> void:
	var direct_index := _direct_choice_index_down()
	var direct_down := direct_index >= 0
	if direct_down and not _choice_direct_was_down:
		_select_choice(direct_index)
		_choice_direct_was_down = direct_down
		return
	_choice_direct_was_down = direct_down

	var navigation_direction := _choice_navigation_direction()
	var navigation_down := navigation_direction != 0
	if navigation_down and not _choice_nav_was_down:
		_choice_index = wrapi(_choice_index + navigation_direction, 0, _choices.size())
		_update_text()
	_choice_nav_was_down = navigation_down

	var select_down := _advance_is_down()
	if select_down and not _advance_was_down:
		_select_choice(_choice_index)
	_advance_was_down = select_down

func _direct_choice_index_down() -> int:
	if _choices.size() > 0 and Input.is_physical_key_pressed(KEY_1):
		return 0
	if _choices.size() > 1 and Input.is_physical_key_pressed(KEY_2):
		return 1
	if _choices.size() > 2 and Input.is_physical_key_pressed(KEY_3):
		return 2
	if _choices.size() > 3 and Input.is_physical_key_pressed(KEY_4):
		return 3
	return -1

func _choice_navigation_direction() -> int:
	if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
		return -1
	if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
		return 1
	return 0

func _advance_is_down() -> bool:
	if _use_single_advance_key:
		return Input.is_physical_key_pressed(_advance_keycode)
	return Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func _advance() -> void:
	_line_index += 1
	if _line_index >= _lines.size():
		_active = false
		visible = false
		_choice_mode = false
		dialogue_finished.emit()
		return
	_update_text()

func _select_choice(index: int) -> void:
	if index < 0 or index >= _choices.size():
		return
	_active = false
	visible = false
	_choice_mode = false
	choice_selected.emit(index)

func _update_text() -> void:
	if _speaker_label != null:
		_speaker_label.text = _speaker
	if _body_label != null:
		if _choice_mode:
			_body_label.text = _choice_text()
		else:
			_body_label.text = _lines[_line_index] if _line_index < _lines.size() else ""
	if _continue_label != null:
		_continue_label.text = _continue_text

func _choice_text() -> String:
	var text := _choice_prompt
	for index in _choices.size():
		var marker := ">" if index == _choice_index else " "
		text += "\n%s %d. %s" % [marker, index + 1, _choices[index]]
	return text
