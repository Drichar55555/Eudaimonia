@tool
extends Line2D

@export_group("Connection")
@export var start_button_path: NodePath:
	set(value):
		start_button_path = value if value is NodePath else NodePath("")
		_request_connection_points_refresh()
@export var target_path: NodePath:
	set(value):
		target_path = value if value is NodePath else NodePath("")
		_request_connection_points_refresh()
@export var auto_bind_button := true:
	set(value):
		auto_bind_button = true if value == null else value == true
@export var auto_route_from_start_end := true:
	set(value):
		auto_route_from_start_end = true if value == null else value == true
		_request_connection_points_refresh()
@export var start_offset := Vector2.ZERO:
	set(value):
		start_offset = value if value is Vector2 else Vector2.ZERO
		_request_connection_points_refresh()
@export var end_offset := Vector2.ZERO:
	set(value):
		end_offset = value if value is Vector2 else Vector2.ZERO
		_request_connection_points_refresh()

@export_group("Editing")
@export var snap_points_in_editor := true:
	set(value):
		snap_points_in_editor = true if value == null else value == true
		_snap_points_to_axes()
		queue_redraw()

@export_group("Timing")
@export_range(0.04, 2.0, 0.01) var activation_time := 0.22

@export_group("Visual")
@export var inactive_color := Color(0.055, 0.062, 0.07, 1.0):
	set(value):
		inactive_color = value
		_update_visual_color()
@export var active_color := Color(0.0, 0.86, 0.76, 1.0):
	set(value):
		active_color = value
		_update_visual_color()
@export_range(1.0, 24.0, 0.5) var wire_width := 5.0:
	set(value):
		wire_width = value
		width = wire_width
		queue_redraw()
@export_range(0.0, 20.0, 0.5) var glow_width := 9.0:
	set(value):
		glow_width = value
		queue_redraw()

var _activation_progress := 0.0
var _activating := false
var _pending_callback := Callable()
var _connection_refresh_requested := false

func _ready() -> void:
	add_to_group("mechanism_wires")
	width = wire_width
	joint_mode = Line2D.LINE_JOINT_ROUND
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	if _connection_refresh_requested or points.size() < 2 or _has_default_template_points():
		_refresh_connection_points()
	_connection_refresh_requested = false
	_update_visual_color()
	if not Engine.is_editor_hint() and auto_bind_button:
		call_deferred("bind_to_button_now")
	set_process(Engine.is_editor_hint())

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		if snap_points_in_editor:
			_snap_points_to_axes()
		return
	if not _activating:
		set_process(false)
		return
	_activation_progress = clampf(_activation_progress + delta / maxf(activation_time, 0.001), 0.0, 1.0)
	_update_visual_color()
	if _activation_progress >= 1.0:
		_activating = false
		_finish_activation()

func _draw() -> void:
	if glow_width <= 0.0 or points.size() < 2 or _activation_progress <= 0.01:
		return
	var glow_color := active_color
	glow_color.a = 0.22 * _activation_progress
	draw_polyline(points, glow_color, width + glow_width, true)

func activate_wire(finished_callback: Callable = Callable()) -> void:
	_pending_callback = finished_callback
	if _activation_progress >= 1.0:
		_finish_activation()
		return
	_activating = true
	set_process(true)
	_update_visual_color()

func deactivate_wire() -> void:
	_activating = false
	_pending_callback = Callable()
	_activation_progress = 0.0
	_update_visual_color()
	if not Engine.is_editor_hint():
		set_process(false)

func set_wire_active(is_active: bool) -> void:
	_activating = false
	_pending_callback = Callable()
	_activation_progress = 1.0 if is_active else 0.0
	_update_visual_color()
	if not Engine.is_editor_hint():
		set_process(false)

func is_wire_active() -> bool:
	return _activation_progress >= 1.0

func snap_points_now() -> void:
	_snap_points_to_axes()
	queue_redraw()

func route_points_from_start_end_now() -> void:
	_connection_refresh_requested = false
	_refresh_connection_points(true)

func bind_to_button_now() -> void:
	var button := get_start_button()
	if button == null or not button.has_method("bind_mechanism_wire"):
		return
	button.call("bind_mechanism_wire", self, get_target_node())

func get_start_button() -> Node:
	return get_node_or_null(start_button_path)

func get_target_node() -> Node:
	return get_node_or_null(target_path)

func connects_button(button: Node) -> bool:
	return button != null and get_start_button() == button

func connects_target(target: Node) -> bool:
	return target != null and get_target_node() == target

func _finish_activation() -> void:
	_update_visual_color()
	if _pending_callback.is_valid():
		var callback := _pending_callback
		_pending_callback = Callable()
		callback.call()
		return
	_activate_target()

func _activate_target() -> void:
	var target := get_target_node()
	if target == null:
		return
	if target.has_method("activate"):
		target.call("activate")
	elif target.has_method("trigger_open"):
		target.call("trigger_open")

func _update_visual_color() -> void:
	default_color = inactive_color.lerp(active_color, _ease_out_cubic(_activation_progress))
	width = wire_width
	queue_redraw()

func _request_connection_points_refresh() -> void:
	_connection_refresh_requested = true
	if is_inside_tree():
		call_deferred("_run_requested_connection_points_refresh")

func _run_requested_connection_points_refresh() -> void:
	if not _connection_refresh_requested:
		return
	_connection_refresh_requested = false
	_refresh_connection_points()

func _refresh_connection_points(force_update := false) -> void:
	if not auto_route_from_start_end or not is_inside_tree():
		return
	if not force_update and points.size() >= 2 and not _has_default_template_points():
		return
	var start_node := get_start_button() as Node2D
	var end_node := get_target_node() as Node2D
	if start_node == null or end_node == null:
		return
	points = _routed_points(to_local(start_node.global_position) + start_offset, to_local(end_node.global_position) + end_offset)
	queue_redraw()

func _routed_points(start_point: Vector2, end_point: Vector2) -> PackedVector2Array:
	var routed := PackedVector2Array()
	routed.append(start_point)
	var delta := end_point - start_point
	if not _is_snapped_direction(delta):
		var elbow := Vector2(end_point.x, start_point.y) if absf(delta.x) >= absf(delta.y) else Vector2(start_point.x, end_point.y)
		if elbow.distance_squared_to(start_point) > 0.001 and elbow.distance_squared_to(end_point) > 0.001:
			routed.append(elbow)
	routed.append(end_point)
	return routed

func _is_snapped_direction(delta: Vector2) -> bool:
	if delta.length_squared() <= 0.001:
		return true
	if absf(delta.x) <= 0.001 or absf(delta.y) <= 0.001:
		return true
	return absf(absf(delta.x) - absf(delta.y)) <= 0.001

func _has_default_template_points() -> bool:
	return points.size() == 2 and points[0].is_equal_approx(Vector2.ZERO) and points[1].is_equal_approx(Vector2(96.0, 0.0))

func _snap_points_to_axes() -> void:
	if points.size() < 2:
		return
	var snapped := PackedVector2Array()
	snapped.resize(points.size())
	snapped[0] = points[0]
	var changed := false
	for index in range(1, points.size()):
		var next_point := _snapped_point(snapped[index - 1], points[index])
		snapped[index] = next_point
		if next_point.distance_squared_to(points[index]) > 0.001:
			changed = true
	if changed:
		points = snapped

func _snapped_point(from_point: Vector2, raw_point: Vector2) -> Vector2:
	var delta := raw_point - from_point
	var length := delta.length()
	if length <= 0.001:
		return raw_point
	var snapped_angle := roundf(atan2(delta.y, delta.x) / (PI * 0.25)) * PI * 0.25
	var direction := Vector2(cos(snapped_angle), sin(snapped_angle))
	return from_point + direction * length

func _ease_out_cubic(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)
