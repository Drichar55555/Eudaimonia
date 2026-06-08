extends Node2D

@export var room_group := "camera_rooms"
@export var light_color := Color(1.0, 0.86, 0.58, 1.0)
@export_range(0.0, 2.0, 0.02) var light_energy := 0.34
@export_range(0.5, 2.0, 0.05) var room_size_factor := 1.15
@export_range(-4096, 4096, 1) var light_z_min := -100
@export_range(-4096, 4096, 1) var light_z_max := 2

var _light_texture: Texture2D

func _ready() -> void:
	z_index = 1
	z_as_relative = false
	visible = false

func rebuild_lights() -> void:
	_clear_existing_lights()
	if _light_texture == null:
		_light_texture = _make_radial_light_texture(256, 1.35)
	var index := 0
	for room in get_tree().get_nodes_in_group(room_group):
		var room_node := room as Node2D
		if room_node == null:
			continue
		var room_rect := _room_rect(room_node)
		if room_rect.size.x <= 0.0 or room_rect.size.y <= 0.0:
			continue
		var light := PointLight2D.new()
		light.name = "RoomFillLight%d" % index
		light.global_position = room_rect.get_center()
		light.color = light_color
		light.energy = light_energy
		light.texture = _light_texture
		light.texture_scale = maxf(room_rect.size.x, room_rect.size.y) / 256.0 * room_size_factor
		light.range_z_min = light_z_min
		light.range_z_max = light_z_max
		light.z_index = 1
		light.z_as_relative = false
		add_child(light)
		index += 1

func _clear_existing_lights() -> void:
	for child in get_children():
		if child is PointLight2D:
			child.queue_free()

func _room_rect(room: Node2D) -> Rect2:
	if room.has_method("get_camera_rect"):
		return room.call("get_camera_rect") as Rect2
	var collision_shape := room.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null and collision_shape.shape != null:
		return _global_bounds_for_shape(room, collision_shape)
	return Rect2(room.global_position, Vector2.ZERO)

func _global_bounds_for_shape(room: Node2D, collision_shape: CollisionShape2D) -> Rect2:
	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle != null:
		var half_size := rectangle.size * 0.5
		var points := [
			Vector2(-half_size.x, -half_size.y),
			Vector2(half_size.x, -half_size.y),
			Vector2(half_size.x, half_size.y),
			Vector2(-half_size.x, half_size.y),
		]
		var bounds := Rect2(collision_shape.to_global(points[0]), Vector2.ZERO)
		for point in points:
			bounds = bounds.expand(collision_shape.to_global(point))
		return bounds
	return Rect2(room.global_position, Vector2.ZERO)

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
