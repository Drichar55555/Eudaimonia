extends Sprite2D

@export var camera_group := "room_cameras"
@export var screen_offset := Vector2.ZERO
@export var fit_to_camera_view := true
@export_range(1.0, 2.0, 0.01) var cover_margin := 1.04
@export_group("Background Light")
@export var emit_background_light := true:
	set(value):
		emit_background_light = value
		_update_background_light()
@export var background_light_color := Color(1.0, 0.82, 0.46, 1.0):
	set(value):
		background_light_color = value
		_update_background_light()
@export_range(0.0, 2.0, 0.02) var background_light_energy := 0.26:
	set(value):
		background_light_energy = maxf(value, 0.0)
		_update_background_light()

var _has_reference := false
var _background_light: PointLight2D
var _background_light_texture: Texture2D

func _ready() -> void:
	var camera := _current_camera()
	if camera != null:
		_capture_reference(camera)
	_ensure_background_light()
	set_process(not Engine.is_editor_hint())

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var camera := _current_camera()
	if camera == null:
		return
	if not _has_reference:
		_capture_reference(camera)

	global_position = camera.global_position + Vector2(
		screen_offset.x / maxf(camera.zoom.x, 0.001),
		screen_offset.y / maxf(camera.zoom.y, 0.001)
	)
	_fit_to_camera_view(camera)
	if _background_light != null:
		_background_light.position = Vector2.ZERO

func _capture_reference(_camera: Camera2D) -> void:
	_has_reference = true

func _fit_to_camera_view(camera: Camera2D) -> void:
	if not fit_to_camera_view or texture == null:
		return
	var texture_size := texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var viewport_size := get_viewport_rect().size
	var view_size := Vector2(
		viewport_size.x / maxf(camera.zoom.x, 0.001),
		viewport_size.y / maxf(camera.zoom.y, 0.001)
	)
	var cover_scale := maxf(view_size.x / texture_size.x, view_size.y / texture_size.y) * cover_margin
	scale = Vector2.ONE * cover_scale
	_update_background_light_scale(view_size)

func _ensure_background_light() -> void:
	_background_light = get_node_or_null("BackgroundLight") as PointLight2D
	if _background_light == null:
		_background_light = PointLight2D.new()
		_background_light.name = "BackgroundLight"
		add_child(_background_light)
	_update_background_light()

func _update_background_light() -> void:
	if _background_light == null:
		return
	_background_light.enabled = emit_background_light
	_background_light.color = background_light_color
	_background_light.energy = background_light_energy
	_background_light.range_z_min = -1000
	_background_light.range_z_max = 1
	_background_light.z_index = -10
	_background_light.z_as_relative = false
	if _background_light_texture == null:
		_background_light_texture = _make_radial_light_texture(256, 1.25)
	_background_light.texture = _background_light_texture

func _update_background_light_scale(view_size: Vector2) -> void:
	if _background_light == null:
		return
	_background_light.texture_scale = maxf(view_size.x, view_size.y) / 128.0

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

func _current_camera() -> Camera2D:
	for camera in get_tree().get_nodes_in_group(camera_group):
		if camera is Camera2D and (camera as Camera2D).is_current():
			return camera as Camera2D
	var viewport_camera := get_viewport().get_camera_2d()
	if viewport_camera != null:
		return viewport_camera
	for camera in get_tree().get_nodes_in_group(camera_group):
		if camera is Camera2D:
			return camera as Camera2D
	return null
