@tool
extends StaticBody2D

const TERRAIN_LAYER := 1 << 0

enum UnlockMask { EUDA_MASK = 1, GHOST_MASK = 2 }
enum SpawnEnemyKind { NORMAL, GHOST }

@export_enum("Euda Mask", "Ghost Mask") var unlock_mask := 0:
	set(value):
		unlock_mask = value
		queue_redraw()
@export_range(1, 12, 1) var hits_to_break := 3
@export var interaction_prompt := "Press E"

@export_group("Monster Spawning")
@export var spawn_monsters_before_break := true
@export var enemy_scene: PackedScene
@export_enum("Normal Enemy", "Ghost Enemy") var spawned_enemy_kind := 0
@export var spawn_on_hit_before_break := true
@export_range(1, 8, 1) var spawn_count_per_hit := 1
@export var auto_spawn_before_break := true
@export_range(0.1, 30.0, 0.1, "suffix:s") var auto_spawn_interval := 1.0
@export_range(1, 12, 1) var auto_spawn_count := 1
@export_range(0, 24, 1) var max_alive_spawned_enemies := 4
@export var spawn_parent_path := NodePath("../../Enemies")
@export var spawn_offsets: Array[Vector2] = [Vector2(-72.0, 0.0), Vector2(72.0, 0.0)]
@export var spawn_jitter := Vector2(18.0, 6.0)

@export_group("Visual")
@export var intact_color := Color(0.38, 0.40, 0.38, 1.0):
	set(value):
		intact_color = value
		queue_redraw()
@export var broken_color := Color(0.24, 0.25, 0.24, 1.0):
	set(value):
		broken_color = value
		queue_redraw()
@export var edge_color := Color(0.06, 0.07, 0.07, 0.9):
	set(value):
		edge_color = value
		queue_redraw()
@export var glyph_color := Color(0.9, 0.82, 0.32, 1.0):
	set(value):
		glyph_color = value
		queue_redraw()
@export var interaction_color := Color(1.0, 0.9, 0.36, 1.0):
	set(value):
		interaction_color = value
		queue_redraw()

var health := 3
var broken := false
var unlocked := false
var _player_inside: Node
var _interact_was_down := false
var _flash_timer := 0.0
var _auto_spawn_timer := 1.0
var _spawn_sequence := 0
var _spawned_enemy_paths: Array[NodePath] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("saveable")
	_rng.randomize()
	collision_layer = TERRAIN_LAYER
	collision_mask = 0
	health = hits_to_break
	_auto_spawn_timer = auto_spawn_interval
	_update_collision_enabled()
	_connect_areas()
	set_process(not Engine.is_editor_hint())
	queue_redraw()

func _process(delta: float) -> void:
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	if not Engine.is_editor_hint():
		_update_auto_spawn(delta)
		_handle_interaction_input()
	queue_redraw()

func take_boomerang_hit(_boomerang: Node) -> void:
	if broken:
		return
	health = maxi(health - 1, 0)
	_flash_timer = 0.12
	if health <= 0:
		break_tombstone()
	elif spawn_on_hit_before_break:
		_spawn_monsters_if_needed(spawn_count_per_hit)
	queue_redraw()

func break_tombstone() -> void:
	broken = true
	health = 0
	_update_collision_enabled()
	queue_redraw()

func unlock_for_player(player: Node) -> bool:
	if not broken or unlocked or player == null or not player.has_method("unlock_mask_state"):
		return false
	var mask_state := _unlock_mask_state_value()
	var did_unlock := bool(player.call("unlock_mask_state", mask_state))
	unlocked = true
	_show_unlock_popup(player)
	queue_redraw()
	return did_unlock

func get_save_state() -> Dictionary:
	return {
		"health": health,
		"broken": broken,
		"unlocked": unlocked,
		"auto_spawn_timer": _auto_spawn_timer,
		"spawn_sequence": _spawn_sequence,
		"spawned_enemy_paths": _spawned_enemy_paths.duplicate(),
	}

func apply_save_state(state: Dictionary) -> void:
	health = int(state.get("health", hits_to_break))
	broken = bool(state.get("broken", health <= 0))
	unlocked = bool(state.get("unlocked", false))
	_auto_spawn_timer = float(state.get("auto_spawn_timer", auto_spawn_interval))
	_spawn_sequence = int(state.get("spawn_sequence", 0))
	_spawned_enemy_paths = state.get("spawned_enemy_paths", []) as Array[NodePath]
	_update_collision_enabled()
	queue_redraw()

func _update_auto_spawn(delta: float) -> void:
	var interval := maxf(auto_spawn_interval, 0.1)
	if broken or not spawn_monsters_before_break or not auto_spawn_before_break:
		_auto_spawn_timer = interval
		return

	if _auto_spawn_timer > interval:
		_auto_spawn_timer = interval
	_auto_spawn_timer -= delta
	if _auto_spawn_timer <= 0.0:
		_spawn_monsters_if_needed(auto_spawn_count)
		_auto_spawn_timer = interval

func _spawn_monsters_if_needed(spawn_count: int) -> void:
	if not spawn_monsters_before_break or enemy_scene == null or spawn_count <= 0:
		return

	_prune_spawned_enemies()
	var alive_count := _spawned_enemy_paths.size()
	if max_alive_spawned_enemies > 0 and alive_count >= max_alive_spawned_enemies:
		return

	var spawn_parent := get_node_or_null(spawn_parent_path)
	if spawn_parent == null:
		spawn_parent = get_parent()
	if spawn_parent == null:
		return

	var available_slots := spawn_count
	if max_alive_spawned_enemies > 0:
		available_slots = mini(available_slots, max_alive_spawned_enemies - alive_count)

	for index in available_slots:
		var enemy := enemy_scene.instantiate() as Node2D
		if enemy == null:
			continue
		_spawn_sequence += 1
		enemy.name = "%sSpawnedEnemy%d" % [name, _spawn_sequence]
		spawn_parent.add_child(enemy)
		enemy.global_position = global_position + _spawn_offset(index)
		_configure_spawned_enemy(enemy)
		_spawned_enemy_paths.append(enemy.get_path())

func _spawn_offset(index: int) -> Vector2:
	var base_offset := Vector2(72.0, 0.0)
	if not spawn_offsets.is_empty():
		base_offset = spawn_offsets[index % spawn_offsets.size()]
	var jitter := Vector2(_rng.randf_range(-spawn_jitter.x, spawn_jitter.x), _rng.randf_range(-spawn_jitter.y, spawn_jitter.y))
	return base_offset + jitter

func _configure_spawned_enemy(enemy: Node2D) -> void:
	if spawned_enemy_kind == SpawnEnemyKind.GHOST:
		enemy.set("can_touch_ghost_blocks", true)
		enemy.set("body_color", Color(0.42, 0.58, 1.0, 1.0))
		enemy.set("edge_color", Color(0.04, 0.08, 0.18, 1.0))
	else:
		enemy.set("can_touch_ghost_blocks", false)

func _prune_spawned_enemies() -> void:
	var alive_paths: Array[NodePath] = []
	for enemy_path in _spawned_enemy_paths:
		if get_node_or_null(enemy_path) != null:
			alive_paths.append(enemy_path)
	_spawned_enemy_paths = alive_paths

func _draw() -> void:
	var body_color := broken_color if broken else intact_color
	if _flash_timer > 0.0:
		body_color = body_color.lerp(Color(1.0, 1.0, 1.0, 1.0), 0.55)

	if broken:
		_draw_broken_tombstone(body_color)
	else:
		_draw_intact_tombstone(body_color)

	_draw_glyph()
	_draw_health_cracks()
	if broken and not unlocked and _player_inside != null:
		_draw_interaction_prompt()

func _draw_intact_tombstone(color: Color) -> void:
	draw_circle(Vector2(0.0, -28.0), 28.0, color)
	draw_rect(Rect2(Vector2(-28.0, -28.0), Vector2(56.0, 62.0)), color, true)
	draw_arc(Vector2(0.0, -28.0), 28.0, PI, TAU, 24, edge_color, 3.0)
	draw_line(Vector2(-28.0, -28.0), Vector2(-28.0, 34.0), edge_color, 3.0)
	draw_line(Vector2(28.0, -28.0), Vector2(28.0, 34.0), edge_color, 3.0)
	draw_line(Vector2(-32.0, 34.0), Vector2(32.0, 34.0), edge_color, 3.0)

func _draw_broken_tombstone(color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		Vector2(-30.0, 34.0),
		Vector2(-28.0, -18.0),
		Vector2(-10.0, -48.0),
		Vector2(6.0, -30.0),
		Vector2(28.0, -22.0),
		Vector2(28.0, 34.0)
	]), color)
	draw_polyline(PackedVector2Array([
		Vector2(-30.0, 34.0),
		Vector2(-28.0, -18.0),
		Vector2(-10.0, -48.0),
		Vector2(6.0, -30.0),
		Vector2(28.0, -22.0),
		Vector2(28.0, 34.0),
		Vector2(-30.0, 34.0)
	]), edge_color, 3.0)
	draw_line(Vector2(-22.0, 10.0), Vector2(-46.0, 38.0), edge_color, 3.0)
	draw_line(Vector2(18.0, 13.0), Vector2(46.0, 38.0), edge_color, 3.0)

func _draw_glyph() -> void:
	var y := -16.0
	if _unlock_mask_state_value() == 1:
		draw_circle(Vector2(0.0, y), 10.0, glyph_color)
		draw_circle(Vector2(0.0, y), 4.0, edge_color)
	else:
		draw_arc(Vector2(0.0, y), 13.0, 0.25, TAU - 0.25, 24, glyph_color, 4.0)
		draw_line(Vector2(-7.0, y + 10.0), Vector2(-12.0, y + 19.0), glyph_color, 3.0)
		draw_line(Vector2(7.0, y + 10.0), Vector2(12.0, y + 19.0), glyph_color, 3.0)

func _draw_health_cracks() -> void:
	if broken:
		return
	var cracks := hits_to_break - health
	for index in cracks:
		var offset := -12.0 + index * 12.0
		draw_line(Vector2(offset, -36.0), Vector2(offset + 7.0, -12.0), edge_color, 2.0)
		draw_line(Vector2(offset + 7.0, -12.0), Vector2(offset + 1.0, 4.0), edge_color, 2.0)

func _draw_interaction_prompt() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var text := interaction_prompt
	if unlocked:
		text = "Unlocked"
	draw_rect(Rect2(Vector2(-45.0, -88.0), Vector2(90.0, 22.0)), Color(0.02, 0.025, 0.035, 0.72), true)
	draw_string(font, Vector2(-38.0, -72.0), text, HORIZONTAL_ALIGNMENT_CENTER, 76.0, 13, interaction_color)

func _handle_interaction_input() -> void:
	var interact_down := Input.is_physical_key_pressed(KEY_E)
	if interact_down and not _interact_was_down and _player_inside != null:
		unlock_for_player(_player_inside)
	_interact_was_down = interact_down

func _connect_areas() -> void:
	var interaction_area := get_node_or_null("InteractionArea") as Area2D
	if interaction_area != null:
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

func _update_collision_enabled() -> void:
	collision_layer = 0 if broken else TERRAIN_LAYER
	var collision_shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null:
		collision_shape.disabled = broken

func _unlock_mask_state_value() -> int:
	return 1 if unlock_mask == 0 else 2

func _show_unlock_popup(player: Node) -> void:
	var mask_name := "euda_mask" if _unlock_mask_state_value() == 1 else "ghost_mask"
	for popup in get_tree().get_nodes_in_group("unlock_popups"):
		if popup.has_method("show_unlock"):
			popup.show_unlock(mask_name)
			return
