extends CharacterBody2D

signal mask_state_changed(mask_state: int, state_name: String)
signal mask_health_changed(mask_state: int, health: int, max_health: int)
signal mask_unlocked(mask_state: int, state_name: String)
signal player_died(mask_state: int, checkpoint_position: Vector2)
signal key_count_changed(key_count: int)
signal player_damaged(damage: int, cause: String)

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
@export var can_step_over_small_obstacles := true
@export_range(0.0, 96.0, 1.0) var max_step_height := 28.0
@export_range(2.0, 24.0, 1.0) var step_scan_increment := 4.0
@export_range(4.0, 80.0, 1.0) var floor_probe_forward := 26.0
@export_range(8.0, 140.0, 1.0) var floor_probe_depth := 72.0

@export_group("Test Mode")
@export var test_mode_speed_multiplier := 3.0

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
@export var ghost_block_fall_memory_time := 3.0

@export_group("Inventory")
@export_range(0, 99, 1) var starting_keys := 0

@export_group("Lighting")
@export var emit_player_light := true
@export_range(0.0, 2.0, 0.02) var player_light_energy := 0.58
@export_range(0.2, 5.0, 0.05) var player_light_scale := 2.15
@export_group("Healing Flash")
@export var soul_heal_flash_color := Color(0.58, 0.86, 1.0, 1.0)
@export_range(0.04, 0.8, 0.01) var soul_heal_flash_duration := 0.18
@export_range(0.0, 3.0, 0.05) var soul_heal_light_boost := 1.05

@export_group("Visual Animation")
@export var visual_sprite_path := NodePath("Sprite2D")
@export var animation_player_path := NodePath("AnimationPlayer")
@export var left_eye_point_path := NodePath("EyeGlow/LeftEyePoint")
@export var right_eye_point_path := NodePath("EyeGlow/RightEyePoint")
@export var eye_glow_path := NodePath("EyeGlow")
@export var artwork_faces_left := true
@export var idle_visual_position_offset := Vector2.ZERO
@export var run_visual_position_offset := Vector2(0.0, -11.5)
@export var no_mask_eye_color := Color(1.0, 0.46, 0.08, 1.0)
@export var euda_mask_eye_color := Color(0.36, 1.0, 0.42, 1.0)
@export var ghost_mask_eye_color := Color(0.3, 0.66, 1.0, 1.0)
@export var run_animation_name: StringName = &"Euda-run"
@export var idle_texture: Texture2D = preload("res://ArtWorks/Euda/Euda-2.png")
@export var run_reference_texture: Texture2D = preload("res://ArtWorks/Euda/Euda-run/Euda-run-1.png")

var facing_direction := 1.0
var active_boomerang: Node
var current_mask_state := MaskState.NO_MASK
var previous_mask_state := MaskState.NO_MASK
var current_animation_name := "no_mask_idle"
var mask_health := [3, 3, 3]
var unlocked_mask_states := [true, false, false]
var key_count := 0
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _throw_cooldown_timer := 0.0
var _mask_switch_timer := 0.0
var _damage_invulnerability_timer := 0.0
var _ground_speed_multiplier := 1.0
var _ground_speed_multiplier_timer := 0.0
var _last_damage_cause := "unknown"
var _fall_respawn_pending := false
var _ghost_block_context_timer := 0.0
var _jump_was_down := false
var _throw_was_down := false
var _mask_cycle_was_down := false
var _test_mode_enabled := false
var _test_mode_was_down := false
var _test_mode_collision_shape_states := {}
var _player_light: PointLight2D
var _player_light_texture: Texture2D
var _visual_sprite: Sprite2D
var _movement_animation_player: AnimationPlayer
var _idle_texture: Texture2D
var _base_visual_scale := Vector2.ONE
var _base_visual_position := Vector2.ZERO
var _base_visual_modulate := Color(1.0, 1.0, 1.0, 1.0)
var _left_eye_point: Marker2D
var _right_eye_point: Marker2D
var _eye_glow: Node
var _idle_left_eye_position := Vector2.ZERO
var _idle_right_eye_position := Vector2.ZERO
var _current_visual_movement_suffix := "idle"
var _soul_heal_flash_timer := 0.0
var _active_soul_heal_flash_color := Color(0.58, 0.86, 1.0, 1.0)

func _ready() -> void:
	add_to_group("players")
	add_to_group("saveable")
	_ensure_player_light()
	_setup_visual_animation()
	_reset_mask_health()
	_reset_unlocked_masks()
	key_count = starting_keys
	current_mask_state = clampi(starting_mask_state, MaskState.NO_MASK, MaskState.GHOST_MASK)
	if not is_mask_state_unlocked(current_mask_state):
		current_mask_state = MaskState.NO_MASK
	previous_mask_state = current_mask_state
	_apply_mask_state_effects()
	_update_animation_name()
	_update_eye_glow_state()

func _physics_process(delta: float) -> void:
	_handle_test_mode_toggle()
	if _test_mode_enabled:
		_update_timers(delta)
		_update_soul_heal_flash_visual()
		_handle_test_mode_movement(delta)
		_update_throw_point()
		_update_animation_name()
		return

	_update_ghost_block_context(delta)
	if global_position.y > reset_below_y or (reset_above_enabled and global_position.y < reset_above_y):
		_handle_fall_respawn()
		return

	_update_timers(delta)
	_update_soul_heal_flash_visual()
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
	_try_step_up(horizontal_input, on_floor)
	_handle_boomerang_throw()
	_update_throw_point()
	_update_animation_name()

	move_and_slide()
	_handle_pushable_collisions(delta, horizontal_input)
	_handle_mechanism_wall_collisions()

func _update_timers(delta: float) -> void:
	_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_throw_cooldown_timer = maxf(_throw_cooldown_timer - delta, 0.0)
	_mask_switch_timer = maxf(_mask_switch_timer - delta, 0.0)
	_damage_invulnerability_timer = maxf(_damage_invulnerability_timer - delta, 0.0)
	_ground_speed_multiplier_timer = maxf(_ground_speed_multiplier_timer - delta, 0.0)
	_ghost_block_context_timer = maxf(_ghost_block_context_timer - delta, 0.0)
	_soul_heal_flash_timer = maxf(_soul_heal_flash_timer - delta, 0.0)
	if _ground_speed_multiplier_timer <= 0.0:
		_ground_speed_multiplier = 1.0

func play_soul_heal_flash(flash_color: Color = Color(0.58, 0.86, 1.0, 1.0)) -> void:
	_active_soul_heal_flash_color = flash_color
	_soul_heal_flash_timer = maxf(soul_heal_flash_duration, 0.01)
	_update_soul_heal_flash_visual()

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
	_update_eye_glow_state()
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
	return _test_mode_enabled or _damage_invulnerability_timer > 0.0

func grant_invulnerability(duration: float = 1.0) -> void:
	_damage_invulnerability_timer = maxf(_damage_invulnerability_timer, maxf(duration, 0.0))

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

func restore_mask_health(mask_state_value: int) -> bool:
	var state := clampi(mask_state_value, MaskState.NO_MASK, MaskState.GHOST_MASK)
	if state != MaskState.NO_MASK and not is_mask_state_unlocked(state):
		return false
	if int(mask_health[state]) >= max_health_per_mask:
		return false
	mask_health[state] = max_health_per_mask
	if state == current_mask_state:
		_update_eye_glow_state()
	mask_health_changed.emit(state, get_mask_health(state), max_health_per_mask)
	return true

func restore_soul_lamp_energy(mask_state_value: int) -> bool:
	var did_restore := restore_mask_health(MaskState.NO_MASK)
	var state := clampi(mask_state_value, MaskState.NO_MASK, MaskState.GHOST_MASK)
	if state != MaskState.NO_MASK:
		did_restore = restore_mask_health(state) or did_restore
	return did_restore

func get_soul_lamp_missing_energy_states(mask_state_value: int) -> Array[int]:
	var states: Array[int] = []
	_append_missing_energy_states(states, MaskState.NO_MASK)
	var state := clampi(mask_state_value, MaskState.NO_MASK, MaskState.GHOST_MASK)
	if state != MaskState.NO_MASK:
		_append_missing_energy_states(states, state)
	return states

func restore_mask_health_step(mask_state_value: int) -> bool:
	var state := clampi(mask_state_value, MaskState.NO_MASK, MaskState.GHOST_MASK)
	if state != MaskState.NO_MASK and not is_mask_state_unlocked(state):
		return false
	if int(mask_health[state]) >= max_health_per_mask:
		return false
	mask_health[state] = mini(int(mask_health[state]) + 1, max_health_per_mask)
	if state == current_mask_state:
		_update_eye_glow_state()
	mask_health_changed.emit(state, get_mask_health(state), max_health_per_mask)
	return true

func _append_missing_energy_states(states: Array[int], mask_state_value: int) -> void:
	var state := clampi(mask_state_value, MaskState.NO_MASK, MaskState.GHOST_MASK)
	if state != MaskState.NO_MASK and not is_mask_state_unlocked(state):
		return
	var missing := maxi(max_health_per_mask - int(mask_health[state]), 0)
	for _index in range(missing):
		states.append(state)

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
		"key_count": key_count,
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
	key_count = maxi(int(state.get("key_count", starting_keys)), 0)

	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_throw_cooldown_timer = 0.0
	_mask_switch_timer = 0.0
	_damage_invulnerability_timer = respawn_invulnerability_time
	_apply_mask_state_effects()
	_update_animation_name()
	_update_eye_glow_state()
	for mask_state in range(MASK_STATE_COUNT):
		mask_health_changed.emit(mask_state, get_mask_health(mask_state), max_health_per_mask)
	key_count_changed.emit(key_count)

func take_enemy_hit(damage: int = 1, hit_source: Node = null) -> bool:
	if _test_mode_enabled:
		return false
	if damage <= 0 or is_damage_invulnerable():
		return false

	var next_health := maxi(get_current_mask_health() - damage, 0)
	mask_health[current_mask_state] = next_health
	_update_eye_glow_state()
	_last_damage_cause = "enemy"
	_damage_invulnerability_timer = damage_invulnerability_time
	_apply_damage_knockback(hit_source)
	mask_health_changed.emit(current_mask_state, next_health, max_health_per_mask)
	if next_health > 0:
		_notify_damage_taken(damage, hit_source, _last_damage_cause)

	if next_health <= 0:
		_die_and_load_checkpoint()
	return true

func take_environment_hit(damage: int = 1, hit_source: Node = null, hit_direction: Vector2 = Vector2.ZERO, knockback: Vector2 = Vector2(220.0, -180.0)) -> bool:
	if _test_mode_enabled:
		return false
	if damage <= 0 or is_damage_invulnerable():
		return false

	var next_health := maxi(get_current_mask_health() - damage, 0)
	mask_health[current_mask_state] = next_health
	_update_eye_glow_state()
	_last_damage_cause = _damage_cause_from_source(hit_source)
	_damage_invulnerability_timer = damage_invulnerability_time
	var horizontal_direction := -signf(hit_direction.x) if absf(hit_direction.x) > absf(hit_direction.y) else signf(hit_direction.x)
	if is_zero_approx(horizontal_direction):
		horizontal_direction = -facing_direction
	velocity.x = absf(knockback.x) * horizontal_direction
	velocity.y = minf(velocity.y, knockback.y)
	mask_health_changed.emit(current_mask_state, next_health, max_health_per_mask)
	if next_health > 0:
		_notify_damage_taken(damage, hit_source, _last_damage_cause)
	if next_health <= 0:
		_die_and_load_checkpoint()
	return true

func apply_ground_speed_multiplier(multiplier: float, duration: float = 0.08) -> void:
	_ground_speed_multiplier = minf(_ground_speed_multiplier, clampf(multiplier, 0.05, 1.0))
	_ground_speed_multiplier_timer = maxf(_ground_speed_multiplier_timer, duration)

func get_ground_speed_multiplier() -> float:
	return _ground_speed_multiplier

func add_keys(amount: int = 1) -> int:
	if amount <= 0:
		return key_count
	key_count += amount
	key_count_changed.emit(key_count)
	return key_count

func can_spend_keys(amount: int = 1) -> bool:
	return amount <= 0 or key_count >= amount

func spend_keys(amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if key_count < amount:
		return false
	key_count -= amount
	key_count_changed.emit(key_count)
	return true

func get_key_count() -> int:
	return key_count

func take_mechanism_crush(damage: int = 1, hit_source: Node = null, hit_direction: Vector2 = Vector2.ZERO, knockback: Vector2 = Vector2(280.0, -180.0)) -> bool:
	if _test_mode_enabled:
		return false
	if damage <= 0:
		return false

	var is_falling_wall_crush := hit_direction.y > 0.25
	var should_escape_mechanism := hit_source != null and hit_source.has_method("get_mechanism_escape_position") and hit_direction.length_squared() > 0.01
	if should_escape_mechanism:
		var escape_position: Vector2 = hit_source.call("get_mechanism_escape_position", self)
		global_position = escape_position

	if is_damage_invulnerable():
		return false

	var next_health := maxi(get_current_mask_health() - damage, 0)
	mask_health[current_mask_state] = next_health
	_update_eye_glow_state()
	_last_damage_cause = "mechanism"
	_damage_invulnerability_timer = maxf(_damage_invulnerability_timer, damage_invulnerability_time)
	var horizontal_direction := -signf(hit_direction.x) if absf(hit_direction.x) > absf(hit_direction.y) else signf(hit_direction.x)
	if is_zero_approx(horizontal_direction):
		var source := hit_source as Node2D
		horizontal_direction = signf(global_position.x - source.global_position.x) if source != null else -facing_direction
		if is_zero_approx(horizontal_direction):
			horizontal_direction = -facing_direction
	velocity.x = absf(knockback.x) * horizontal_direction
	if is_falling_wall_crush:
		velocity.y = maxf(velocity.y, 0.0)
	else:
		velocity.y = minf(velocity.y, knockback.y)
	mask_health_changed.emit(current_mask_state, next_health, max_health_per_mask)
	if next_health > 0:
		_notify_damage_taken(damage, hit_source, _last_damage_cause)
	if next_health <= 0:
		_die_and_load_checkpoint()
	return true

func _reset_mask_health() -> void:
	mask_health = []
	for _index in range(MASK_STATE_COUNT):
		mask_health.append(max_health_per_mask)
	_update_eye_glow_state()

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
	var story_controller := get_tree().get_first_node_in_group("story_controllers")
	if story_controller != null and story_controller.has_method("handle_player_death"):
		if bool(story_controller.call("handle_player_death", self, defeated_mask_state, checkpoint_position, _last_damage_cause)):
			return
	var respawn_controller := get_tree().get_first_node_in_group("death_respawn_controllers")
	if respawn_controller != null and respawn_controller.has_method("request_player_respawn"):
		if bool(respawn_controller.call("request_player_respawn", self, checkpoint_position)):
			return
	var save_manager := _save_manager()
	if save_manager != null and save_manager.has_method("load_checkpoint") and save_manager.has_method("has_checkpoint") and save_manager.has_checkpoint():
		save_manager.load_checkpoint()
	else:
		apply_save_state({"position": spawn_position})

func _apply_mask_state_effects() -> void:
	if _test_mode_enabled:
		_disable_test_mode_collisions()
		_update_ghost_block_visibility()
		_update_player_light()
		_update_eye_glow_state()
		return
	collision_layer = TERRAIN_LAYER
	collision_mask = TERRAIN_LAYER
	if can_stand_on_ghost_blocks():
		collision_mask |= GHOST_BLOCK_LAYER
	_update_ghost_block_visibility()
	_update_player_light()
	_update_eye_glow_state()

func _ensure_player_light() -> void:
	_player_light = get_node_or_null("PlayerLight") as PointLight2D
	if _player_light == null:
		_player_light = PointLight2D.new()
		_player_light.name = "PlayerLight"
		add_child(_player_light)
	_player_light.position = Vector2(0.0, -20.0)
	_player_light.z_index = 1
	_player_light.z_as_relative = false
	_player_light.range_z_min = -100
	_player_light.range_z_max = 1
	if _player_light_texture == null:
		_player_light_texture = _make_radial_light_texture(192, 1.65)
	_player_light.texture = _player_light_texture
	_update_player_light()

func _update_player_light() -> void:
	if _player_light == null:
		return
	var flash_progress := _soul_heal_flash_progress()
	_player_light.enabled = emit_player_light
	_player_light.energy = player_light_energy + soul_heal_light_boost * flash_progress
	_player_light.texture_scale = player_light_scale
	_player_light.color = _player_light_color().lerp(_active_soul_heal_flash_color, flash_progress)

func _update_soul_heal_flash_visual() -> void:
	var flash_progress := _soul_heal_flash_progress()
	if _visual_sprite != null:
		var visual_pulse := sin(flash_progress * PI)
		_visual_sprite.modulate = _base_visual_modulate.lerp(_active_soul_heal_flash_color, visual_pulse * 0.62)
	_update_player_light()

func _soul_heal_flash_progress() -> float:
	if soul_heal_flash_duration <= 0.0:
		return 0.0
	return clampf(_soul_heal_flash_timer / soul_heal_flash_duration, 0.0, 1.0)

func _player_light_color() -> Color:
	match current_mask_state:
		MaskState.EUDA_MASK:
			return Color(1.0, 0.86, 0.28, 1.0)
		MaskState.GHOST_MASK:
			return Color(0.42, 1.0, 0.58, 1.0)
		_:
			return Color(1.0, 1.0, 1.0, 1.0)

func _make_radial_light_texture(size: int, falloff: float) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var radius := float(size) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(x, y).distance_to(center) / radius
			var alpha := pow(clampf(1.0 - distance, 0.0, 1.0), falloff)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)

func _update_ghost_block_visibility() -> void:
	for ghost_block in get_tree().get_nodes_in_group("ghost_blocks"):
		if ghost_block.has_method("set_revealed_by_euda_mask"):
			ghost_block.set_revealed_by_euda_mask(can_see_ghost_blocks())

func _update_animation_name() -> void:
	if is_switching_mask():
		current_animation_name = "mask_switch_cutscene"
		_update_visual_animation("idle")
		return

	var state_prefix := get_mask_state_name()
	var movement_suffix := "idle"
	if not is_on_floor():
		movement_suffix = "jump" if velocity.y < 0.0 else "fall"
	elif absf(velocity.x) > 12.0:
		movement_suffix = "run"
	current_animation_name = "%s_%s" % [state_prefix, movement_suffix]
	_update_visual_animation(movement_suffix)

func _setup_visual_animation() -> void:
	_visual_sprite = get_node_or_null(visual_sprite_path) as Sprite2D
	_movement_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	_left_eye_point = get_node_or_null(left_eye_point_path) as Marker2D
	_right_eye_point = get_node_or_null(right_eye_point_path) as Marker2D
	_eye_glow = get_node_or_null(eye_glow_path)
	_idle_texture = idle_texture
	if _idle_texture == null and _visual_sprite != null:
		_idle_texture = _visual_sprite.texture
	if _visual_sprite != null:
		_base_visual_scale = _visual_sprite.scale
		_base_visual_position = _visual_sprite.position
		_base_visual_modulate = _visual_sprite.modulate
	if _left_eye_point != null:
		_idle_left_eye_position = _left_eye_point.position
	if _right_eye_point != null:
		_idle_right_eye_position = _right_eye_point.position
	_update_visual_animation("idle")
	_apply_visual_facing()

func _update_visual_animation(movement_suffix: String) -> void:
	_current_visual_movement_suffix = movement_suffix
	if movement_suffix == "run" and _can_play_run_animation():
		_apply_visual_scale(_run_visual_scale_multiplier())
		_apply_visual_position(run_visual_position_offset)
		_apply_visual_facing()
		if _movement_animation_player.current_animation != run_animation_name or not _movement_animation_player.is_playing():
			_movement_animation_player.play(run_animation_name)
		return

	if _movement_animation_player != null and _movement_animation_player.current_animation == run_animation_name:
		_movement_animation_player.stop(true)
	_apply_visual_scale(1.0)
	_apply_visual_position(idle_visual_position_offset)
	_restore_idle_eye_positions()
	_apply_visual_facing()
	if _visual_sprite != null and _idle_texture != null:
		_visual_sprite.texture = _idle_texture

func _can_play_run_animation() -> bool:
	return _movement_animation_player != null and _movement_animation_player.has_animation(run_animation_name)

func _run_visual_scale_multiplier() -> float:
	if _idle_texture == null or run_reference_texture == null:
		return 1.0
	var run_height := run_reference_texture.get_height()
	if run_height <= 0:
		return 1.0
	return float(_idle_texture.get_height()) / float(run_height)

func _apply_visual_scale(multiplier: float) -> void:
	if _visual_sprite == null:
		return
	_visual_sprite.scale = _base_visual_scale * multiplier

func _apply_visual_position(offset: Vector2) -> void:
	if _visual_sprite == null:
		return
	_visual_sprite.position = _base_visual_position + offset

func _apply_visual_facing() -> void:
	var should_mirror := _should_mirror_visuals()
	if _visual_sprite != null:
		_visual_sprite.flip_h = should_mirror
	if _eye_glow != null:
		_eye_glow.set("mirror_horizontally", should_mirror)
		if _visual_sprite != null:
			_eye_glow.set("mirror_axis_x", _visual_sprite.position.x)
		_update_eye_glow_state()

func _should_mirror_visuals() -> bool:
	return facing_direction > 0.0 if artwork_faces_left else facing_direction < 0.0

func _update_eye_glow_state() -> void:
	if _eye_glow == null:
		return
	var health := get_current_mask_health()
	var missing_health := maxi(max_health_per_mask - health, 0)
	var left_eye_has_light := health > 0 and missing_health < 1
	var right_eye_has_light := health > 0 and missing_health < 2
	if _current_visual_movement_suffix == "run":
		var visible_left_eye := facing_direction > 0.0
		var visible_right_eye := facing_direction < 0.0
		left_eye_has_light = left_eye_has_light and visible_left_eye
		right_eye_has_light = right_eye_has_light and visible_right_eye
	_eye_glow.set("glow_color", _eye_glow_color())
	_eye_glow.set("left_eye_enabled", left_eye_has_light)
	_eye_glow.set("right_eye_enabled", right_eye_has_light)

func _eye_glow_color() -> Color:
	match current_mask_state:
		MaskState.EUDA_MASK:
			return euda_mask_eye_color
		MaskState.GHOST_MASK:
			return ghost_mask_eye_color
		_:
			return no_mask_eye_color

func _restore_idle_eye_positions() -> void:
	if _left_eye_point != null:
		_left_eye_point.position = _idle_left_eye_position
	if _right_eye_point != null:
		_right_eye_point.position = _idle_right_eye_position

func _apply_horizontal_movement(horizontal_input: float, on_floor: bool, delta: float) -> void:
	var speed_multiplier := _ground_speed_multiplier if on_floor else 1.0
	var target_speed := horizontal_input * max_run_speed * speed_multiplier
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

func _try_step_up(horizontal_input: float, on_floor: bool) -> bool:
	if not can_step_over_small_obstacles or max_step_height <= 0.0 or not on_floor:
		return false
	if not is_on_wall():
		return false
	var direction := signf(horizontal_input)
	if is_zero_approx(direction):
		return false

	var body_size := _player_body_size()
	var step := maxf(step_scan_increment, 1.0)
	var forward_motion := Vector2(direction * maxf(floor_probe_forward, body_size.x * 0.35), 0.0)
	while step <= max_step_height:
		var stepped_transform := global_transform.translated(Vector2(0.0, -step))
		var blocked_after_step := test_move(stepped_transform, forward_motion)
		if not blocked_after_step and _has_floor_from_position(global_position + Vector2(direction * floor_probe_forward, -step), body_size):
			global_position.y -= step
			return true
		step += maxf(step_scan_increment, 1.0)
	return false

func _has_floor_from_position(position: Vector2, body_size: Vector2) -> bool:
	var cast_start := position + Vector2(0.0, -2.0)
	var cast_end := cast_start + Vector2(0.0, body_size.y * 0.5 + floor_probe_depth)
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(cast_start, cast_end, _navigation_block_mask())
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	return not space_state.intersect_ray(query).is_empty()

func _navigation_block_mask() -> int:
	var block_mask := collision_mask & (TERRAIN_LAYER | GHOST_BLOCK_LAYER)
	return block_mask if block_mask != 0 else TERRAIN_LAYER

func _player_body_size() -> Vector2:
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape == null or collision_shape.shape == null:
		return Vector2(36.0, 36.0)
	var shape := collision_shape.shape
	var scale := Vector2(absf(collision_shape.global_scale.x), absf(collision_shape.global_scale.y))
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size * scale
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		return Vector2(capsule.radius * 2.0, capsule.height) * scale
	if shape is CircleShape2D:
		var radius := (shape as CircleShape2D).radius
		return Vector2(radius * 2.0, radius * 2.0) * scale
	return Vector2(36.0, 36.0) * scale

func _handle_boomerang_throw() -> void:
	var throw_down := _throw_is_down()
	var throw_pressed := throw_down and not _throw_was_down
	_throw_was_down = throw_down

	if not can_throw_mask_boomerang():
		return

	if not throw_pressed or _throw_cooldown_timer > 0.0:
		return

	if active_boomerang != null and is_instance_valid(active_boomerang):
		return

	_throw_cooldown_timer = boomerang_cooldown
	_throw_boomerang()

func _handle_test_mode_toggle() -> void:
	var test_mode_down := Input.is_physical_key_pressed(KEY_U)
	if test_mode_down and not _test_mode_was_down:
		_set_test_mode_enabled(not _test_mode_enabled)
	_test_mode_was_down = test_mode_down

func _set_test_mode_enabled(enabled: bool) -> void:
	if _test_mode_enabled == enabled:
		return
	_test_mode_enabled = enabled
	velocity = Vector2.ZERO
	_fall_respawn_pending = false
	_damage_invulnerability_timer = 0.0
	if _test_mode_enabled:
		_disable_test_mode_collisions()
	else:
		_restore_test_mode_collisions()
		_apply_mask_state_effects()
	_notify_room_cameras_test_mode(_test_mode_enabled)

func _handle_test_mode_movement(delta: float) -> void:
	var input_vector := Vector2.ZERO
	input_vector.x = Input.get_axis("ui_left", "ui_right")
	if Input.is_physical_key_pressed(KEY_A):
		input_vector.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input_vector.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_SPACE):
		input_vector.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input_vector.y += 1.0
	input_vector = input_vector.normalized() if input_vector.length_squared() > 1.0 else input_vector
	var test_speed := max_run_speed * maxf(test_mode_speed_multiplier, 0.1)
	velocity = input_vector * test_speed
	global_position += velocity * delta
	if not is_zero_approx(input_vector.x):
		facing_direction = signf(input_vector.x)

func _disable_test_mode_collisions() -> void:
	collision_layer = 0
	collision_mask = 0
	for collision_shape in _player_collision_shapes():
		var shape_path := str(collision_shape.get_path())
		if not _test_mode_collision_shape_states.has(shape_path):
			_test_mode_collision_shape_states[shape_path] = collision_shape.disabled
		collision_shape.disabled = true

func _restore_test_mode_collisions() -> void:
	for collision_shape in _player_collision_shapes():
		var shape_path := str(collision_shape.get_path())
		collision_shape.disabled = bool(_test_mode_collision_shape_states.get(shape_path, false))
	_test_mode_collision_shape_states.clear()

func _player_collision_shapes(root_node: Node = self) -> Array[CollisionShape2D]:
	var shapes: Array[CollisionShape2D] = []
	for child in root_node.get_children():
		var collision_shape := child as CollisionShape2D
		if collision_shape != null:
			shapes.append(collision_shape)
		shapes.append_array(_player_collision_shapes(child))
	return shapes

func _notify_room_cameras_test_mode(enabled: bool) -> void:
	for camera in get_tree().get_nodes_in_group("room_cameras"):
		if camera != null and camera.has_method("set_test_mode_free_camera"):
			camera.call("set_test_mode_free_camera", enabled)

func start_with_right_shot() -> bool:
	facing_direction = 1.0
	_update_throw_point()
	if not can_throw_mask_boomerang():
		return false
	if active_boomerang != null and is_instance_valid(active_boomerang):
		return false
	_throw_cooldown_timer = boomerang_cooldown
	_throw_boomerang()
	return active_boomerang != null and is_instance_valid(active_boomerang)

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
	_last_damage_cause = "ghost_block" if _is_ghost_related_fall() else "fall"
	_die_and_load_checkpoint()

func _handle_fall_respawn() -> void:
	if _fall_respawn_pending:
		return
	_fall_respawn_pending = true
	_last_damage_cause = "ghost_block" if _is_ghost_related_fall() else "fall"
	var story_controller := get_tree().get_first_node_in_group("story_controllers")
	if story_controller != null and story_controller.has_method("handle_player_fall_death"):
		if bool(story_controller.call("handle_player_fall_death", self, Callable(self, "_finish_pending_fall_respawn"), _last_damage_cause)):
			return
	_finish_pending_fall_respawn()

func _finish_pending_fall_respawn() -> void:
	_fall_respawn_pending = false
	_die_and_load_checkpoint()

func _save_manager() -> Node:
	return get_tree().get_first_node_in_group("save_managers")

func enter_death_space_state() -> void:
	_recall_active_boomerang()
	current_mask_state = MaskState.NO_MASK
	previous_mask_state = MaskState.NO_MASK
	unlocked_mask_states = [true, false, false]
	mask_health = [0, 0, 0]
	velocity = Vector2.ZERO
	_damage_invulnerability_timer = 0.0
	_mask_switch_timer = 0.0
	_apply_mask_state_effects()
	_update_animation_name()
	for mask_state in range(MASK_STATE_COUNT):
		mask_health_changed.emit(mask_state, get_mask_health(mask_state), max_health_per_mask)
	mask_state_changed.emit(current_mask_state, get_mask_state_name())

func _notify_damage_taken(damage: int, source: Node, cause: String) -> void:
	player_damaged.emit(damage, cause)
	var story_controller := get_tree().get_first_node_in_group("story_controllers")
	if story_controller != null and story_controller.has_method("handle_player_damaged"):
		story_controller.call("handle_player_damaged", self, damage, source, cause)

func _damage_cause_from_source(source: Node) -> String:
	if current_mask_state == MaskState.EUDA_MASK or current_mask_state == MaskState.GHOST_MASK:
		return "ghost_block"
	if source != null:
		if source.is_in_group("ghost_blocks"):
			return "ghost_block"
		if String(source.name).to_lower().contains("ghost"):
			return "ghost_block"
	return "environment"

func _is_ghost_related_fall() -> bool:
	return current_mask_state == MaskState.EUDA_MASK or current_mask_state == MaskState.GHOST_MASK or _ghost_block_context_timer > 0.0

func _update_ghost_block_context(_delta: float) -> void:
	if _is_touching_ghost_block_area():
		_ghost_block_context_timer = ghost_block_fall_memory_time

func _is_touching_ghost_block_area() -> bool:
	for ghost_block in get_tree().get_nodes_in_group("ghost_blocks"):
		var block_node := ghost_block as Node
		if block_node == null:
			continue
		for collision_polygon in _collision_polygon_descendants(block_node):
			var points := _global_polygon_points(collision_polygon)
			for probe_point in _player_probe_points():
				if Geometry2D.is_point_in_polygon(probe_point, points) or _distance_to_polygon(probe_point, points) <= 8.0:
					return true
	return false

func _player_probe_points() -> Array[Vector2]:
	var half_size := _player_half_size()
	return [
		global_position,
		global_position + Vector2(-half_size.x, -half_size.y),
		global_position + Vector2(half_size.x, -half_size.y),
		global_position + Vector2(-half_size.x, half_size.y),
		global_position + Vector2(half_size.x, half_size.y),
		global_position + Vector2(0.0, half_size.y),
	]

func _player_half_size() -> Vector2:
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null and collision_shape.shape != null:
		var rectangle := collision_shape.shape as RectangleShape2D
		if rectangle != null:
			return rectangle.size * collision_shape.scale.abs() * 0.5
	return Vector2(18.0, 18.0)

func _collision_polygon_descendants(root_node: Node) -> Array[CollisionPolygon2D]:
	var polygons: Array[CollisionPolygon2D] = []
	for child in root_node.get_children():
		var collision_polygon := child as CollisionPolygon2D
		if collision_polygon != null and collision_polygon.polygon.size() >= 3:
			polygons.append(collision_polygon)
		polygons.append_array(_collision_polygon_descendants(child))
	return polygons

func _global_polygon_points(collision_polygon: CollisionPolygon2D) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(collision_polygon.polygon.size())
	for index in collision_polygon.polygon.size():
		points[index] = collision_polygon.to_global(collision_polygon.polygon[index])
	return points

func _distance_to_polygon(point: Vector2, points: PackedVector2Array) -> float:
	var best_distance := INF
	for index in points.size():
		var closest := Geometry2D.get_closest_point_to_segment(point, points[index], points[(index + 1) % points.size()])
		best_distance = minf(best_distance, point.distance_to(closest))
	return best_distance

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
		if collider.has_method("is_body_touching_impact_surface") and not bool(collider.call("is_body_touching_impact_surface", self)):
			continue
		if not collider.has_method("is_body_touching_impact_surface") and collider.has_method("is_body_touching_impact_bottom") and not bool(collider.call("is_body_touching_impact_bottom", self)):
			continue
		var damage := int(collider.call("get_mechanism_impact_damage")) if collider.has_method("get_mechanism_impact_damage") else 1
		var direction: Vector2 = collider.call("get_mechanism_impact_direction") if collider.has_method("get_mechanism_impact_direction") else collision.get_normal() * -1.0
		var knockback: Vector2 = collider.call("get_mechanism_impact_knockback") if collider.has_method("get_mechanism_impact_knockback") else hit_knockback
		take_mechanism_crush(damage, collider, direction, knockback)
		return

func _handle_pushable_collisions(delta: float, horizontal_input: float) -> void:
	if absf(horizontal_input) < 0.1:
		return
	var push_direction := signf(horizontal_input)
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var collider := collision.get_collider()
		if collider == null or not collider.is_in_group("pushable_boxes"):
			continue
		if collision.get_normal().x * push_direction > -0.35:
			continue
		if not collider.has_method("push_from_player"):
			continue
		var did_push := bool(collider.call("push_from_player", push_direction, absf(velocity.x), delta, self))
		if did_push:
			var speed_multiplier := float(collider.call("get_push_speed_multiplier")) if collider.has_method("get_push_speed_multiplier") else 0.55
			apply_ground_speed_multiplier(speed_multiplier, 0.14)
			velocity.x = signf(velocity.x) * minf(absf(velocity.x), max_run_speed * speed_multiplier)
			return
