extends CharacterBody2D

signal mask_state_changed(mask_state: int, state_name: String)
signal mask_health_changed(mask_state: int, health: int, max_health: int)
signal mask_unlocked(mask_state: int, state_name: String)
signal player_died(mask_state: int, checkpoint_position: Vector2)

const TERRAIN_LAYER := 1 << 0
const GHOST_BLOCK_LAYER := 1 << 3
const MASK_STATE_COUNT := 3

enum MaskState { NO_MASK, EUDA_MASK, GHOST_MASK }

@export_group("Movement")
@export var max_run_speed: float = 360.0
@export var ground_acceleration: float = 3000.0
@export var ground_deceleration: float = 3500.0
@export var air_acceleration: float = 1850.0
@export var air_deceleration: float = 980.0
@export var turn_acceleration: float = 4300.0

@export_group("Jump")
@export var jump_velocity: float = -710.0
@export var gravity_scale: float = 1.0
@export var fall_gravity_multiplier: float = 1.35
@export var low_jump_gravity_multiplier: float = 1.75
@export var jump_cut_multiplier: float = 0.62
@export var max_fall_speed: float = 900.0
@export var coyote_time: float = 0.1
@export var jump_buffer_time: float = 0.12

@export_group("Mask Boomerang")
@export var boomerang_scene: PackedScene
@export var boomerang_throw_offset := Vector2(34.0, -20.0)
@export var boomerang_cooldown: float = 0.18

@export_group("Mask State")
@export_enum("No Mask", "Euda Mask", "Ghost Mask") var starting_mask_state := 0
@export var mask_switch_duration := 0.42
@export var euda_mask_unlocked_at_start := false
@export var ghost_mask_unlocked_at_start := false

@export_group("Health")
@export_range(1, 12, 1) var max_health_per_mask := 3
@export var damage_invulnerability_time := 0.75
@export var respawn_invulnerability_time := 1.1
@export var hit_knockback := Vector2(220.0, -180.0)

@export_group("Respawn")
@export var spawn_position := Vector2(80.0, 420.0)
@export var reset_below_y: float = 980.0
@export var reset_above_enabled := false
@export var reset_above_y: float = -220.0

var facing_direction := 1.0
var active_boomerang: Node
var current_mask_state := MaskState.NO_MASK
var previous_mask_state := MaskState.NO_MASK
var current_animation_name := "no_mask_idle"
var mask_health := [3, 3, 3]
var unlocked_mask_states := [true, false, false]
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _throw_cooldown_timer := 0.0
var _mask_switch_timer := 0.0
var _damage_invulnerability_timer := 0.0
var _jump_was_down := false
var _throw_was_down := false
var _mask_cycle_was_down := false

func _ready() -> void:
	add_to_group("players")
	add_to_group("saveable")
	_reset_mask_health()
	_reset_unlocked_masks()
	current_mask_state = clampi(starting_mask_state, MaskState.NO_MASK, MaskState.GHOST_MASK)
	if not is_mask_state_unlocked(current_mask_state):
		current_mask_state = MaskState.NO_MASK
	previous_mask_state = current_mask_state
	_apply_mask_state_effects()
	_update_animation_name()

func _physics_process(delta: float) -> void:
	if global_position.y > reset_below_y or (reset_above_enabled and global_position.y < reset_above_y):
		_respawn()

	_update_timers(delta)
	_handle_mask_state_input()

	var horizontal_input := Input.get_axis("ui_left", "ui_right")

	if Input.is_key_pressed(KEY_A):
		horizontal_input -= 1.0
	if Input.is_key_pressed(KEY_D):
		horizontal_input += 1.0

	horizontal_input = clampf(horizontal_input, -1.0, 1.0)
	var on_floor := is_on_floor()

	if on_floor:
		_coyote_timer = coyote_time

	var jump_down := _jump_is_down()
	var jump_pressed := jump_down and not _jump_was_down
	var jump_released := not jump_down and _jump_was_down
	_jump_was_down = jump_down

	if jump_pressed:
		_jump_buffer_timer = jump_buffer_time

	_apply_horizontal_movement(horizontal_input, on_floor, delta)
	_apply_jump(jump_released)
	_apply_gravity(on_floor, jump_down, delta)
	_handle_boomerang_throw()
	_update_throw_point()
	_update_animation_name()

	move_and_slide()
	_handle_mechanism_wall_collisions()

func _update_timers(delta: float) -> void:
	_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_throw_cooldown_timer = maxf(_throw_cooldown_timer - delta, 0.0)
	_mask_switch_timer = maxf(_mask_switch_timer - delta, 0.0)
	_damage_invulnerability_timer = maxf(_damage_invulnerability_timer - delta, 0.0)

func _handle_mask_state_input() -> void:
	var requested_state := current_mask_state
	if Input.is_physical_key_pressed(KEY_1):
		requested_state = MaskState.NO_MASK
	elif Input.is_physical_key_pressed(KEY_2):
		requested_state = MaskState.EUDA_MASK
	elif Input.is_physical_key_pressed(KEY_3):
		requested_state = MaskState.GHOST_MASK

	var cycle_down := Input.is_physical_key_pressed(KEY_TAB)
	if cycle_down and not _mask_cycle_was_down:
		requested_state = _next_unlocked_mask_state()
	_mask_cycle_was_down = cycle_down

	if requested_state != current_mask_state:
		set_mask_state(requested_state)

func set_mask_state(next_state: int) -> void:
	next_state = clampi(next_state, MaskState.NO_MASK, MaskState.GHOST_MASK)
	if not is_mask_state_unlocked(next_state):
		return
	if next_state == current_mask_state:
		return

	previous_mask_state = current_mask_state
	current_mask_state = next_state
	_mask_switch_timer = mask_switch_duration
	if current_mask_state != MaskState.NO_MASK:
		_recall_active_boomerang()
	_apply_mask_state_effects()
	_update_animation_name()
	mask_state_changed.emit(current_mask_state, get_mask_state_name())

func get_mask_state_name(mask_state_value: int = -1) -> String:
	var state := current_mask_state if mask_state_value < 0 else mask_state_value
	match state:
		MaskState.EUDA_MASK:
			return "euda_mask"
		MaskState.GHOST_MASK:
			return "ghost_mask"
		_:
			return "no_mask"

func get_previous_mask_state_name() -> String:
	return get_mask_state_name(previous_mask_state)

func unlock_mask_state(mask_state_value: int) -> bool:
	var state := clampi(mask_state_value, MaskState.NO_MASK, MaskState.GHOST_MASK)
	if bool(unlocked_mask_states[state]):
		return false
	unlocked_mask_states[state] = true
	mask_unlocked.emit(state, get_mask_state_name(state))
	return true

func is_mask_state_unlocked(mask_state_value: int) -> bool:
	var state := clampi(mask_state_value, MaskState.NO_MASK, MaskState.GHOST_MASK)
	return bool(unlocked_mask_states[state])

func _reset_unlocked_masks() -> void:
	unlocked_mask_states = [true, euda_mask_unlocked_at_start, ghost_mask_unlocked_at_start]

func _next_unlocked_mask_state() -> int:
	for step in range(1, MASK_STATE_COUNT + 1):
		var next_state := (current_mask_state + step) % MASK_STATE_COUNT
		if is_mask_state_unlocked(next_state):
			return next_state
	return current_mask_state

func get_current_animation_name() -> String:
	return current_animation_name

func get_mask_switch_progress() -> float:
	if mask_switch_duration <= 0.0 or _mask_switch_timer <= 0.0:
		return 1.0
	return 1.0 - (_mask_switch_timer / mask_switch_duration)

func is_switching_mask() -> bool:
	return _mask_switch_timer > 0.0

func is_damage_invulnerable() -> bool:
	return _damage_invulnerability_timer > 0.0

func can_throw_mask_boomerang() -> bool:
	return current_mask_state == MaskState.NO_MASK

func can_see_ghost_blocks() -> bool:
	return current_mask_state == MaskState.EUDA_MASK

func can_stand_on_ghost_blocks() -> bool:
	return current_mask_state == MaskState.GHOST_MASK

func get_current_mask_health() -> int:
	return int(mask_health[current_mask_state])

func get_mask_health(mask_state_value: int) -> int:
	var state := clampi(mask_state_value, MaskState.NO_MASK, MaskState.GHOST_MASK)
	return int(mask_health[state])

func get_max_mask_health() -> int:
	return max_health_per_mask

func save_checkpoint(checkpoint_position: Vector2 = Vector2.INF) -> void:
	var save_manager := _save_manager()
	if save_manager != null and save_manager.has_method("request_save"):
		save_manager.request_save(global_position if checkpoint_position == Vector2.INF else checkpoint_position)

func get_checkpoint_position() -> Vector2:
	var save_manager := _save_manager()
	if save_manager != null and save_manager.has_method("has_checkpoint") and save_manager.has_checkpoint():
		return save_manager.get("current_checkpoint_position")
	return spawn_position

func get_save_state() -> Dictionary:
	return {
		"position": global_position,
		"velocity": velocity,
		"facing_direction": facing_direction,
		"current_mask_state": current_mask_state,
		"previous_mask_state": previous_mask_state,
		"mask_health": mask_health.duplicate(),
		"unlocked_mask_states": unlocked_mask_states.duplicate(),
	}

func apply_save_state(state: Dictionary) -> void:
	_recall_active_boomerang()
	global_position = state.get("position", spawn_position)
	velocity = state.get("velocity", Vector2.ZERO)
	facing_direction = float(state.get("facing_direction", 1.0))
	current_mask_state = clampi(int(state.get("current_mask_state", starting_mask_state)), MaskState.NO_MASK, MaskState.GHOST_MASK)
	previous_mask_state = clampi(int(state.get("previous_mask_state", current_mask_state)), MaskState.NO_MASK, MaskState.GHOST_MASK)

	var saved_health := state.get("mask_health", []) as Array
	if saved_health.size() == MASK_STATE_COUNT:
		mask_health = saved_health.duplicate()
	else:
		_reset_mask_health()

	var saved_unlocks := state.get("unlocked_mask_states", []) as Array
	if saved_unlocks.size() == MASK_STATE_COUNT:
		unlocked_mask_states = saved_unlocks.duplicate()
	else:
		_reset_unlocked_masks()
	unlocked_mask_states[MaskState.NO_MASK] = true
	if not is_mask_state_unlocked(current_mask_state):
		current_mask_state = MaskState.NO_MASK

	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_throw_cooldown_timer = 0.0
	_mask_switch_timer = 0.0
	_damage_invulnerability_timer = respawn_invulnerability_time
	_apply_mask_state_effects()
	_update_animation_name()
	for mask_state in range(MASK_STATE_COUNT):
		mask_health_changed.emit(mask_state, get_mask_health(mask_state), max_health_per_mask)

func take_enemy_hit(damage: int = 1, hit_source: Node = null) -> bool:
	if damage <= 0 or is_damage_invulnerable():
		return false

	var next_health := maxi(get_current_mask_health() - damage, 0)
	mask_health[current_mask_state] = next_health
	_damage_invulnerability_timer = damage_invulnerability_time
	_apply_damage_knockback(hit_source)
	mask_health_changed.emit(current_mask_state, next_health, max_health_per_mask)

	if next_health <= 0:
		_die_and_load_checkpoint()
	return true

func take_environment_hit(damage: int = 1, hit_source: Node = null, hit_direction: Vector2 = Vector2.ZERO, knockback: Vector2 = Vector2(220.0, -180.0)) -> bool:
	if damage <= 0 or is_damage_invulnerable():
		return false

	var next_health := maxi(get_current_mask_health() - damage, 0)
	mask_health[current_mask_state] = next_health
	_damage_invulnerability_timer = damage_invulnerability_time
	var horizontal_direction := signf(hit_direction.x)
	if is_zero_approx(horizontal_direction):
		horizontal_direction = -facing_direction
	velocity.x = absf(knockback.x) * horizontal_direction
	velocity.y = minf(velocity.y, knockback.y)
	mask_health_changed.emit(current_mask_state, next_health, max_health_per_mask)
	if next_health <= 0:
		_die_and_load_checkpoint()
	return true

func take_mechanism_crush(damage: int = 1, hit_source: Node = null, hit_direction: Vector2 = Vector2.ZERO, knockback: Vector2 = Vector2(280.0, -180.0)) -> bool:
	if damage <= 0:
		return false
	var next_health := maxi(get_current_mask_health() - damage, 0)
	mask_health[current_mask_state] = next_health
	_damage_invulnerability_timer = maxf(_damage_invulnerability_timer, damage_invulnerability_time)
	var horizontal_direction := signf(hit_direction.x)
	if is_zero_approx(horizontal_direction):
		var source := hit_source as Node2D
		horizontal_direction = signf(global_position.x - source.global_position.x) if source != null else -facing_direction
		if is_zero_approx(horizontal_direction):
			horizontal_direction = -facing_direction
	velocity.x = absf(knockback.x) * horizontal_direction
	velocity.y = minf(velocity.y, knockback.y)
	mask_health_changed.emit(current_mask_state, next_health, max_health_per_mask)
	if next_health <= 0:
		_die_and_load_checkpoint()
	return true

func _reset_mask_health() -> void:
	mask_health = []
	for _index in range(MASK_STATE_COUNT):
		mask_health.append(max_health_per_mask)

func _apply_damage_knockback(hit_source: Node) -> void:
	var knockback_direction := -facing_direction
	var source := hit_source as Node2D
	if source != null:
		knockback_direction = signf(global_position.x - source.global_position.x)
		if is_zero_approx(knockback_direction):
			knockback_direction = -facing_direction
	velocity.x = hit_knockback.x * knockback_direction
	velocity.y = minf(velocity.y, hit_knockback.y)

func _die_and_load_checkpoint() -> void:
	var defeated_mask_state := current_mask_state
	var checkpoint_position := get_checkpoint_position()
	player_died.emit(defeated_mask_state, checkpoint_position)
	var save_manager := _save_manager()
	if save_manager != null and save_manager.has_method("load_checkpoint") and save_manager.has_method("has_checkpoint") and save_manager.has_checkpoint():
		save_manager.load_checkpoint()
	else:
		apply_save_state({"position": spawn_position})

func _apply_mask_state_effects() -> void:
	collision_layer = TERRAIN_LAYER
	collision_mask = TERRAIN_LAYER
	if can_stand_on_ghost_blocks():
		collision_mask |= GHOST_BLOCK_LAYER
	_update_ghost_block_visibility()

func _update_ghost_block_visibility() -> void:
	for ghost_block in get_tree().get_nodes_in_group("ghost_blocks"):
		if ghost_block.has_method("set_revealed_by_euda_mask"):
			ghost_block.set_revealed_by_euda_mask(can_see_ghost_blocks())

func _update_animation_name() -> void:
	if is_switching_mask():
		current_animation_name = "mask_switch_cutscene"
		return

	var state_prefix := get_mask_state_name()
	var movement_suffix := "idle"
	if not is_on_floor():
		movement_suffix = "jump" if velocity.y < 0.0 else "fall"
	elif absf(velocity.x) > 12.0:
		movement_suffix = "run"
	current_animation_name = "%s_%s" % [state_prefix, movement_suffix]

func _apply_horizontal_movement(horizontal_input: float, on_floor: bool, delta: float) -> void:
	var target_speed := horizontal_input * max_run_speed
	var accel := ground_acceleration if on_floor else air_acceleration
	var decel := ground_deceleration if on_floor else air_deceleration

	if not is_zero_approx(horizontal_input):
		facing_direction = signf(horizontal_input)
		var is_turning := signf(velocity.x) != signf(horizontal_input) and absf(velocity.x) > 8.0
		var current_acceleration := turn_acceleration if is_turning else accel
		velocity.x = move_toward(velocity.x, target_speed, current_acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, decel * delta)

func _apply_jump(jump_released: bool) -> void:
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		return

	if jump_released and velocity.y < 0.0:
		velocity.y *= jump_cut_multiplier

func _apply_gravity(on_floor: bool, jump_down: bool, delta: float) -> void:
	if on_floor and velocity.y > 0.0:
		velocity.y = 0.0
		return

	var gravity := ProjectSettings.get_setting("physics/2d/default_gravity") as float
	var gravity_multiplier := 1.0
	if velocity.y > 0.0:
		gravity_multiplier = fall_gravity_multiplier
	elif velocity.y < 0.0 and not jump_down:
		gravity_multiplier = low_jump_gravity_multiplier

	velocity.y += gravity * gravity_scale * gravity_multiplier * delta
	velocity.y = minf(velocity.y, max_fall_speed)

func _handle_boomerang_throw() -> void:
	var throw_down := _throw_is_down()
	var throw_pressed := throw_down and not _throw_was_down
	_throw_was_down = throw_down

	if not can_throw_mask_boomerang():
		return

	if not throw_pressed or _throw_cooldown_timer > 0.0:
		return

	_throw_cooldown_timer = boomerang_cooldown

	if active_boomerang != null and is_instance_valid(active_boomerang):
		if active_boomerang.has_method("start_return"):
			active_boomerang.start_return()
		return

	_throw_boomerang()

func _throw_boomerang() -> void:
	if boomerang_scene == null:
		return

	var boomerang := boomerang_scene.instantiate() as Node2D
	if boomerang == null:
		return

	var world := get_parent()
	if world == null:
		return

	world.add_child(boomerang)
	boomerang.global_position = global_position + Vector2(boomerang_throw_offset.x * facing_direction, boomerang_throw_offset.y)
	if boomerang.has_method("setup"):
		boomerang.setup(self, facing_direction)
	if boomerang.has_signal("returned"):
		boomerang.returned.connect(_on_boomerang_returned)
	boomerang.tree_exited.connect(_on_boomerang_tree_exited.bind(boomerang))
	active_boomerang = boomerang

func _recall_active_boomerang() -> void:
	if active_boomerang != null and is_instance_valid(active_boomerang) and active_boomerang.has_method("start_return"):
		active_boomerang.start_return()

func _on_boomerang_returned(boomerang: Node) -> void:
	if boomerang == active_boomerang:
		active_boomerang = null

func _on_boomerang_tree_exited(boomerang: Node) -> void:
	if boomerang == active_boomerang:
		active_boomerang = null

func _update_throw_point() -> void:
	var throw_point := get_node_or_null("ThrowPoint") as Marker2D
	if throw_point != null:
		throw_point.position = Vector2(boomerang_throw_offset.x * facing_direction, boomerang_throw_offset.y)

func _jump_is_down() -> bool:
	return Input.is_action_pressed("ui_accept") or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_SPACE)

func _throw_is_down() -> bool:
	return Input.is_physical_key_pressed(KEY_J) or Input.is_physical_key_pressed(KEY_X)

func _respawn() -> void:
	_die_and_load_checkpoint()

func _save_manager() -> Node:
	return get_tree().get_first_node_in_group("save_managers")

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
		var knockback: Vector2 = collider.call("get_mechanism_impact_knockback") if collider.has_method("get_mechanism_impact_knockback") else hit_knockback
		take_mechanism_crush(damage, collider, direction, knockback)
		return
