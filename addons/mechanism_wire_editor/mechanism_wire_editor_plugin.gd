@tool
extends EditorPlugin

const WIRE_SCRIPT_PATH := "res://scripts/mechanism_wire.gd"
const HANDLE_RADIUS := 7.0
const HANDLE_HIT_RADIUS := 13.0
const SEGMENT_HIT_RADIUS := 9.0
const WIRE_PICK_RADIUS := 14.0
const HANDLE_FILL := Color(0.0, 0.86, 0.76, 1.0)
const HANDLE_HOVER := Color(1.0, 0.78, 0.24, 1.0)
const HANDLE_OUTLINE := Color(0.04, 0.06, 0.07, 0.92)
const SEGMENT_INSERT := Color(0.0, 0.86, 0.76, 0.55)

var _wire: Line2D
var _hover_wire: Line2D
var _drag_index := -1
var _hover_index := -1
var _hover_segment := -1

func _enter_tree() -> void:
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()

func _handles(object: Object) -> bool:
	return _is_mechanism_wire(object)

func _edit(object: Object) -> void:
	if _is_mechanism_wire(object):
		_wire = object as Line2D
	else:
		_wire = null
	_hover_wire = null
	_drag_index = -1
	_hover_index = -1
	_hover_segment = -1
	update_overlays()

func _make_visible(visible: bool) -> void:
	if not visible:
		_wire = null
		_hover_wire = null
		_drag_index = -1
		_hover_index = -1
		_hover_segment = -1
	update_overlays()

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion != null:
		if _drag_index >= 0:
			if not _is_editable_wire(_wire):
				_cancel_edit_state()
				return false
			_set_point_from_viewport(_drag_index, mouse_motion.position)
			update_overlays()
			return true
		if _is_editable_wire(_wire):
			_snap_wire_points()
		var active_wire := _wire if _is_editable_wire(_wire) else _find_wire_at(mouse_motion.position)
		_hover_wire = active_wire if active_wire != _wire else null
		if not _is_editable_wire(active_wire):
			_hover_index = -1
			_hover_segment = -1
			update_overlays()
			return false
		var previous_wire := _wire
		_wire = active_wire
		_hover_index = _find_handle_at(mouse_motion.position)
		_hover_segment = -1 if _hover_index >= 0 else _find_segment_at(mouse_motion.position)
		_wire = previous_wire
		update_overlays()
		return false

	var mouse_button := event as InputEventMouseButton
	if mouse_button == null:
		return false
	if not _is_editable_wire(_wire):
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
			var picked_wire := _find_wire_at(mouse_button.position)
			if picked_wire != null:
				_select_wire(picked_wire)
				var handle_index := _find_handle_at(mouse_button.position)
				if handle_index >= 0:
					_drag_index = handle_index
				else:
					_hover_segment = _find_segment_at(mouse_button.position)
				return true
		return false

	if mouse_button.button_index == MOUSE_BUTTON_LEFT:
		if mouse_button.pressed:
			var picked_wire := _find_wire_at(mouse_button.position)
			if picked_wire != null and picked_wire != _wire:
				_select_wire(picked_wire)
			var handle_index := _find_handle_at(mouse_button.position)
			if handle_index >= 0:
				_drag_index = handle_index
				return true
			var segment_index := _find_segment_at(mouse_button.position)
			if segment_index >= 0:
				if mouse_button.double_click:
					_insert_point_after(segment_index, mouse_button.position)
					_drag_index = segment_index + 1
				return true
			if mouse_button.double_click:
				return false
		else:
			if _drag_index >= 0:
				_drag_index = -1
				_snap_wire_points()
				return true
			_snap_wire_points()

	if mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
		var delete_index := _find_handle_at(mouse_button.position)
		if delete_index >= 0 and _wire.points.size() > 2:
			_delete_point(delete_index)
			return true

	return false

func _forward_canvas_draw_over_viewport(viewport_control: Control) -> void:
	_draw_wire_handles(viewport_control)

func _forward_canvas_force_draw_over_viewport(viewport_control: Control) -> void:
	_draw_wire_handles(viewport_control)

func _draw_wire_handles(viewport_control: Control) -> void:
	var draw_wire := _wire if _is_editable_wire(_wire) else _hover_wire
	if not _is_editable_wire(draw_wire):
		return
	var transform := draw_wire.get_global_transform_with_canvas()
	for index in range(draw_wire.points.size()):
		var point := transform * draw_wire.points[index]
		var fill := HANDLE_HOVER if index == _hover_index or index == _drag_index else HANDLE_FILL
		viewport_control.draw_circle(point, HANDLE_RADIUS + 2.0, HANDLE_OUTLINE)
		viewport_control.draw_circle(point, HANDLE_RADIUS, fill)

	if _hover_segment >= 0 and _hover_segment < draw_wire.points.size() - 1:
		var start_point := transform * draw_wire.points[_hover_segment]
		var end_point := transform * draw_wire.points[_hover_segment + 1]
		var midpoint := (start_point + end_point) * 0.5
		viewport_control.draw_circle(midpoint, HANDLE_RADIUS + 1.0, HANDLE_OUTLINE)
		viewport_control.draw_circle(midpoint, HANDLE_RADIUS - 1.0, SEGMENT_INSERT)

func _is_mechanism_wire(object: Object) -> bool:
	if not object is Line2D:
		return false
	var script := object.get_script()
	return script != null and script.resource_path == WIRE_SCRIPT_PATH

func _is_editable_wire(node: Line2D) -> bool:
	return node != null and is_instance_valid(node) and node.is_inside_tree() and _is_mechanism_wire(node)

func _find_handle_at(viewport_position: Vector2) -> int:
	var transform := _wire.get_global_transform_with_canvas()
	for index in range(_wire.points.size()):
		var point := transform * _wire.points[index]
		if point.distance_to(viewport_position) <= HANDLE_HIT_RADIUS:
			return index
	return -1

func _find_segment_at(viewport_position: Vector2) -> int:
	if _wire.points.size() < 2:
		return -1
	var transform := _wire.get_global_transform_with_canvas()
	var best_index := -1
	var best_distance := SEGMENT_HIT_RADIUS
	for index in range(_wire.points.size() - 1):
		var start_point := transform * _wire.points[index]
		var end_point := transform * _wire.points[index + 1]
		var distance := _distance_to_segment(viewport_position, start_point, end_point)
		if distance <= best_distance:
			best_index = index
			best_distance = distance
	return best_index

func _find_wire_at(viewport_position: Vector2) -> Line2D:
	var best_wire: Line2D
	var best_distance := INF
	for node in _get_wire_candidates():
		var wire := node as Line2D
		if not _is_editable_wire(wire) or wire.points.size() < 2:
			continue
		var pick_radius := WIRE_PICK_RADIUS
		var editor_pick_radius = wire.get("editor_pick_radius")
		if editor_pick_radius != null:
			pick_radius = maxf(pick_radius, float(editor_pick_radius))
		var local_position := wire.get_global_transform_with_canvas().affine_inverse() * viewport_position
		if wire.has_method("is_point_near_wire") and not wire.call("is_point_near_wire", local_position, pick_radius):
			continue
		var transform := wire.get_global_transform_with_canvas()
		for index in range(wire.points.size() - 1):
			var start_point := transform * wire.points[index]
			var end_point := transform * wire.points[index + 1]
			var distance := _distance_to_segment(viewport_position, start_point, end_point)
			if distance <= pick_radius and distance < best_distance:
				best_wire = wire
				best_distance = distance
	return best_wire

func _get_wire_candidates() -> Array[Node]:
	var candidates: Array[Node] = []
	var seen := {}
	for node in get_tree().get_nodes_in_group("mechanism_wires"):
		if node is Node:
			candidates.append(node)
			seen[node.get_instance_id()] = true
	var scene_root := get_editor_interface().get_edited_scene_root()
	_collect_wires(scene_root, candidates, seen)
	return candidates

func _collect_wires(node: Node, candidates: Array[Node], seen: Dictionary) -> void:
	if node == null:
		return
	if not seen.has(node.get_instance_id()) and _is_mechanism_wire(node):
		candidates.append(node)
		seen[node.get_instance_id()] = true
	for child in node.get_children():
		_collect_wires(child, candidates, seen)

func _select_wire(wire: Line2D) -> void:
	_wire = wire
	_hover_wire = null
	_drag_index = -1
	_hover_index = -1
	_hover_segment = -1
	var selection := get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(wire)
	get_editor_interface().edit_node(wire)
	update_overlays()

func _cancel_edit_state() -> void:
	_wire = null
	_hover_wire = null
	_drag_index = -1
	_hover_index = -1
	_hover_segment = -1
	update_overlays()

func _set_point_from_viewport(index: int, viewport_position: Vector2) -> void:
	var updated_points := _wire.points
	updated_points[index] = _wire.get_global_transform_with_canvas().affine_inverse() * viewport_position
	_wire.points = _snapped_points(updated_points) if _should_snap_wire_points() else updated_points
	_wire.queue_redraw()

func _insert_point_after(segment_index: int, viewport_position: Vector2) -> void:
	var local_position := _wire.get_global_transform_with_canvas().affine_inverse() * viewport_position
	var updated_points := PackedVector2Array()
	for index in range(_wire.points.size()):
		updated_points.append(_wire.points[index])
		if index == segment_index:
			updated_points.append(local_position)
	_wire.points = _snapped_points(updated_points) if _should_snap_wire_points() else updated_points
	_wire.queue_redraw()
	_hover_index = segment_index + 1
	_hover_segment = -1
	update_overlays()

func _delete_point(index_to_delete: int) -> void:
	var updated_points := PackedVector2Array()
	for index in range(_wire.points.size()):
		if index != index_to_delete:
			updated_points.append(_wire.points[index])
	_wire.points = _snapped_points(updated_points) if _should_snap_wire_points() else updated_points
	_wire.queue_redraw()
	_hover_index = -1
	_hover_segment = -1
	update_overlays()

func _snap_wire_points() -> void:
	if not _should_snap_wire_points():
		return
	_wire.points = _snapped_points(_wire.points)
	_wire.queue_redraw()

func _should_snap_wire_points() -> bool:
	return _wire != null and _wire.get("snap_points_in_editor") != false

func _snapped_points(raw_points: PackedVector2Array) -> PackedVector2Array:
	if raw_points.size() < 2:
		return raw_points
	var snapped := PackedVector2Array()
	snapped.resize(raw_points.size())
	snapped[0] = raw_points[0]
	for index in range(1, raw_points.size()):
		snapped[index] = _snapped_point(snapped[index - 1], raw_points[index])
	return snapped

func _snapped_point(from_point: Vector2, raw_point: Vector2) -> Vector2:
	var delta := raw_point - from_point
	var length := delta.length()
	if length <= 0.001:
		return raw_point
	var snapped_angle := roundf(atan2(delta.y, delta.x) / (PI * 0.25)) * PI * 0.25
	var direction := Vector2(cos(snapped_angle), sin(snapped_angle))
	return from_point + direction * length

func _distance_to_segment(point: Vector2, start_point: Vector2, end_point: Vector2) -> float:
	var segment := end_point - start_point
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start_point)
	var progress := clampf((point - start_point).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start_point + segment * progress)
