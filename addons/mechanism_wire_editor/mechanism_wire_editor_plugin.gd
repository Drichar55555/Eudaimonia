@tool
extends EditorPlugin

const WIRE_SCRIPT_PATH := "res://scripts/mechanism_wire.gd"
const HANDLE_RADIUS := 7.0
const HANDLE_HIT_RADIUS := 13.0
const SEGMENT_HIT_RADIUS := 9.0
const HANDLE_FILL := Color(0.0, 0.86, 0.76, 1.0)
const HANDLE_HOVER := Color(1.0, 0.78, 0.24, 1.0)
const HANDLE_OUTLINE := Color(0.04, 0.06, 0.07, 0.92)
const SEGMENT_INSERT := Color(0.0, 0.86, 0.76, 0.55)

var _wire: Line2D
var _drag_index := -1
var _hover_index := -1
var _hover_segment := -1

func _handles(object: Object) -> bool:
	return _is_mechanism_wire(object)

func _edit(object: Object) -> void:
	if _is_mechanism_wire(object):
		_wire = object as Line2D
	else:
		_wire = null
	_drag_index = -1
	_hover_index = -1
	_hover_segment = -1
	update_overlays()

func _make_visible(visible: bool) -> void:
	if not visible:
		_wire = null
		_drag_index = -1
		_hover_index = -1
		_hover_segment = -1
	update_overlays()

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _is_editable_wire(_wire):
		return false

	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion != null:
		if _drag_index >= 0:
			_set_point_from_viewport(_drag_index, mouse_motion.position)
			update_overlays()
			return true
		_hover_index = _find_handle_at(mouse_motion.position)
		_hover_segment = -1 if _hover_index >= 0 else _find_segment_at(mouse_motion.position)
		update_overlays()
		return false

	var mouse_button := event as InputEventMouseButton
	if mouse_button == null:
		return false

	if mouse_button.button_index == MOUSE_BUTTON_LEFT:
		if mouse_button.pressed:
			var handle_index := _find_handle_at(mouse_button.position)
			if handle_index >= 0:
				_drag_index = handle_index
				return true
			if mouse_button.double_click:
				var segment_index := _find_segment_at(mouse_button.position)
				if segment_index >= 0:
					_insert_point_after(segment_index, mouse_button.position)
					_drag_index = segment_index + 1
					return true
		else:
			if _drag_index >= 0:
				_drag_index = -1
				return true

	if mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
		var delete_index := _find_handle_at(mouse_button.position)
		if delete_index >= 0 and _wire.points.size() > 2:
			_delete_point(delete_index)
			return true

	return false

func _forward_canvas_draw_over_viewport(viewport_control: Control) -> void:
	if not _is_editable_wire(_wire):
		return
	var transform := _wire.get_global_transform_with_canvas()
	for index in range(_wire.points.size()):
		var point := transform * _wire.points[index]
		var fill := HANDLE_HOVER if index == _hover_index or index == _drag_index else HANDLE_FILL
		viewport_control.draw_circle(point, HANDLE_RADIUS + 2.0, HANDLE_OUTLINE)
		viewport_control.draw_circle(point, HANDLE_RADIUS, fill)

	if _hover_segment >= 0 and _hover_segment < _wire.points.size() - 1:
		var start_point := transform * _wire.points[_hover_segment]
		var end_point := transform * _wire.points[_hover_segment + 1]
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

func _set_point_from_viewport(index: int, viewport_position: Vector2) -> void:
	var updated_points := _wire.points
	updated_points[index] = _wire.get_global_transform_with_canvas().affine_inverse() * viewport_position
	_wire.points = updated_points
	_snap_wire_points()
	_wire.queue_redraw()

func _insert_point_after(segment_index: int, viewport_position: Vector2) -> void:
	var local_position := _wire.get_global_transform_with_canvas().affine_inverse() * viewport_position
	var updated_points := PackedVector2Array()
	for index in range(_wire.points.size()):
		updated_points.append(_wire.points[index])
		if index == segment_index:
			updated_points.append(local_position)
	_wire.points = updated_points
	_snap_wire_points()
	_wire.queue_redraw()
	_hover_index = segment_index + 1
	_hover_segment = -1
	update_overlays()

func _delete_point(index_to_delete: int) -> void:
	var updated_points := PackedVector2Array()
	for index in range(_wire.points.size()):
		if index != index_to_delete:
			updated_points.append(_wire.points[index])
	_wire.points = updated_points
	_snap_wire_points()
	_wire.queue_redraw()
	_hover_index = -1
	_hover_segment = -1
	update_overlays()

func _snap_wire_points() -> void:
	if _wire.get("snap_points_in_editor") == false:
		return
	if _wire.has_method("snap_points_now"):
		_wire.call("snap_points_now")
	elif _wire.has_method("_snap_points_to_axes"):
		_wire.call("_snap_points_to_axes")

func _distance_to_segment(point: Vector2, start_point: Vector2, end_point: Vector2) -> float:
	var segment := end_point - start_point
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start_point)
	var progress := clampf((point - start_point).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start_point + segment * progress)
