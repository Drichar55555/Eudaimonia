extends Node

@export var toggle_key := KEY_L
@export var disable_canvas_modulates := true
@export var canvas_modulate_off_color := Color.WHITE
@export var print_status := true

var _no_light_mode_enabled := false
var _records: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 10000
	set_process_unhandled_input(true)
	set_process(false)

func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != toggle_key and key_event.physical_keycode != toggle_key:
		return
	_set_no_light_mode_enabled(not _no_light_mode_enabled)
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if _no_light_mode_enabled:
		_apply_no_light_mode()

func is_no_light_mode_enabled() -> bool:
	return _no_light_mode_enabled

func _set_no_light_mode_enabled(value: bool) -> void:
	if _no_light_mode_enabled == value:
		return
	_no_light_mode_enabled = value
	if _no_light_mode_enabled:
		_records.clear()
		_apply_no_light_mode()
		set_process(true)
	else:
		set_process(false)
		_notify_no_light_mode(false)
		_restore_records()
	if print_status:
		print("No light mode: %s" % ("ON" if _no_light_mode_enabled else "OFF"))

func _apply_no_light_mode() -> void:
	_notify_no_light_mode(true)
	_disable_tree_lighting(get_tree().root)

func _notify_no_light_mode(value: bool) -> void:
	_notify_tree_no_light_mode(get_tree().root, value)

func _notify_tree_no_light_mode(node: Node, value: bool) -> void:
	if node != self and node.has_method("set_no_light_mode_enabled"):
		node.call("set_no_light_mode_enabled", value)
	for child in node.get_children():
		_notify_tree_no_light_mode(child, value)

func _disable_tree_lighting(node: Node) -> void:
	if node is Light2D:
		_remember_property(node, &"enabled")
		_remember_property(node, &"visible")
		node.set(&"enabled", false)
		(node as CanvasItem).visible = false
	elif disable_canvas_modulates and node is CanvasModulate:
		_remember_property(node, &"visible")
		_remember_property(node, &"color")
		(node as CanvasModulate).visible = false
		(node as CanvasModulate).color = canvas_modulate_off_color
	for child in node.get_children():
		_disable_tree_lighting(child)

func _remember_property(node: Object, property_name: StringName) -> void:
	var instance_id := node.get_instance_id()
	if not _records.has(instance_id):
		_records[instance_id] = {
			"node": weakref(node),
			"properties": {},
		}
	var record := _records[instance_id] as Dictionary
	var properties := record.get("properties") as Dictionary
	if properties.has(property_name):
		return
	properties[property_name] = node.get(property_name)

func _restore_records() -> void:
	for record in _records.values():
		var weak_reference := record.get("node") as WeakRef
		if weak_reference == null:
			continue
		var node := weak_reference.get_ref() as Object
		if node == null or not is_instance_valid(node):
			continue
		var properties := record.get("properties") as Dictionary
		for property_name in properties.keys():
			node.set(property_name, properties[property_name])
	_records.clear()
