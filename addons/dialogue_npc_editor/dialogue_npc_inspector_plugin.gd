@tool
extends EditorInspectorPlugin

const CollisionLinesProperty = preload("res://addons/dialogue_npc_editor/npc_collision_lines_property.gd")

func _can_handle(object: Object) -> bool:
	if object == null:
		return false
	# Instanced @tool nodes can be represented by placeholder objects in the
	# editor. Their exported properties remain available, but has_method() can
	# return false, so recognize NPCs by the property this plugin replaces.
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
	add_property_editor(name, CollisionLinesProperty.new())
	return true
