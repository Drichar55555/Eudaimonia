extends Camera2D

@export var target_path: NodePath
@export var lookahead_distance: float = 96.0
@export var horizontal_dead_zone: float = 42.0
@export var vertical_dead_zone: float = 88.0
@export var catchup_speed: float = 7.5
@export var vertical_catchup_speed: float = 4.5
@export var default_room_rect := Rect2(-180.0, -120.0, 1280.0, 720.0)
@export var default_zoom := Vector2.ONE
@export var room_transition_duration: float = 0.58

var target: CharacterBody2D
var desired_position: Vector2
var active_room_rect: Rect2
var target_zoom: Vector2
var active_room_name := "Default"
var active_room: Node
var is_room_transitioning := false
var _is_room_transitioning := false
var _transition_elapsed := 0.0
var _transition_duration := 0.58
var _transition_from_position := Vector2.ZERO
var _transition_to_position := Vector2.ZERO
var _transition_from_zoom := Vector2.ONE
var _transition_to_zoom := Vector2.ONE

func _ready() -> void:
	enabled = true
	make_current()
	add_to_group("room_cameras")

	active_room_rect = default_room_rect
	target_zoom = default_zoom
	zoom = default_zoom

	if not target_path.is_empty():
		target = get_node_or_null(target_path) as CharacterBody2D

	if target != null:
		global_position = target.global_position
		desired_position = global_position
		call_deferred("_find_starting_room")

func _physics_process(delta: float) -> void:
	if target == null:
		return

	_update_room_from_target_position()

	if _is_room_transitioning:
		_update_room_transition(delta)
		return

	var target_position := target.global_position
	var facing: float = signf(target.velocity.x)

	if is_zero_approx(facing):
		facing = _read_horizontal_intent()
	if is_zero_approx(facing):
		facing = 1.0

	var next_position := desired_position
	var horizontal_delta := target_position.x - desired_position.x
	var vertical_delta := target_position.y - desired_position.y

	if absf(horizontal_delta) > horizontal_dead_zone:
		next_position.x = target_position.x - signf(horizontal_delta) * horizontal_dead_zone

	if absf(vertical_delta) > vertical_dead_zone:
		next_position.y = target_position.y - signf(vertical_delta) * vertical_dead_zone

	next_position.x += facing * lookahead_distance
	desired_position = desired_position.lerp(next_position, 1.0 - exp(-catchup_speed * delta))

	var smoothed_y := global_position.y + (desired_position.y - global_position.y) * (1.0 - exp(-vertical_catchup_speed * delta))
	var unclamped_position := Vector2(desired_position.x, smoothed_y)
	var smoothing := 1.0 - exp(5.0 * -delta)
	zoom = zoom.lerp(target_zoom, smoothing)
	global_position = _clamp_to_room(unclamped_position)

func set_room(room: Node) -> void:
	if room == null or not room.has_method("get_camera_rect"):
		return

	var next_room_rect: Rect2 = room.get_camera_rect()
	var room_id_value: Variant = room.get("room_id")
	var next_room_name: String = str(room_id_value) if room_id_value != null else room.name

	if room == active_room:
		return

	var next_zoom: Vector2 = _zoom_for_room(next_room_rect)
	var next_position: Vector2 = _room_focus_position(next_room_rect, next_zoom)

	active_room_rect = next_room_rect
	active_room_name = next_room_name
	active_room = room
	target_zoom = next_zoom
	_start_room_transition(next_position, next_zoom)

func _find_starting_room() -> void:
	if target == null:
		return

	for room in get_tree().get_nodes_in_group("camera_rooms"):
		if room.has_method("contains_point") and room.contains_point(target.global_position):
			set_room(room)
			return

func _update_room_from_target_position() -> void:
	var room := _room_at_point(target.global_position)
	if room != null and room != active_room:
		set_room(room)

func _room_at_point(point: Vector2) -> Node:
	var best_room: Node
	var best_distance := INF

	for room in get_tree().get_nodes_in_group("camera_rooms"):
		if not room.has_method("contains_point") or not room.contains_point(point):
			continue

		var room_rect: Rect2 = room.get_camera_rect()
		var distance := point.distance_squared_to(room_rect.get_center())
		if distance < best_distance:
			best_distance = distance
			best_room = room

	return best_room

func _zoom_for_room(room_rect: Rect2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	var required_zoom := maxf(viewport_size.x / room_rect.size.x, viewport_size.y / room_rect.size.y)
	required_zoom = maxf(required_zoom, 1.0)
	return Vector2(required_zoom, required_zoom)

func _room_focus_position(room_rect: Rect2, room_zoom: Vector2) -> Vector2:
	var focus_position := target.global_position if target != null else room_rect.get_center()
	return _clamp_position_to_rect(focus_position, room_rect, room_zoom)

func _start_room_transition(next_position: Vector2, next_zoom: Vector2) -> void:
	_is_room_transitioning = true
	is_room_transitioning = true
	_transition_elapsed = 0.0
	_transition_duration = room_transition_duration
	_transition_from_position = global_position
	_transition_to_position = next_position
	_transition_from_zoom = zoom
	_transition_to_zoom = next_zoom
	desired_position = next_position

func _update_room_transition(delta: float) -> void:
	_transition_elapsed += delta
	var raw_progress := clampf(_transition_elapsed / maxf(_transition_duration, 0.001), 0.0, 1.0)
	var progress := _ease_in_out_cubic(raw_progress)

	zoom = _transition_from_zoom.lerp(_transition_to_zoom, progress)
	global_position = _transition_from_position.lerp(_transition_to_position, progress)

	if raw_progress >= 1.0:
		_is_room_transitioning = false
		is_room_transitioning = false
		zoom = _transition_to_zoom
		global_position = _clamp_to_room(_transition_to_position)
		desired_position = global_position

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

func _read_horizontal_intent() -> float:
	var direction := 0.0
	if Input.is_action_pressed("ui_left") or Input.is_physical_key_pressed(KEY_A):
		direction -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_physical_key_pressed(KEY_D):
		direction += 1.0
	return clampf(direction, -1.0, 1.0)