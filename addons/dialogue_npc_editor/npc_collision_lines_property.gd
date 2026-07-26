@tool
extends EditorProperty

var _rows := VBoxContainer.new()
var _add_button := Button.new()
var _updating := false

func _init() -> void:
	draw_label = false
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(panel)
	set_bottom_editor(panel)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "碰撞短句"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_add_button.text = "+"
	_add_button.tooltip_text = "添加一行内容和权重"
	_add_button.pressed.connect(_add_line)
	header.add_child(_add_button)
	panel.add_child(header)
	panel.add_child(_rows)

func _update_property() -> void:
	_rebuild_rows()

func _set_read_only(read_only: bool) -> void:
	_add_button.disabled = read_only
	for row in _rows.get_children():
		for control in row.get_children():
			if control is LineEdit:
				(control as LineEdit).editable = not read_only
			elif control is SpinBox:
				(control as SpinBox).editable = not read_only
			elif control is Button:
				(control as Button).disabled = read_only

func _rebuild_rows() -> void:
	_updating = true
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var responses: Array = get_edited_object().get(get_edited_property())
	for index in responses.size():
		var entry := _entry_to_dictionary(responses[index])
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var text_edit := LineEdit.new()
		text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_edit.placeholder_text = "内容"
		text_edit.text = str(entry.get("content", ""))
		text_edit.tooltip_text = "NPC 被撞后可能显示的短句"
		text_edit.text_changed.connect(_change_text.bind(index))
		add_focusable(text_edit)
		row.add_child(text_edit)
		var weight_edit := SpinBox.new()
		weight_edit.min_value = 0.0
		weight_edit.max_value = 1000.0
		weight_edit.step = 0.1
		weight_edit.custom_arrow_step = 0.1
		weight_edit.value = float(entry.get("weight", 1.0))
		weight_edit.tooltip_text = "权重（默认 1）"
		weight_edit.prefix = "权重 "
		weight_edit.value_changed.connect(_change_weight.bind(index))
		add_focusable(weight_edit)
		row.add_child(weight_edit)
		var remove_button := Button.new()
		remove_button.text = "−"
		remove_button.tooltip_text = "删除这条短句"
		remove_button.pressed.connect(_remove_line.bind(index))
		row.add_child(remove_button)
		_rows.add_child(row)
	_updating = false

func _add_line() -> void:
	var responses := _duplicate_responses()
	responses.append({"content": "", "weight": 1.0})
	emit_changed(get_edited_property(), responses)

func _remove_line(index: int) -> void:
	var responses := _duplicate_responses()
	if index < 0 or index >= responses.size():
		return
	responses.remove_at(index)
	emit_changed(get_edited_property(), responses)

func _change_text(text: String, index: int) -> void:
	if _updating:
		return
	var responses := _duplicate_responses()
	if index < 0 or index >= responses.size():
		return
	responses[index]["content"] = text
	emit_changed(get_edited_property(), responses, &"", true)

func _change_weight(value: float, index: int) -> void:
	if _updating:
		return
	var responses := _duplicate_responses()
	if index < 0 or index >= responses.size():
		return
	responses[index]["weight"] = maxf(value, 0.0)
	emit_changed(get_edited_property(), responses, &"", true)

func _duplicate_responses() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current: Array = get_edited_object().get(get_edited_property())
	for value in current:
		result.append(_entry_to_dictionary(value))
	return result

func _entry_to_dictionary(value: Variant) -> Dictionary:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Resource:
		var resource := value as Resource
		return {
			"content": str(resource.get("text")),
			"weight": float(resource.get("weight")) if resource.get("weight") != null else 1.0,
		}
	return {"content": "", "weight": 1.0}
