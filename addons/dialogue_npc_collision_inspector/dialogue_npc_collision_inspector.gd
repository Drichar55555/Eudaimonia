@tool
extends EditorPlugin

const CollisionResponsesProperty = preload("res://addons/dialogue_npc_editor/npc_collision_lines_property.gd")

class CollisionResponsesInspector extends EditorInspectorPlugin:
	func _can_handle(object: Object) -> bool:
		if object == null:
			return false
		for property in object.get_property_list():
			var property_name := String(property.get("name", ""))
			if property_name == "collision_responses" or property_name == "collision_lines":
				return true
		return false

	func _parse_property(
		_object: Object,
		_type: Variant.Type,
		name: String,
		_hint_type: PropertyHint,
		_hint_string: String,
		_usage_flags: int,
		_wide: bool
	) -> bool:
		if name != "collision_responses" and name != "collision_lines":
			return false
		add_property_editor(name, CollisionResponsesProperty.new())
		return true

var _inspector_plugin: EditorInspectorPlugin

func _enter_tree() -> void:
	_inspector_plugin = CollisionResponsesInspector.new()
	add_inspector_plugin(_inspector_plugin)
	_refresh_inspector.call_deferred()

func _refresh_inspector() -> void:
	var inspector := get_editor_interface().get_inspector()
	var edited_object := inspector.get_edited_object()
	if edited_object != null:
		inspector.edit(null)
		inspector.edit(edited_object)

func _exit_tree() -> void:
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null
