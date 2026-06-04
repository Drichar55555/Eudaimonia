extends ColorRect

signal respawn_finished(player: Node)
signal transition_finished(player: Node)

@export var player_path: NodePath
@export var save_manager_path: NodePath
@export var camera_path: NodePath
@export_range(0.05, 3.0, 0.05) var fade_in_duration := 0.22
@export_range(0.0, 2.0, 0.05) var hold_duration := 0.12
@export_range(0.05, 3.0, 0.05) var fade_out_duration := 0.28
@export var fade_color := Color(0.0, 0.0, 0.0, 1.0)

var _player: Node
var _save_manager: Node
var _camera: Node
var _active := false
var _mode := "respawn"
var _phase := 0
var _elapsed := 0.0
var _checkpoint_position := Vector2.ZERO
var _during_black_callback := Callable()
var _finished_callback := Callable()

func _ready() -> void:
	add_to_group("death_respawn_controllers")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
	visible = false
	set_process(false)
	_resolve_nodes()

func request_player_respawn(player: Node, checkpoint_position: Vector2) -> bool:
	if _active:
		return true
	_player = player
	_checkpoint_position = checkpoint_position
	_mode = "respawn"
	_during_black_callback = Callable()
	_finished_callback = Callable()
	_start_transition()
	return true

func request_black_transition(player: Node, during_black_callback: Callable = Callable(), finished_callback: Callable = Callable()) -> bool:
	if _active:
		return false
	_player = player
	_checkpoint_position = Vector2.ZERO
	_mode = "transition"
	_during_black_callback = during_black_callback
	_finished_callback = finished_callback
	_start_transition()
	return true

func _start_transition() -> void:
	_active = true
	_phase = 0
	_elapsed = 0.0
	visible = true
	color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
	_set_player_paused(true)
	set_process(true)

func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	match _phase:
		0:
			var progress := clampf(_elapsed / maxf(fade_in_duration, 0.001), 0.0, 1.0)
			_set_alpha(progress)
			if progress >= 1.0:
				_perform_respawn()
				_phase = 1
				_elapsed = 0.0
		1:
			_set_alpha(1.0)
			if _elapsed >= hold_duration:
				_phase = 2
				_elapsed = 0.0
		2:
			var progress := clampf(_elapsed / maxf(fade_out_duration, 0.001), 0.0, 1.0)
			_set_alpha(1.0 - progress)
			if progress >= 1.0:
				_finish_respawn()

func _perform_respawn() -> void:
	_resolve_nodes()
	if _mode == "transition":
		if _during_black_callback.is_valid():
			_during_black_callback.call()
		_resolve_player()
		_snap_camera_to_player_room()
		_set_player_paused(true)
		return
	if _save_manager != null and _save_manager.has_method("has_checkpoint") and bool(_save_manager.call("has_checkpoint")) and _save_manager.has_method("load_checkpoint"):
		_save_manager.call("load_checkpoint")
	else:
		_resolve_player()
		if _player != null and _player.has_method("apply_save_state"):
			_player.call("apply_save_state", {"position": _checkpoint_position})
	_resolve_player()
	_snap_camera_to_player_room()
	_set_player_paused(true)

func _finish_respawn() -> void:
	_set_alpha(0.0)
	visible = false
	_active = false
	set_process(false)
	_resolve_player()
	_set_player_paused(false)
	if _mode == "transition":
		if _finished_callback.is_valid():
			_finished_callback.call()
		transition_finished.emit(_player)
	else:
		respawn_finished.emit(_player)
	_mode = "respawn"
	_during_black_callback = Callable()
	_finished_callback = Callable()

func _set_alpha(alpha: float) -> void:
	color = Color(fade_color.r, fade_color.g, fade_color.b, clampf(alpha, 0.0, 1.0))

func _resolve_nodes() -> void:
	_resolve_player()
	if not save_manager_path.is_empty():
		_save_manager = get_node_or_null(save_manager_path)
	if _save_manager == null:
		_save_manager = get_tree().get_first_node_in_group("save_managers")
	if not camera_path.is_empty():
		_camera = get_node_or_null(camera_path)
	if _camera == null:
		_camera = get_viewport().get_camera_2d()

func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	if not player_path.is_empty():
		_player = get_node_or_null(player_path)
	if _player == null:
		_player = get_tree().get_first_node_in_group("players")

func _set_player_paused(paused: bool) -> void:
	_resolve_player()
	if _player == null or not is_instance_valid(_player):
		return
	_player.set_physics_process(not paused)
	if paused and _player is CharacterBody2D:
		(_player as CharacterBody2D).velocity = Vector2.ZERO

func _snap_camera_to_player_room() -> void:
	_resolve_nodes()
	if _camera != null and _camera.has_method("snap_to_target_room"):
		_camera.call("snap_to_target_room")
