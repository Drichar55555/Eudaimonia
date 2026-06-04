@tool
extends StaticBody2D

const TERRAIN_LAYER := 1 << 0

@export_range(0, 99, 1) var keys_required := 1
@export var interaction_prompt := "Press E"
@export var opened_prompt := "Open"

@export_group("Visual")
@export var closed_color := Color(0.28, 0.22, 0.16, 1.0):
	set(value):
		closed_color = value
		queue_redraw()
@export var open_color := Color(0.18, 0.16, 0.13, 0.45):
	set(value):
		open_color = value
		queue_redraw()
@export var edge_color := Color(0.07, 0.05, 0.035, 0.95):
	set(value):
		edge_color = value
		queue_redraw()
@export var lock_color := Color(0.95, 0.78, 0.26, 1.0):
	set(value):
		lock_color = value
		queue_redraw()
@export var interaction_color := Color(1.0, 0.9, 0.36, 1.0):
	set(value):
		interaction_color = value
		queue_redraw()

var opened := false
var _player_inside: Node
var _interact_was_down := false

func _ready() -> void:
	z_index = 18
	z_as_relative = false
	add_to_group("saveable")
	collision_layer = TERRAIN_LAYER
	collision_mask = 0
	_update_collision_enabled()
	_connect_interaction_area()
	set_process(not Engine.is_editor_hint())
	queue_redraw()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		_handle_interaction_input()
	queue_redraw()

func try_open_with_player(player: Node) -> bool:
	if opened:
		return true
	if player == null or not player.has_method("spend_keys"):
		return false
	if not bool(player.call("spend_keys", keys_required)):
		queue_redraw()
		return false
	open_door()
	return true

func open_door() -> void:
	opened = true
	_update_collision_enabled()
	queue_redraw()

func get_save_state() -> Dictionary:
	return {"opened": opened}

func apply_save_state(state: Dictionary) -> void:
	opened = bool(state.get("opened", false))
	_update_collision_enabled()
	queue_redraw()

func _update_collision_enabled() -> void:
	collision_layer = 0 if opened else TERRAIN_LAYER
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null:
		collision_shape.set_deferred("disabled", opened)

func _handle_interaction_input() -> void:
	var interact_down := Input.is_physical_key_pressed(KEY_E)
	if interact_down and not _interact_was_down and _player_inside != null:
		try_open_with_player(_player_inside)
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
	draw_rect(Rect2(Vector2(-30.0, -72.0), Vector2(60.0, 144.0)), body_color, true)
	draw_rect(Rect2(Vector2(-30.0, -72.0), Vector2(60.0, 144.0)), edge_color, false, 3.0)
	if not opened:
		_draw_lock()
	if _player_inside != null:
		_draw_interaction_prompt()

func _draw_lock() -> void:
	draw_rect(Rect2(Vector2(-12.0, -2.0), Vector2(24.0, 22.0)), lock_color, true)
	draw_rect(Rect2(Vector2(-12.0, -2.0), Vector2(24.0, 22.0)), edge_color, false, 2.0)
	draw_arc(Vector2(0.0, -2.0), 12.0, PI, TAU, 18, lock_color, 4.0)
	draw_circle(Vector2(0.0, 8.0), 3.0, edge_color)

func _draw_interaction_prompt() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var player_keys := 0
	if _player_inside != null and _player_inside.has_method("get_key_count"):
		player_keys = int(_player_inside.call("get_key_count"))
	var text := opened_prompt if opened else "%s  %d/%d" % [interaction_prompt, player_keys, keys_required]
	draw_rect(Rect2(Vector2(-54.0, -104.0), Vector2(108.0, 22.0)), Color(0.02, 0.025, 0.035, 0.72), true)
	draw_string(font, Vector2(-48.0, -88.0), text, HORIZONTAL_ALIGNMENT_CENTER, 96.0, 13, interaction_color)
