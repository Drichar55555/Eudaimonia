extends Area2D

signal returned(boomerang: Node)

@export var outbound_speed := 780.0
@export var return_speed := 920.0
@export var max_distance := 360.0
@export var catch_distance := 28.0
@export var catch_delay := 0.14
@export var spin_speed := 14.0
@export_range(0, 5, 1) var hit_pause_frames := 5

var thrower: Node2D
var direction := Vector2.RIGHT
var start_position := Vector2.ZERO
var returning := false
var _catch_timer := 0.0
var _hit_pause_frames_left := 0
var _hit_target_phases := {}

func _ready() -> void:
	add_to_group("save_transients")
	add_to_group("player_weapons")
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	start_position = global_position
	_catch_timer = catch_delay
	queue_redraw()

func setup(new_thrower: Node2D, facing_direction: float) -> void:
	thrower = new_thrower
	direction = Vector2.RIGHT if facing_direction >= 0.0 else Vector2.LEFT
	rotation = direction.angle()
	start_position = global_position
	_catch_timer = catch_delay

func _physics_process(delta: float) -> void:
	if thrower == null or not is_instance_valid(thrower):
		queue_free()
		return

	_catch_timer = maxf(_catch_timer - delta, 0.0)
	if _hit_pause_frames_left > 0:
		_hit_pause_frames_left -= 1
		queue_redraw()
		return

	if returning:
		_move_returning(delta)
	else:
		_move_outbound(delta)

	rotation += spin_speed * delta
	queue_redraw()

func start_return() -> void:
	returning = true

func _move_outbound(delta: float) -> void:
	global_position += direction * outbound_speed * delta
	if global_position.distance_to(start_position) >= max_distance:
		start_return()

func _move_returning(delta: float) -> void:
	var target_position := thrower.global_position + Vector2(0.0, -18.0)
	var to_thrower := target_position - global_position
	if to_thrower.length() <= catch_distance and _catch_timer <= 0.0:
		returned.emit(self)
		queue_free()
		return

	global_position += to_thrower.normalized() * return_speed * delta

func _on_body_entered(body: Node) -> void:
	if body == thrower and _catch_timer > 0.0:
		return
	start_return()

func _on_area_entered(area: Area2D) -> void:
	if area == self:
		return
	if not area.is_in_group("boomerang_targets"):
		return
	var target := area.get_parent()
	if target == null or not target.has_method("take_boomerang_hit"):
		return

	var hit_key := "%s:%s" % [target.get_instance_id(), _hit_phase_name()]
	if _hit_target_phases.has(hit_key):
		return

	_hit_target_phases[hit_key] = true
	if hit_pause_frames > _hit_pause_frames_left:
		_hit_pause_frames_left = hit_pause_frames
	target.take_boomerang_hit(self)

func _hit_phase_name() -> String:
	return "returning" if returning else "outbound"

func _draw() -> void:
	var fill := Color(0.96, 0.86, 0.36, 1.0)
	var edge := Color(0.08, 0.06, 0.04, 1.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -15),
		Vector2(16, 0),
		Vector2(0, 15),
		Vector2(-16, 0)
	]), fill)
	draw_polyline(PackedVector2Array([
		Vector2(0, -15),
		Vector2(16, 0),
		Vector2(0, 15),
		Vector2(-16, 0),
		Vector2(0, -15)
	]), edge, 3.0)
	draw_circle(Vector2(-5, -2), 2.3, edge)
	draw_circle(Vector2(5, -2), 2.3, edge)