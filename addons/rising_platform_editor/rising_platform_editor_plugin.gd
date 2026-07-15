@tool
extends EditorPlugin

const PLATFORM_SCRIPT_PATH := "res://scripts/rising_platform.gd"
const HANDLE_RADIUS := 7.0
const HANDLE_HIT_RADIUS := 14.0
const HANDLE_FILL := Color(0.0, 0.86, 0.76, 1.0)
const HANDLE_HOVER := Color(1.0, 0.82, 0.28, 1.0)
const HANDLE_OUTLINE := Color(0.04, 0.06, 0.07, 0.95)
const GUIDE_COLOR := Color(0.0, 0.86, 0.76, 0.72)

var _platform: Node2D
var _dragging := false
var _hovering := false

func _enter_tree() -> void:
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()

func _handles(object: Object) -> bool:
	return _is_platform(object)

func _edit(object: Object) -> void:
	_platform = object as Node2D if _is_platform(object) else null
	_dragging = false
	_hovering = false
	update_overlays()

func _make_visible(visible: bool) -> void:
	if not visible:
		_platform = null
		_dragging = false
		_hovering = false
	update_overlays()

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _is_editable_platform(_platform):
		return false
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _dragging:
			_set_height_from_viewport(motion.position)
			update_overlays()
			return true
		_hovering = _handle_viewport_position().distance_to(motion.position) <= HANDLE_HIT_RADIUS
		update_overlays()
		return false
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return false
	if button.pressed:
		if _handle_viewport_position().distance_to(button.position) <= HANDLE_HIT_RADIUS:
			_dragging = true
			_hovering = true
			return true
	elif _dragging:
		_dragging = false
		return true
	return false

func _forward_canvas_draw_over_viewport(viewport_control: Control) -> void:
	_draw_handle(viewport_control)

func _forward_canvas_force_draw_over_viewport(viewport_control: Control) -> void:
	_draw_handle(viewport_control)

func _draw_handle(viewport_control: Control) -> void:
	if not _is_editable_platform(_platform):
		return
	var transform := _platform.get_global_transform_with_canvas()
	var origin := transform * Vector2.ZERO
	var target := _handle_viewport_position()
	viewport_control.draw_dashed_line(origin, target, GUIDE_COLOR, 2.0, 8.0, true)
	var fill := HANDLE_HOVER if _hovering or _dragging else HANDLE_FILL
	viewport_control.draw_circle(target, HANDLE_RADIUS + 2.0, HANDLE_OUTLINE)
	viewport_control.draw_circle(target, HANDLE_RADIUS, fill)

func _handle_viewport_position() -> Vector2:
	var target: Vector2 = _platform.call("get_rise_target_point")
	return _platform.get_global_transform_with_canvas() * target

func _set_height_from_viewport(viewport_position: Vector2) -> void:
	var local_position := _platform.get_global_transform_with_canvas().affine_inverse() * viewport_position
	local_position.x = 0.0
	_platform.call("set_rise_height_from_editor", local_position)

func _is_platform(object: Object) -> bool:
	if not object is Node2D:
		return false
	var script := object.get_script()
	return script != null and script.resource_path == PLATFORM_SCRIPT_PATH

func _is_editable_platform(platform: Node2D) -> bool:
	return platform != null and is_instance_valid(platform) and platform.is_inside_tree() and _is_platform(platform)
