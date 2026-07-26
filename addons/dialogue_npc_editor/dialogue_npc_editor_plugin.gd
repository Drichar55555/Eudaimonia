@tool
extends EditorPlugin

const HANDLE_RADIUS := 7.0
const HANDLE_HIT_RADIUS := 14.0
const HANDLE_FILL := Color(0.2, 0.78, 1.0, 1.0)
const HANDLE_HOVER := Color(1.0, 0.78, 0.24, 1.0)
const HANDLE_OUTLINE := Color(0.04, 0.06, 0.08, 0.95)
const GUIDE_COLOR := Color(0.2, 0.78, 1.0, 0.76)
const CENTER_COLOR := Color(1.0, 1.0, 1.0, 0.75)

var _npc: Node2D
var _drag_index := -1
var _hover_index := -1
var _editor_selection: EditorSelection

func _enter_tree() -> void:
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	_editor_selection = get_editor_interface().get_selection()
	if _editor_selection != null and not _editor_selection.selection_changed.is_connected(_sync_npc_from_selection):
		_editor_selection.selection_changed.connect(_sync_npc_from_selection)
	call_deferred("_sync_npc_from_selection")

func _exit_tree() -> void:
	if _editor_selection != null and _editor_selection.selection_changed.is_connected(_sync_npc_from_selection):
		_editor_selection.selection_changed.disconnect(_sync_npc_from_selection)

func _handles(object: Object) -> bool:
	return _npc_from_object(object) != null

func _edit(object: Object) -> void:
	_npc = _npc_from_object(object)
	_drag_index = -1
	_hover_index = -1
	update_overlays()

func _make_visible(visible: bool) -> void:
	if visible:
		_sync_npc_from_selection()
	elif _drag_index < 0:
		call_deferred("_sync_npc_from_selection")
	update_overlays()

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _is_editable_npc(_npc):
		_sync_npc_from_selection()
	var motion := event as InputEventMouseMotion
	if motion != null:
		if not _is_editable_npc(_npc):
			return false
		if _drag_index >= 0:
			_set_endpoint_from_viewport(_drag_index, motion.position)
			update_overlays()
			return true
		_hover_index = _find_handle(motion.position)
		update_overlays()
		return false
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return false
	if button.pressed:
		if not _is_editable_npc(_npc):
			var picked := _find_npc_handle_at(button.position)
			if not picked.is_empty():
				_select_npc(picked["npc"] as Node2D)
				_drag_index = int(picked["index"])
				_hover_index = _drag_index
				return true
			return false
		var handle_index := _find_handle(button.position)
		if handle_index < 0:
			var picked := _find_npc_handle_at(button.position)
			if not picked.is_empty():
				_select_npc(picked["npc"] as Node2D)
				handle_index = int(picked["index"])
		if handle_index >= 0:
			_drag_index = handle_index
			_hover_index = handle_index
			return true
	elif _drag_index >= 0:
		_drag_index = -1
		return true
	return false

func _forward_canvas_draw_over_viewport(viewport_control: Control) -> void:
	_draw_handles(viewport_control)

func _forward_canvas_force_draw_over_viewport(viewport_control: Control) -> void:
	_draw_handles(viewport_control)

func _draw_handles(viewport_control: Control) -> void:
	for candidate in _get_npc_candidates():
		var npc := candidate as Node2D
		if _is_editable_npc(npc):
			_draw_npc_handles(viewport_control, npc)

func _draw_npc_handles(viewport_control: Control, npc: Node2D) -> void:
	var points: PackedVector2Array = npc.call("get_walk_range_points")
	if points.size() < 2:
		return
	var transform := npc.get_global_transform_with_canvas()
	var left := transform * points[0]
	var right := transform * points[1]
	var center := transform * Vector2.ZERO
	var selected := npc == _npc
	var guide_color := GUIDE_COLOR if selected else Color(GUIDE_COLOR.r, GUIDE_COLOR.g, GUIDE_COLOR.b, 0.46)
	viewport_control.draw_dashed_line(left, right, guide_color, 3.0 if selected else 2.0, 8.0, true)
	viewport_control.draw_line(center + Vector2(0.0, -9.0), center + Vector2(0.0, 9.0), CENTER_COLOR, 2.0, true)
	for index in 2:
		var point := left if index == 0 else right
		var fill := HANDLE_HOVER if selected and (index == _hover_index or index == _drag_index) else HANDLE_FILL
		viewport_control.draw_circle(point, HANDLE_RADIUS + 2.0, HANDLE_OUTLINE)
		viewport_control.draw_circle(point, HANDLE_RADIUS, fill)

func _find_handle(viewport_position: Vector2) -> int:
	if not _is_editable_npc(_npc):
		return -1
	var points: PackedVector2Array = _npc.call("get_walk_range_points")
	var transform := _npc.get_global_transform_with_canvas()
	for index in points.size():
		if (transform * points[index]).distance_to(viewport_position) <= HANDLE_HIT_RADIUS:
			return index
	return -1

func _set_endpoint_from_viewport(index: int, viewport_position: Vector2) -> void:
	var local_position := _npc.get_global_transform_with_canvas().affine_inverse() * viewport_position
	local_position.y = 0.0
	_npc.call("set_walk_range_endpoint_from_editor", index, local_position)

func _sync_npc_from_selection() -> void:
	if _editor_selection == null:
		_editor_selection = get_editor_interface().get_selection()
	var selected_npc: Node2D
	if _editor_selection != null:
		for selected_node in _editor_selection.get_selected_nodes():
			selected_npc = _npc_from_object(selected_node)
			if selected_npc != null:
				break
	if selected_npc != _npc:
		_npc = selected_npc
		_drag_index = -1
		_hover_index = -1
	update_overlays()

func _find_npc_handle_at(viewport_position: Vector2) -> Dictionary:
	for candidate in _get_npc_candidates():
		var npc := candidate as Node2D
		if not _is_editable_npc(npc):
			continue
		var points: PackedVector2Array = npc.call("get_walk_range_points")
		var transform := npc.get_global_transform_with_canvas()
		for index in points.size():
			if (transform * points[index]).distance_to(viewport_position) <= HANDLE_HIT_RADIUS:
				return {"npc": npc, "index": index}
	return {}

func _get_npc_candidates() -> Array[Node]:
	var candidates: Array[Node] = []
	var seen := {}
	for node in get_tree().get_nodes_in_group("editable_dialogue_npcs"):
		if node is Node and not seen.has(node.get_instance_id()):
			candidates.append(node)
			seen[node.get_instance_id()] = true
	_collect_npcs(get_editor_interface().get_edited_scene_root(), candidates, seen)
	return candidates

func _collect_npcs(node: Node, candidates: Array[Node], seen: Dictionary) -> void:
	if node == null:
		return
	if _is_npc(node) and not seen.has(node.get_instance_id()):
		candidates.append(node)
		seen[node.get_instance_id()] = true
	for child in node.get_children():
		_collect_npcs(child, candidates, seen)

func _select_npc(npc: Node2D) -> void:
	if not _is_editable_npc(npc):
		return
	_npc = npc
	if _editor_selection == null:
		_editor_selection = get_editor_interface().get_selection()
	if _editor_selection != null:
		_editor_selection.clear()
		_editor_selection.add_node(npc)
	get_editor_interface().edit_node(npc)
	update_overlays()

func _npc_from_object(object: Object) -> Node2D:
	var node := object as Node
	while node != null:
		if _is_npc(node):
			return node as Node2D
		node = node.get_parent()
	return null

func _is_npc(object: Object) -> bool:
	if not object is Node2D:
		return false
	return object.has_method("get_walk_range_points") and object.has_method("set_walk_range_endpoint_from_editor")

func _is_editable_npc(npc: Node2D) -> bool:
	return npc != null and is_instance_valid(npc) and npc.is_inside_tree() and _is_npc(npc)
