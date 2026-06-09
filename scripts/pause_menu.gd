extends Control

@export var title_text := "PAUSED"
@export var hint_text := "Press Esc to resume"
@export var panel_color := Color(0.02, 0.025, 0.035, 0.88)
@export var overlay_color := Color(0.0, 0.0, 0.0, 0.58)
@export var accent_color := Color(1.0, 0.86, 0.28, 1.0)

var _paused_by_menu := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_ESCAPE and key_event.physical_keycode != KEY_ESCAPE:
		return
	_toggle_pause()
	get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if _paused_by_menu and get_tree() != null:
		get_tree().paused = false

func _toggle_pause() -> void:
	if visible:
		_resume_game()
	else:
		_pause_game()

func _pause_game() -> void:
	visible = true
	_paused_by_menu = get_tree() != null and not get_tree().paused
	if get_tree() != null:
		get_tree().paused = true
	queue_redraw()

func _resume_game() -> void:
	visible = false
	if _paused_by_menu and get_tree() != null:
		get_tree().paused = false
	_paused_by_menu = false
	queue_redraw()

func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), overlay_color)

	var panel_size := Vector2(minf(size.x * 0.74, 520.0), 210.0)
	var panel_position := (size - panel_size) * 0.5
	var panel_rect := Rect2(panel_position, panel_size)
	draw_rect(panel_rect, panel_color)
	draw_rect(panel_rect, Color(accent_color.r, accent_color.g, accent_color.b, 0.82), false, 3.0)
	draw_line(panel_position + Vector2(28.0, 70.0), panel_position + Vector2(panel_size.x - 28.0, 70.0), Color(accent_color.r, accent_color.g, accent_color.b, 0.55), 2.0, true)

	var font := get_theme_default_font()
	if font == null:
		return
	var title_size := 34
	var hint_size := 18
	var title_y := panel_position.y + 52.0
	var hint_y := panel_position.y + 128.0
	draw_string(font, Vector2(panel_position.x, title_y), title_text, HORIZONTAL_ALIGNMENT_CENTER, panel_size.x, title_size, Color(0.98, 0.96, 0.86, 1.0))
	draw_string(font, Vector2(panel_position.x, hint_y), hint_text, HORIZONTAL_ALIGNMENT_CENTER, panel_size.x, hint_size, Color(0.78, 0.84, 0.92, 1.0))