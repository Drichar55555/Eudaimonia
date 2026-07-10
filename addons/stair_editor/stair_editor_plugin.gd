@tool
extends EditorPlugin

const STAIR_SCRIPT_PATH := "res://scripts/stair.gd"
const HANDLE_RADIUS := 7.0
const HANDLE_HIT_RADIUS := 13.0
const STAIR_PICK_RADIUS := 14.0
const HANDLE_FILL := Color(0.95, 0.72, 0.25, 1.0)
const HANDLE_HOVER := Color(0.0, 0.86, 0.76, 1.0)
const HANDLE_OUTLINE := Color(0.04, 0.06, 0.07, 0.92)
const TRIANGLE_GUIDE := Color(0.95, 0.72, 0.25, 0.65)

var _stair: Node2D
var _hover_stair: Node2D
var _drag_stair: Node2D
var _drag_index := -1
var _hover_index := -1

func _enter_tree() -> void:
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()

func _handles(object: Object) -> bool:
	return _stair_from_object(object) != null

func _edit(object: Object) -> void:
	var previous_stair := _stair
	var edited_stair := _stair_from_object(object)
	var keep_drag := _drag_index >= 0 and edited_stair != null and edited_stair == previous_stair
	if edited_stair != null:
		_stair = edited_stair
		if object != edited_stair:
			call_deferred("_select_stair", edited_stair, keep_drag)
	else:
		_stair = null
	_hover_stair = null
	if not keep_drag:
		_drag_stair = null
		_drag_index = -1
		_hover_index = -1
	update_overlays()

func _make_visible(visible: bool) -> void:
	if not visible:
		_stair = null
		_hover_stair = null
		_drag_stair = null
		_drag_index = -1
		_hover_index = -1
	update_overlays()

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion != null:
		if _drag_index >= 0:
			var drag_stair := _drag_stair if _is_editable_stair(_drag_stair) else _stair
			if not _is_editable_stair(drag_stair):
				_cancel_edit_state()
				return false
			_stair = drag_stair
			_set_corner_from_viewport(_drag_index, mouse_motion.position, drag_stair)
			update_overlays()
			return true
		if _is_editable_stair(_stair) and _stair.has_method("snap_triangle_now"):
			_stair.call("snap_triangle_now")
		var active_stair := _stair if _is_editable_stair(_stair) else _find_stair_at(mouse_motion.position)
		_hover_stair = active_stair if active_stair != _stair else null
		if not _is_editable_stair(active_stair):
			_hover_index = -1
			update_overlays()
			return false
		var previous_stair := _stair
		_stair = active_stair
		_hover_index = _find_handle_at(mouse_motion.position)
		_stair = previous_stair
		update_overlays()
		return false

	var mouse_button := event as InputEventMouseButton
	if mouse_button == null:
		return false
	if not _is_editable_stair(_stair):
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			var picked_stair := _find_stair_at(mouse_button.position)
			if picked_stair != null:
				var handle_index := _find_handle_on_stair(picked_stair, mouse_button.position)
				_select_stair(picked_stair, handle_index >= 0)
				if handle_index >= 0:
					_drag_stair = picked_stair
					_drag_index = handle_index
					_hover_index = handle_index
				return true
		return false

	if mouse_button.button_index == MOUSE_BUTTON_LEFT:
		if mouse_button.pressed:
			var picked_stair := _find_stair_at(mouse_button.position)
			if picked_stair != null and picked_stair != _stair:
				var picked_handle_index := _find_handle_on_stair(picked_stair, mouse_button.position)
				_select_stair(picked_stair, picked_handle_index >= 0)
				if picked_handle_index >= 0:
					_drag_stair = picked_stair
					_drag_index = picked_handle_index
					_hover_index = picked_handle_index
					return true
			var handle_index := _find_handle_at(mouse_button.position)
			if handle_index >= 0:
				_drag_stair = _stair
				_drag_index = handle_index
				_hover_index = handle_index
				return true
			if picked_stair == _stair:
				return true
		else:
			if _drag_index >= 0:
				_drag_stair = null
				_drag_index = -1
				if _is_editable_stair(_stair) and _stair.has_method("snap_triangle_now"):
					_stair.call("snap_triangle_now")
				return true
			if _is_editable_stair(_stair) and _stair.has_method("snap_triangle_now"):
				_stair.call("snap_triangle_now")

	return false

func _forward_canvas_draw_over_viewport(viewport_control: Control) -> void:
	_draw_stair_handles(viewport_control)

func _forward_canvas_force_draw_over_viewport(viewport_control: Control) -> void:
	_draw_stair_handles(viewport_control)

func _draw_stair_handles(viewport_control: Control) -> void:
	var draw_stair := _stair if _is_editable_stair(_stair) else _hover_stair
	if not _is_editable_stair(draw_stair):
		return
	var points: PackedVector2Array = draw_stair.call("get_triangle_points")
	var transform := draw_stair.get_global_transform_with_canvas()
	if points.size() >= 3:
		var viewport_points := PackedVector2Array()
		for point in points:
			viewport_points.append(transform * point)
		viewport_points.append(viewport_points[0])
		viewport_control.draw_polyline(viewport_points, TRIANGLE_GUIDE, 2.0, true)
	for index in range(points.size()):
		var point := transform * points[index]
		var fill := HANDLE_HOVER if index == _hover_index or index == _drag_index else HANDLE_FILL
		viewport_control.draw_circle(point, HANDLE_RADIUS + 2.0, HANDLE_OUTLINE)
		viewport_control.draw_circle(point, HANDLE_RADIUS, fill)

func _is_stair(object: Object) -> bool:
	return _is_stair_node(object)

func _is_stair_node(object: Object) -> bool:
	if not object is Node2D:
		return false
	var script := object.get_script()
	return script != null and script.resource_path == STAIR_SCRIPT_PATH

func _stair_from_object(object: Object) -> Node2D:
	if _is_stair_node(object):
		return object as Node2D
	if object is Node:
		var parent := (object as Node).get_parent()
		if _is_stair_node(parent):
			return parent as Node2D
	return null

func _is_editable_stair(node: Node2D) -> bool:
	return node != null and is_instance_valid(node) and node.is_inside_tree() and _is_stair_node(node)

func _find_handle_at(viewport_position: Vector2) -> int:
	return _find_handle_on_stair(_stair, viewport_position)

func _find_handle_on_stair(stair: Node2D, viewport_position: Vector2) -> int:
	if not _is_editable_stair(stair):
		return -1
	var transform := stair.get_global_transform_with_canvas()
	var points: PackedVector2Array = stair.call("get_triangle_points")
	for index in range(points.size()):
		var point := transform * points[index]
		if point.distance_to(viewport_position) <= HANDLE_HIT_RADIUS:
			return index
	return -1

func _find_stair_at(viewport_position: Vector2) -> Node2D:
	var best_stair: Node2D
	var best_distance := INF
	for node in _get_stair_candidates():
		var stair := node as Node2D
		if not _is_editable_stair(stair):
			continue
		var pick_radius := STAIR_PICK_RADIUS
		var local_position := stair.get_global_transform_with_canvas().affine_inverse() * viewport_position
		if stair.has_method("is_point_near_stair") and not stair.call("is_point_near_stair", local_position, pick_radius):
			continue
		var points: PackedVector2Array = stair.call("get_triangle_points")
		if Geometry2D.is_point_in_polygon(local_position, points):
			best_stair = stair
			best_distance = 0.0
			continue
		var transform := stair.get_global_transform_with_canvas()
		for index in range(points.size()):
			var start_point := transform * points[index]
			var end_point := transform * points[(index + 1) % points.size()]
			var distance := _distance_to_segment(viewport_position, start_point, end_point)
			if distance <= pick_radius and distance < best_distance:
				best_stair = stair
				best_distance = distance
	return best_stair

func _get_stair_candidates() -> Array[Node]:
	var candidates: Array[Node] = []
	var seen := {}
	for node in get_tree().get_nodes_in_group("editable_stairs"):
		if node is Node:
			candidates.append(node)
			seen[node.get_instance_id()] = true
	var scene_root := get_editor_interface().get_edited_scene_root()
	_collect_stairs(scene_root, candidates, seen)
	return candidates

func _collect_stairs(node: Node, candidates: Array[Node], seen: Dictionary) -> void:
	if node == null:
		return
	if not seen.has(node.get_instance_id()) and _is_stair(node):
		candidates.append(node)
		seen[node.get_instance_id()] = true
	for child in node.get_children():
		_collect_stairs(child, candidates, seen)

func _select_stair(stair: Node2D, keep_drag := false) -> void:
	_stair = stair
	_hover_stair = null
	if not keep_drag:
		_drag_stair = null
		_drag_index = -1
		_hover_index = -1
	var selection := get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(stair)
	get_editor_interface().edit_node(stair)
	update_overlays()

func _cancel_edit_state() -> void:
	_stair = null
	_hover_stair = null
	_drag_stair = null
	_drag_index = -1
	_hover_index = -1
	update_overlays()

func _set_corner_from_viewport(index: int, viewport_position: Vector2, stair: Node2D = null) -> void:
	var target_stair := stair if _is_editable_stair(stair) else _stair
	if not _is_editable_stair(target_stair):
		return
	var local_position := target_stair.get_global_transform_with_canvas().affine_inverse() * viewport_position
	if target_stair.has_method("set_triangle_corner_from_editor"):
		target_stair.call("set_triangle_corner_from_editor", index, local_position)

func _distance_to_segment(point: Vector2, start_point: Vector2, end_point: Vector2) -> float:
	var segment := end_point - start_point
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start_point)
	var progress := clampf((point - start_point).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start_point + segment * progress)