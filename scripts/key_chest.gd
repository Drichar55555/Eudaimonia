@tool
extends StaticBody2D

@export_range(1, 99, 1) var key_reward := 1
@export var interaction_prompt := "Press E"
@export var opened_prompt := "Key +1"

@export_group("Visual")
@export var closed_color := Color(0.42, 0.27, 0.14, 1.0):
	set(value):
		closed_color = value
		queue_redraw()
@export var open_color := Color(0.30, 0.20, 0.13, 1.0):
	set(value):
		open_color = value
		queue_redraw()
@export var edge_color := Color(0.09, 0.06, 0.035, 0.95):
	set(value):
		edge_color = value
		queue_redraw()
@export var key_color := Color(0.95, 0.78, 0.26, 1.0):
	set(value):
		key_color = value
		queue_redraw()
@export var interaction_color := Color(1.0, 0.9, 0.36, 1.0):
	set(value):
		interaction_color = value
		queue_redraw()

var opened := false
var _player_inside: Node
var _interact_was_down := false

func _ready() -> void:
	z_index = 16
	z_as_relative = false
	add_to_group("saveable")
	collision_layer = 1
	collision_mask = 0
	_connect_interaction_area()
	set_process(not Engine.is_editor_hint())
	queue_redraw()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		_handle_interaction_input()
	queue_redraw()

func open_with_player(player: Node) -> bool:
	if opened or player == null or not player.has_method("add_keys"):
		return false
	opened = true
	player.call("add_keys", key_reward)
	queue_redraw()
	return true

func get_save_state() -> Dictionary:
	return {"opened": opened}

func apply_save_state(state: Dictionary) -> void:
	opened = bool(state.get("opened", false))
	queue_redraw()

func _handle_interaction_input() -> void:
	var interact_down := Input.is_physical_key_pressed(KEY_E)
	if interact_down and not _interact_was_down and _player_inside != null:
		open_with_player(_player_inside)
	_interact_was_down = interact_down

func _connect_interaction_area() -> void:
	var interaction_area := get_node_or_null("InteractionArea") as Area2D
	if interaction_area == null:
		return
	interaction_area.body_entered.connect(_on_interaction_body_entered)
	interaction_area.body_exited.connect(_on_interaction_body_exited)

func _on_interaction_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		_player_inside = body
		queue_redraw()

func _on_interaction_body_exited(body: Node) -> void:
	if body == _player_inside:
		_player_inside = null
		queue_redraw()

func _draw() -> void:
	var body_color := open_color if opened else closed_color
	draw_rect(Rect2(Vector2(-34.0, -24.0), Vector2(68.0, 48.0)), body_color, true)
	draw_rect(Rect2(Vector2(-34.0, -24.0), Vector2(68.0, 48.0)), edge_color, false, 3.0)
	draw_line(Vector2(-30.0, -2.0), Vector2(30.0, -2.0), edge_color, 2.0)
	if opened:
		draw_line(Vector2(-30.0, -24.0), Vector2(4.0, -44.0), edge_color, 3.0)
		draw_line(Vector2(4.0, -44.0), Vector2(36.0, -24.0), edge_color, 3.0)
	else:
		_draw_key_mark(Vector2.ZERO)
	if _player_inside != null:
		_draw_interaction_prompt()

func _draw_key_mark(center: Vector2) -> void:
	draw_circle(center + Vector2(-6.0, 2.0), 5.0, key_color)
	draw_line(center + Vector2(-1.0, 2.0), center + Vector2(14.0, 2.0), key_color, 3.0)
	draw_line(center + Vector2(8.0, 2.0), center + Vector2(8.0, 8.0), key_color, 2.0)
	draw_line(center + Vector2(14.0, 2.0), center + Vector2(14.0, 7.0), key_color, 2.0)

func _draw_interaction_prompt() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var text := opened_prompt if opened else interaction_prompt
	draw_rect(Rect2(Vector2(-44.0, -62.0), Vector2(88.0, 22.0)), Color(0.02, 0.025, 0.035, 0.72), true)
	draw_string(font, Vector2(-38.0, -46.0), text, HORIZONTAL_ALIGNMENT_CENTER, 76.0, 13, interaction_color)
