@tool
extends Area2D

@export var save_manager_path: NodePath
@export var reenter_cooldown := 20.0
@export var show_editor_visual := true:
	set(value):
		show_editor_visual = value
		queue_redraw()
@export var show_runtime_visual := false:
	set(value):
		show_runtime_visual = value
		queue_redraw()
@export var debug_radius := 96.0:
	set(value):
		debug_radius = maxf(value, 12.0)
		_update_shape()
		queue_redraw()
@export var debug_color := Color(0.9, 0.8, 0.25, 0.18):
	set(value):
		debug_color = value
		queue_redraw()

var _save_manager: Node
var _player_inside := false
var _last_exit_time := -INF

func _ready() -> void:
	add_to_group("save_debug_areas")
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_update_shape()
	set_process(Engine.is_editor_hint())
	if not Engine.is_editor_hint():
		_save_manager = get_node_or_null(save_manager_path)
		call_deferred("_check_initial_overlap")

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()

func _draw() -> void:
	if Engine.is_editor_hint():
		if not show_editor_visual:
			return
	elif not show_runtime_visual:
		return

	var outline := debug_color
	outline.a = minf(debug_color.a + 0.45, 1.0)
	draw_circle(Vector2.ZERO, debug_radius, debug_color)
	draw_arc(Vector2.ZERO, debug_radius, 0.0, TAU, 48, outline, 3.0, true)
	draw_line(Vector2(-14.0, 0.0), Vector2(14.0, 0.0), outline, 3.0)
	draw_line(Vector2(0.0, -14.0), Vector2(0.0, 14.0), outline, 3.0)

func _check_initial_overlap() -> void:
	for body in get_overlapping_bodies():
		if _is_player(body):
			_try_start_save(body)
			return

func _on_body_entered(body: Node) -> void:
	if Engine.is_editor_hint() or not _is_player(body):
		return
	_try_start_save(body)

func _on_body_exited(body: Node) -> void:
	if Engine.is_editor_hint() or not _is_player(body):
		return
	_player_inside = false
	_last_exit_time = _now_seconds()

func _try_start_save(_player: Node) -> void:
	if _player_inside:
		return
	_player_inside = true
	if _now_seconds() - _last_exit_time < reenter_cooldown:
		return
	if _save_manager == null:
		_save_manager = get_node_or_null(save_manager_path)
	if _save_manager != null and _save_manager.has_method("request_save"):
		_save_manager.request_save(global_position)

func _is_player(node: Node) -> bool:
	return node != null and node.is_in_group("players")

func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0

func set_debug_visuals_visible(value: bool) -> void:
	show_runtime_visual = value
	queue_redraw()

func _update_shape() -> void:
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape == null:
		return
	var circle := collision_shape.shape as CircleShape2D
	if circle == null:
		circle = CircleShape2D.new()
		collision_shape.shape = circle
	circle.radius = debug_radius
