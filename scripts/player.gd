extends CharacterBody2D

@export_group("Movement")
@export var max_run_speed: float = 320.0
@export var ground_acceleration: float = 2600.0
@export var ground_deceleration: float = 3200.0
@export var air_acceleration: float = 1650.0
@export var air_deceleration: float = 900.0
@export var turn_acceleration: float = 3800.0

@export_group("Jump")
@export var jump_velocity: float = -585.0
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

@export_group("Respawn")
@export var spawn_position := Vector2(80.0, 420.0)
@export var reset_below_y: float = 980.0
@export var reset_above_y: float = -220.0

var facing_direction := 1.0
var active_boomerang: Node
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _throw_cooldown_timer := 0.0
var _jump_was_down := false
var _throw_was_down := false

func _ready() -> void:
	add_to_group("players")

func _physics_process(delta: float) -> void:
	if global_position.y > reset_below_y or global_position.y < reset_above_y:
		_respawn()

	_update_timers(delta)

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

	move_and_slide()

func _update_timers(delta: float) -> void:
	_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	_throw_cooldown_timer = maxf(_throw_cooldown_timer - delta, 0.0)

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
	global_position = spawn_position
	velocity = Vector2.ZERO
