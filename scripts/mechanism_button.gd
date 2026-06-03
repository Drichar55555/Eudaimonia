@tool
extends StaticBody2D

const TERRAIN_LAYER := 1 << 0

enum CinematicState { NONE, MOVE_IN, WALL_MOVE, MOVE_OUT }
enum ButtonMode { LATCH, HOLD, SHOT }

@export var moving_wall_path: NodePath
@export_enum("latch", "hold", "shot") var button_mode := 0
@export var trigger_once := true
@export var latch_when_activated := true
@export_range(0.05, 10.0, 0.05) var release_delay := 1.0
@export_range(0.05, 10.0, 0.05) var shot_reset_delay := 3.0
@export var press_depth := 8.0:
	set(value):
		press_depth = maxf(value, 0.0)
		queue_redraw()
@export_range(0.03, 1.2, 0.01) var press_animation_time := 0.22
@export var detect_players := true
@export var detect_enemies := true
@export var detect_player_weapons := true

@export_group("Screen Shake")
@export var shake_on_press := 0.26
@export var shake_while_moving := 0.06
@export_range(0.05, 1.0, 0.01) var moving_shake_interval := 0.16
@export var shake_on_finish := 0.5

@export_group("Cinematic")
@export var play_cinematic := false
@export var pause_gameplay_during_cinematic := true
@export_range(0.05, 6.0, 0.05) var camera_move_in_time := 0.45
@export_range(0.0, 4.0, 0.05) var camera_hold_time := 0.18
@export_range(0.05, 6.0, 0.05) var camera_move_out_time := 0.45
@export var cinematic_view_size := Vector2(760.0, 430.0)
@export_range(0.0, 480.0, 4.0) var cinematic_padding := 120.0

@export_group("Visual")
@export var body_color := Color(0.22, 0.28, 0.30, 1.0):
	set(value):
		body_color = value
		queue_redraw()
@export var active_color := Color(1.0, 0.78, 0.24, 1.0):
	set(value):
		active_color = value
		queue_redraw()
@export var detect_color := Color(1.0, 0.78, 0.24, 0.14):
	set(value):
		detect_color = value
		queue_redraw()
@export var show_detection_area := true:
	set(value):
		show_detection_area = value
		queue_redraw()

var _moving_wall: Node
var _sensor: Area2D
var _pressed := false
var _press_visual_depth := 0.0
var _activated := false
var _release_timer := 0.0
var _shot_reset_timer := 0.0
var _watching_wall_finish := false
var _last_wall_moving := false
var _moving_shake_timer := 0.0
var _finish_shake_sent := false
var _cinematic_state := CinematicState.NONE
var _cinematic_timer := 0.0
var _camera: Camera2D
var _camera_start_position := Vector2.ZERO
var _camera_start_zoom := Vector2.ONE
var _camera_focus_position := Vector2.ZERO
var _camera_focus_zoom := Vector2.ONE
var _paused_nodes: Array[Dictionary] = []

func _ready() -> void:
	z_index = -20
	z_as_relative = false
	add_to_group("mechanism_buttons")
	add_to_group("saveable")
	collision_layer = TERRAIN_LAYER
	collision_mask = 0
	_sensor = get_node_or_null("PressSensor") as Area2D
	if _sensor != null:
		_sensor.monitoring = true
		_sensor.monitorable = true
		_sensor.body_entered.connect(_on_body_entered)
		_sensor.body_exited.connect(_on_body_exited)
		_sensor.area_entered.connect(_on_area_entered)
	_resolve_wall()
	set_process(Engine.is_editor_hint())
	queue_redraw()

func _process(delta: float) -> void:
	_update_press_animation(delta)
	_update_button_timers(delta)
	_update_wall_shake(delta)
	if _cinematic_state != CinematicState.NONE:
		_update_cinematic(delta)
	else:
		_ensure_process_needed()

func _draw() -> void:
	if show_detection_area:
		_draw_detection_area()

	var depth := _press_visual_depth
	var plate_color := active_color if _pressed else body_color
	_draw_capsule(Vector2(0.0, -3.0 + depth), Vector2(76.0, 22.0), plate_color, Color(0.03, 0.035, 0.04, 1.0), 3.0)
	_draw_capsule(Vector2(0.0, 14.0), Vector2(92.0, 14.0), Color(0.08, 0.09, 0.10, 1.0), Color(0.03, 0.035, 0.04, 1.0), 2.0)

	if _activated:
		var status_color := active_color
		if button_mode == ButtonMode.SHOT and _shot_reset_timer > 0.0:
			status_color.a = _shot_blink_alpha()
		draw_circle(Vector2(0.0, -28.0), 5.0, status_color)

func get_save_state() -> Dictionary:
	return {
		"pressed": _pressed,
		"activated": _activated,
		"watching_wall_finish": _watching_wall_finish,
		"release_timer": _release_timer,
		"shot_reset_timer": _shot_reset_timer,
	}

func apply_save_state(state: Dictionary) -> void:
	_pressed = bool(state.get("pressed", false))
	_press_visual_depth = _target_press_depth()
	_activated = bool(state.get("activated", false))
	_watching_wall_finish = bool(state.get("watching_wall_finish", false))
	_release_timer = float(state.get("release_timer", 0.0))
	_shot_reset_timer = float(state.get("shot_reset_timer", 0.0))
	_last_wall_moving = false
	_moving_shake_timer = 0.0
	_finish_shake_sent = false
	_ensure_process_needed()
	queue_redraw()

func _on_body_entered(body: Node) -> void:
	if Engine.is_editor_hint() or not _can_trigger(body):
		return
	if button_mode == ButtonMode.HOLD:
		_release_timer = 0.0
	_pressed = true
	_shake_camera(shake_on_press)
	set_process(true)
	queue_redraw()
	_trigger_mechanism()

func _on_body_exited(body: Node) -> void:
	if Engine.is_editor_hint() or not _can_trigger(body):
		return
	if button_mode == ButtonMode.HOLD:
		_release_timer = release_delay if not _has_trigger_body_inside() else 0.0
		set_process(true)
		return
	if latch_when_activated and _activated:
		_pressed = true
		set_process(true)
		queue_redraw()
		return
	_pressed = _has_trigger_body_inside()
	set_process(true)
	queue_redraw()

func _on_area_entered(area: Area2D) -> void:
	if Engine.is_editor_hint() or button_mode != ButtonMode.SHOT or not _can_projectile_trigger(area):
		return
	_pressed = true
	_shake_camera(shake_on_press)
	set_process(true)
	queue_redraw()
	_trigger_mechanism()

func _trigger_mechanism() -> void:
	if trigger_once and _activated and button_mode == ButtonMode.LATCH:
		return
	_resolve_wall()
	if _moving_wall == null:
		return

	_activated = true
	_finish_shake_sent = false
	if button_mode == ButtonMode.SHOT:
		_shot_reset_timer = shot_reset_delay
	if play_cinematic:
		_start_cinematic()
	else:
		_activate_target()
		_start_wall_finish_watch()
	queue_redraw()

func _start_cinematic() -> void:
	_camera = _current_camera()
	if _camera == null:
		_activate_target()
		_start_wall_finish_watch()
		return

	_pause_gameplay_nodes()
	_camera_start_position = _camera.global_position
	_camera_start_zoom = _camera.zoom
	_camera_focus_position = _cinematic_focus_position()
	_camera_focus_zoom = _cinematic_zoom()
	if _camera.has_method("begin_cinematic_override"):
		_camera.begin_cinematic_override(_camera_start_position, _camera_start_zoom)
	_cinematic_state = CinematicState.MOVE_IN
	_cinematic_timer = 0.0
	set_process(true)

func _update_cinematic(delta: float) -> void:
	match _cinematic_state:
		CinematicState.MOVE_IN:
			_cinematic_timer += delta
			var progress := _smooth_progress(_cinematic_timer / maxf(camera_move_in_time, 0.001))
			_update_camera(_camera_start_position.lerp(_camera_focus_position, progress), _camera_start_zoom.lerp(_camera_focus_zoom, progress))
			if progress >= 1.0:
				_activate_target()
				_start_wall_finish_watch()
				_cinematic_state = CinematicState.WALL_MOVE
				_cinematic_timer = 0.0
		CinematicState.WALL_MOVE:
			_cinematic_timer += delta
			_update_camera(_camera_focus_position, _camera_focus_zoom)
			var wall_done: bool = not _moving_wall.has_method("is_moving") or not bool(_moving_wall.call("is_moving"))
			if wall_done and _cinematic_timer >= camera_hold_time:
				_emit_finish_shake_once()
				_cinematic_state = CinematicState.MOVE_OUT
				_cinematic_timer = 0.0
		CinematicState.MOVE_OUT:
			_cinematic_timer += delta
			var progress := _smooth_progress(_cinematic_timer / maxf(camera_move_out_time, 0.001))
			_update_camera(_camera_focus_position.lerp(_camera_start_position, progress), _camera_focus_zoom.lerp(_camera_start_zoom, progress))
			if progress >= 1.0:
				_end_cinematic()
		_:
			_ensure_process_needed()

func _end_cinematic() -> void:
	if _camera != null and _camera.has_method("end_cinematic_override"):
		_camera.end_cinematic_override()
	_resume_gameplay_nodes()
	_cinematic_state = CinematicState.NONE
	_ensure_process_needed()

func _update_press_animation(delta: float) -> void:
	var target_depth := _target_press_depth()
	var step := press_depth * delta / maxf(press_animation_time, 0.001)
	_press_visual_depth = move_toward(_press_visual_depth, target_depth, step)
	if Engine.is_editor_hint():
		_press_visual_depth = target_depth
	queue_redraw()

func _target_press_depth() -> float:
	return press_depth if _pressed else 0.0

func _update_button_timers(delta: float) -> void:
	if button_mode == ButtonMode.HOLD and _release_timer > 0.0:
		_release_timer = maxf(_release_timer - delta, 0.0)
		if _release_timer <= 0.0 and not _has_trigger_body_inside():
			_deactivate_button()
	if button_mode == ButtonMode.SHOT and _shot_reset_timer > 0.0:
		_shot_reset_timer = maxf(_shot_reset_timer - delta, 0.0)
		if _shot_reset_timer <= 0.0:
			_deactivate_button()
		queue_redraw()

func _deactivate_button() -> void:
	_pressed = false
	_activated = false
	_finish_shake_sent = false
	_deactivate_target()
	_start_wall_finish_watch()
	_shake_camera(shake_on_finish)
	queue_redraw()

func _ensure_process_needed() -> void:
	if Engine.is_editor_hint() or _cinematic_state != CinematicState.NONE or _press_visual_depth != _target_press_depth() or _watching_wall_finish or _release_timer > 0.0 or _shot_reset_timer > 0.0:
		set_process(true)
	else:
		set_process(false)

func _start_wall_finish_watch() -> void:
	_watching_wall_finish = true
	_last_wall_moving = true
	_moving_shake_timer = 0.0
	_ensure_process_needed()

func _update_wall_shake(delta: float) -> void:
	if not _watching_wall_finish or _moving_wall == null:
		return

	var wall_moving := _moving_wall.has_method("is_moving") and bool(_moving_wall.call("is_moving"))
	if wall_moving:
		_moving_shake_timer -= delta
		if _moving_shake_timer <= 0.0:
			_shake_camera(shake_while_moving)
			_moving_shake_timer = moving_shake_interval
		_last_wall_moving = true
		return

	if _last_wall_moving:
		_emit_finish_shake_once()
	_watching_wall_finish = false
	_last_wall_moving = false
	_ensure_process_needed()

func _emit_finish_shake_once() -> void:
	if _finish_shake_sent:
		return
	_finish_shake_sent = true
	_shake_camera(shake_on_finish)

func _activate_target() -> void:
	if _moving_wall == null:
		return
	if _moving_wall.has_method("activate"):
		_moving_wall.activate()
	elif _moving_wall.has_method("trigger_open"):
		_moving_wall.trigger_open()

func _deactivate_target() -> void:
	if _moving_wall == null:
		_resolve_wall()
	if _moving_wall == null:
		return
	if _moving_wall.has_method("deactivate"):
		_moving_wall.deactivate()
	elif _moving_wall.has_method("trigger_close"):
		_moving_wall.trigger_close()

func _shot_blink_alpha() -> float:
	var remaining := _shot_reset_timer
	var speed := 18.0 if remaining <= 1.0 else 7.0
	return 0.28 + 0.72 * absf(sin(Time.get_ticks_msec() / 1000.0 * speed))

func _pause_gameplay_nodes() -> void:
	_paused_nodes.clear()
	if not pause_gameplay_during_cinematic:
		return
	for group_name in ["players", "enemies"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node == null or not is_instance_valid(node):
				continue
			_paused_nodes.append({
				"node": node,
				"physics": node.is_physics_processing(),
				"process": node.is_processing(),
			})
			node.set_physics_process(false)
			node.set_process(false)

func _resume_gameplay_nodes() -> void:
	for record in _paused_nodes:
		var node := record["node"] as Node
		if node != null and is_instance_valid(node):
			node.set_physics_process(bool(record["physics"]))
			node.set_process(bool(record["process"]))
	_paused_nodes.clear()

func _update_camera(position: Vector2, zoom: Vector2) -> void:
	if _camera == null:
		return
	if _camera.has_method("update_cinematic_override"):
		_camera.update_cinematic_override(position, zoom)
	else:
		_camera.global_position = position
		_camera.zoom = zoom

func _cinematic_focus_position() -> Vector2:
	var bounds := Rect2(global_position, Vector2.ZERO)
	if _moving_wall != null and _moving_wall.has_method("get_mechanism_rect"):
		bounds = bounds.merge(_moving_wall.get_mechanism_rect())
	return bounds.grow(cinematic_padding).get_center()

func _cinematic_zoom() -> Vector2:
	var viewport_size := get_viewport_rect().size
	var target_size := cinematic_view_size.max(Vector2(160.0, 90.0))
	return Vector2(maxf(viewport_size.x / target_size.x, 1.0), maxf(viewport_size.y / target_size.y, 1.0))

func _draw_detection_area() -> void:
	var collision_shape := get_node_or_null("PressSensor/CollisionShape2D") as CollisionShape2D
	if collision_shape == null or collision_shape.shape == null:
		return
	var color := detect_color
	var outline := detect_color
	outline.a = minf(outline.a + 0.35, 1.0)
	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle != null:
		var rect := Rect2(collision_shape.position - rectangle.size * 0.5, rectangle.size)
		draw_rect(rect, color, true)
		draw_rect(rect, outline, false, 2.0)
		return
	var circle := collision_shape.shape as CircleShape2D
	if circle != null:
		draw_circle(collision_shape.position, circle.radius, color)
		draw_arc(collision_shape.position, circle.radius, 0.0, TAU, 36, outline, 2.0, true)
		return
	var capsule := collision_shape.shape as CapsuleShape2D
	if capsule != null:
		var horizontal := absf(absf(collision_shape.rotation) - PI * 0.5) < 0.01
		var size := Vector2(capsule.height, capsule.radius * 2.0) if horizontal else Vector2(capsule.radius * 2.0, capsule.height)
		_draw_capsule(collision_shape.position, size, color, outline, 2.0)

func _draw_capsule(center: Vector2, size: Vector2, fill: Color, outline: Color, outline_width: float) -> void:
	var radius := minf(size.y * 0.5, size.x * 0.5)
	var middle_width := maxf(size.x - radius * 2.0, 0.0)
	var rect := Rect2(center + Vector2(-middle_width * 0.5, -radius), Vector2(middle_width, radius * 2.0))
	if middle_width > 0.0:
		draw_rect(rect, fill, true)
	draw_circle(center + Vector2(-middle_width * 0.5, 0.0), radius, fill)
	draw_circle(center + Vector2(middle_width * 0.5, 0.0), radius, fill)
	if outline_width <= 0.0:
		return
	var points := PackedVector2Array()
	var segments := 14
	for index in range(segments + 1):
		var angle := PI * 0.5 + float(index) / float(segments) * PI
		points.append(center + Vector2(-middle_width * 0.5, 0.0) + Vector2(cos(angle), sin(angle)) * radius)
	for index in range(segments + 1):
		var angle := -PI * 0.5 + float(index) / float(segments) * PI
		points.append(center + Vector2(middle_width * 0.5, 0.0) + Vector2(cos(angle), sin(angle)) * radius)
	points.append(points[0])
	draw_polyline(points, outline, outline_width, true)

func _can_trigger(body: Node) -> bool:
	if detect_players and body.is_in_group("players"):
		return true
	if detect_enemies and body.is_in_group("enemies"):
		return true
	return false

func _can_projectile_trigger(area: Area2D) -> bool:
	return detect_player_weapons and area != null and area.is_in_group("player_weapons")

func _has_trigger_body_inside() -> bool:
	if _sensor == null:
		return false
	for body in _sensor.get_overlapping_bodies():
		if _can_trigger(body):
			return true
	return false

func _shake_camera(amount: float) -> void:
	if amount <= 0.0:
		return
	var did_shake := false
	for camera in get_tree().get_nodes_in_group("room_cameras"):
		if camera != null and is_instance_valid(camera) and camera.has_method("add_hit_shake"):
			camera.add_hit_shake(amount)
			did_shake = true
	if did_shake:
		return

	var camera := _current_camera()
	if camera != null and camera.has_method("add_hit_shake"):
		camera.add_hit_shake(amount)

func _resolve_wall() -> void:
	_moving_wall = get_node_or_null(moving_wall_path)

func _current_camera() -> Camera2D:
	var viewport_camera := get_viewport().get_camera_2d()
	if viewport_camera != null:
		return viewport_camera
	for camera in get_tree().get_nodes_in_group("room_cameras"):
		if camera is Camera2D:
			return camera
	return null

func _smooth_progress(value: float) -> float:
	value = clampf(value, 0.0, 1.0)
	return value * value * (3.0 - 2.0 * value)
