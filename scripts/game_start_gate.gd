extends Control

@export var player_path: NodePath
@export var save_manager_path: NodePath
@export var respawn_controller_path: NodePath
@export var dialogue_box_path: NodePath
@export var title_text := "EUDAIMONIA"
@export var ui_font: Font
@export var background_color := Color(0.015, 0.018, 0.022, 1.0)
@export var horizon_color := Color(0.05, 0.065, 0.075, 1.0)
@export var panel_color := Color(0.02, 0.025, 0.035, 0.92)
@export var accent_color := Color(1.0, 0.86, 0.28, 1.0)
@export var button_color := Color(0.08, 0.1, 0.13, 0.94)
@export var button_hover_color := Color(0.16, 0.18, 0.22, 0.98)
@export var button_disabled_color := Color(0.06, 0.065, 0.075, 0.68)
@export var rollback_card_color := Color(0.045, 0.055, 0.07, 0.96)

const NEW_GAME_INTRO_DIALOGUE: Array[String] = ["按x发射我吧"]

var _player: Node
var _save_manager: Node
var _respawn_controller: Node
var _dialogue_box: Node
var _paused_by_gate := false
var _started := false
var _view_mode := "main"
var _main_selection := 0
var _rollback_selection := 0
var _confirm_selection := 1
var _confirm_rollback_index := -1
var _load_transition_active := false
var _pending_rollback_index := -1
var _buttons: Array[Dictionary] = []
var _rollback_cards: Array[Dictionary] = []
var _rollback_buttons: Array[Dictionary] = []
var _confirm_buttons: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	set_process_unhandled_input(true)
	call_deferred("show_main_menu")

func _unhandled_input(event: InputEvent) -> void:
	if _started or not visible:
		return
	if _load_transition_active:
		get_viewport().set_input_as_handled()
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if _is_key(key_event, KEY_ESCAPE):
		_handle_escape_key()
		get_viewport().set_input_as_handled()
		return
	if _handle_navigation_key(key_event):
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		_sync_selection_to_point(event.position)
		queue_redraw()
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var point := mouse_event.position
	if _view_mode == "confirm_rollback":
		_handle_confirm_click(point)
	elif _view_mode == "rollback":
		_handle_rollback_click(point)
	else:
		_handle_main_click(point)
	accept_event()

func _exit_tree() -> void:
	if _paused_by_gate and get_tree() != null:
		get_tree().paused = false

func show_main_menu() -> void:
	_started = false
	visible = true
	_view_mode = "main"
	_main_selection = _first_enabled_main_selection()
	_rollback_selection = 0
	_confirm_selection = 1
	_confirm_rollback_index = -1
	_load_transition_active = false
	_pending_rollback_index = -1
	_resolve_player()
	_resolve_save_manager()
	_resolve_respawn_controller()
	_resolve_dialogue_box()
	if get_tree() != null:
		get_tree().paused = true
		_paused_by_gate = true
	if not _can_continue_game():
		_main_selection = 1
	queue_redraw()

func _handle_escape_key() -> void:
	if _view_mode == "confirm_rollback":
		_cancel_rollback_confirmation()
	elif _view_mode == "rollback":
		_view_mode = "main"
		_main_selection = _first_enabled_main_selection()
		queue_redraw()

func _handle_navigation_key(key_event: InputEventKey) -> bool:
	if _is_key(key_event, KEY_UP):
		_move_selection(Vector2i(0, -1))
		return true
	if _is_key(key_event, KEY_DOWN):
		_move_selection(Vector2i(0, 1))
		return true
	if _is_key(key_event, KEY_LEFT):
		_move_selection(Vector2i(-1, 0))
		return true
	if _is_key(key_event, KEY_RIGHT):
		_move_selection(Vector2i(1, 0))
		return true
	if _is_key(key_event, KEY_SPACE) or _is_key(key_event, KEY_ENTER):
		_activate_selected_item()
		return true
	return false

func _is_key(key_event: InputEventKey, keycode: Key) -> bool:
	return key_event.keycode == keycode or key_event.physical_keycode == keycode

func _handle_main_click(point: Vector2) -> void:
	for button in _buttons:
		var rect := button.get("rect") as Rect2
		if not rect.has_point(point):
			continue
		match str(button.get("action", "")):
			"continue":
				if bool(button.get("enabled", true)):
					_open_load_view()
			"new_start":
				_start_new_game()
			"exit":
				get_tree().quit()
		return

func _handle_rollback_click(point: Vector2) -> void:
	for button in _buttons:
		var rect := button.get("rect") as Rect2
		if rect.has_point(point) and str(button.get("action", "")) == "back":
			_view_mode = "main"
			_main_selection = _first_enabled_main_selection()
			_rollback_selection = 0
			queue_redraw()
			return
	for button in _rollback_buttons:
		var rect := button.get("rect") as Rect2
		if not rect.has_point(point):
			continue
		var index := int(button.get("index", -1))
		_rollback_selection = index + 1
		_request_rollback_confirmation(index)
		return

func _handle_confirm_click(point: Vector2) -> void:
	for button in _confirm_buttons:
		var rect := button.get("rect") as Rect2
		if not rect.has_point(point):
			continue
		_confirm_selection = int(button.get("index", 1))
		_activate_confirm_selection()
		return

func _move_selection(direction: Vector2i) -> void:
	if _view_mode == "confirm_rollback":
		_move_confirm_selection(direction)
	elif _view_mode == "rollback":
		_move_rollback_selection(direction)
	else:
		_move_main_selection(direction)
	queue_redraw()

func _move_main_selection(direction: Vector2i) -> void:
	var delta := 0
	if direction.y < 0 or direction.x < 0:
		delta = -1
	elif direction.y > 0 or direction.x > 0:
		delta = 1
	if delta != 0:
		var next_selection := _main_selection
		for _step in 3:
			next_selection = _wrapped_index(next_selection + delta, 3)
			if _main_item_enabled(next_selection):
				_main_selection = next_selection
				return

func _move_rollback_selection(direction: Vector2i) -> void:
	var entry_count := _visible_rollback_entry_count()
	if entry_count <= 0:
		_rollback_selection = 0
		return
	if direction.y < 0:
		_rollback_selection = 0
	elif direction.y > 0:
		if _rollback_selection == 0:
			_rollback_selection = 1
	elif direction.x < 0:
		if _rollback_selection == 0:
			_rollback_selection = entry_count
		else:
			_rollback_selection = 1 + _wrapped_index(_rollback_selection - 2, entry_count)
	elif direction.x > 0:
		if _rollback_selection == 0:
			_rollback_selection = 1
		else:
			_rollback_selection = 1 + _wrapped_index(_rollback_selection, entry_count)

func _move_confirm_selection(direction: Vector2i) -> void:
	if direction.x < 0 or direction.y < 0:
		_confirm_selection = 0
	elif direction.x > 0 or direction.y > 0:
		_confirm_selection = 1

func _activate_selected_item() -> void:
	if _view_mode == "confirm_rollback":
		_activate_confirm_selection()
		return
	if _view_mode == "rollback":
		if _rollback_selection == 0:
			_view_mode = "main"
			_main_selection = _first_enabled_main_selection()
			queue_redraw()
		else:
			_request_rollback_confirmation(_rollback_selection - 1)
		return
	match _main_selection:
		0:
			if _can_continue_game():
				_open_load_view()
		1:
			_start_new_game()
		2:
			get_tree().quit()

func _sync_selection_to_point(point: Vector2) -> void:
	if _view_mode == "confirm_rollback":
		for button in _confirm_buttons:
			var confirm_rect := button.get("rect") as Rect2
			if confirm_rect.has_point(point):
				_confirm_selection = int(button.get("index", 1))
				return
		return
	if _view_mode == "rollback":
		for button in _buttons:
			var button_rect := button.get("rect") as Rect2
			if button_rect.has_point(point) and str(button.get("action", "")) == "back":
				_rollback_selection = 0
				return
		for card in _rollback_cards:
			var card_rect := card.get("rect") as Rect2
			if card_rect.has_point(point):
				_rollback_selection = int(card.get("index", -1)) + 1
				return
		return
	for button in _buttons:
		var rect := button.get("rect") as Rect2
		if rect.has_point(point) and bool(button.get("enabled", true)):
			match str(button.get("action", "")):
				"continue":
					_main_selection = 0
				"new_start":
					_main_selection = 1
				"exit":
					_main_selection = 2
			return

func _open_load_view() -> void:
	if not _can_continue_game():
		_main_selection = _first_enabled_main_selection()
		queue_redraw()
		return
	_select_first_rollback_item()
	_view_mode = "rollback"
	queue_redraw()

func _start_new_game() -> void:
	_resolve_save_manager()
	if _save_manager != null and _save_manager.has_method("reset_to_initial_state"):
		_save_manager.call("reset_to_initial_state")
	_snap_cameras_to_loaded_room()
	_show_new_game_intro_dialogue()

func _start_game(play_intro_shot: bool) -> void:
	_started = true
	visible = false
	if _paused_by_gate and get_tree() != null:
		get_tree().paused = false
	_paused_by_gate = false
	_resolve_player()
	if play_intro_shot and _player != null and _player.has_method("start_with_right_shot"):
		_player.call("start_with_right_shot")
	queue_redraw()

func _show_new_game_intro_dialogue() -> void:
	_resolve_dialogue_box()
	visible = false
	if get_tree() != null:
		get_tree().paused = true
		_paused_by_gate = true
	if _dialogue_box == null or not _dialogue_box.has_method("show_key_dialogue"):
		_start_game(true)
		return
	if _dialogue_box.has_signal("dialogue_finished"):
		_dialogue_box.dialogue_finished.connect(func() -> void:
			_start_game(true)
		, CONNECT_ONE_SHOT)
	_dialogue_box.call("show_key_dialogue", "面具", NEW_GAME_INTRO_DIALOGUE, "X", KEY_X)

func _can_continue_game() -> bool:
	return _visible_rollback_entry_count() > 0

func _main_item_enabled(index: int) -> bool:
	if index == 0:
		return _can_continue_game()
	return index >= 0 and index <= 2

func _first_enabled_main_selection() -> int:
	return 0 if _can_continue_game() else 1

func _select_first_rollback_item() -> void:
	_rollback_selection = 1 if _visible_rollback_entry_count() > 0 else 0

func _visible_rollback_entry_count() -> int:
	_resolve_save_manager()
	if _save_manager == null or not _save_manager.has_method("get_rollback_entries"):
		return 0
	var entries := _save_manager.call("get_rollback_entries") as Array
	return mini(entries.size(), 3)

func _clamp_rollback_selection(entry_count: int) -> void:
	if entry_count <= 0:
		_rollback_selection = 0
	else:
		_rollback_selection = clampi(_rollback_selection, 0, entry_count)

func _wrapped_index(index: int, count: int) -> int:
	if count <= 0:
		return 0
	while index < 0:
		index += count
	while index >= count:
		index -= count
	return index

func _request_rollback_confirmation(index: int) -> void:
	_confirm_rollback_index = index
	_confirm_selection = 1
	_view_mode = "confirm_rollback"
	queue_redraw()

func _cancel_rollback_confirmation() -> void:
	_view_mode = "rollback"
	_confirm_rollback_index = -1
	_confirm_selection = 1
	queue_redraw()

func _activate_confirm_selection() -> void:
	if _confirm_selection == 0 and _confirm_rollback_index >= 0:
		var index := _confirm_rollback_index
		_confirm_rollback_index = -1
		_start_rollback_load(index)
	else:
		_cancel_rollback_confirmation()

func _start_rollback_load(index: int) -> void:
	if _load_transition_active:
		return
	_resolve_respawn_controller()
	if _respawn_controller != null and _respawn_controller.has_method("request_black_transition"):
		_pending_rollback_index = index
		_load_transition_active = true
		visible = false
		var did_start := bool(_respawn_controller.call(
			"request_black_transition",
			_current_player(),
			Callable(self, "_perform_pending_rollback_load"),
			Callable(self, "_finish_rollback_load_transition")
		))
		if did_start:
			return
		_load_transition_active = false
		_pending_rollback_index = -1
		visible = true
	if _load_rollback_immediately(index):
		_finish_rollback_load_transition()
	else:
		_cancel_rollback_confirmation()

func _perform_pending_rollback_load() -> void:
	if _pending_rollback_index >= 0:
		_load_rollback_immediately(_pending_rollback_index)

func _finish_rollback_load_transition() -> void:
	_load_transition_active = false
	_pending_rollback_index = -1
	_start_game(false)

func _load_rollback_immediately(index: int) -> bool:
	_resolve_save_manager()
	if _save_manager == null or not _save_manager.has_method("load_rollback_entry"):
		return false
	var did_load := bool(_save_manager.call("load_rollback_entry", index))
	if not did_load:
		return false
	_snap_cameras_to_loaded_room()
	return true

func _current_player() -> Node:
	_resolve_player()
	return _player

func _snap_cameras_to_loaded_room() -> void:
	if get_tree() == null:
		return
	for camera in get_tree().get_nodes_in_group("room_cameras"):
		if camera != null and camera.has_method("snap_to_target_room"):
			camera.call("snap_to_target_room")

func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	if not player_path.is_empty():
		_player = get_node_or_null(player_path)
	if _player == null and get_tree() != null:
		_player = get_tree().get_first_node_in_group("players")

func _resolve_save_manager() -> void:
	if _save_manager != null and is_instance_valid(_save_manager):
		return
	if not save_manager_path.is_empty():
		_save_manager = get_node_or_null(save_manager_path)
	if _save_manager == null and get_tree() != null:
		_save_manager = get_tree().get_first_node_in_group("save_managers")

func _resolve_respawn_controller() -> void:
	if _respawn_controller != null and is_instance_valid(_respawn_controller):
		return
	if not respawn_controller_path.is_empty():
		_respawn_controller = get_node_or_null(respawn_controller_path)
	if _respawn_controller == null and get_tree() != null:
		_respawn_controller = get_tree().get_first_node_in_group("death_respawn_controllers")

func _resolve_dialogue_box() -> void:
	if _dialogue_box != null and is_instance_valid(_dialogue_box):
		return
	if not dialogue_box_path.is_empty():
		_dialogue_box = get_node_or_null(dialogue_box_path)

func _draw() -> void:
	if not visible or size.x <= 1.0 or size.y <= 1.0:
		return
	_draw_fullscreen_background()
	_buttons.clear()
	_rollback_cards.clear()
	_rollback_buttons.clear()
	_confirm_buttons.clear()
	if _view_mode == "confirm_rollback":
		_draw_rollback_view()
		_draw_confirm_rollback_view()
	elif _view_mode == "rollback":
		_draw_rollback_view()
	else:
		_draw_main_view()

func _draw_fullscreen_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color)
	var horizon_height := size.y * 0.38
	draw_rect(Rect2(Vector2(0.0, size.y - horizon_height), Vector2(size.x, horizon_height)), horizon_color)
	for index in 9:
		var y := size.y * (0.22 + float(index) * 0.075)
		var alpha := 0.035 + float(index) * 0.012
		draw_line(Vector2(size.x * 0.08, y), Vector2(size.x * 0.92, y + 22.0), Color(accent_color.r, accent_color.g, accent_color.b, alpha), 1.0, true)

func _draw_main_view() -> void:
	var font := _menu_font()
	if font == null:
		return
	var content_width := minf(size.x * 0.72, 780.0)
	var content_x := (size.x - content_width) * 0.5
	var title_y := maxf(size.y * 0.18, 108.0)
	_draw_centered_text(font, title_text, title_y, content_width, content_x, 54, Color(0.98, 0.96, 0.86, 1.0))
	draw_line(Vector2(content_x + content_width * 0.18, title_y + 24.0), Vector2(content_x + content_width * 0.82, title_y + 24.0), Color(accent_color.r, accent_color.g, accent_color.b, 0.64), 2.0, true)
	var button_width := minf(content_width, 420.0)
	var button_x := (size.x - button_width) * 0.5
	var button_y := maxf(size.y * 0.45, title_y + 108.0)
	var can_continue := _can_continue_game()
	_draw_button(Rect2(Vector2(button_x, button_y), Vector2(button_width, 52.0)), "继续", "continue", font, 22, _main_selection == 0 and can_continue, can_continue)
	_draw_button(Rect2(Vector2(button_x, button_y + 72.0), Vector2(button_width, 52.0)), "重新开始", "new_start", font, 22, _main_selection == 1)
	_draw_button(Rect2(Vector2(button_x, button_y + 144.0), Vector2(button_width, 52.0)), "退出", "exit", font, 22, _main_selection == 2)

func _draw_rollback_view() -> void:
	_resolve_save_manager()
	var font := _menu_font()
	if font == null:
		return
	var entries: Array = []
	if _save_manager != null and _save_manager.has_method("get_rollback_entries"):
		entries = _save_manager.call("get_rollback_entries") as Array
	var entry_count := mini(entries.size(), 3)
	_clamp_rollback_selection(entry_count)
	var margin := Vector2(maxf(size.x * 0.055, 36.0), maxf(size.y * 0.08, 36.0))
	draw_string(font, Vector2(margin.x, margin.y + 42.0), "读取存档", HORIZONTAL_ALIGNMENT_LEFT, size.x - margin.x * 2.0, 34, Color(0.98, 0.96, 0.86, 1.0))
	_draw_button(Rect2(Vector2(size.x - margin.x - 112.0, margin.y + 14.0), Vector2(112.0, 40.0)), "返回", "back", font, 17, _rollback_selection == 0)
	draw_line(Vector2(margin.x, margin.y + 68.0), Vector2(size.x - margin.x, margin.y + 68.0), Color(accent_color.r, accent_color.g, accent_color.b, 0.55), 2.0, true)
	if entries.is_empty():
		_draw_centered_text(font, "暂无存档", size.y * 0.54, size.x, 0.0, 24, Color(0.78, 0.84, 0.92, 1.0))
		return
	var card_gap := 20.0
	var available_width := size.x - margin.x * 2.0
	var card_width := (available_width - card_gap * 2.0) / 3.0
	var card_height := minf(size.y - margin.y * 2.0 - 118.0, 500.0)
	var card_y := margin.y + 98.0
	for index in entry_count:
		var card_rect := Rect2(Vector2(margin.x + index * (card_width + card_gap), card_y), Vector2(card_width, card_height))
		_draw_rollback_card(card_rect, entries[index], index, font, _rollback_selection == index + 1)

func _draw_confirm_rollback_view() -> void:
	var font := _menu_font()
	if font == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.52))
	var panel_size := Vector2(minf(size.x * 0.72, 460.0), 190.0)
	var panel_position := (size - panel_size) * 0.5
	var panel_rect := Rect2(panel_position, panel_size)
	_draw_panel(panel_rect)
	draw_string(font, Vector2(panel_position.x, panel_position.y + 50.0), "确认读取这个存档？", HORIZONTAL_ALIGNMENT_CENTER, panel_size.x, 24, Color(0.98, 0.96, 0.86, 1.0))
	draw_string(font, Vector2(panel_position.x, panel_position.y + 84.0), "当前进度会回到所选存档。", HORIZONTAL_ALIGNMENT_CENTER, panel_size.x, 16, Color(0.72, 0.8, 0.9, 1.0))
	var button_size := Vector2(128.0, 40.0)
	var gap := 22.0
	var total_width := button_size.x * 2.0 + gap
	var button_y := panel_position.y + 118.0
	var confirm_rect := Rect2(Vector2(panel_position.x + (panel_size.x - total_width) * 0.5, button_y), button_size)
	var cancel_rect := Rect2(Vector2(confirm_rect.end.x + gap, button_y), button_size)
	_draw_confirm_button(confirm_rect, "确定", 0, font)
	_draw_confirm_button(cancel_rect, "取消", 1, font)

func _draw_panel(panel_rect: Rect2) -> void:
	draw_rect(panel_rect, panel_color)
	draw_rect(panel_rect, Color(accent_color.r, accent_color.g, accent_color.b, 0.82), false, 3.0)

func _draw_button(rect: Rect2, text: String, action: String, font: Font, font_size: int = 20, selected: bool = false, enabled: bool = true) -> void:
	var hovered := rect.has_point(get_local_mouse_position())
	var active_hover := enabled and hovered
	draw_rect(rect, button_hover_color if active_hover or selected else button_color if enabled else button_disabled_color)
	draw_rect(rect, Color(accent_color.r, accent_color.g, accent_color.b, 0.82 if selected else 0.62 if active_hover else 0.36 if enabled else 0.16), false, 2.0 if not selected else 3.0)
	if selected:
		_draw_cursor_marker(rect)
	draw_string(font, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.64), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, Color(0.94, 0.96, 1.0, 1.0) if enabled else Color(0.42, 0.45, 0.5, 1.0))
	_buttons.append({"rect": rect, "action": action, "enabled": enabled})

func _draw_rollback_card(rect: Rect2, entry: Dictionary, index: int, font: Font, selected: bool) -> void:
	var hovered := rect.has_point(get_local_mouse_position())
	draw_rect(rect, button_hover_color if hovered or selected else rollback_card_color)
	draw_rect(rect, Color(accent_color.r, accent_color.g, accent_color.b, 0.86 if selected else 0.72 if hovered else 0.38), false, 2.0 if not selected else 3.0)
	if selected:
		_draw_cursor_marker(rect)
	_rollback_cards.append({"rect": rect, "index": index})
	var thumbnail_rect := Rect2(rect.position + Vector2(14.0, 14.0), Vector2(rect.size.x - 28.0, minf((rect.size.x - 28.0) * 0.5625, rect.size.y * 0.52)))
	_draw_thumbnail(thumbnail_rect, entry)
	var text_y := thumbnail_rect.end.y + 34.0
	draw_string(font, Vector2(rect.position.x + 18.0, text_y), str(entry.get("checkpoint_name", "未知地点")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 19, Color(0.98, 0.96, 0.86, 1.0))
	draw_string(font, Vector2(rect.position.x + 18.0, text_y + 32.0), str(entry.get("saved_at_text", "--")), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 36.0, 16, Color(0.72, 0.8, 0.9, 1.0))
	var button_rect := Rect2(Vector2(rect.position.x + 18.0, rect.end.y - 56.0), Vector2(rect.size.x - 36.0, 38.0))
	var button_hovered := button_rect.has_point(get_local_mouse_position())
	draw_rect(button_rect, Color(0.16, 0.18, 0.22, 0.96) if button_hovered or selected else Color(0.08, 0.1, 0.13, 0.92))
	draw_rect(button_rect, Color(accent_color.r, accent_color.g, accent_color.b, 0.76 if selected else 0.65 if button_hovered else 0.38), false, 2.0)
	draw_string(font, Vector2(button_rect.position.x, button_rect.position.y + 25.0), "读取", HORIZONTAL_ALIGNMENT_CENTER, button_rect.size.x, 17, Color(0.94, 0.96, 1.0, 1.0))
	_rollback_buttons.append({"rect": button_rect, "index": index})

func _draw_confirm_button(rect: Rect2, text: String, index: int, font: Font) -> void:
	var selected := _confirm_selection == index
	var hovered := rect.has_point(get_local_mouse_position())
	draw_rect(rect, button_hover_color if hovered or selected else button_color)
	draw_rect(rect, Color(accent_color.r, accent_color.g, accent_color.b, 0.82 if selected else 0.62 if hovered else 0.36), false, 2.0 if not selected else 3.0)
	if selected:
		_draw_cursor_marker(rect)
	draw_string(font, Vector2(rect.position.x, rect.position.y + 26.0), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 18, Color(0.94, 0.96, 1.0, 1.0))
	_confirm_buttons.append({"rect": rect, "index": index})

func _draw_cursor_marker(target_rect: Rect2) -> void:
	var center_y := target_rect.get_center().y
	var tip_x := target_rect.position.x - 10.0
	var tail_x := target_rect.position.x - 26.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(tip_x, center_y),
		Vector2(tail_x, center_y - 9.0),
		Vector2(tail_x, center_y + 9.0),
	]), accent_color)

func _draw_thumbnail(rect: Rect2, entry: Dictionary) -> void:
	draw_rect(rect, Color(0.01, 0.012, 0.018, 1.0))
	var texture := entry.get("thumbnail") as Texture2D
	if texture != null:
		var texture_size := Vector2(texture.get_width(), texture.get_height())
		if texture_size.x > 0.0 and texture_size.y > 0.0:
			var scale := minf(rect.size.x / texture_size.x, rect.size.y / texture_size.y)
			var draw_size := texture_size * scale
			var draw_rect := Rect2(rect.position + (rect.size - draw_size) * 0.5, draw_size)
			draw_texture_rect(texture, draw_rect, false)
			draw_rect(rect, Color(1.0, 1.0, 1.0, 0.12), false, 1.0)
			return
	var font := _menu_font()
	if font != null:
		draw_string(font, Vector2(rect.position.x, rect.get_center().y + 5.0), "截图生成中", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 15, Color(0.62, 0.68, 0.76, 1.0))
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.12), false, 1.0)

func _menu_font() -> Font:
	if ui_font != null:
		return ui_font
	return get_theme_default_font()

func _draw_centered_text(font: Font, text: String, baseline_y: float, width: float, x: float, font_size: int, color: Color) -> void:
	draw_string(font, Vector2(x, baseline_y), text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)
