@tool
extends "res://scripts/save_point.gd"

enum SoulMask { EUDA_MASK = 1, GHOST_MASK = 2 }

@export_group("Soul")
@export_enum("Euda Mask", "Ghost Mask") var soul_mask_state := 0:
	set(value):
		soul_mask_state = value
		_update_soul_colors()
		queue_redraw()

@export_group("Soul Lamp Visual")
@export var lamp_color := Color(0.22, 0.28, 0.26, 1.0):
	set(value):
		lamp_color = value
		queue_redraw()
@export var lamp_edge_color := Color(0.07, 0.09, 0.08, 0.9):
	set(value):
		lamp_edge_color = value
		queue_redraw()
@export var flame_color := Color(0.56, 0.92, 1.0, 0.9):
	set(value):
		flame_color = value
		queue_redraw()
@export var glow_color := Color(0.42, 0.82, 1.0, 0.18):
	set(value):
		glow_color = value
		queue_redraw()
@export_group("Lighting")
@export var emit_blue_light := true:
	set(value):
		emit_blue_light = value
		_update_light()
@export var soul_light_color := Color(0.36, 0.72, 1.0, 1.0):
	set(value):
		soul_light_color = value
		_update_light()
@export_range(0.0, 4.0, 0.05) var soul_light_energy := 1.45:
	set(value):
		soul_light_energy = maxf(value, 0.0)
		_update_light()
@export_range(0.2, 8.0, 0.05) var soul_light_scale := 2.6:
	set(value):
		soul_light_scale = maxf(value, 0.01)
		_update_light()
@export_range(-4096, 4096, 1) var soul_light_z_min := -100:
	set(value):
		soul_light_z_min = value
		_update_light()
@export_range(-4096, 4096, 1) var soul_light_z_max := 1:
	set(value):
		soul_light_z_max = value
		_update_light()
@export var base_height := 88.0:
	set(value):
		base_height = maxf(value, 24.0)
		_update_light_position()
		queue_redraw()
@export var lamp_width := 36.0:
	set(value):
		lamp_width = maxf(value, 14.0)
		queue_redraw()

var _soul_light: PointLight2D
var _soul_light_texture: Texture2D

func _ready() -> void:
	_update_soul_colors()
	super._ready()
	_ensure_soul_light()

func _try_start_save(player: Node) -> void:
	_restore_player_energy(player)
	super._try_start_save(player)

func _restore_player_energy(player: Node) -> void:
	if player != null and player.has_method("restore_soul_lamp_energy"):
		player.call("restore_soul_lamp_energy", _mask_state_value())

func _mask_state_value() -> int:
	return SoulMask.GHOST_MASK if soul_mask_state == 1 else SoulMask.EUDA_MASK

func _update_soul_colors() -> void:
	if soul_mask_state == 1:
		flame_color = Color(0.72, 0.92, 1.0, 0.95)
		glow_color = Color(0.50, 0.72, 1.0, 0.18)
		return
	flame_color = Color(0.64, 0.90, 1.0, 0.95)
	glow_color = Color(0.42, 0.82, 1.0, 0.18)

func _ensure_soul_light() -> void:
	_soul_light = get_node_or_null("SoulLight") as PointLight2D
	if _soul_light == null:
		_soul_light = PointLight2D.new()
		_soul_light.name = "SoulLight"
		add_child(_soul_light)
	_update_light_position()
	_update_light()

func _update_light_position() -> void:
	if _soul_light != null:
		_soul_light.position = Vector2(0.0, -base_height - 8.0)

func _update_light() -> void:
	if _soul_light == null:
		return
	_soul_light.enabled = emit_blue_light
	_soul_light.color = soul_light_color
	_soul_light.energy = soul_light_energy
	_soul_light.texture_scale = soul_light_scale
	_soul_light.range_z_min = soul_light_z_min
	_soul_light.range_z_max = soul_light_z_max
	_soul_light.z_index = 1
	_soul_light.z_as_relative = false
	if _soul_light_texture == null:
		_soul_light_texture = _make_radial_light_texture(256)
	_soul_light.texture = _soul_light_texture

func _make_radial_light_texture(size: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var radius := float(size) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(x, y).distance_to(center) / radius
			var alpha := pow(clampf(1.0 - distance, 0.0, 1.0), 1.8)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)

func _draw() -> void:
	_draw_lamp()
	_draw_save_radius()

func _draw_lamp() -> void:
	var post_top := Vector2(0.0, -base_height)
	var post_bottom := Vector2(0.0, 0.0)
	draw_line(post_bottom, post_top, lamp_edge_color, 6.0, true)
	draw_line(post_bottom + Vector2(-16.0, 0.0), post_bottom + Vector2(16.0, 0.0), lamp_edge_color, 5.0, true)
	draw_line(post_bottom + Vector2(-10.0, -10.0), post_bottom + Vector2(10.0, -10.0), lamp_color, 7.0, true)

	var head_center := post_top + Vector2(0.0, -12.0)
	var half_width := lamp_width * 0.5
	var lamp_points := PackedVector2Array([
		head_center + Vector2(-half_width, -10.0),
		head_center + Vector2(half_width, -10.0),
		head_center + Vector2(half_width * 0.72, 16.0),
		head_center + Vector2(-half_width * 0.72, 16.0),
	])
	draw_colored_polygon(lamp_points, lamp_color)
	var closed := PackedVector2Array(lamp_points)
	closed.append(lamp_points[0])
	draw_polyline(closed, lamp_edge_color, 3.0, true)

	draw_circle(head_center + Vector2(0.0, 4.0), half_width * 1.6, glow_color)
	draw_circle(head_center + Vector2(0.0, 4.0), half_width * 0.42, flame_color)
	draw_circle(head_center + Vector2(0.0, 4.0), half_width * 0.16, Color(1.0, 1.0, 1.0, 0.82))

func _draw_save_radius() -> void:
	if Engine.is_editor_hint():
		if not show_editor_visual:
			return
	elif not show_runtime_visual:
		return
	var outline := debug_color
	outline.a = minf(debug_color.a + 0.45, 1.0)
	draw_circle(Vector2.ZERO, debug_radius, debug_color)
	draw_arc(Vector2.ZERO, debug_radius, 0.0, TAU, 48, outline, 3.0, true)
