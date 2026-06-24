extends Camera2D

const CONNECTED_ROOM_ADJACENCY_TOLERANCE := 8.0

@export var target_path: NodePath
@export var lookahead_distance: float = 96.0
@export var facing_lookahead_speed: float = 4.5
@export var horizontal_dead_zone: float = 42.0
@export var vertical_dead_zone: float = 88.0
@export var catchup_speed: float = 7.5
@export var vertical_catchup_speed: float = 4.5
@export var default_room_rect := Rect2(-180.0, -120.0, 1280.0, 720.0)
@export var default_zoom := Vector2.ONE
@export var room_transition_duration: float = 0.58
@export var room_switch_pause_duration: float = 0.3
@export var fade_out_duration: float = 0.16
@export var fade_hold_duration: float = 0.08
@export var fade_in_duration: float = 0.2
@export var show_camera_zone_overlay := false
@export_group("Hit Feedback")
@export var shake_decay: float = 5.5
@export var max_shake_offset := Vector2(18.0, 12.0)
@export var shake_trauma_power: float = 2.0

var target: CharacterBody2D
var desired_position: Vector2
var active_room_rect: Rect2
var target_zoom: Vector2
var active_room_name := "Default"
var active_camera_profile := "custom"
var active_camera_view_mode := "free_size"
var active_no_follow := false
var active_lookahead_distance := 96.0
var active_facing_lookahead_speed := 4.5
var active_vertical_offset := 0.0
var active_dead_zone := Vector2(42.0, 88.0)
var active_border_zone := Vector2(180.0, 140.0)
var active_follow_damping := Vector2(7.5, 4.5)
var active_border_damping := Vector2(15.0, 10.0)
var active_room: Node
var is_room_transitioning := false
var transition_mask_alpha := 0.0
var _is_room_transitioning := false
var _is_fade_transitioning := false
var _transition_elapsed := 0.0
var _transition_duration := 0.58
var _transition_from_position := Vector2.ZERO
var _transition_to_position := Vector2.ZERO
var _transition_from_zoom := Vector2.ONE
var _transition_to_zoom := Vector2.ONE
var _transition_limit_rect := Rect2()
var _fade_phase := 0
var _fade_elapsed := 0.0
var _pending_room: Node
var _pending_room_rect := Rect2()
var _pending_room_name := ""
var _pending_room_zoom := Vector2.ONE
var _pending_room_position := Vector2.ZERO
var _pending_camera_settings := {}
var _base_camera_offset := Vector2.ZERO
var _shake_trauma := 0.0
var _shake_rng := RandomNumberGenerator.new()
var _cinematic_override_active := false
var _cinematic_override_position := Vector2.ZERO
var _cinematic_override_zoom := Vector2.ONE
var _room_switch_pause_generation := 0
var _room_switch_pause_active := false
var _restore_tree_paused_after_room_switch := false
var _facing_lookahead_offset := 0.0
var _continuous_room_limits_active := false
var _continuous_room_limit_rect := Rect2()
var _test_mode_free_camera := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = true
	make_current()
	add_to_group("room_cameras")
	_base_camera_offset = offset
	_shake_rng.randomize()

	active_room_rect = default_room_rect
	target_zoom = default_zoom
	zoom = default_zoom
	_apply_camera_settings(_default_camera_settings())
	_apply_native_camera_limits(active_room_rect)

	if not target_path.is_empty():
		target = get_node_or_null(target_path) as CharacterBody2D

	if target != null:
		global_position = target.global_position
		desired_position = global_position
		call_deferred("_find_starting_room")

func _process(delta: float) -> void:
	_update_hit_shake(delta)
	if _cinematic_override_active:
		global_position = _cinematic_override_position
		zoom = _cinematic_override_zoom
		return
	if _test_mode_free_camera:
		return
	if not _is_room_transitioning and not _is_fade_transitioning:
		var camera_limit_rect := _active_camera_limit_rect()
		_apply_native_camera_limits(camera_limit_rect)
		global_position = _clamp_position_to_rect(global_position, camera_limit_rect, zoom)

func add_hit_shake(amount: float = 0.18) -> void:
	_shake_trauma = clampf(_shake_trauma + amount, 0.0, 1.0)

func get_hit_shake_trauma() -> float:
	return _shake_trauma

func begin_cinematic_override(position: Vector2, camera_zoom: Vector2) -> void:
	_cinematic_override_active = true
	_cinematic_override_position = position
	_cinematic_override_zoom = camera_zoom
	global_position = position
	zoom = camera_zoom

func update_cinematic_override(position: Vector2, camera_zoom: Vector2) -> void:
	_cinematic_override_active = true
	_cinematic_override_position = position
	_cinematic_override_zoom = camera_zoom
	global_position = position
	zoom = camera_zoom

func end_cinematic_override() -> void:
	_cinematic_override_active = false
	desired_position = global_position

func _physics_process(delta: float) -> void:
	if _cinematic_override_active:
		global_position = _cinematic_override_position
		zoom = _cinematic_override_zoom
		return

	if target == null:
		return

	if _test_mode_free_camera:
		_update_test_mode_free_camera(delta)
		return

	_update_room_from_target_position()

	if _is_fade_transitioning:
		_update_fade_transition(delta)
		return

	if _is_room_transitioning:
		_update_room_transition(delta)
		return

	if active_no_follow:
		zoom = target_zoom
		var no_follow_limit_rect := _active_camera_limit_rect()
		_apply_native_camera_limits(no_follow_limit_rect)
		global_position = _clamp_position_to_rect(active_room_rect.get_center(), no_follow_limit_rect, zoom)
		desired_position = global_position
		return

	var target_position := target.global_position + Vector2(0.0, active_vertical_offset)
	var facing := _target_facing_direction()
	var target_lookahead_offset := facing * (active_lookahead_distance + active_dead_zone.x)
	_facing_lookahead_offset = lerpf(_facing_lookahead_offset, target_lookahead_offset, 1.0 - exp(-active_facing_lookahead_speed * delta))
	var tracked_position := target_position + Vector2(_facing_lookahead_offset, 0.0)
	var next_position := desired_position
	var follow_damping := active_follow_damping
	var fixed_axis_position := _fixed_axis_position()
	if active_camera_view_mode == "horizontal_follow":
		tracked_position.y = fixed_axis_position.y
		next_position.y = fixed_axis_position.y
		desired_position.y = fixed_axis_position.y
	elif active_camera_view_mode == "vertical_follow":
		tracked_position.x = fixed_axis_position.x
		next_position.x = fixed_axis_position.x
		desired_position.x = fixed_axis_position.x
	var horizontal_delta := tracked_position.x - desired_position.x
	var vertical_delta := tracked_position.y - desired_position.y

	if absf(horizontal_delta) > active_dead_zone.x:
		next_position.x = tracked_position.x - signf(horizontal_delta) * active_dead_zone.x

	if absf(vertical_delta) > active_dead_zone.y:
		next_position.y = tracked_position.y - signf(vertical_delta) * active_dead_zone.y

	var visible_half := _visible_size_for_zoom(zoom) * 0.5
	var hard_offset := Vector2(
		maxf(active_dead_zone.x, visible_half.x - active_border_zone.x),
		maxf(active_dead_zone.y, visible_half.y - active_border_zone.y)
	)
	var tracked_from_camera := tracked_position - global_position

	if absf(tracked_from_camera.x) > hard_offset.x:
		next_position.x = tracked_position.x - signf(tracked_from_camera.x) * hard_offset.x
		follow_damping.x = active_border_damping.x

	if absf(tracked_from_camera.y) > hard_offset.y:
		next_position.y = tracked_position.y - signf(tracked_from_camera.y) * hard_offset.y
		follow_damping.y = active_border_damping.y

	if active_camera_view_mode == "horizontal_follow":
		next_position.y = fixed_axis_position.y
		follow_damping.y = active_border_damping.y
	elif active_camera_view_mode == "vertical_follow":
		next_position.x = fixed_axis_position.x
		follow_damping.x = active_border_damping.x

	desired_position.x = lerpf(desired_position.x, next_position.x, 1.0 - exp(-follow_damping.x * delta))
	desired_position.y = lerpf(desired_position.y, next_position.y, 1.0 - exp(-follow_damping.y * delta))

	var unclamped_position := desired_position
	var smoothing := 1.0 - exp(5.0 * -delta)
	zoom = zoom.lerp(target_zoom, smoothing)
	zoom = _safe_zoom_for_room(active_room_rect, zoom)
	var camera_limit_rect := _active_camera_limit_rect()
	_apply_native_camera_limits(camera_limit_rect)
	global_position = _clamp_position_to_rect(unclamped_position, camera_limit_rect, zoom)

func set_room(room: Node) -> void:
	if room == null or not room.has_method("get_camera_rect"):
		return

	var next_room_rect: Rect2 = room.get_camera_rect()
	var room_id_value: Variant = room.get("room_id")
	var next_room_name: String = str(room_id_value) if room_id_value != null else room.name

	var requested_zoom := default_zoom
	if room.has_method("get_camera_zoom"):
		requested_zoom = room.get_camera_zoom()
	var next_zoom: Vector2 = _safe_zoom_for_room(next_room_rect, requested_zoom)
	var next_camera_settings := _camera_settings_from_room(room)
	var next_position: Vector2 = _room_focus_position(next_room_rect, next_zoom, float(next_camera_settings["vertical_offset"]))

	if active_room == null:
		_activate_room_immediately(room, next_room_rect, next_room_name, next_zoom, next_position, next_camera_settings)
		return

	if room == active_room:
		active_room_rect = next_room_rect
		active_room_name = next_room_name
		target_zoom = next_zoom
		_apply_camera_settings(next_camera_settings)
		_apply_native_camera_limits(_active_camera_limit_rect())
		if active_no_follow:
			zoom = next_zoom
			global_position = _clamp_position_to_rect(active_room_rect.get_center(), _active_camera_limit_rect(), zoom)
			desired_position = global_position
		return

	if _rooms_are_continuously_connected(active_room, room):
		_activate_connected_room(room, next_room_rect, next_room_name, next_zoom, next_camera_settings)
		return

	var next_transition_mode := _transition_mode_for_connection(active_room, room)

	if next_transition_mode == "fade_to_black":
		_start_fade_transition(room, next_room_rect, next_room_name, next_zoom, next_position, next_camera_settings)
	else:
		_start_smooth_transition(room, next_room_rect, next_room_name, next_zoom, next_position, next_camera_settings)
	_pause_game_for_room_switch()

func set_test_mode_free_camera(enabled: bool) -> void:
	if _test_mode_free_camera == enabled:
		return
	_test_mode_free_camera = enabled
	_is_room_transitioning = false
	_is_fade_transitioning = false
	is_room_transitioning = false
	transition_mask_alpha = 0.0
	_pending_room = null
	_pending_camera_settings = {}
	_clear_continuous_room_limits()
	if _test_mode_free_camera:
		limit_left = -10000000
		limit_top = -10000000
		limit_right = 10000000
		limit_bottom = 10000000
		desired_position = global_position
	else:
		request_room_refresh()

func _update_test_mode_free_camera(delta: float) -> void:
	var smoothing := 1.0 - exp(-12.0 * delta)
	zoom = zoom.lerp(default_zoom, smoothing)
	global_position = global_position.lerp(target.global_position, smoothing)
	desired_position = global_position

func _find_starting_room() -> void:
	if target == null:
		return

	var room := _room_at_point(target.global_position)
	if room != null:
		set_room(room)

func request_room_refresh() -> void:
	if target != null:
		_update_room_from_target_position()

func snap_to_target_room() -> void:
	if target == null:
		return
	var room := _room_at_point(target.global_position)
	if room == null or not room.has_method("get_camera_rect"):
		return
	var room_rect: Rect2 = room.get_camera_rect()
	var room_id_value: Variant = room.get("room_id")
	var room_name: String = str(room_id_value) if room_id_value != null else room.name
	var requested_zoom := default_zoom
	if room.has_method("get_camera_zoom"):
		requested_zoom = room.get_camera_zoom()
	var room_zoom := _safe_zoom_for_room(room_rect, requested_zoom)
	var room_settings := _camera_settings_from_room(room)
	var room_position := _room_focus_position(room_rect, room_zoom, float(room_settings["vertical_offset"]))
	_is_room_transitioning = false
	_is_fade_transitioning = false
	is_room_transitioning = false
	transition_mask_alpha = 0.0
	_pending_room = null
	_pending_camera_settings = {}
	_activate_room_immediately(room, room_rect, room_name, room_zoom, room_position, room_settings)

func _transition_mode_for_connection(from_room: Node, to_room: Node) -> String:
	var from_mode := _room_transition_mode(from_room)
	var to_mode := _room_transition_mode(to_room)

	if from_mode == "fade_to_black" or to_mode == "fade_to_black":
		return "fade_to_black"
	return "smooth"

func _room_transition_mode(room: Node) -> String:
	if room != null and room.has_method("get_transition_mode"):
		return room.get_transition_mode()
	return "smooth"

func _update_room_from_target_position() -> void:
	var room := _room_at_point(target.global_position)
	if _is_room_transitioning:
		if room == active_room:
			_cancel_room_transition()
		elif room != null and room != _pending_room:
			set_room(room)
		return

	if _is_fade_transitioning:
		if room == active_room:
			_cancel_fade_transition()
		elif room != null and room != _pending_room:
			set_room(room)
		return

	if room != null:
		set_room(room)

func _room_at_point(point: Vector2) -> Node:
	if active_room != null and active_room.has_method("contains_point"):
		var active_contains := bool(active_room.contains_point(point))
		var connected_room_at_point := _connected_room_at_point(point, active_contains)
		if connected_room_at_point != null:
			return connected_room_at_point
		if active_contains:
			return active_room

	var best_room: Node
	var best_distance := INF

	for room in get_tree().get_nodes_in_group("camera_rooms"):
		if not room.has_method("contains_point") or not room.contains_point(point):
			continue

		var distance := _room_selection_distance(room, point)
		if distance < best_distance:
			best_distance = distance
			best_room = room

	return best_room

func _room_selection_distance(room: Node, point: Vector2) -> float:
	var room_center := _room_selection_center(room)
	if active_room == null:
		return point.distance_squared_to(room_center)

	return _room_selection_center(active_room).distance_squared_to(room_center)

func _room_selection_center(room: Node) -> Vector2:
	if room != null and room.has_method("get_trigger_rect"):
		return room.get_trigger_rect().get_center()
	if room != null and room.has_method("get_camera_rect"):
		return room.get_camera_rect().get_center()
	return Vector2.ZERO

func _connected_room_at_point(point: Vector2, active_contains: bool) -> Node:
	if active_room == null:
		return null
	var active_distance := point.distance_squared_to(_room_selection_center(active_room)) if active_contains else INF
	var best_room: Node
	var best_distance := active_distance
	for room in get_tree().get_nodes_in_group("camera_rooms"):
		if room == active_room or not _rooms_are_continuously_connected(active_room, room):
			continue
		if not room.has_method("contains_point") or not bool(room.contains_point(point)):
			continue
		var distance := point.distance_squared_to(_room_selection_center(room))
		if not active_contains or distance + 1.0 < best_distance:
			best_distance = distance
			best_room = room
	return best_room

func _rooms_are_continuously_connected(from_room: Node, to_room: Node) -> bool:
	if from_room == null or to_room == null or from_room == to_room:
		return false
	if not _room_is_connected(from_room) or not _room_is_connected(to_room):
		return false
	return _rooms_are_adjacent(from_room, to_room)

func _room_is_connected(room: Node) -> bool:
	return room != null and room.has_method("is_connected_room") and bool(room.call("is_connected_room"))

func _rooms_are_adjacent(from_room: Node, to_room: Node) -> bool:
	var from_rect := _room_trigger_rect(from_room)
	var to_rect := _room_trigger_rect(to_room)
	if from_rect.size.x <= 0.0 or from_rect.size.y <= 0.0 or to_rect.size.x <= 0.0 or to_rect.size.y <= 0.0:
		return false
	var tolerance := CONNECTED_ROOM_ADJACENCY_TOLERANCE
	if from_rect.grow(tolerance).intersects(to_rect, true):
		return true
	var horizontal_touch := absf(from_rect.end.x - to_rect.position.x) <= tolerance or absf(to_rect.end.x - from_rect.position.x) <= tolerance
	var vertical_overlap := from_rect.position.y <= to_rect.end.y + tolerance and to_rect.position.y <= from_rect.end.y + tolerance
	var vertical_touch := absf(from_rect.end.y - to_rect.position.y) <= tolerance or absf(to_rect.end.y - from_rect.position.y) <= tolerance
	var horizontal_overlap := from_rect.position.x <= to_rect.end.x + tolerance and to_rect.position.x <= from_rect.end.x + tolerance
	return (horizontal_touch and vertical_overlap) or (vertical_touch and horizontal_overlap)

func _room_trigger_rect(room: Node) -> Rect2:
	if room != null and room.has_method("get_trigger_rect"):
		return room.call("get_trigger_rect") as Rect2
	if room != null and room.has_method("get_camera_rect"):
		return room.call("get_camera_rect") as Rect2
	return Rect2()

func _safe_zoom_for_room(room_rect: Rect2, requested_zoom: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	var minimum_zoom := maxf(viewport_size.x / room_rect.size.x, viewport_size.y / room_rect.size.y)
	minimum_zoom = maxf(minimum_zoom, 1.0)
	return Vector2(maxf(requested_zoom.x, minimum_zoom), maxf(requested_zoom.y, minimum_zoom))

func _room_focus_position(room_rect: Rect2, room_zoom: Vector2, vertical_offset: float = 0.0) -> Vector2:
	var focus_position := target.global_position + Vector2(0.0, vertical_offset) if target != null else room_rect.get_center()
	return _clamp_position_to_rect(focus_position, room_rect, room_zoom)

func _start_smooth_transition(room: Node, next_room_rect: Rect2, next_room_name: String, next_zoom: Vector2, next_position: Vector2, next_camera_settings: Dictionary) -> void:
	_clear_continuous_room_limits()
	var old_room_rect := active_room_rect
	_pending_room = room
	_pending_room_rect = next_room_rect
	_pending_room_name = next_room_name
	_pending_room_zoom = next_zoom
	_pending_room_position = next_position
	_pending_camera_settings = next_camera_settings
	_transition_limit_rect = old_room_rect.merge(next_room_rect)
	_apply_native_camera_limits(_transition_limit_rect)
	_start_room_transition(next_position, next_zoom)

func _start_room_transition(next_position: Vector2, next_zoom: Vector2) -> void:
	_is_fade_transitioning = false
	_is_room_transitioning = true
	is_room_transitioning = true
	transition_mask_alpha = 0.0
	_transition_elapsed = 0.0
	_transition_duration = room_transition_duration
	_transition_from_position = global_position
	_transition_to_position = next_position
	_transition_from_zoom = zoom
	_transition_to_zoom = next_zoom
	desired_position = next_position

func _cancel_room_transition() -> void:
	_is_room_transitioning = false
	is_room_transitioning = false
	_pending_room = null
	_pending_camera_settings = {}
	transition_mask_alpha = 0.0
	_apply_native_camera_limits(active_room_rect)
	global_position = _clamp_to_room(global_position)
	desired_position = global_position

func _update_room_transition(delta: float) -> void:
	_transition_elapsed += delta
	var raw_progress := clampf(_transition_elapsed / maxf(_transition_duration, 0.001), 0.0, 1.0)
	var progress := _ease_in_out_cubic(raw_progress)

	zoom = _transition_from_zoom.lerp(_transition_to_zoom, progress)
	zoom = _safe_zoom_for_room(_transition_limit_rect, zoom)
	var transition_position := _transition_from_position.lerp(_transition_to_position, progress)
	global_position = _clamp_position_to_rect(transition_position, _transition_limit_rect, zoom)

	if raw_progress >= 1.0:
		_is_room_transitioning = false
		is_room_transitioning = false
		transition_mask_alpha = 0.0
		_activate_pending_room_after_smooth_transition()

func _activate_pending_room_after_smooth_transition() -> void:
	if _pending_room == null:
		zoom = _transition_to_zoom
		global_position = _clamp_to_room(_transition_to_position)
		desired_position = global_position
		return

	_activate_room_immediately(
		_pending_room,
		_pending_room_rect,
		_pending_room_name,
		_pending_room_zoom,
		_transition_to_position,
		_pending_camera_settings
	)
	_pending_room = null
	_pending_camera_settings = {}

func _start_fade_transition(room: Node, next_room_rect: Rect2, next_room_name: String, next_zoom: Vector2, next_position: Vector2, next_camera_settings: Dictionary) -> void:
	_clear_continuous_room_limits()
	_is_room_transitioning = false
	_is_fade_transitioning = true
	is_room_transitioning = true
	_fade_phase = 0
	_fade_elapsed = 0.0
	_pending_room = room
	_pending_room_rect = next_room_rect
	_pending_room_name = next_room_name
	_pending_room_zoom = next_zoom
	_pending_room_position = next_position
	_pending_camera_settings = next_camera_settings

func _pause_game_for_room_switch() -> void:
	if room_switch_pause_duration <= 0.0 or get_tree() == null:
		return
	_room_switch_pause_generation += 1
	var pause_generation := _room_switch_pause_generation
	if not _room_switch_pause_active:
		_restore_tree_paused_after_room_switch = get_tree().paused
		_room_switch_pause_active = true
	get_tree().paused = true
	var pause_timer := get_tree().create_timer(room_switch_pause_duration, true, false, true)
	await pause_timer.timeout
	if pause_generation != _room_switch_pause_generation:
		return
	_room_switch_pause_active = false
	if not _restore_tree_paused_after_room_switch:
		get_tree().paused = false

func _cancel_fade_transition() -> void:
	_is_fade_transitioning = false
	is_room_transitioning = false
	_fade_phase = 0
	_fade_elapsed = 0.0
	_pending_room = null
	_pending_camera_settings = {}
	transition_mask_alpha = 0.0

func _update_fade_transition(delta: float) -> void:
	_fade_elapsed += delta

	if _fade_phase == 0:
		var out_progress := clampf(_fade_elapsed / maxf(fade_out_duration, 0.001), 0.0, 1.0)
		transition_mask_alpha = _ease_in_out_cubic(out_progress)
		if out_progress >= 1.0:
			_activate_pending_fade_room()
			_fade_phase = 1
			_fade_elapsed = 0.0
	elif _fade_phase == 1:
		transition_mask_alpha = 1.0
		if _fade_elapsed >= fade_hold_duration:
			_fade_phase = 2
			_fade_elapsed = 0.0
	else:
		var in_progress := clampf(_fade_elapsed / maxf(fade_in_duration, 0.001), 0.0, 1.0)
		transition_mask_alpha = 1.0 - _ease_in_out_cubic(in_progress)
		if in_progress >= 1.0:
			_is_fade_transitioning = false
			is_room_transitioning = false
			transition_mask_alpha = 0.0
			_pending_room = null

func _activate_pending_fade_room() -> void:
	if _pending_room == null:
		return
	_activate_room_immediately(_pending_room, _pending_room_rect, _pending_room_name, _pending_room_zoom, _pending_room_position, _pending_camera_settings)

func _activate_room_immediately(room: Node, room_rect: Rect2, room_name: String, room_zoom: Vector2, room_position: Vector2, room_settings: Dictionary) -> void:
	_clear_continuous_room_limits()
	active_room = room
	active_room_rect = room_rect
	active_room_name = room_name
	target_zoom = room_zoom
	zoom = room_zoom
	_apply_camera_settings(room_settings)
	_apply_native_camera_limits(active_room_rect)
	global_position = _clamp_to_room(room_position)
	desired_position = global_position

func _activate_connected_room(room: Node, room_rect: Rect2, room_name: String, room_zoom: Vector2, room_settings: Dictionary) -> void:
	var previous_room_rect := active_room_rect
	_is_room_transitioning = false
	_is_fade_transitioning = false
	is_room_transitioning = false
	transition_mask_alpha = 0.0
	_pending_room = null
	_pending_camera_settings = {}
	active_room = room
	active_room_rect = room_rect
	active_room_name = room_name
	target_zoom = room_zoom
	_apply_camera_settings(room_settings)
	_continuous_room_limit_rect = _continuous_limit_rect_for_rooms(previous_room_rect, room_rect)
	_continuous_room_limits_active = true
	_apply_native_camera_limits(_continuous_room_limit_rect)
	desired_position = _clamp_position_to_rect(desired_position, _continuous_room_limit_rect, zoom)
	global_position = _clamp_position_to_rect(global_position, _continuous_room_limit_rect, zoom)

func _continuous_limit_rect_for_rooms(from_rect: Rect2, to_rect: Rect2) -> Rect2:
	var from_center := from_rect.get_center()
	var to_center := to_rect.get_center()
	var delta := to_center - from_center
	if absf(delta.x) >= absf(delta.y):
		var left := minf(from_rect.position.x, to_rect.position.x)
		var right := maxf(from_rect.end.x, to_rect.end.x)
		return Rect2(Vector2(left, to_rect.position.y), Vector2(right - left, to_rect.size.y))
	var top := minf(from_rect.position.y, to_rect.position.y)
	var bottom := maxf(from_rect.end.y, to_rect.end.y)
	return Rect2(Vector2(to_rect.position.x, top), Vector2(to_rect.size.x, bottom - top))

func _active_camera_limit_rect() -> Rect2:
	return _continuous_room_limit_rect if _continuous_room_limits_active else active_room_rect

func _clear_continuous_room_limits() -> void:
	_continuous_room_limits_active = false
	_continuous_room_limit_rect = Rect2()

func _default_camera_settings() -> Dictionary:
	return {
		"profile": "custom",
		"view_mode": "free_size",
		"no_follow": false,
		"lookahead_distance": lookahead_distance,
		"facing_lookahead_speed": facing_lookahead_speed,
		"vertical_offset": 0.0,
		"dead_zone": Vector2(horizontal_dead_zone, vertical_dead_zone),
		"border_zone": Vector2(180.0, 140.0),
		"follow_damping": Vector2(catchup_speed, vertical_catchup_speed),
		"border_damping": Vector2(15.0, 10.0)
	}

func _camera_settings_from_room(room: Node) -> Dictionary:
	var settings := _default_camera_settings()
	if room == null:
		return settings

	if room.has_method("get_camera_profile"):
		settings["profile"] = room.get_camera_profile()
	if room.has_method("get_camera_view_mode"):
		settings["view_mode"] = room.get_camera_view_mode()
	if room.has_method("get_no_follow"):
		settings["no_follow"] = bool(room.get_no_follow())
	if room.has_method("get_lookahead_distance"):
		settings["lookahead_distance"] = float(room.get_lookahead_distance())
	if room.has_method("get_facing_lookahead_speed"):
		settings["facing_lookahead_speed"] = float(room.get_facing_lookahead_speed())
	if room.has_method("get_vertical_offset"):
		settings["vertical_offset"] = float(room.get_vertical_offset())
	if room.has_method("get_dead_zone"):
		settings["dead_zone"] = room.get_dead_zone()
	if room.has_method("get_border_zone"):
		settings["border_zone"] = room.get_border_zone()
	if room.has_method("get_follow_damping"):
		settings["follow_damping"] = room.get_follow_damping()
	if room.has_method("get_border_damping"):
		settings["border_damping"] = room.get_border_damping()

	return settings

func _apply_camera_settings(settings: Dictionary) -> void:
	active_camera_profile = str(settings["profile"])
	active_camera_view_mode = str(settings["view_mode"])
	active_no_follow = bool(settings.get("no_follow", false))
	active_lookahead_distance = float(settings["lookahead_distance"])
	active_facing_lookahead_speed = float(settings.get("facing_lookahead_speed", facing_lookahead_speed))
	active_vertical_offset = float(settings["vertical_offset"])
	active_dead_zone = settings["dead_zone"]
	active_border_zone = settings["border_zone"]
	active_follow_damping = settings["follow_damping"]
	active_border_damping = settings["border_damping"]

func _visible_size_for_zoom(camera_zoom: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	return Vector2(viewport_size.x / camera_zoom.x, viewport_size.y / camera_zoom.y)

func _apply_native_camera_limits(room_rect: Rect2) -> void:
	limit_left = floori(room_rect.position.x)
	limit_top = floori(room_rect.position.y)
	limit_right = ceili(room_rect.position.x + room_rect.size.x)
	limit_bottom = ceili(room_rect.position.y + room_rect.size.y)

func _update_hit_shake(delta: float) -> void:
	if _shake_trauma <= 0.0:
		offset = _base_camera_offset
		return

	_shake_trauma = maxf(_shake_trauma - shake_decay * delta, 0.0)
	var amount := pow(_shake_trauma, shake_trauma_power)
	offset = _base_camera_offset + Vector2(
		_shake_rng.randf_range(-max_shake_offset.x, max_shake_offset.x) * amount,
		_shake_rng.randf_range(-max_shake_offset.y, max_shake_offset.y) * amount
	)

func _ease_in_out_cubic(value: float) -> float:
	if value < 0.5:
		return 4.0 * value * value * value
	var shifted := -2.0 * value + 2.0
	return 1.0 - (shifted * shifted * shifted) / 2.0

func _clamp_to_room(position: Vector2) -> Vector2:
	return _clamp_position_to_rect(position, active_room_rect, zoom)

func _clamp_position_to_rect(position: Vector2, room_rect: Rect2, room_zoom: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	var visible_size := Vector2(viewport_size.x / room_zoom.x, viewport_size.y / room_zoom.y)
	var half_visible := visible_size * 0.5
	var min_position := room_rect.position + half_visible
	var max_position := room_rect.position + room_rect.size - half_visible

	if min_position.x > max_position.x:
		position.x = room_rect.get_center().x
	else:
		position.x = clampf(position.x, min_position.x, max_position.x)

	if min_position.y > max_position.y:
		position.y = room_rect.get_center().y
	else:
		position.y = clampf(position.y, min_position.y, max_position.y)

	return position

func _fixed_axis_position() -> Vector2:
	var center := active_room_rect.get_center()
	center.y += active_vertical_offset
	return _clamp_position_to_rect(center, active_room_rect, zoom)

func _read_horizontal_intent() -> float:
	var direction := 0.0
	if Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A):
		direction -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D):
		direction += 1.0
	return clampf(direction, -1.0, 1.0)

func _target_facing_direction() -> float:
	if target == null:
		return 1.0
	var target_facing: Variant = target.get("facing_direction")
	var facing := signf(float(target_facing)) if target_facing != null else 0.0
	if not is_zero_approx(facing):
		return facing
	facing = signf(target.velocity.x)
	if not is_zero_approx(facing):
		return facing
	facing = _read_horizontal_intent()
	if not is_zero_approx(facing):
		return facing
	return 1.0