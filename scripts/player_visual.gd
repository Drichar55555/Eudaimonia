extends Node2D

const NO_MASK_COLOR := Color(0.36, 0.78, 1.0, 1.0)
const EUDA_MASK_COLOR := Color(0.36, 1.0, 0.68, 1.0)
const GHOST_MASK_COLOR := Color(0.68, 0.76, 1.0, 0.88)
const EDGE_COLOR := Color(0.02, 0.03, 0.04, 1.0)

var player: Node

func _ready() -> void:
	z_index = 100
	z_as_relative = false
	player = get_parent()
	set_process(true)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var mask_name := _mask_state_name()
	var animation_name := _animation_name()
	var body_color := _body_color(mask_name)
	var switch_progress := _mask_switch_progress()
	var switching := animation_name == "mask_switch_cutscene"
	if _damage_invulnerable():
		var pulse := 0.35 + 0.25 * sin(float(Time.get_ticks_msec()) * 0.035)
		body_color = body_color.lerp(Color(1.0, 1.0, 1.0, 1.0), pulse)

	_draw_body(body_color, switching, switch_progress)
	_draw_face(mask_name)
	_draw_mask_icon(mask_name, switching, switch_progress)
	_draw_mask_health(mask_name)
	_draw_animator_label(mask_name, animation_name)

	if switching:
		_draw_mask_switch_cutscene(mask_name, switch_progress)

func _draw_body(body_color: Color, switching: bool, progress: float) -> void:
	var squash := sin(progress * PI) * 0.14 if switching else 0.0
	var body_size := Vector2(48.0 * (1.0 + squash), 56.0 * (1.0 - squash * 0.45))
	var rect := Rect2(-body_size * 0.5 + Vector2(0.0, -14.0), body_size)
	draw_rect(rect, body_color, true)
	draw_rect(rect, EDGE_COLOR, false, 5.0)

func _draw_face(mask_name: String) -> void:
	if mask_name == "ghost_mask":
		draw_circle(Vector2(-9, -21), 4.0, Color(0.9, 1.0, 1.0, 0.95))
		draw_circle(Vector2(9, -21), 4.0, Color(0.9, 1.0, 1.0, 0.95))
		draw_line(Vector2(-10, -4), Vector2(10, -4), Color(0.9, 1.0, 1.0, 0.8), 3.0)
		return

	draw_circle(Vector2(-9, -20), 4.0, EDGE_COLOR)
	draw_circle(Vector2(9, -20), 4.0, EDGE_COLOR)
	if mask_name == "euda_mask":
		draw_arc(Vector2(0, -9), 12.0, 0.15, 2.99, 16, Color(0.02, 0.22, 0.12, 1.0), 4.0)
		draw_circle(Vector2(0, -23), 6.0, Color(0.9, 1.0, 0.86, 0.9))
		draw_circle(Vector2(0, -23), 2.4, Color(0.02, 0.24, 0.1, 1.0))
	else:
		draw_arc(Vector2(0, -8), 12.0, 0.2, 2.94, 16, EDGE_COLOR, 4.0)

func _draw_mask_icon(mask_name: String, switching: bool, progress: float) -> void:
	var y_offset := -68.0 - sin(progress * PI) * 10.0 if switching else -64.0
	var icon_color := _mask_icon_color(mask_name)
	if mask_name == "no_mask":
		draw_polyline(PackedVector2Array([
			Vector2(0, y_offset - 12),
			Vector2(15, y_offset),
			Vector2(0, y_offset + 12),
			Vector2(-15, y_offset),
			Vector2(0, y_offset - 12)
		]), icon_color, 4.0)
		return

	draw_colored_polygon(PackedVector2Array([
		Vector2(0, y_offset - 15),
		Vector2(16, y_offset - 2),
		Vector2(10, y_offset + 16),
		Vector2(-10, y_offset + 16),
		Vector2(-16, y_offset - 2)
	]), icon_color)
	draw_polyline(PackedVector2Array([
		Vector2(0, y_offset - 15),
		Vector2(16, y_offset - 2),
		Vector2(10, y_offset + 16),
		Vector2(-10, y_offset + 16),
		Vector2(-16, y_offset - 2),
		Vector2(0, y_offset - 15)
	]), EDGE_COLOR, 3.0)

func _draw_animator_label(mask_name: String, animation_name: String) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return

	var label_color := Color(0.92, 0.96, 1.0, 1.0)
	var background := Color(0.02, 0.025, 0.035, 0.72)
	draw_rect(Rect2(Vector2(-92, -112), Vector2(184, 33)), background, true)
	draw_rect(Rect2(Vector2(-92, -112), Vector2(184, 33)), _mask_icon_color(mask_name), false, 2.0)
	draw_string(font, Vector2(-86, -98), "Mask: %s" % mask_name, HORIZONTAL_ALIGNMENT_LEFT, 172.0, 11, label_color)
	draw_string(font, Vector2(-86, -84), "Anim: %s" % animation_name, HORIZONTAL_ALIGNMENT_LEFT, 172.0, 11, label_color)

func _draw_mask_health(active_mask_name: String) -> void:
	if player == null or not player.has_method("get_mask_health") or not player.has_method("get_max_mask_health"):
		return

	var max_health := int(player.get_max_mask_health())
	var row_names := ["no_mask", "euda_mask", "ghost_mask"]
	var row_colors := [NO_MASK_COLOR, EUDA_MASK_COLOR, GHOST_MASK_COLOR]
	for row in row_names.size():
		var row_y := -72.0 + row * 10.0
		var row_color: Color = row_colors[row]
		var health := int(player.get_mask_health(row))
		var active_alpha := 1.0 if row_names[row] == active_mask_name else 0.38
		for index in max_health:
			var pip_color := row_color if index < health else Color(0.1, 0.11, 0.14, 0.72)
			pip_color.a *= active_alpha
			draw_circle(Vector2(-28.0 + index * 12.0, row_y), 3.5, pip_color)
			draw_circle(Vector2(-28.0 + index * 12.0, row_y), 3.5, Color(0.02, 0.03, 0.04, active_alpha), false, 1.4)

func _draw_mask_switch_cutscene(mask_name: String, progress: float) -> void:
	var eased := _ease_out_cubic(progress)
	var ring_color := _mask_icon_color(mask_name)
	ring_color.a = 1.0 - progress * 0.35
	var radius := lerpf(24.0, 78.0, eased)
	draw_arc(Vector2(0, -20), radius, 0.0, TAU, 48, ring_color, 4.0, true)
	draw_arc(Vector2(0, -20), radius * 0.65, -PI * progress, TAU - PI * progress, 48, Color(1.0, 1.0, 1.0, 0.65), 2.0, true)

	var bar_color := Color(0.02, 0.025, 0.035, 0.86 * (1.0 - progress * 0.35))
	draw_rect(Rect2(Vector2(-96, -144), Vector2(192, 14)), bar_color, true)
	draw_rect(Rect2(Vector2(-96, 36), Vector2(192, 14)), bar_color, true)

	var font: Font = ThemeDB.fallback_font
	if font != null:
		draw_string(font, Vector2(-70, 30), "mask_switch_cutscene", HORIZONTAL_ALIGNMENT_LEFT, 140.0, 12, Color(1.0, 0.96, 0.72, 1.0))

func _mask_state_name() -> String:
	if player != null and player.has_method("get_mask_state_name"):
		return player.get_mask_state_name()
	return "no_mask"

func _animation_name() -> String:
	if player != null and player.has_method("get_current_animation_name"):
		return player.get_current_animation_name()
	return "no_mask_idle"

func _mask_switch_progress() -> float:
	if player != null and player.has_method("get_mask_switch_progress"):
		return float(player.get_mask_switch_progress())
	return 1.0

func _damage_invulnerable() -> bool:
	return player != null and player.has_method("is_damage_invulnerable") and bool(player.is_damage_invulnerable())

func _body_color(mask_name: String) -> Color:
	match mask_name:
		"euda_mask":
			return EUDA_MASK_COLOR
		"ghost_mask":
			return GHOST_MASK_COLOR
		_:
			return NO_MASK_COLOR

func _mask_icon_color(mask_name: String) -> Color:
	match mask_name:
		"euda_mask":
			return Color(0.78, 1.0, 0.42, 1.0)
		"ghost_mask":
			return Color(0.72, 0.92, 1.0, 1.0)
		_:
			return Color(1.0, 0.86, 0.2, 1.0)

func _ease_out_cubic(value: float) -> float:
	var shifted := 1.0 - clampf(value, 0.0, 1.0)
	return 1.0 - shifted * shifted * shifted
