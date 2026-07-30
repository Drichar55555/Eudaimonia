@tool
extends Area2D

const FADE_LAYER_NAME := "TeleportDoorFadeLayer"
const FADE_RECT_NAME := "FadeRect"

@export var interaction_prompt := "E  Enter":
	set(value):
		interaction_prompt = value
		queue_redraw()
@export var arrival_offset := Vector2.ZERO
@export_range(0.05, 2.0, 0.01) var fade_out_duration := 0.22
@export_range(0.0, 1.0, 0.01) var black_hold_duration := 0.08
@export_range(0.05, 2.0, 0.01) var fade_in_duration := 0.28

@export_group("Visual")
@export var door_color := Color(0.12, 0.16, 0.22, 1.0):
	set(value):
		door_color = value
		queue_redraw()
@export var inner_color := Color(0.025, 0.035, 0.055, 1.0):
	set(value):
		inner_color = value
		queue_redraw()
@export var edge_color := Color(0.25, 0.78, 0.76, 0.95):
	set(value):
		edge_color = value
		queue_redraw()
@export var prompt_color := Color(0.72, 1.0, 0.94, 1.0):
	set(value):
		prompt_color = value
		queue_redraw()

var _player_inside: CharacterBody2D
var _interact_was_down := false
var _teleporting := false

func _ready() -> void:
	add_to_group("paired_teleport_doors")
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	set_process(not Engine.is_editor_hint())
	queue_redraw()

func _process(_delta: float) -> void:
	var interact_down := Input.is_physical_key_pressed(KEY_E)
	if interact_down and not _interact_was_down and _player_inside != null and not _teleporting:
		teleport_player(_player_inside)
	_interact_was_down = interact_down
	queue_redraw()

func teleport_player(player: CharacterBody2D) -> bool:
	if player == null or _teleporting:
		return false
	var destination := find_paired_door()
	if destination == null:
		push_warning("No paired door found for '%s'. Use matching names such as door-a and door-b." % name)
		return false
	_perform_teleport(player, destination)
	return true

func find_paired_door() -> Node2D:
	var target_name := _paired_name(String(name))
	if target_name.is_empty():
		return null
	for candidate in get_tree().get_nodes_in_group("paired_teleport_doors"):
		if candidate != self and candidate is Node2D and String(candidate.name) == target_name:
			return candidate as Node2D
	return null

func _perform_teleport(player: CharacterBody2D, destination: Node2D) -> void:
	_teleporting = true
	var destination_door := destination as Area2D
	if destination_door != null:
		destination_door.set("_teleporting", true)
	var player_was_processing := player.is_physics_processing()
	player.set_physics_process(false)
	player.velocity = Vector2.ZERO
	var fade_rect := _get_or_create_fade_rect()
	fade_rect.visible = true
	fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	var fade_out := create_tween()
	fade_out.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade_out.tween_property(fade_rect, "color:a", 1.0, fade_out_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_out.finished
	if not is_instance_valid(player) or not is_instance_valid(destination):
		_finish_teleport_state(destination_door)
		return
	var destination_offset := destination.get("arrival_offset") as Vector2
	player.global_position = destination.global_position + destination_offset
	player.velocity = Vector2.ZERO
	if black_hold_duration > 0.0:
		await get_tree().create_timer(black_hold_duration, true, false, true).timeout
	var fade_in := create_tween()
	fade_in.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade_in.tween_property(fade_rect, "color:a", 0.0, fade_in_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_in.finished
	fade_rect.visible = false
	if is_instance_valid(player):
		player.set_physics_process(player_was_processing)
	_finish_teleport_state(destination_door)

func _finish_teleport_state(destination_door: Area2D) -> void:
	_teleporting = false
	if destination_door != null and is_instance_valid(destination_door):
		destination_door.set("_teleporting", false)

func _get_or_create_fade_rect() -> ColorRect:
	var tree_root := get_tree().root
	var fade_layer := tree_root.get_node_or_null(FADE_LAYER_NAME) as CanvasLayer
	if fade_layer == null:
		fade_layer = CanvasLayer.new()
		fade_layer.name = FADE_LAYER_NAME
		fade_layer.layer = 1000
		tree_root.add_child(fade_layer)
	var fade_rect := fade_layer.get_node_or_null(FADE_RECT_NAME) as ColorRect
	if fade_rect == null:
		fade_rect = ColorRect.new()
		fade_rect.name = FADE_RECT_NAME
		fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
		fade_rect.visible = false
		fade_layer.add_child(fade_rect)
	return fade_rect

func _paired_name(door_name: String) -> String:
	if door_name.ends_with("-a"):
		return door_name.trim_suffix("-a") + "-b"
	if door_name.ends_with("-b"):
		return door_name.trim_suffix("-b") + "-a"
	if door_name.ends_with("_a"):
		return door_name.trim_suffix("_a") + "_b"
	if door_name.ends_with("_b"):
		return door_name.trim_suffix("_b") + "_a"
	return ""

func _on_body_entered(body: Node2D) -> void:
	if body is CharacterBody2D and body.is_in_group("players"):
		_player_inside = body as CharacterBody2D
		queue_redraw()

func _on_body_exited(body: Node2D) -> void:
	if body == _player_inside:
		_player_inside = null
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2(-34.0, -76.0), Vector2(68.0, 152.0)), door_color, true)
	draw_rect(Rect2(Vector2(-34.0, -76.0), Vector2(68.0, 152.0)), edge_color, false, 3.0)
	draw_rect(Rect2(Vector2(-24.0, -64.0), Vector2(48.0, 140.0)), inner_color, true)
	draw_arc(Vector2.ZERO, 29.0, PI, TAU, 24, edge_color, 3.0)
	draw_circle(Vector2(17.0, 6.0), 3.5, edge_color)
	if _player_inside != null and not _teleporting:
		_draw_interaction_prompt()

func _draw_interaction_prompt() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	draw_rect(Rect2(Vector2(-58.0, -108.0), Vector2(116.0, 24.0)), Color(0.015, 0.025, 0.04, 0.82), true)
	draw_string(font, Vector2(-52.0, -91.0), interaction_prompt, HORIZONTAL_ALIGNMENT_CENTER, 104.0, 14, prompt_color)

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if _paired_name(String(name)).is_empty():
		warnings.append("Door name must end with -a/-b (or _a/_b), for example door-a and door-b.")
	return warnings
