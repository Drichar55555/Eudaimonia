@tool
extends StaticBody2D

const TERRAIN_LAYER := 1 << 0

@export_group("Damage")
@export_range(0, 6, 1) var damage := 1
@export_range(0.05, 5.0, 0.05, "suffix:s") var damage_interval := 1.0
@export var knockback := Vector2(180.0, -140.0)
@export_range(0.0, 64.0, 1.0) var contact_padding := 18.0

@export_group("Movement")
@export_range(0.05, 1.0, 0.05) var top_walk_speed_multiplier := 0.55
@export_range(0.0, 1.0, 0.05) var top_normal_threshold := 0.45

@export_group("Visual")
@export var show_temporary_visual := true:
	set(value):
		show_temporary_visual = value
		queue_redraw()
@export var fill_color := Color(0.32, 0.34, 0.32, 1.0):
	set(value):
		fill_color = value
		queue_redraw()
@export var edge_color := Color(0.08, 0.10, 0.10, 0.65):
	set(value):
		edge_color = value
		queue_redraw()
@export_range(0.0, 8.0, 0.25) var outline_width := 2.0:
	set(value):
		outline_width = value
		queue_redraw()

var _damage_cooldowns := {}

func _ready() -> void:
	add_to_group("spike_blocks")
	collision_layer = TERRAIN_LAYER
	collision_mask = 0
	set_process(Engine.is_editor_hint())
	set_physics_process(not Engine.is_editor_hint())
	queue_redraw()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()

func _physics_process(delta: float) -> void:
	_update_damage_cooldowns(delta)
	for player in get_tree().get_nodes_in_group("players"):
		var player_body := player as Node2D
		if player_body == null or not is_instance_valid(player_body):
			continue
		if not _player_feet_are_near_top(player_body):
			continue
		_apply_slow(player_body)
		_apply_damage_if_ready(player_body)

func _draw() -> void:
	if not show_temporary_visual:
		return
	for collision_polygon in _collision_polygons():
		var points := _transformed_polygon(collision_polygon)
		_draw_fill(points, fill_color)
		_draw_outline(points, edge_color, outline_width)

func _apply_damage_if_ready(player_body: Node2D) -> void:
	if damage <= 0 or not player_body.has_method("take_environment_hit"):
		return
	var body_id := player_body.get_instance_id()
	if _damage_cooldowns.has(body_id):
		return
	var direction := (player_body.global_position - global_position).normalized()
	if direction.length_squared() <= 0.001:
		direction = Vector2.UP
	var did_hit := bool(player_body.call("take_environment_hit", damage, self, direction, knockback))
	if did_hit:
		_damage_cooldowns[body_id] = damage_interval

func _apply_slow(player_body: Node2D) -> void:
	if not player_body.has_method("apply_ground_speed_multiplier"):
		return
	player_body.call("apply_ground_speed_multiplier", top_walk_speed_multiplier)

func _player_feet_are_near_top(player_body: Node2D) -> bool:
	var half_size := _player_half_size(player_body)
	var feet_y := player_body.global_position.y + half_size.y
	var foot_left := player_body.global_position + Vector2(-half_size.x * 0.7, half_size.y)
	var foot_right := player_body.global_position + Vector2(half_size.x * 0.7, half_size.y)
	var foot_center := player_body.global_position + Vector2(0.0, half_size.y)
	for collision_polygon in _collision_polygons():
		var points := _global_polygon(collision_polygon)
		var bounds := _polygon_bounds(points)
		if maxf(foot_left.x, foot_right.x) < bounds.position.x or minf(foot_left.x, foot_right.x) > bounds.end.x:
			continue
		if feet_y < bounds.position.y - contact_padding or feet_y > bounds.position.y + contact_padding:
			continue
		if _distance_to_polygon(foot_center, points) <= contact_padding or _distance_to_polygon(foot_left, points) <= contact_padding or _distance_to_polygon(foot_right, points) <= contact_padding:
			return true
	return false

func _player_half_size(player_body: Node2D) -> Vector2:
	var collision_shape := player_body.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape != null and collision_shape.shape != null:
		var rectangle := collision_shape.shape as RectangleShape2D
		if rectangle != null:
			return rectangle.size * collision_shape.scale.abs() * 0.5
	return Vector2(18.0, 18.0)

func _update_damage_cooldowns(delta: float) -> void:
	for body_id in _damage_cooldowns.keys().duplicate():
		var remaining := float(_damage_cooldowns[body_id]) - delta
		if remaining <= 0.0:
			_damage_cooldowns.erase(body_id)
		else:
			_damage_cooldowns[body_id] = remaining

func _collision_polygons() -> Array[CollisionPolygon2D]:
	var polygons: Array[CollisionPolygon2D] = []
	for child in get_children():
		var collision_polygon := child as CollisionPolygon2D
		if collision_polygon != null and collision_polygon.polygon.size() >= 3:
			polygons.append(collision_polygon)
	return polygons

func _transformed_polygon(collision_polygon: CollisionPolygon2D) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(collision_polygon.polygon.size())
	for index in collision_polygon.polygon.size():
		points[index] = collision_polygon.transform * collision_polygon.polygon[index]
	return points

func _global_polygon(collision_polygon: CollisionPolygon2D) -> PackedVector2Array:
	var local_points := _transformed_polygon(collision_polygon)
	var points := PackedVector2Array()
	points.resize(local_points.size())
	for index in local_points.size():
		points[index] = to_global(local_points[index])
	return points

func _distance_to_polygon(point: Vector2, points: PackedVector2Array) -> float:
	var best_distance := INF
	for index in points.size():
		var closest := Geometry2D.get_closest_point_to_segment(point, points[index], points[(index + 1) % points.size()])
		best_distance = minf(best_distance, point.distance_to(closest))
	return best_distance

func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2(global_position, Vector2.ZERO)
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds

func _draw_fill(points: PackedVector2Array, color: Color) -> void:
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.size() >= 3:
		for index in range(0, indices.size(), 3):
			_draw_triangle(points[indices[index]], points[indices[index + 1]], points[indices[index + 2]], color)
		return
	var center := _polygon_center(points)
	for index in points.size():
		_draw_triangle(center, points[index], points[(index + 1) % points.size()], color)

func _draw_triangle(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	if absf((b - a).cross(c - a)) < 0.01:
		return
	draw_colored_polygon(PackedVector2Array([a, b, c]), color)

func _draw_outline(points: PackedVector2Array, color: Color, width: float) -> void:
	if width <= 0.0:
		return
	var closed := PackedVector2Array(points)
	closed.append(points[0])
	draw_polyline(closed, color, width, true)

func _polygon_center(points: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in points:
		center += point
	return center / float(points.size())
