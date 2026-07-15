@tool
extends Line2D

const MIN_DISPLAY_Z_INDEX := 2

@export_group("Connection")
@export var start_button_path: NodePath:
	set(value):
		start_button_path = value if value is NodePath else NodePath("")
@export var auto_bind_button := true:
	set(value):
		auto_bind_button = true if value == null else value == true

@export_group("Editing")
@export var bake_transform_in_editor := true
@export var snap_points_in_editor := true:
	set(value):
		snap_points_in_editor = true if value == null else value == true
		_snap_points_to_axes()
		queue_redraw()
@export_range(4.0, 64.0, 1.0) var editor_pick_radius := 18.0

@export_group("Timing")
@export_range(0.04, 2.0, 0.01) var activation_time := 0.22:
	set(value):
		activation_time = 0.22 if value == null else maxf(float(value), 0.04)
@export_range(0.04, 2.0, 0.01) var deactivation_time := 0.18:
	set(value):
		deactivation_time = 0.18 if value == null else maxf(float(value), 0.04)

@export_group("Visual")
@export var inactive_color := Color(0.055, 0.062, 0.07, 1.0):
	set(value):
		inactive_color = value
		_update_visual_color()
@export var active_color := Color(0.0, 0.86, 0.76, 1.0):
	set(value):
		active_color = value
		_update_visual_color()
@export_range(-4096, 4096, 1) var display_z_index := MIN_DISPLAY_Z_INDEX:
	set(value):
		display_z_index = int(value)
		_apply_display_layer()
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
var _animation_direction := 0.0
var _pending_callback := Callable()

func _ready() -> void:
	add_to_group("mechanism_wires")
	_apply_display_layer()
	width = wire_width
	joint_mode = Line2D.LINE_JOINT_ROUND
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	_update_visual_color()
	if not Engine.is_editor_hint() and auto_bind_button:
		call_deferred("bind_to_button_now")
	set_process(Engine.is_editor_hint())

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		if bake_transform_in_editor:
			_bake_editor_transform_into_points()
		if snap_points_in_editor:
			_snap_points_to_axes()
		return
	if is_zero_approx(_animation_direction):
		set_process(false)
		return
	var animation_time := activation_time if _animation_direction > 0.0 else deactivation_time
	_activation_progress = clampf(_activation_progress + _animation_direction * delta / maxf(animation_time, 0.001), 0.0, 1.0)
	_update_visual_color()
	if _animation_direction > 0.0 and _activation_progress >= 1.0:
		_animation_direction = 0.0
		_finish_activation()
	elif _animation_direction < 0.0 and _activation_progress <= 0.0:
		_animation_direction = 0.0
		_pending_callback = Callable()
		set_process(false)

func _draw() -> void:
	if points.size() < 2 or _activation_progress <= 0.01:
		return
	var active_points := _progress_points(_ease_out_cubic(_activation_progress))
	if active_points.size() < 2:
		return
	if glow_width > 0.0:
		var glow_color := active_color
		glow_color.a = 0.22
		draw_polyline(active_points, glow_color, width + glow_width, true)
	var glow_color := active_color
	glow_color.a = active_color.a
	draw_polyline(active_points, glow_color, wire_width, true)

func activate_wire(finished_callback: Callable = Callable()) -> void:
	_pending_callback = finished_callback
	if _activation_progress >= 1.0:
		_finish_activation()
		return
	_animation_direction = 1.0
	set_process(true)
	_update_visual_color()

func deactivate_wire() -> void:
	_animation_direction = -1.0
	_pending_callback = Callable()
	if _activation_progress <= 0.0:
		_animation_direction = 0.0
	_update_visual_color()
	if not Engine.is_editor_hint():
		set_process(_animation_direction != 0.0)

func set_wire_active(is_active: bool) -> void:
	_animation_direction = 0.0
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

func bind_to_button_now() -> void:
	var button := get_start_button()
	if button == null or not button.has_method("bind_mechanism_wire"):
		return
	button.call("bind_mechanism_wire", self)

func get_start_button() -> Node:
	return get_node_or_null(start_button_path)

func connects_button(button: Node) -> bool:
	return button != null and get_start_button() == button

func is_point_near_wire(local_point: Vector2, radius: float) -> bool:
	if points.size() < 2:
		return false
	for index in range(points.size() - 1):
		if _distance_to_segment(local_point, points[index], points[index + 1]) <= radius:
			return true
	return false

func _finish_activation() -> void:
	_update_visual_color()
	if _pending_callback.is_valid():
		var callback := _pending_callback
		_pending_callback = Callable()
		callback.call()

func _update_visual_color() -> void:
	default_color = inactive_color
	width = wire_width
	queue_redraw()

func _apply_display_layer() -> void:
	z_as_relative = false
	z_index = maxi(display_z_index, MIN_DISPLAY_Z_INDEX)

func _progress_points(progress: float) -> PackedVector2Array:
	var total_length := _wire_length()
	if total_length <= 0.001:
		return PackedVector2Array()
	var remaining_length := total_length * clampf(progress, 0.0, 1.0)
	var visible_points := PackedVector2Array()
	visible_points.append(points[0])
	for index in range(1, points.size()):
		var start_point := points[index - 1]
		var end_point := points[index]
		var segment_length := start_point.distance_to(end_point)
		if segment_length <= 0.001:
			continue
		if remaining_length >= segment_length:
			visible_points.append(end_point)
			remaining_length -= segment_length
			continue
		visible_points.append(start_point.lerp(end_point, remaining_length / segment_length))
		break
	return visible_points

func _wire_length() -> float:
	var total_length := 0.0
	for index in range(1, points.size()):
		total_length += points[index - 1].distance_to(points[index])
	return total_length

func _distance_to_segment(point: Vector2, start_point: Vector2, end_point: Vector2) -> float:
	var segment := end_point - start_point
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start_point)
	var progress := clampf((point - start_point).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start_point + segment * progress)

func _bake_editor_transform_into_points() -> void:
	if points.is_empty():
		return
	if position.is_equal_approx(Vector2.ZERO) and is_zero_approx(rotation) and scale.is_equal_approx(Vector2.ONE) and is_zero_approx(skew):
		return
	var local_transform := transform
	var baked_points := PackedVector2Array()
	baked_points.resize(points.size())
	for index in range(points.size()):
		baked_points[index] = local_transform * points[index]
	points = baked_points
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	skew = 0.0
	queue_redraw()

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
