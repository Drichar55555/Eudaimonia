@tool
extends Polygon2D

const MIN_TRIANGLE_WIDTH := 16.0
const MIN_TRIANGLE_HEIGHT := 8.0

@export_group("Shape")
@export var collision_body_path: NodePath = NodePath("CollisionBody")
@export var triangle_size := Vector2(192.0, -96.0):
	set(value):
		triangle_size = _normalized_triangle_size(value)
		if not _syncing_polygon:
			_write_triangle(_points_from_size(triangle_size))
		_rebuild_stairs()
@export var snap_triangle_in_editor := true:
	set(value):
		snap_triangle_in_editor = true if value == null else value == true
		snap_triangle_now()
@export_range(4.0, 64.0, 1.0) var snap_grid := 16.0:
	set(value):
		snap_grid = maxf(float(value), 1.0)
		snap_triangle_now()

@export_group("Steps")
@export_range(4.0, 28.0, 1.0) var target_step_height := 12.0:
	set(value):
		target_step_height = maxf(float(value), 1.0)
		_rebuild_stairs()
@export_range(8.0, 48.0, 1.0) var max_step_width := 24.0:
	set(value):
		max_step_width = maxf(float(value), 1.0)
		_rebuild_stairs()

@export_group("Visual")
@export_range(-4096, 4096, 1) var display_z_index := 0:
	set(value):
		display_z_index = int(value)
		_apply_display_layer()
@export var fill_color := Color(0.18, 0.18, 0.17, 0.72):
	set(value):
		fill_color = value
		queue_redraw()
@export var outline_color := Color(0.56, 0.52, 0.43, 0.95):
	set(value):
		outline_color = value
		queue_redraw()
@export_range(0.0, 8.0, 0.5) var outline_width := 2.0:
	set(value):
		outline_width = maxf(float(value), 0.0)
		queue_redraw()

var _last_triangle := PackedVector2Array()
var _syncing_polygon := false

func _ready() -> void:
	add_to_group("editable_stairs")
	color = Color(1.0, 1.0, 1.0, 0.0)
	_apply_display_layer()
	_update_collision_body_marker()
	_sync_from_polygon(true)
	set_process(Engine.is_editor_hint())
	_rebuild_stairs()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_from_polygon(false)

func _draw() -> void:
	var stair_polygon := get_stair_polygon()
	if stair_polygon.size() < 3:
		return
	draw_colored_polygon(stair_polygon, fill_color)
	if outline_width > 0.0:
		draw_polyline(_closed_polygon(stair_polygon), outline_color, outline_width, true)

func _edit_is_selected_on_click(point: Vector2, tolerance: float) -> bool:
	return is_point_near_stair(point, maxf(tolerance, 8.0))

func get_triangle_points() -> PackedVector2Array:
	if polygon.size() >= 3:
		return PackedVector2Array([polygon[0], polygon[1], polygon[2]])
	return _points_from_size(triangle_size)

func get_stair_polygon() -> PackedVector2Array:
	var triangle := get_triangle_points()
	if triangle.size() < 3:
		return triangle
	var start_point := triangle[0]
	var right_angle := triangle[1]
	var end_point := triangle[2]
	var width := absf(right_angle.x - start_point.x)
	var height := absf(end_point.y - start_point.y)
	if width <= 0.001 or height <= 0.001:
		return triangle

	var horizontal_direction := signf(right_angle.x - start_point.x)
	var vertical_direction := signf(end_point.y - start_point.y)
	var step_count := _step_count(width, height)
	var points := PackedVector2Array()
	points.append(start_point)
	if vertical_direction < 0.0:
		for step_index in range(1, step_count + 1):
			var previous_x := start_point.x + horizontal_direction * width * float(step_index - 1) / float(step_count)
			var current_x := start_point.x + horizontal_direction * width * float(step_index) / float(step_count)
			var current_y := start_point.y + vertical_direction * height * float(step_index) / float(step_count)
			points.append(Vector2(previous_x, current_y))
			points.append(Vector2(current_x, current_y))
		points.append(right_angle)
	else:
		for step_index in range(1, step_count + 1):
			var previous_y := start_point.y + vertical_direction * height * float(step_index - 1) / float(step_count)
			var current_x := start_point.x + horizontal_direction * width * float(step_index) / float(step_count)
			var current_y := start_point.y + vertical_direction * height * float(step_index) / float(step_count)
			points.append(Vector2(current_x, previous_y))
			points.append(Vector2(current_x, current_y))
		points.append(Vector2(start_point.x, end_point.y))
	return points

func snap_triangle_now() -> void:
	var points := get_triangle_points()
	if points.size() < 3:
		points = _default_triangle()
	_write_triangle(_normalized_triangle_points(points, -1))
	_sync_from_polygon(true)

func set_triangle_corner_from_editor(corner_index: int, local_position: Vector2) -> void:
	var points := get_triangle_points()
	if points.size() < 3:
		points = _default_triangle()
	if corner_index < 0 or corner_index >= 3:
		return
	points[corner_index] = local_position
	set_triangle_points_from_editor(points, corner_index)

func set_triangle_points_from_editor(points: PackedVector2Array, changed_index := -1) -> void:
	_write_triangle(_normalized_triangle_points(points, changed_index))
	_sync_from_polygon(true)

func is_point_near_stair(local_point: Vector2, radius: float) -> bool:
	var triangle_points := get_triangle_points()
	if Geometry2D.is_point_in_polygon(local_point, triangle_points):
		return true
	for index in range(triangle_points.size()):
		var start_point := triangle_points[index]
		var end_point := triangle_points[(index + 1) % triangle_points.size()]
		if _distance_to_segment(local_point, start_point, end_point) <= radius:
			return true
	return false

func _sync_from_polygon(force: bool) -> void:
	var raw_points := polygon
	if raw_points.size() < 3:
		raw_points = _default_triangle()
	var changed_index := _changed_triangle_point_index(raw_points)
	var normalized_points := _normalized_triangle_points(raw_points, changed_index)
	var changed := force or not _packed_points_equal(raw_points, _last_triangle)
	if not changed:
		return
	if not _packed_points_equal(raw_points, normalized_points):
		_write_triangle(normalized_points)
	else:
		_last_triangle = PackedVector2Array(raw_points)
	_syncing_polygon = true
	triangle_size = normalized_points[2] - normalized_points[0]
	_syncing_polygon = false
	_rebuild_stairs()

func _normalized_triangle_points(raw_points: PackedVector2Array, changed_index: int) -> PackedVector2Array:
	var points := PackedVector2Array(raw_points)
	while points.size() < 3:
		points.append(_default_triangle()[points.size()])
	var start_point := points[0]
	if Engine.is_editor_hint() and snap_triangle_in_editor:
		start_point = _snapped_vector(start_point)

	var width_source := points[1].x - start_point.x
	if changed_index == 2:
		width_source = points[2].x - start_point.x
	elif changed_index == 0 and _last_triangle.size() >= 3:
		width_source = _last_triangle[1].x - _last_triangle[0].x
	var height_source := points[2].y - start_point.y
	if changed_index == 1 and _last_triangle.size() >= 3:
		height_source = _last_triangle[2].y - _last_triangle[0].y

	var normalized_size := _normalized_triangle_size(Vector2(width_source, height_source))
	return PackedVector2Array([
		start_point,
		start_point + Vector2(normalized_size.x, 0.0),
		start_point + normalized_size,
	])

func _write_triangle(points: PackedVector2Array) -> void:
	_syncing_polygon = true
	polygon = points
	_last_triangle = PackedVector2Array(points)
	_syncing_polygon = false
	queue_redraw()

func _rebuild_stairs() -> void:
	_apply_display_layer()
	_update_collision_body_marker()
	_rebuild_collision_shapes()
	queue_redraw()

func _rebuild_collision_shapes() -> void:
	var collision_body := _collision_body()
	if collision_body == null:
		return
	_remove_legacy_root_step_collisions()
	var rects := _step_collision_rects()
	for index in range(rects.size()):
		var collision_shape := _get_or_create_step_collision(collision_body, index)
		var rectangle_shape := RectangleShape2D.new()
		rectangle_shape.size = rects[index].size
		collision_shape.shape = rectangle_shape
		collision_shape.position = rects[index].position + rects[index].size * 0.5
		collision_shape.disabled = false
	_remove_extra_step_collisions(collision_body, rects.size())

func _step_collision_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var triangle := get_triangle_points()
	if triangle.size() < 3:
		return rects
	var start_point := triangle[0]
	var right_angle := triangle[1]
	var end_point := triangle[2]
	var width := absf(right_angle.x - start_point.x)
	var height := absf(end_point.y - start_point.y)
	if width <= 0.001 or height <= 0.001:
		return rects
	var horizontal_direction := signf(right_angle.x - start_point.x)
	var vertical_direction := signf(end_point.y - start_point.y)
	var step_count := _step_count(width, height)
	for step_index in range(1, step_count + 1):
		var previous_x := start_point.x + horizontal_direction * width * float(step_index - 1) / float(step_count)
		var current_x := start_point.x + horizontal_direction * width * float(step_index) / float(step_count)
		var top_y := 0.0
		var bottom_y := 0.0
		if vertical_direction < 0.0:
			top_y = start_point.y + vertical_direction * height * float(step_index) / float(step_count)
			bottom_y = start_point.y
		else:
			top_y = start_point.y + vertical_direction * height * float(step_index - 1) / float(step_count)
			bottom_y = end_point.y
		var left := minf(previous_x, current_x)
		var right := maxf(previous_x, current_x)
		var top := minf(top_y, bottom_y)
		var bottom := maxf(top_y, bottom_y)
		var rect_size := Vector2(right - left, bottom - top)
		if rect_size.x > 0.001 and rect_size.y > 0.001:
			rects.append(Rect2(Vector2(left, top), rect_size))
	return rects

func _get_or_create_step_collision(collision_body: StaticBody2D, index: int) -> CollisionShape2D:
	var node_name := "StepCollision%d" % index
	var collision_shape := collision_body.get_node_or_null(node_name) as CollisionShape2D
	if collision_shape != null:
		return collision_shape
	collision_shape = CollisionShape2D.new()
	collision_shape.name = node_name
	collision_shape.set_meta("generated_stair_collision", true)
	collision_body.add_child(collision_shape)
	return collision_shape

func _remove_extra_step_collisions(collision_body: StaticBody2D, first_extra_index: int) -> void:
	var index := first_extra_index
	while true:
		var node_name := "StepCollision%d" % index
		var collision_shape := collision_body.get_node_or_null(node_name) as CollisionShape2D
		if collision_shape == null:
			break
		collision_body.remove_child(collision_shape)
		collision_shape.queue_free()
		index += 1

func _remove_legacy_root_step_collisions() -> void:
	for child in get_children():
		if child is CollisionShape2D and child.name.begins_with("StepCollision"):
			remove_child(child)
			child.queue_free()

func _apply_display_layer() -> void:
	z_as_relative = false
	z_index = display_z_index

func _normalized_triangle_size(raw_size: Vector2) -> Vector2:
	var normalized := raw_size
	if Engine.is_editor_hint() and snap_triangle_in_editor:
		normalized.x = roundf(normalized.x / snap_grid) * snap_grid
		normalized.y = roundf(normalized.y / snap_grid) * snap_grid
	if absf(normalized.x) < MIN_TRIANGLE_WIDTH:
		normalized.x = MIN_TRIANGLE_WIDTH * _non_zero_sign(normalized.x, 1.0)
	if absf(normalized.y) < MIN_TRIANGLE_HEIGHT:
		normalized.y = MIN_TRIANGLE_HEIGHT * _non_zero_sign(normalized.y, -1.0)
	return normalized

func _points_from_size(size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size])

func _default_triangle() -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(192.0, 0.0), Vector2(192.0, -96.0)])

func _step_count(width: float, height: float) -> int:
	var height_steps := ceili(height / maxf(target_step_height, 1.0))
	var width_steps := ceili(width / maxf(max_step_width, 1.0))
	return maxi(1, maxi(height_steps, width_steps))

func _closed_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var closed_points := PackedVector2Array(points)
	if not closed_points.is_empty():
		closed_points.append(closed_points[0])
	return closed_points

func _collision_body() -> StaticBody2D:
	return get_node_or_null(collision_body_path) as StaticBody2D

func _update_collision_body_marker() -> void:
	var collision_body := _collision_body()
	if collision_body == null:
		return
	collision_body.add_to_group("stair_collision_bodies")
	collision_body.set_meta("is_stair_collision", true)

func _changed_triangle_point_index(raw_points: PackedVector2Array) -> int:
	if raw_points.size() < 3 or _last_triangle.size() < 3:
		return -1
	var best_index := -1
	var best_distance := 0.0
	for index in range(3):
		var distance := raw_points[index].distance_squared_to(_last_triangle[index])
		if distance > best_distance:
			best_index = index
			best_distance = distance
	return best_index

func _snapped_vector(value: Vector2) -> Vector2:
	return Vector2(roundf(value.x / snap_grid) * snap_grid, roundf(value.y / snap_grid) * snap_grid)

func _packed_points_equal(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for index in range(a.size()):
		if a[index].distance_squared_to(b[index]) > 0.001:
			return false
	return true

func _distance_to_segment(point: Vector2, start_point: Vector2, end_point: Vector2) -> float:
	var segment := end_point - start_point
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start_point)
	var progress := clampf((point - start_point).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start_point + segment * progress)

func _non_zero_sign(value: float, fallback: float) -> float:
	if is_zero_approx(value):
		return fallback
	return signf(value)
