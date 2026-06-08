@tool
extends CharacterBody2D

const HIT_SPARK_SCENE := preload("res://scenes/hit_spark.tscn")

const TERRAIN_LAYER := 1 << 0
const ENEMY_LAYER := 1 << 2
const GHOST_BLOCK_LAYER := 1 << 3

enum EnemyState { PATROL, CHASE }

@export_group("AI")
@export var ai_enabled := true
@export var target_path: NodePath
@export var constrain_to_starting_room := true
@export var active_only_in_current_room := true
@export var lock_chase_after_detection := true
@export var patrol_enabled := true:
	set(value):
		patrol_enabled = value
		queue_redraw()
@export_range(0.0, 800.0, 1.0) var patrol_distance := 180.0:
	set(value):
		patrol_distance = maxf(value, 0.0)
		queue_redraw()
@export var vision_range := Vector2(1200.0, 620.0):
	set(value):
		vision_range = Vector2(maxf(absf(value.x), 24.0), maxf(absf(value.y), 24.0))
		queue_redraw()
@export var hearing_range := Vector2(220.0, 200.0):
	set(value):
		hearing_range = Vector2(maxf(absf(value.x), 16.0), maxf(absf(value.y), 16.0))
		queue_redraw()
@export var awareness_range := Vector2(900.0, 520.0):
	set(value):
		awareness_range = Vector2(maxf(absf(value.x), 16.0), maxf(absf(value.y), 16.0))
		queue_redraw()
@export var enforce_minimum_detection_ranges := true
@export var minimum_vision_range := Vector2(1200.0, 620.0)
@export var minimum_hearing_range := Vector2(220.0, 200.0)
@export var minimum_awareness_range := Vector2(900.0, 520.0)
@export_range(0.0, 2.0, 0.05) var chase_memory_time := 0.55
@export_range(0.0, 160.0, 1.0) var stop_distance := 34.0
@export_range(0.0, 360.0, 1.0) var patrol_speed := 34.0
@export_range(0.0, 480.0, 1.0) var chase_speed := 64.0
@export_range(0.0, 4000.0, 10.0) var ground_acceleration := 560.0
@export_range(0.0, 4000.0, 10.0) var ground_deceleration := 760.0
@export_range(0.1, 3.0, 0.05) var gravity_scale := 1.0
@export_range(120.0, 1800.0, 10.0) var max_fall_speed := 900.0
@export_range(-1.0, 1.0, 1.0) var initial_patrol_direction := -1.0
@export var avoid_ledges := true
@export var require_line_of_sight := false
@export_range(4.0, 80.0, 1.0) var floor_probe_forward := 26.0
@export_range(8.0, 140.0, 1.0) var floor_probe_depth := 72.0
@export var can_step_over_small_obstacles := true
@export_range(0.0, 96.0, 1.0) var max_step_height := 28.0
@export_range(2.0, 24.0, 1.0) var step_scan_increment := 4.0

@export_group("Attack")
@export_range(1, 6, 1) var attack_damage := 1
@export var attack_range := Vector2(44.0, 42.0)
@export_range(0.1, 4.0, 0.05) var attack_cooldown := 0.85

@export_group("Queue")
@export var queue_enabled := true
@export_range(24.0, 140.0, 1.0) var queue_spacing := 56.0
@export_range(12.0, 120.0, 1.0) var queue_vertical_tolerance := 40.0

@export_group("AI Debug")
@export var show_ai_ranges := true:
	set(value):
		show_ai_ranges = value
		queue_redraw()
@export var show_runtime_ai_ranges := false:
	set(value):
		show_runtime_ai_ranges = value
		queue_redraw()
@export_range(0.02, 0.6, 0.01) var ai_visual_alpha := 0.16:
	set(value):
		ai_visual_alpha = clampf(value, 0.02, 0.6)
		queue_redraw()

@export_group("Stats")
@export var max_health := 3
@export var can_touch_ghost_blocks := false:
	set(value):
		can_touch_ghost_blocks = value
		_update_collision_layers()
		queue_redraw()

@export_group("Visual")
@export var body_size := Vector2(40.0, 48.0):
	set(value):
		body_size = value.max(Vector2(12.0, 12.0))
		_update_shapes()
		queue_redraw()

@export var body_color := Color(0.92, 0.34, 0.26, 1.0):
	set(value):
		body_color = value
		queue_redraw()

@export var edge_color := Color(0.12, 0.05, 0.04, 1.0):
	set(value):
		edge_color = value
		queue_redraw()

@export var ghost_mark_color := Color(0.55, 0.95, 1.0, 0.9):
	set(value):
		ghost_mark_color = value
		queue_redraw()

@export var hit_flash_time := 0.12
@export var hit_flash_color := Color(1.0, 1.0, 1.0, 1.0)
@export var hit_push_distance := 8.0
@export var hit_spark_color := Color(1.0, 0.82, 0.24, 1.0)
@export var hit_shake_amount := 0.18
@export var defeat_shake_amount := 0.32

var health := 3
var target: Node2D
var current_state := EnemyState.PATROL
var _home_position := Vector2.ZERO
var _last_seen_position := Vector2.ZERO
var _sight_memory_timer := 0.0
var _patrol_direction := -1.0
var _attack_cooldown_timer := 0.0
var _hit_flash_timer := 0.0
var _hit_squash_timer := 0.0
var _hit_push_direction := Vector2.ZERO
var _home_room: Node
var _home_room_rect := Rect2()

func _ready() -> void:
	z_index = 80
	z_as_relative = false
	add_to_group("enemies")
	add_to_group("saveable")
	_home_position = global_position
	_last_seen_position = global_position
	_patrol_direction = -1.0 if initial_patrol_direction < 0.0 else 1.0
	set_process(false)
	set_physics_process(not Engine.is_editor_hint())
	health = max_health
	_apply_minimum_detection_ranges()
	_update_shapes()
	_update_collision_layers()
	_resolve_target()
	call_deferred("_detect_home_room")
	queue_redraw()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _is_active_in_current_room():
		velocity = Vector2.ZERO
		return

	if not ai_enabled:
		_apply_gravity(delta)
		velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
		move_and_slide()
		return

	if target == null or not is_instance_valid(target):
		_resolve_target()
	_attack_cooldown_timer = maxf(_attack_cooldown_timer - delta, 0.0)

	_update_ai_state(delta)
	_try_attack_target()
	_apply_gravity(delta)
	_apply_horizontal_ai(delta)
	move_and_slide()
	_handle_mechanism_wall_collisions()
	if show_ai_ranges and show_runtime_ai_ranges:
		queue_redraw()

func _process(delta: float) -> void:
	_hit_flash_timer = maxf(_hit_flash_timer - delta, 0.0)
	_hit_squash_timer = maxf(_hit_squash_timer - delta, 0.0)
	queue_redraw()
	if _hit_flash_timer <= 0.0 and _hit_squash_timer <= 0.0:
		set_process(false)

func take_boomerang_hit(_boomerang: Node) -> void:
	health -= 1
	_hit_flash_timer = hit_flash_time
	_hit_squash_timer = hit_flash_time
	_update_hit_push_direction(_boomerang)
	_spawn_hit_spark(_boomerang, health <= 0)
	_shake_camera(defeat_shake_amount if health <= 0 else hit_shake_amount)
	set_process(not Engine.is_editor_hint())
	if health <= 0:
		queue_free()
		return
	queue_redraw()

func take_environment_hit(damage: int = 1, hit_source: Node = null, hit_direction: Vector2 = Vector2.ZERO, knockback: Vector2 = Vector2(220.0, -160.0)) -> bool:
	if damage <= 0:
		return false
	health -= damage
	_hit_flash_timer = hit_flash_time
	_hit_squash_timer = hit_flash_time
	_update_hit_push_direction(hit_source)
	velocity.x = absf(knockback.x) * signf(hit_direction.x if not is_zero_approx(hit_direction.x) else global_position.x - (hit_source as Node2D).global_position.x if hit_source is Node2D else 1.0)
	velocity.y = minf(velocity.y, knockback.y)
	_shake_camera(defeat_shake_amount if health <= 0 else hit_shake_amount)
	set_process(not Engine.is_editor_hint())
	if health <= 0:
		queue_free()
		return true
	queue_redraw()
	return true

func take_mechanism_crush(damage: int = 1, hit_source: Node = null, hit_direction: Vector2 = Vector2.ZERO, knockback: Vector2 = Vector2(280.0, -160.0)) -> bool:
	return take_environment_hit(damage, hit_source, hit_direction, knockback)

func set_spawn_facing_direction(direction: float) -> void:
	initial_patrol_direction = -1.0 if direction < 0.0 else 1.0
	_patrol_direction = initial_patrol_direction
	queue_redraw()

func get_save_scene_path() -> String:
	return "res://scenes/enemy.tscn"

func get_save_state() -> Dictionary:
	return {
		"config": _get_save_config(),
		"position": global_position,
		"velocity": velocity,
		"health": health,
		"current_state": current_state,
		"home_position": _home_position,
		"last_seen_position": _last_seen_position,
		"sight_memory_timer": _sight_memory_timer,
		"patrol_direction": _patrol_direction,
		"attack_cooldown_timer": _attack_cooldown_timer,
		"hit_flash_timer": _hit_flash_timer,
		"hit_squash_timer": _hit_squash_timer,
		"visible": visible,
	}

func apply_save_state(state: Dictionary) -> void:
	_apply_save_config(state.get("config", {}))
	global_position = state.get("position", global_position)
	velocity = state.get("velocity", Vector2.ZERO)
	health = int(state.get("health", max_health))
	current_state = int(state.get("current_state", EnemyState.PATROL))
	_home_position = state.get("home_position", global_position)
	_last_seen_position = state.get("last_seen_position", global_position)
	_sight_memory_timer = float(state.get("sight_memory_timer", 0.0))
	_patrol_direction = float(state.get("patrol_direction", initial_patrol_direction))
	_attack_cooldown_timer = float(state.get("attack_cooldown_timer", 0.0))
	_hit_flash_timer = float(state.get("hit_flash_timer", 0.0))
	_hit_squash_timer = float(state.get("hit_squash_timer", 0.0))
	visible = bool(state.get("visible", true))
	_update_collision_layers()
	_update_shapes()
	_resolve_target()
	queue_redraw()

func _get_save_config() -> Dictionary:
	return {
		"ai_enabled": ai_enabled,
		"target_path": target_path,
		"constrain_to_starting_room": constrain_to_starting_room,
		"active_only_in_current_room": active_only_in_current_room,
		"lock_chase_after_detection": lock_chase_after_detection,
		"patrol_enabled": patrol_enabled,
		"patrol_distance": patrol_distance,
		"vision_range": vision_range,
		"hearing_range": hearing_range,
		"awareness_range": awareness_range,
		"enforce_minimum_detection_ranges": enforce_minimum_detection_ranges,
		"minimum_vision_range": minimum_vision_range,
		"minimum_hearing_range": minimum_hearing_range,
		"minimum_awareness_range": minimum_awareness_range,
		"chase_memory_time": chase_memory_time,
		"stop_distance": stop_distance,
		"patrol_speed": patrol_speed,
		"chase_speed": chase_speed,
		"ground_acceleration": ground_acceleration,
		"ground_deceleration": ground_deceleration,
		"gravity_scale": gravity_scale,
		"max_fall_speed": max_fall_speed,
		"initial_patrol_direction": initial_patrol_direction,
		"avoid_ledges": avoid_ledges,
		"require_line_of_sight": require_line_of_sight,
		"floor_probe_forward": floor_probe_forward,
		"floor_probe_depth": floor_probe_depth,
		"can_step_over_small_obstacles": can_step_over_small_obstacles,
		"max_step_height": max_step_height,
		"step_scan_increment": step_scan_increment,
		"attack_damage": attack_damage,
		"attack_range": attack_range,
		"attack_cooldown": attack_cooldown,
		"queue_enabled": queue_enabled,
		"queue_spacing": queue_spacing,
		"queue_vertical_tolerance": queue_vertical_tolerance,
		"show_ai_ranges": show_ai_ranges,
		"show_runtime_ai_ranges": show_runtime_ai_ranges,
		"ai_visual_alpha": ai_visual_alpha,
		"max_health": max_health,
		"can_touch_ghost_blocks": can_touch_ghost_blocks,
		"body_size": body_size,
		"body_color": body_color,
		"edge_color": edge_color,
		"ghost_mark_color": ghost_mark_color,
		"hit_flash_time": hit_flash_time,
		"hit_flash_color": hit_flash_color,
		"hit_push_distance": hit_push_distance,
		"hit_spark_color": hit_spark_color,
		"hit_shake_amount": hit_shake_amount,
		"defeat_shake_amount": defeat_shake_amount,
	}

func _apply_save_config(config: Dictionary) -> void:
	if config.is_empty():
		return
	ai_enabled = bool(config.get("ai_enabled", ai_enabled))
	target_path = config.get("target_path", target_path)
	constrain_to_starting_room = bool(config.get("constrain_to_starting_room", constrain_to_starting_room))
	active_only_in_current_room = bool(config.get("active_only_in_current_room", active_only_in_current_room))
	lock_chase_after_detection = bool(config.get("lock_chase_after_detection", lock_chase_after_detection))
	patrol_enabled = bool(config.get("patrol_enabled", patrol_enabled))
	patrol_distance = float(config.get("patrol_distance", patrol_distance))
	vision_range = config.get("vision_range", vision_range)
	hearing_range = config.get("hearing_range", hearing_range)
	awareness_range = config.get("awareness_range", awareness_range)
	enforce_minimum_detection_ranges = bool(config.get("enforce_minimum_detection_ranges", enforce_minimum_detection_ranges))
	minimum_vision_range = config.get("minimum_vision_range", minimum_vision_range)
	minimum_hearing_range = config.get("minimum_hearing_range", minimum_hearing_range)
	minimum_awareness_range = config.get("minimum_awareness_range", minimum_awareness_range)
	_apply_minimum_detection_ranges()
	chase_memory_time = float(config.get("chase_memory_time", chase_memory_time))
	stop_distance = float(config.get("stop_distance", stop_distance))
	patrol_speed = float(config.get("patrol_speed", patrol_speed))
	chase_speed = float(config.get("chase_speed", chase_speed))
	ground_acceleration = float(config.get("ground_acceleration", ground_acceleration))
	ground_deceleration = float(config.get("ground_deceleration", ground_deceleration))
	gravity_scale = float(config.get("gravity_scale", gravity_scale))
	max_fall_speed = float(config.get("max_fall_speed", max_fall_speed))
	initial_patrol_direction = float(config.get("initial_patrol_direction", initial_patrol_direction))
	avoid_ledges = bool(config.get("avoid_ledges", avoid_ledges))
	require_line_of_sight = bool(config.get("require_line_of_sight", require_line_of_sight))
	floor_probe_forward = float(config.get("floor_probe_forward", floor_probe_forward))
	floor_probe_depth = float(config.get("floor_probe_depth", floor_probe_depth))
	can_step_over_small_obstacles = bool(config.get("can_step_over_small_obstacles", can_step_over_small_obstacles))
	max_step_height = float(config.get("max_step_height", max_step_height))
	step_scan_increment = float(config.get("step_scan_increment", step_scan_increment))
	attack_damage = int(config.get("attack_damage", attack_damage))
	attack_range = config.get("attack_range", attack_range)
	attack_cooldown = float(config.get("attack_cooldown", attack_cooldown))
	queue_enabled = bool(config.get("queue_enabled", queue_enabled))
	queue_spacing = float(config.get("queue_spacing", queue_spacing))
	queue_vertical_tolerance = float(config.get("queue_vertical_tolerance", queue_vertical_tolerance))
	show_ai_ranges = bool(config.get("show_ai_ranges", show_ai_ranges))
	show_runtime_ai_ranges = bool(config.get("show_runtime_ai_ranges", show_runtime_ai_ranges))
	ai_visual_alpha = float(config.get("ai_visual_alpha", ai_visual_alpha))
	max_health = int(config.get("max_health", max_health))
	can_touch_ghost_blocks = bool(config.get("can_touch_ghost_blocks", can_touch_ghost_blocks))
	body_size = config.get("body_size", body_size)
	body_color = config.get("body_color", body_color)
	edge_color = config.get("edge_color", edge_color)
	ghost_mark_color = config.get("ghost_mark_color", ghost_mark_color)
	hit_flash_time = float(config.get("hit_flash_time", hit_flash_time))
	hit_flash_color = config.get("hit_flash_color", hit_flash_color)
	hit_push_distance = float(config.get("hit_push_distance", hit_push_distance))
	hit_spark_color = config.get("hit_spark_color", hit_spark_color)
	hit_shake_amount = float(config.get("hit_shake_amount", hit_shake_amount))
	defeat_shake_amount = float(config.get("defeat_shake_amount", defeat_shake_amount))

func _apply_minimum_detection_ranges() -> void:
	if not enforce_minimum_detection_ranges:
		return
	vision_range = Vector2(maxf(vision_range.x, minimum_vision_range.x), maxf(vision_range.y, minimum_vision_range.y))
	hearing_range = Vector2(maxf(hearing_range.x, minimum_hearing_range.x), maxf(hearing_range.y, minimum_hearing_range.y))
	awareness_range = Vector2(maxf(awareness_range.x, minimum_awareness_range.x), maxf(awareness_range.y, minimum_awareness_range.y))

func _draw() -> void:
	_draw_ai_ranges()

	var draw_size := body_size
	var hit_amount := _hit_squash_timer / maxf(hit_flash_time, 0.001)
	if _hit_squash_timer > 0.0:
		draw_size = Vector2(body_size.x * (1.0 + 0.12 * hit_amount), body_size.y * (1.0 - 0.08 * hit_amount))

	var hit_offset := _hit_push_direction * hit_push_distance * hit_amount
	var rect := Rect2(-draw_size * 0.5 + hit_offset, draw_size)
	var fill_color := hit_flash_color if _hit_flash_timer > 0.0 else body_color
	draw_rect(rect, fill_color, true)
	draw_rect(rect, edge_color, false, 3.0)
	draw_circle(hit_offset + Vector2(-8.0, -7.0), 3.0, edge_color)
	draw_circle(hit_offset + Vector2(8.0, -7.0), 3.0, edge_color)
	draw_line(hit_offset + Vector2(-8.0, 9.0), hit_offset + Vector2(8.0, 9.0), edge_color, 3.0)
	_draw_health_pips(rect)
	if can_touch_ghost_blocks:
		_draw_ghost_mark(rect)

func _draw_health_pips(rect: Rect2) -> void:
	for index in max_health:
		var pip_position := Vector2(rect.position.x + 8.0 + index * 10.0, rect.position.y - 9.0)
		var color := Color(1.0, 0.85, 0.25, 1.0) if index < health else Color(0.2, 0.16, 0.12, 0.8)
		draw_circle(pip_position, 3.0, color)

func _draw_ghost_mark(rect: Rect2) -> void:
	var top := rect.position.y + 8.0
	draw_line(Vector2(rect.position.x + 6.0, top), Vector2(rect.end.x - 6.0, top + 18.0), ghost_mark_color, 2.0)
	draw_line(Vector2(rect.end.x - 6.0, top), Vector2(rect.position.x + 6.0, top + 18.0), ghost_mark_color, 2.0)

func _update_ai_state(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		_set_state(EnemyState.PATROL)
		return

	if _can_see_target():
		_last_seen_position = target.global_position
		_sight_memory_timer = chase_memory_time
		_set_state(EnemyState.CHASE)
		return

	if current_state == EnemyState.CHASE and lock_chase_after_detection:
		if _is_point_in_home_room(target.global_position):
			_last_seen_position = target.global_position
		return

	if current_state == EnemyState.CHASE:
		_sight_memory_timer = maxf(_sight_memory_timer - delta, 0.0)
		if _sight_memory_timer <= 0.0:
			_set_state(EnemyState.PATROL)

func _apply_horizontal_ai(delta: float) -> void:
	var desired_speed := 0.0
	if current_state == EnemyState.CHASE:
		desired_speed = _chase_desired_speed()
	else:
		desired_speed = _patrol_desired_speed()

	var rate := ground_acceleration if absf(desired_speed) > absf(velocity.x) else ground_deceleration
	if not is_zero_approx(desired_speed) and not is_zero_approx(velocity.x) and signf(desired_speed) != signf(velocity.x):
		rate = ground_acceleration + ground_deceleration
	desired_speed = _queue_adjusted_speed(desired_speed)
	velocity.x = move_toward(velocity.x, desired_speed, rate * delta)

func _patrol_desired_speed() -> float:
	if not patrol_enabled or patrol_distance <= 0.0:
		return 0.0

	var left_bound := _home_position.x - patrol_distance
	var right_bound := _home_position.x + patrol_distance
	if global_position.x <= left_bound:
		_patrol_direction = 1.0
	elif global_position.x >= right_bound:
		_patrol_direction = -1.0

	if _is_blocked_ahead(_patrol_direction):
		_patrol_direction *= -1.0
	if _would_leave_home_room(_patrol_direction):
		_patrol_direction *= -1.0

	return _patrol_direction * patrol_speed

func _chase_desired_speed() -> float:
	var delta_x := _last_seen_position.x - global_position.x
	if absf(delta_x) <= stop_distance:
		return 0.0

	var chase_direction := signf(delta_x)
	if _is_blocked_ahead(chase_direction):
		return 0.0
	if _would_leave_home_room(chase_direction):
		return 0.0

	_patrol_direction = chase_direction
	return chase_direction * chase_speed

func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y > 0.0:
		velocity.y = 0.0
		return

	var gravity := ProjectSettings.get_setting("physics/2d/default_gravity") as float
	velocity.y = minf(velocity.y + gravity * gravity_scale * delta, max_fall_speed)

func _can_see_target() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if constrain_to_starting_room and not _is_point_in_home_room(target.global_position):
		return false

	var to_target := target.global_position - global_position
	var facing := _facing_direction()
	var forward_distance := to_target.x * facing
	var vertical_distance := to_target.y
	var in_forward_vision := _is_inside_forward_vision(forward_distance, vertical_distance)
	var in_hearing := _is_inside_hearing(to_target)
	var in_awareness := _is_inside_awareness(to_target)

	if not in_forward_vision and not in_hearing and not in_awareness:
		return false

	if (in_forward_vision or in_awareness) and require_line_of_sight and _line_of_sight_blocked():
		return false

	return true

func _try_attack_target() -> void:
	if _attack_cooldown_timer > 0.0 or target == null or not is_instance_valid(target):
		return
	if not _is_target_in_attack_range():
		return
	if not target.has_method("take_enemy_hit"):
		return

	var did_hit := bool(target.call("take_enemy_hit", attack_damage, self))
	if did_hit:
		_attack_cooldown_timer = attack_cooldown
		velocity.x = 0.0

func _is_target_in_attack_range() -> bool:
	if target == null:
		return false
	var offset := target.global_position - global_position
	var normalized := Vector2(absf(offset.x) / maxf(attack_range.x, 0.001), absf(offset.y) / maxf(attack_range.y, 0.001))
	return normalized.length_squared() <= 1.0

func _queue_adjusted_speed(desired_speed: float) -> float:
	if not queue_enabled or is_zero_approx(desired_speed):
		return desired_speed

	var movement_direction := signf(desired_speed)
	for other in get_tree().get_nodes_in_group("enemies"):
		var other_enemy := other as CharacterBody2D
		if other_enemy == null or other_enemy == self or not is_instance_valid(other_enemy):
			continue
		if absf(other_enemy.global_position.y - global_position.y) > queue_vertical_tolerance:
			continue

		var ahead_distance := (other_enemy.global_position.x - global_position.x) * movement_direction
		if absf(ahead_distance) <= 2.0 and other_enemy.get_instance_id() < get_instance_id():
			ahead_distance = 1.0
		if ahead_distance > 0.0 and ahead_distance < queue_spacing:
			return 0.0

	return desired_speed

func _is_inside_forward_vision(forward_distance: float, vertical_distance: float) -> bool:
	if forward_distance < 0.0:
		return false

	var half_width := maxf(vision_range.x * 0.5, 0.001)
	var normalized := Vector2((forward_distance - half_width) / half_width, vertical_distance / maxf(vision_range.y, 0.001))
	return normalized.length_squared() <= 1.0

func _is_inside_hearing(target_offset: Vector2) -> bool:
	var normalized := Vector2(absf(target_offset.x) / maxf(hearing_range.x, 0.001), absf(target_offset.y) / maxf(hearing_range.y, 0.001))
	return normalized.length_squared() <= 1.0

func _is_inside_awareness(target_offset: Vector2) -> bool:
	var normalized := Vector2(absf(target_offset.x) / maxf(awareness_range.x, 0.001), absf(target_offset.y) / maxf(awareness_range.y, 0.001))
	return normalized.length_squared() <= 1.0

func _facing_direction() -> float:
	if current_state == EnemyState.CHASE:
		var to_last_seen := _last_seen_position.x - global_position.x
		if absf(to_last_seen) > stop_distance:
			return signf(to_last_seen)
	if not is_zero_approx(_patrol_direction):
		return signf(_patrol_direction)
	return 1.0

func _line_of_sight_blocked() -> bool:
	if target == null or not is_instance_valid(target):
		return true

	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position, _sight_block_mask())
	var excluded := [get_rid()]
	var target_collision := target as CollisionObject2D
	if target_collision != null:
		excluded.append(target_collision.get_rid())
	query.exclude = excluded
	query.collide_with_areas = false
	return not space_state.intersect_ray(query).is_empty()

func _sight_block_mask() -> int:
	var block_mask := TERRAIN_LAYER
	if can_touch_ghost_blocks:
		block_mask |= GHOST_BLOCK_LAYER
	return block_mask

func _is_blocked_ahead(move_direction: float) -> bool:
	if is_zero_approx(move_direction):
		return false
	if is_on_wall():
		if _try_step_up(move_direction):
			return false
		return true
	if avoid_ledges and is_on_floor() and not _has_floor_ahead(move_direction):
		return true
	return false

func _has_floor_ahead(move_direction: float) -> bool:
	var cast_start := global_position + Vector2(signf(move_direction) * (body_size.x * 0.5 + floor_probe_forward), -2.0)
	var cast_end := cast_start + Vector2(0.0, body_size.y * 0.5 + floor_probe_depth)
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(cast_start, cast_end, _navigation_block_mask())
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	return not space_state.intersect_ray(query).is_empty()

func _try_step_up(move_direction: float) -> bool:
	if not can_step_over_small_obstacles or max_step_height <= 0.0 or not is_on_floor():
		return false
	var direction := signf(move_direction)
	if is_zero_approx(direction):
		return false
	var step := maxf(step_scan_increment, 1.0)
	var forward_motion := Vector2(direction * maxf(floor_probe_forward, body_size.x * 0.35), 0.0)
	while step <= max_step_height:
		var stepped_transform := global_transform.translated(Vector2(0.0, -step))
		var blocked_after_step := test_move(stepped_transform, forward_motion)
		if not blocked_after_step and _has_floor_from_position(global_position + Vector2(direction * floor_probe_forward, -step)):
			global_position.y -= step
			return true
		step += maxf(step_scan_increment, 1.0)
	return false

func _has_floor_from_position(position: Vector2) -> bool:
	var cast_start := position + Vector2(0.0, -2.0)
	var cast_end := cast_start + Vector2(0.0, body_size.y * 0.5 + floor_probe_depth)
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(cast_start, cast_end, _navigation_block_mask())
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	return not space_state.intersect_ray(query).is_empty()

func _navigation_block_mask() -> int:
	return TERRAIN_LAYER | GHOST_BLOCK_LAYER

func _resolve_target() -> void:
	if not target_path.is_empty():
		target = get_node_or_null(target_path) as Node2D
		if target != null:
			return

	target = get_tree().get_first_node_in_group("players") as Node2D
	if target != null:
		return

	target = get_tree().root.find_child("Player", true, false) as Node2D

func _detect_home_room() -> void:
	_home_room = _room_containing_point(_home_position)
	if _home_room != null and _home_room.has_method("get_trigger_rect"):
		_home_room_rect = _home_room.call("get_trigger_rect") as Rect2
	elif _home_room != null and _home_room.has_method("get_camera_rect"):
		_home_room_rect = _home_room.call("get_camera_rect") as Rect2
	else:
		_home_room_rect = Rect2()

func _is_active_in_current_room() -> bool:
	if not active_only_in_current_room:
		return true
	if _home_room == null:
		return true
	var current_room := _current_camera_room()
	if current_room == null:
		return true
	return current_room == _home_room

func _current_camera_room() -> Node:
	for camera in get_tree().get_nodes_in_group("room_cameras"):
		if camera == null or not is_instance_valid(camera):
			continue
		var room_value: Variant = camera.get("active_room")
		var room := room_value as Node
		if room != null:
			return room
	return null

func _room_containing_point(point: Vector2) -> Node:
	var best_room: Node
	var best_area := INF
	for room in get_tree().get_nodes_in_group("camera_rooms"):
		if room == null or not room.has_method("contains_point") or not bool(room.call("contains_point", point)):
			continue
		var room_rect := Rect2()
		if room.has_method("get_trigger_rect"):
			room_rect = room.call("get_trigger_rect") as Rect2
		elif room.has_method("get_camera_rect"):
			room_rect = room.call("get_camera_rect") as Rect2
		else:
			continue
		var area := room_rect.size.x * room_rect.size.y
		if area < best_area:
			best_area = area
			best_room = room
	return best_room

func _is_point_in_home_room(point: Vector2) -> bool:
	if not constrain_to_starting_room or _home_room == null:
		return true
	if _home_room.has_method("contains_point"):
		return bool(_home_room.call("contains_point", point))
	return _home_room_rect.has_point(point) if _home_room_rect.size != Vector2.ZERO else true

func _would_leave_home_room(move_direction: float) -> bool:
	if not constrain_to_starting_room or _home_room_rect.size == Vector2.ZERO or is_zero_approx(move_direction):
		return false
	var half_width := body_size.x * 0.5
	var next_edge_x := global_position.x + signf(move_direction) * (half_width + floor_probe_forward)
	if move_direction < 0.0:
		return next_edge_x <= _home_room_rect.position.x
	return next_edge_x >= _home_room_rect.end.x

func _set_state(next_state: EnemyState) -> void:
	if current_state == next_state:
		return
	current_state = next_state
	queue_redraw()

func get_ai_state() -> String:
	return "chase" if current_state == EnemyState.CHASE else "patrol"

func _draw_ai_ranges() -> void:
	if not show_ai_ranges:
		return
	if not Engine.is_editor_hint() and not show_runtime_ai_ranges:
		return

	var state_color := _ai_state_color()
	var vision_fill := state_color
	vision_fill.a = ai_visual_alpha
	var vision_outline := state_color
	vision_outline.a = minf(ai_visual_alpha + 0.38, 1.0)
	var facing := _facing_direction()
	_draw_ellipse(Vector2(facing * vision_range.x * 0.5, 0.0), Vector2(vision_range.x * 0.5, vision_range.y), vision_fill, vision_outline, 2.0)

	var hearing_fill := Color(0.5, 0.86, 1.0, ai_visual_alpha * 0.55)
	var hearing_outline := Color(0.5, 0.86, 1.0, minf(ai_visual_alpha + 0.2, 0.75))
	_draw_ellipse(Vector2.ZERO, hearing_range, hearing_fill, hearing_outline, 1.5)

	var awareness_fill := Color(1.0, 0.72, 0.22, ai_visual_alpha * 0.22)
	var awareness_outline := Color(1.0, 0.72, 0.22, minf(ai_visual_alpha + 0.12, 0.64))
	_draw_ellipse(Vector2.ZERO, awareness_range, awareness_fill, awareness_outline, 1.25)

	var arrow_color := vision_outline
	draw_line(Vector2.ZERO, Vector2(facing * minf(42.0, vision_range.x * 0.22), 0.0), arrow_color, 2.0, true)

	if patrol_enabled and patrol_distance > 0.0:
		var patrol_origin := Vector2.ZERO if Engine.is_editor_hint() else to_local(_home_position)
		var patrol_y := body_size.y * 0.5 + 18.0
		var left_point := patrol_origin + Vector2(-patrol_distance, patrol_y)
		var right_point := patrol_origin + Vector2(patrol_distance, patrol_y)
		var patrol_color := Color(0.32, 0.78, 1.0, minf(ai_visual_alpha + 0.42, 1.0))
		draw_line(left_point, right_point, patrol_color, 2.0, true)
		draw_line(left_point + Vector2(0.0, -7.0), left_point + Vector2(0.0, 7.0), patrol_color, 2.0, true)
		draw_line(right_point + Vector2(0.0, -7.0), right_point + Vector2(0.0, 7.0), patrol_color, 2.0, true)

	var marker_color := state_color
	marker_color.a = 0.95
	draw_circle(Vector2(0.0, -body_size.y * 0.5 - 13.0), 5.0, marker_color)

	if current_state == EnemyState.CHASE:
		var target_local := to_local(_last_seen_position)
		draw_line(Vector2.ZERO, target_local, vision_outline, 2.0, true)

func _ai_state_color() -> Color:
	if current_state == EnemyState.CHASE:
		return Color(1.0, 0.26, 0.14, 1.0)
	return Color(0.22, 0.72, 1.0, 1.0)

func _draw_ellipse(center: Vector2, radius: Vector2, fill_color: Color, outline_color: Color, line_width: float) -> void:
	var points := PackedVector2Array()
	var segments := 48
	for index in segments:
		var angle := float(index) / float(segments) * TAU
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))

	if fill_color.a > 0.0:
		draw_colored_polygon(points, fill_color)

	points.append(points[0])
	draw_polyline(points, outline_color, line_width, true)

func _update_hit_push_direction(hit_source: Node) -> void:
	var source := hit_source as Node2D
	if source == null:
		_hit_push_direction = Vector2.ZERO
		return

	var away_from_source := global_position - source.global_position
	if away_from_source.length_squared() <= 0.001:
		_hit_push_direction = Vector2.RIGHT
		return

	_hit_push_direction = away_from_source.normalized()

func _spawn_hit_spark(hit_source: Node, is_finisher: bool) -> void:
	if Engine.is_editor_hint() or HIT_SPARK_SCENE == null:
		return

	var spark := HIT_SPARK_SCENE.instantiate() as Node2D
	if spark == null:
		return

	var world := get_parent()
	if world == null:
		return

	world.add_child(spark)
	var source := hit_source as Node2D
	var impact_direction := _hit_push_direction
	if source != null:
		spark.global_position = source.global_position.lerp(global_position, 0.35)
		var source_direction = source.get("direction") if source.has_method("get") else null
		if source_direction is Vector2 and (source_direction as Vector2).length_squared() > 0.001:
			impact_direction = (source_direction as Vector2).normalized()
	else:
		spark.global_position = global_position

	if impact_direction.length_squared() <= 0.001:
		impact_direction = Vector2.RIGHT

	if spark.has_method("setup"):
		spark.setup(impact_direction, hit_spark_color, is_finisher)

func _shake_camera(amount: float) -> void:
	if Engine.is_editor_hint():
		return

	for camera in get_tree().get_nodes_in_group("room_cameras"):
		if camera.has_method("add_hit_shake"):
			camera.add_hit_shake(amount)

func _update_collision_layers() -> void:
	collision_layer = ENEMY_LAYER
	collision_mask = TERRAIN_LAYER
	if can_touch_ghost_blocks:
		collision_mask |= GHOST_BLOCK_LAYER

func _update_shapes() -> void:
	var body_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	_set_rectangle_shape_size(body_shape, body_size)
	var hitbox_shape := get_node_or_null("Hitbox/CollisionShape2D") as CollisionShape2D
	_set_rectangle_shape_size(hitbox_shape, body_size + Vector2(8.0, 8.0))

func _set_rectangle_shape_size(collision_shape: CollisionShape2D, size: Vector2) -> void:
	if collision_shape == null:
		return
	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle == null:
		rectangle = RectangleShape2D.new()
		collision_shape.shape = rectangle
	rectangle.size = size

func _handle_mechanism_wall_collisions() -> void:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var collider := collision.get_collider()
		if collider == null or not collider.is_in_group("moving_mechanism_walls"):
			continue
		if collider.has_method("can_apply_mechanism_crush") and not bool(collider.call("can_apply_mechanism_crush")):
			continue
		if collider.has_method("is_moving") and not bool(collider.call("is_moving")):
			continue
		var damage := int(collider.call("get_mechanism_impact_damage")) if collider.has_method("get_mechanism_impact_damage") else 1
		var direction: Vector2 = collider.call("get_mechanism_impact_direction") if collider.has_method("get_mechanism_impact_direction") else collision.get_normal() * -1.0
		var knockback: Vector2 = collider.call("get_mechanism_impact_knockback") if collider.has_method("get_mechanism_impact_knockback") else Vector2(280.0, -160.0)
		take_mechanism_crush(damage, collider, direction, knockback)
		return
