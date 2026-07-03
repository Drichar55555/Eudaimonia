extends Control

@export var prompt_icon_texture: Texture2D
@export var ui_font: Font
@export_range(0.4, 8.0, 0.1) var display_duration := 2.8
@export var overlay_color := Color(0.0, 0.0, 0.0, 0.18)
@export var panel_color := Color(0.02, 0.025, 0.035, 0.9)
@export var accent_color := Color(1.0, 0.86, 0.28, 1.0)
@export var title_color := Color(0.98, 0.96, 0.86, 1.0)
@export var description_color := Color(0.66, 0.72, 0.8, 1.0)

var _item_title := ""
var _item_description := ""
var _item_icon: Texture2D
var _display_timer := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("item_obtain_prompt_ui")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(true)

func _process(delta: float) -> void:
	if not visible:
		return
	_display_timer = maxf(_display_timer - delta, 0.0)
	if _display_timer <= 0.0:
		_hide()
		return
	queue_redraw()

func show_item_obtained(item_info: Dictionary) -> void:
	_item_title = str(item_info.get("title", ""))
	_item_description = str(item_info.get("description", ""))
	_item_icon = item_info.get("icon", prompt_icon_texture) as Texture2D
	if _item_icon == null:
		_item_icon = prompt_icon_texture
	_display_timer = display_duration
	visible = true
	queue_redraw()

func _hide() -> void:
	visible = false
	_display_timer = 0.0
	queue_redraw()

func _draw() -> void:
	if not visible or size.x <= 1.0 or size.y <= 1.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), overlay_color)
	var panel_size := Vector2(minf(size.x * 0.78, 620.0), 220.0)
	var panel_position := (size - panel_size) * 0.5
	var panel_rect := Rect2(panel_position, panel_size)
	draw_rect(panel_rect, panel_color)
	draw_rect(panel_rect, Color(accent_color.r, accent_color.g, accent_color.b, 0.86), false, 3.0)
	draw_line(panel_position + Vector2(30.0, 48.0), panel_position + Vector2(panel_size.x - 30.0, 48.0), Color(accent_color.r, accent_color.g, accent_color.b, 0.5), 2.0, true)
	_draw_icon(Rect2(panel_position + Vector2(38.0, 72.0), Vector2(88.0, 88.0)))
	var font := _prompt_font()
	if font == null:
		return
	var text_x := panel_position.x + 160.0
	var text_width := panel_size.x - 198.0
	draw_string(font, Vector2(text_x, panel_position.y + 92.0), _item_title, HORIZONTAL_ALIGNMENT_LEFT, text_width, 26, title_color)
	draw_string(font, Vector2(text_x, panel_position.y + 124.0), _item_description, HORIZONTAL_ALIGNMENT_LEFT, text_width, 16, description_color)

func _draw_icon(rect: Rect2) -> void:
	if _item_icon == null:
		draw_rect(rect, Color(accent_color.r, accent_color.g, accent_color.b, 0.16))
		draw_rect(rect, Color(accent_color.r, accent_color.g, accent_color.b, 0.55), false, 2.0)
		return
	var texture_size := Vector2(_item_icon.get_width(), _item_icon.get_height())
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var scale := minf(rect.size.x / texture_size.x, rect.size.y / texture_size.y)
	var draw_size := texture_size * scale
	var draw_rect := Rect2(rect.position + (rect.size - draw_size) * 0.5, draw_size)
	draw_texture_rect(_item_icon, draw_rect, false)

func _prompt_font() -> Font:
	if ui_font != null:
		return ui_font
	return get_theme_default_font()
