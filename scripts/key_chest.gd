@tool
extends StaticBody2D

const ITEM_SMALL_KEY := "小钥匙"
const SMALL_KEY_ICON: Texture2D = preload("res://ArtWorks/editor_sun_handle.png")

const ITEM_DEFINITIONS := {
	ITEM_SMALL_KEY: {
		"title": "小钥匙",
		"description": "可以用它打开上锁的门",
		"key_reward": 1,
		"icon": SMALL_KEY_ICON,
	},
}

@export_enum("小钥匙") var item_id := ITEM_SMALL_KEY
@export var interaction_prompt := "Press E"

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
var _interaction_area: Area2D
var _interact_was_down := false

func _ready() -> void:
	z_index = 16
	z_as_relative = false
	add_to_group("saveable")
	add_to_group("key_chests")
	collision_layer = 1
	collision_mask = 0
	_connect_interaction_area()
	set_process(not Engine.is_editor_hint())
	queue_redraw()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		_refresh_player_inside()
		_handle_interaction_input()
	queue_redraw()

func open_with_player(player: Node) -> bool:
	if opened or player == null:
		return false
	var item_info := _item_definition()
	var key_amount := int(item_info.get("key_reward", 0))
	if key_amount > 0 and not player.has_method("add_keys"):
		return false
	opened = true
	if key_amount > 0:
		player.call("add_keys", key_amount)
	_show_item_obtained_ui(item_info)
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
	_interaction_area = get_node_or_null("InteractionArea") as Area2D
	if _interaction_area == null:
		return
	_interaction_area.body_entered.connect(_on_interaction_body_entered)
	_interaction_area.body_exited.connect(_on_interaction_body_exited)

func _refresh_player_inside() -> void:
	if _player_inside != null and is_instance_valid(_player_inside):
		return
	if _interaction_area == null:
		return
	for body in _interaction_area.get_overlapping_bodies():
		if body != null and body.is_in_group("players"):
			_player_inside = body
			return

func _on_interaction_body_entered(body: Node) -> void:
	if body.is_in_group("players"):
		_player_inside = body
		queue_redraw()

func _on_interaction_body_exited(body: Node) -> void:
	if body == _player_inside:
		_player_inside = null
		queue_redraw()

func _exit_tree() -> void:
	pass

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
	if _should_draw_interaction_prompt():
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
	draw_rect(Rect2(Vector2(-46.0, -68.0), Vector2(92.0, 24.0)), Color(0.02, 0.025, 0.035, 0.78), true)
	draw_rect(Rect2(Vector2(-46.0, -68.0), Vector2(92.0, 24.0)), Color(interaction_color.r, interaction_color.g, interaction_color.b, 0.46), false, 1.5)
	draw_string(font, Vector2(-41.0, -51.0), interaction_prompt, HORIZONTAL_ALIGNMENT_CENTER, 82.0, 13, interaction_color)

func _should_draw_interaction_prompt() -> bool:
	return _player_inside != null and not opened and not _has_opened_any_key_chest()

func _show_item_obtained_ui(item_info: Dictionary) -> void:
	if get_tree() == null:
		return
	for prompt_ui in get_tree().get_nodes_in_group("item_obtain_prompt_ui"):
		if prompt_ui != null and is_instance_valid(prompt_ui) and prompt_ui.has_method("show_item_obtained"):
			prompt_ui.call("show_item_obtained", item_info)

func _item_definition() -> Dictionary:
	var definition := ITEM_DEFINITIONS.get(item_id, {}) as Dictionary
	if definition.is_empty():
		definition = ITEM_DEFINITIONS[ITEM_SMALL_KEY]
	return definition

func _has_opened_any_key_chest() -> bool:
	if get_tree() == null:
		return opened
	for chest in get_tree().get_nodes_in_group("key_chests"):
		if chest != null and is_instance_valid(chest) and bool(chest.get("opened")):
			return true
	return false
