extends CharacterBody2D

@export var move_speed: float = 285.0
@export var acceleration: float = 2200.0
@export var deceleration: float = 2600.0
@export var jump_velocity: float = -520.0
@export var gravity_scale: float = 1.0
@export var fall_gravity_multiplier: float = 1.35
@export var spawn_position := Vector2(80.0, 420.0)
@export var reset_below_y: float = 980.0
@export var reset_above_y: float = -220.0

var facing_direction := 1.0

func _physics_process(delta: float) -> void:
	if global_position.y > reset_below_y or global_position.y < reset_above_y:
		_respawn()

	var horizontal_input := Input.get_axis("ui_left", "ui_right")

	if Input.is_key_pressed(KEY_A):
		horizontal_input -= 1.0
	if Input.is_key_pressed(KEY_D):
		horizontal_input += 1.0

	horizontal_input = clampf(horizontal_input, -1.0, 1.0)

	if not is_zero_approx(horizontal_input):
		facing_direction = signf(horizontal_input)
		velocity.x = move_toward(velocity.x, horizontal_input * move_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)

	var gravity := ProjectSettings.get_setting("physics/2d/default_gravity") as float
	var gravity_multiplier := fall_gravity_multiplier if velocity.y > 0.0 else 1.0
	velocity.y += gravity * gravity_scale * gravity_multiplier * delta

	if _wants_jump() and is_on_floor():
		velocity.y = jump_velocity

	move_and_slide()

func _wants_jump() -> bool:
	return Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_W)

func _respawn() -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
