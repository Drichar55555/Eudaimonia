@tool
extends Area2D

@export var glow_color := Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		glow_color = value
		_update_light()
		queue_redraw()
@export_range(0.0, 12.0, 0.05) var light_energy := 6.2:
	set(value):
		light_energy = value
		_update_light()
@export_range(0.2, 10.0, 0.05) var light_scale := 3.4:
	set(value):
		light_scale = value
		_update_light()
@export_range(12.0, 240.0, 1.0) var glow_radius := 92.0:
	set(value):
		glow_radius = value
		queue_redraw()

var _light: PointLight2D
var _texture: Texture2D

func _ready() -> void:
	_hide_collision_visuals()
	_ensure_light()
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, glow_radius * 0.24, Color(1.0, 1.0, 1.0, 1.0))

func _ensure_light() -> void:
	_light = get_node_or_null("ReturnGateLight") as PointLight2D
	if _light == null:
		_light = PointLight2D.new()
		_light.name = "ReturnGateLight"
		add_child(_light)
	_update_light()

func _update_light() -> void:
	if _light == null:
		return
	if _texture == null:
		_texture = _make_radial_light_texture(256)
	_light.texture = _texture
	_light.color = glow_color
	_light.energy = light_energy
	_light.texture_scale = light_scale
	_light.range_z_min = -100
	_light.range_z_max = 100
	_light.z_index = 20
	_light.z_as_relative = false
	_light.enabled = true

func _hide_collision_visuals() -> void:
	for child in get_children():
		if child is CanvasItem and child.name != "ReturnGateLight":
			(child as CanvasItem).visible = false
		if child is CollisionShape2D:
			(child as CollisionShape2D).debug_color = Color(1.0, 1.0, 1.0, 0.0)

func _make_radial_light_texture(size: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var radius := float(size) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(x, y).distance_to(center) / radius
			var alpha := pow(clampf(1.0 - distance, 0.0, 1.0), 1.9)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)
