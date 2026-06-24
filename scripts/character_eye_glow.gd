extends Node2D

@export var left_eye_point_path := NodePath("LeftEyePoint")
@export var right_eye_point_path := NodePath("RightEyePoint")
@export var left_eye_position := Vector2(-12.0, -126.0):
	set(value):
		left_eye_position = value
		_update_lights()
		queue_redraw()
@export var right_eye_position := Vector2(12.0, -126.0):
	set(value):
		right_eye_position = value
		_update_lights()
		queue_redraw()
@export var glow_color := Color(1.0, 0.46, 0.08, 1.0):
	set(value):
		glow_color = value
		_update_lights()
		queue_redraw()
@export var left_eye_enabled := true:
	set(value):
		left_eye_enabled = value
		_update_lights()
		queue_redraw()
@export var right_eye_enabled := true:
	set(value):
		right_eye_enabled = value
		_update_lights()
		queue_redraw()
@export_range(0.0, 3.0, 0.01) var light_energy := 0.16:
	set(value):
		light_energy = value
		_update_lights()
@export_range(0.05, 2.0, 0.01) var light_scale := 0.18:
	set(value):
		light_scale = value
		_update_lights()
@export_range(0.0, 12.0, 0.1) var core_radius := 1.2:
	set(value):
		core_radius = value
		queue_redraw()
@export_range(0.0, 48.0, 0.5) var halo_radius := 6.0:
	set(value):
		halo_radius = value
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var pulse_strength := 0.04
@export_range(0.0, 8.0, 0.1) var pulse_speed := 1.2
@export_range(0.0, 1.0, 0.01) var surface_alpha := 0.12
@export_range(0.0, 1.0, 0.01) var core_alpha := 0.18
@export_range(0.0, 24.0, 0.1) var merge_distance := 5.0:
	set(value):
		merge_distance = value
		_update_lights()
		queue_redraw()
@export_range(0.0, 1.0, 0.01) var merged_light_multiplier := 0.75:
	set(value):
		merged_light_multiplier = value
		_update_lights()
		queue_redraw()
@export var mirror_horizontally := false:
	set(value):
		mirror_horizontally = value
		_update_lights()
		queue_redraw()
@export var mirror_axis_x := 2.0:
	set(value):
		mirror_axis_x = value
		_update_lights()
		queue_redraw()

var _left_light: PointLight2D
var _right_light: PointLight2D
var _light_texture: Texture2D
var _left_eye_point: Node2D
var _right_eye_point: Node2D
var _time := 0.0

func _ready() -> void:
	z_index = 6
	z_as_relative = true
	var additive_material := CanvasItemMaterial.new()
	additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive_material
	_left_eye_point = get_node_or_null(left_eye_point_path) as Node2D
	_right_eye_point = get_node_or_null(right_eye_point_path) as Node2D
	_light_texture = _make_radial_light_texture(128, 2.2)
	_left_light = _make_eye_light("LeftEyeLight")
	_right_light = _make_eye_light("RightEyeLight")
	_update_lights()
	set_process(not Engine.is_editor_hint())
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	_update_lights()
	queue_redraw()

func _draw() -> void:
	var pulse := _pulse_amount()
	var left_position := _left_eye_position()
	var right_position := _right_eye_position()
	if left_eye_enabled and right_eye_enabled and _eyes_are_merged(left_position, right_position):
		_draw_eye(left_position.lerp(right_position, 0.5), pulse, merged_light_multiplier)
		return
	if left_eye_enabled:
		_draw_eye(left_position, pulse, 1.0)
	if right_eye_enabled:
		_draw_eye(right_position, pulse, 1.0)

func _draw_eye(position_value: Vector2, pulse: float, intensity: float) -> void:
	if halo_radius <= 0.0 and core_radius <= 0.0:
		return
	var halo_color := glow_color
	if halo_radius > 0.0 and surface_alpha > 0.0:
		for layer in 8:
			var layer_progress := float(layer) / 7.0
			var radius := lerpf(halo_radius * (1.0 + pulse * 0.18), maxf(core_radius, 0.1), layer_progress)
			halo_color.a = lerpf(surface_alpha * 0.08, surface_alpha, layer_progress) * (1.0 + pulse) * intensity
			draw_circle(position_value, radius, halo_color)
	if core_radius > 0.0 and core_alpha > 0.0:
		var core_color := glow_color.lerp(Color(1.0, 0.78, 0.36, 1.0), 0.28)
		core_color.a = core_alpha * (1.0 + pulse * 0.2) * intensity
		draw_circle(position_value, core_radius * (1.0 + pulse * 0.1), core_color)

func _make_eye_light(light_name: String) -> PointLight2D:
	var eye_light := PointLight2D.new()
	eye_light.name = light_name
	eye_light.texture = _light_texture
	eye_light.range_z_min = -100
	eye_light.range_z_max = 100
	add_child(eye_light)
	return eye_light

func _update_lights() -> void:
	if _left_light == null or _right_light == null:
		return
	var pulse := _pulse_amount()
	var left_position := _left_eye_position()
	var right_position := _right_eye_position()
	if left_eye_enabled and right_eye_enabled and _eyes_are_merged(left_position, right_position):
		var merged_position := left_position.lerp(right_position, 0.5)
		_apply_eye_light(_left_light, merged_position, pulse, merged_light_multiplier)
		_right_light.enabled = false
		return
	if left_eye_enabled:
		_apply_eye_light(_left_light, left_position, pulse, 1.0)
	else:
		_left_light.enabled = false
	if right_eye_enabled:
		_apply_eye_light(_right_light, right_position, pulse, 1.0)
	else:
		_right_light.enabled = false

func _apply_eye_light(eye_light: PointLight2D, eye_position: Vector2, pulse: float, intensity: float) -> void:
	eye_light.position = eye_position
	eye_light.color = glow_color
	eye_light.energy = light_energy * (1.0 + pulse) * intensity
	eye_light.texture_scale = light_scale * (1.0 + pulse * 0.12)
	eye_light.enabled = visible and intensity > 0.0

func _eyes_are_merged(left_position: Vector2, right_position: Vector2) -> bool:
	return merge_distance > 0.0 and left_position.distance_to(right_position) <= merge_distance

func _left_eye_position() -> Vector2:
	var eye_position := _left_eye_point.position if _left_eye_point != null else left_eye_position
	return _mirrored_eye_position(eye_position)

func _right_eye_position() -> Vector2:
	var eye_position := _right_eye_point.position if _right_eye_point != null else right_eye_position
	return _mirrored_eye_position(eye_position)

func _mirrored_eye_position(eye_position: Vector2) -> Vector2:
	if not mirror_horizontally:
		return eye_position
	return Vector2(mirror_axis_x * 2.0 - eye_position.x, eye_position.y)

func _pulse_amount() -> float:
	if pulse_strength <= 0.0 or pulse_speed <= 0.0:
		return 0.0
	return (0.5 + 0.5 * sin(_time * pulse_speed)) * pulse_strength

func _make_radial_light_texture(size: int, falloff: float) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var radius := float(size) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(x, y).distance_to(center) / radius
			var alpha := pow(clampf(1.0 - distance, 0.0, 1.0), falloff)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)