extends Node

@export var player_path: NodePath
@export var save_manager_path: NodePath
@export var dialogue_box_path: NodePath
@export var death_space_spawn := Vector2(8000.0, 420.0)
@export var death_return_gate_path: NodePath
@export_range(0.0, 5.0, 0.05) var dialogue_invulnerability_time := 1.0

var first_damage_dialogue_seen := false
var first_death_sequence_seen := false
var ghost_death_dialogue_seen := false
var _pending_ghost_death_dialogue := false
var _player: Node
var _save_manager: Node
var _dialogue_box: Node
var _death_return_gate: Area2D
var _respawn_controller: Node
var _player_control_was_enabled := true
var _pause_depth := 0
var _in_death_space := false

func _ready() -> void:
	add_to_group("story_controllers")
	call_deferred("_initialize_story_links")

func _initialize_story_links() -> void:
	_resolve_nodes()
	_connect_return_gate()
	_connect_respawn_controller()

func handle_player_damaged(player: Node, _damage: int, _source: Node, _cause: String) -> void:
	if first_damage_dialogue_seen:
		return
	first_damage_dialogue_seen = true
	_show_energy_damage_dialogue(player)

func handle_player_fall_death(player: Node, continue_callback: Callable, cause: String = "fall") -> bool:
	if cause == "ghost_block":
		return false
	if first_damage_dialogue_seen:
		return false
	first_damage_dialogue_seen = true
	_show_energy_damage_dialogue(player, continue_callback)
	return true

func _show_energy_damage_dialogue(player: Node, finished_callback: Callable = Callable()) -> void:
	_show_dialogue(player, [
		"如果受到伤害，能量值就会下降",
		"当能量值没了……你就会死",
	], finished_callback)

func handle_player_death(player: Node, defeated_mask_state: int, checkpoint_position: Vector2, cause: String) -> bool:
	if cause == "ghost_block" and not ghost_death_dialogue_seen:
		_pending_ghost_death_dialogue = true
	if first_death_sequence_seen:
		return false
	first_death_sequence_seen = true
	_enter_first_death_space(player, defeated_mask_state, checkpoint_position)
	return true

func _enter_first_death_space(player: Node, _defeated_mask_state: int, _checkpoint_position: Vector2) -> void:
	_player = player
	_request_black_transition(player, Callable(self, "_move_player_to_death_space"), Callable(self, "_show_first_death_dialogue_in_space"))

func _show_first_death_dialogue_in_space() -> void:
	_resolve_player()
	_show_dialogue(_player, [
		"……你死了，因为你的能量耗尽了",
		"你会回到上一个提供能量的地方",
	])

func _move_player_to_death_space() -> void:
	_resolve_player()
	if _player == null:
		return
	if _player.has_method("enter_death_space_state"):
		_player.call("enter_death_space_state")
	elif _player is CharacterBody2D:
		(_player as CharacterBody2D).velocity = Vector2.ZERO
	(_player as Node2D).global_position = death_space_spawn
	_in_death_space = true
	_set_death_space_filter_visible(true)

func _on_death_return_gate_body_entered(body: Node) -> void:
	if not _in_death_space or body == null or not body.is_in_group("players"):
		return
	return_from_death_space(body)

func return_from_death_space(player: Node) -> void:
	if player == null or not player.is_in_group("players"):
		return
	_in_death_space = false
	_set_death_space_filter_visible(false)
	_player = player
	_request_black_transition(player, Callable(self, "_return_to_checkpoint"), Callable(self, "_maybe_show_ghost_death_dialogue"))

func _return_to_checkpoint() -> void:
	_resolve_nodes()
	if _save_manager != null and _save_manager.has_method("has_checkpoint") and bool(_save_manager.call("has_checkpoint")) and _save_manager.has_method("load_checkpoint"):
		_save_manager.call("load_checkpoint")
	else:
		_resolve_player()
		if _player != null and _player.has_method("apply_save_state"):
			_player.call("apply_save_state", {"position": (_player as Node2D).global_position})

func _on_respawn_finished(_player_node: Node) -> void:
	_maybe_show_ghost_death_dialogue()

func _maybe_show_ghost_death_dialogue() -> void:
	if not _pending_ghost_death_dialogue or ghost_death_dialogue_seen:
		return
	_pending_ghost_death_dialogue = false
	ghost_death_dialogue_seen = true
	_resolve_player()
	_show_dialogue(_player, [
		"哦……那片区域不是真实存在的，这只存在于你的想象",
		"幽灵……是幽灵！无法分辨是非的人会掉进幽灵的陷阱",
		"这些幽灵看起来是真的，只有当你真正触碰，如一阵烟雾，发现它只存在于你的脑海，却已来不及补救",
		"按2键，看看那个墓碑里获得的面具能力有什么用，戴上我吧！",
	])

func _show_dialogue(player: Node, lines: Array[String], finished_callback: Callable = Callable()) -> void:
	_resolve_dialogue_box()
	_pause_player(true)
	if _dialogue_box == null or not _dialogue_box.has_method("show_dialogue"):
		_grant_dialogue_invulnerability(player)
		_pause_player(false)
		if finished_callback.is_valid():
			finished_callback.call()
		return
	if _dialogue_box.has_signal("dialogue_finished"):
		for connection in _dialogue_box.dialogue_finished.get_connections():
			_dialogue_box.dialogue_finished.disconnect(connection.callable)
		_dialogue_box.dialogue_finished.connect(func() -> void:
			_grant_dialogue_invulnerability(player)
			_pause_player(false)
			if finished_callback.is_valid():
				finished_callback.call()
		, CONNECT_ONE_SHOT)
	_dialogue_box.call("show_dialogue", "面具", lines)

func _grant_dialogue_invulnerability(player: Node) -> void:
	if player != null and player.has_method("grant_invulnerability"):
		player.call("grant_invulnerability", dialogue_invulnerability_time)

func _request_black_transition(player: Node, during_black_callback: Callable, finished_callback: Callable = Callable()) -> void:
	_resolve_respawn_controller()
	if _respawn_controller != null and _respawn_controller.has_method("request_black_transition"):
		if bool(_respawn_controller.call("request_black_transition", player, during_black_callback, finished_callback)):
			return
	if during_black_callback.is_valid():
		during_black_callback.call()
	if finished_callback.is_valid():
		finished_callback.call()

func _pause_player(paused: bool) -> void:
	_resolve_player()
	if _player == null or not is_instance_valid(_player):
		return
	if paused:
		if _pause_depth == 0:
			_player_control_was_enabled = _player.is_physics_processing()
		_pause_depth += 1
		_player.set_physics_process(false)
		if _player is CharacterBody2D:
			(_player as CharacterBody2D).velocity = Vector2.ZERO
	else:
		_pause_depth = maxi(_pause_depth - 1, 0)
		if _pause_depth == 0:
			_player.set_physics_process(_player_control_was_enabled)

func _resolve_nodes() -> void:
	_resolve_player()
	_resolve_dialogue_box()
	if not save_manager_path.is_empty():
		_save_manager = get_node_or_null(save_manager_path)
	if _save_manager == null:
		_save_manager = get_tree().get_first_node_in_group("save_managers")
	if not death_return_gate_path.is_empty():
		_death_return_gate = get_node_or_null(death_return_gate_path) as Area2D
	_resolve_respawn_controller()

func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	if not player_path.is_empty():
		_player = get_node_or_null(player_path)
	if _player == null:
		_player = get_tree().get_first_node_in_group("players")

func _resolve_dialogue_box() -> void:
	if _dialogue_box != null and is_instance_valid(_dialogue_box):
		return
	if not dialogue_box_path.is_empty():
		_dialogue_box = get_node_or_null(dialogue_box_path)

func _connect_return_gate() -> void:
	if _death_return_gate == null:
		return
	if not _death_return_gate.body_entered.is_connected(_on_death_return_gate_body_entered):
		_death_return_gate.body_entered.connect(_on_death_return_gate_body_entered)

func _connect_respawn_controller() -> void:
	_resolve_respawn_controller()
	if _respawn_controller != null and _respawn_controller.has_signal("respawn_finished"):
		_respawn_controller.respawn_finished.connect(_on_respawn_finished)

func _resolve_respawn_controller() -> void:
	if _respawn_controller != null and is_instance_valid(_respawn_controller):
		return
	_respawn_controller = get_tree().get_first_node_in_group("death_respawn_controllers")

func _set_death_space_filter_visible(value: bool) -> void:
	get_tree().call_group("death_space_filters", "set_filter_visible", value)
