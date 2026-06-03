@tool
extends AnimatableBody2D

const TERRAIN_LAYER := 1 << 0

enum WallMode { MOVING, BREAKABLE }
enum MovementMode { PHYSICAL, CONSTANT_SPEED }
enum BreakState { INTACT, BROKEN, RESTORING }

@export_enum("moving", "breakable") var wall_mode := 0:
	set(value):
		wall_mode = value
		queue_redraw()

@export_group("Moving Wall")
@export var target_offset := Vector2(0.0, -180.0):
	set(value):
		target_offset = value
		if is_inside_tree():
			_target_position = _origin_position + target_offset
		queue_redraw()
@export_range(0.05, 12.0, 0.05) var move_time := 1.4
@export_enum("physical", "constant_speed") var movement_mode := 0
@export var downward_gravity_acceleration := 2.0
@export var start_moved := false
@export var resettable := false

@export_group("Breakable Wall")
@export_range(0.05, 5.0, 0.05) var break_animation_time := 0.55
@export_range(0.05, 5.0, 0.05) var restore_animation_time := 0.65
@export_range(4, 48, 1) var shard_count := 18
@export var shard_spread := Vector2(120.0, 80.0)
@export var prevent_restore_while_blocked := true
@export var flash_color := Color(1.0, 0.92, 0.45, 0.38):
	set(value):
		flash_color = value
		queue_redraw()

@export_group("Impact")
@export var damage_on_impact := true
@export_range(0, 6, 1) var impact_damage := 1
@export var impact_knockback := Vector2(280.0, -180.0)
@export_range(0.05, 2.0, 0.05) var impact_cooldown := 0.6

@export_group("Visual")
@export var fill_color := Color(0.29, 0.32, 0.31, 1.0):
	set(value):
		fill_color = value
		queue_redraw()
@export var edge_color := Color(0.08, 0.10, 0.10, 0.72):
	set(value):
		edge_color = value
		queue_redraw()
@export var target_preview_color := Color(1.0, 0.86, 0.24, 0.28):
	set(value):
		target_preview_color = value
		queue_redraw()
@export var show_target_preview := true:
	set(value):
		show_target_preview = value
		queue_redraw()
@export_range(0.0, 8.0, 0.25) var outline_width := 2.0:
	set(value):
		outline_width = value
		queue_redraw()

var _origin_position := Vector2.ZERO
var _target_position := Vector2.ZERO
var _move_from := Vector2.ZERO
var _move_to := Vector2.ZERO
var _move_elapsed := 0.0
var _moving := false
var _moved := false
var _last_position := Vector2.ZERO
var _impact_cooldowns := {}
var _impact_sensor: Area2D
var _break_state := BreakState.INTACT
var _break_elapsed := 0.0
var _restore_pending := false
var _shards: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	z_index = 20
	z_as_relative = false
	add_to_group("moving_mechanism_walls")
	add_to_group("saveable")
	collision_layer = TERRAIN_LAYER
	collision_mask = 0
	_impact_sensor = get_node_or_null("ImpactSensor") as Area2D
	if _impact_sensor != null:
		_impact_sensor.monitoring = true
		_impact_sensor.monitorable = true
		_impact_sensor.body_entered.connect(_on_impact_body_entered)
	_origin_position = global_position
	_target_position = _origin_position + target_offset
	if start_moved and wall_mode == WallMode.MOVING:
		global_position = _target_position
		_moved = true
	_last_position = global_position
	_rng.randomize()
	_build_shards()
	set_physics_process(not Engine.is_editor_hint())
	set_process(false)
	queue_redraw()

func _physics_process(delta: float) -> void:
	_update_impact_cooldowns(delta)
	advance_movement(delta)

func _process(delta: float) -> void:
	if wall_mode != WallMode.BREAKABLE:
		set_process(false)
		return
	if _restore_pending:
		if not _is_restore_blocked():
			_restore_pending = false
			restore_wall()
		queue_redraw()
		return
	_break_elapsed += delta
	var duration := break_animation_time if _break_state == BreakState.BROKEN else restore_animation_time
	if _break_elapsed >= duration:
		set_process(false)
	queue_redraw()

func _draw() -> void:
	if wall_mode == WallMode.BREAKABLE:
		_draw_breakable()
	else:
		_draw_moving()

func activate() -> void:
	if wall_mode == WallMode.BREAKABLE:
		break_wall()
	else:
		trigger_open()

func deactivate() -> void:
	if wall_mode == WallMode.BREAKABLE:
		restore_wall()
	else:
		trigger_close()

func trigger_move() -> void:
	if wall_mode != WallMode.MOVING:
		activate()
		return
	if _moving:
		return
	if _moved and not resettable:
		return
	if not _moved:
		refresh_origin_from_current_position()
	var destination := _origin_position if _moved else _target_position
	_begin_move_to(destination)

func trigger_open() -> void:
	if wall_mode != WallMode.MOVING:
		activate()
		return
	if _moving or _moved:
		return
	refresh_origin_from_current_position()
	_begin_move_to(_target_position)

func trigger_close() -> void:
	if wall_mode != WallMode.MOVING:
		deactivate()
		return
	if _moving or not _moved:
		return
	_begin_move_to(_origin_position)

func break_wall() -> void:
	if _break_state == BreakState.BROKEN:
		return
	_break_state = BreakState.BROKEN
	_break_elapsed = 0.0
	_restore_pending = false
	_moved = true
	_set_collision_enabled(false)
	_build_shards()
	set_process(true)
	queue_redraw()

func restore_wall() -> void:
	if _break_state == BreakState.INTACT:
		return
	if prevent_restore_while_blocked and _is_restore_blocked():
		_restore_pending = true
		set_process(true)
		queue_redraw()
		return
	_break_state = BreakState.RESTORING
	_break_elapsed = 0.0
	_restore_pending = false
	_moved = false
	_set_collision_enabled(true)
	set_process(true)
	queue_redraw()

func advance_movement(delta: float) -> void:
	if wall_mode != WallMode.MOVING or not _moving:
		return
	_move_elapsed += delta
	var raw_progress := clampf(_move_elapsed / maxf(move_time, 0.001), 0.0, 1.0)
	var progress := _movement_progress(raw_progress)
	_last_position = global_position
	global_position = _move_from.lerp(_move_to, progress)
	_apply_impact_damage(global_position - _last_position)
	if raw_progress >= 1.0:
		global_position = _move_to
		_moving = false
		_moved = _move_to.distance_squared_to(_origin_position) > 1.0

func is_moving() -> bool:
	return _moving or (wall_mode == WallMode.BREAKABLE and is_processing())

func is_moved() -> bool:
	return _moved if wall_mode == WallMode.MOVING else _break_state == BreakState.BROKEN

func get_mechanism_impact_damage() -> int:
	return impact_damage

func get_mechanism_impact_knockback() -> Vector2:
	return impact_knockback

func get_mechanism_impact_direction() -> Vector2:
	if _moving:
		return (_move_to - _move_from).normalized()
	return Vector2.ZERO

func can_apply_mechanism_crush() -> bool:
	return wall_mode == WallMode.MOVING and _moving and damage_on_impact and impact_damage > 0

func get_origin_position() -> Vector2:
	return _origin_position

func get_target_position() -> Vector2:
	return _preview_target_position()

func refresh_origin_from_current_position() -> void:
	if _moving:
		return
	_origin_position = _current_world_position()
	_target_position = _origin_position + target_offset
	_moved = false

func get_mechanism_rect() -> Rect2:
	var preview_target := _preview_target_position()
	var current_position := _current_world_position()
	var bounds := Rect2(current_position, Vector2.ZERO).merge(Rect2(preview_target, Vector2.ZERO))
	var has_points := false
	for polygon in _collision_polygons():
		for point in _transformed_polygon(polygon):
			var global_point := current_position + point
			bounds = Rect2(global_point, Vector2.ZERO) if not has_points else bounds.expand(global_point)
			has_points = true
			bounds = bounds.expand(global_point + target_offset)
	return bounds.grow(90.0)

func get_save_state() -> Dictionary:
	return {
		"position": global_position,
		"origin_position": _origin_position,
		"target_position": _target_position,
		"moving": _moving,
		"moved": _moved,
		"move_from": _move_from,
		"move_to": _move_to,
		"move_elapsed": _move_elapsed,
		"break_state": _break_state,
		"break_elapsed": _break_elapsed,
		"restore_pending": _restore_pending,
		"collision_enabled": _collision_enabled(),
	}

func apply_save_state(state: Dictionary) -> void:
	_origin_position = state.get("origin_position", _origin_position)
	_target_position = state.get("target_position", _origin_position + target_offset)
	global_position = state.get("position", _origin_position)
	_moving = bool(state.get("moving", false))
	_moved = bool(state.get("moved", false))
	_move_from = state.get("move_from", global_position)
	_move_to = state.get("move_to", _target_position)
	_move_elapsed = float(state.get("move_elapsed", 0.0))
	_break_state = int(state.get("break_state", BreakState.INTACT))
	_break_elapsed = float(state.get("break_elapsed", 0.0))
	_restore_pending = bool(state.get("restore_pending", false))
	_set_collision_enabled(bool(state.get("collision_enabled", _break_state != BreakState.BROKEN)))
	set_process(wall_mode == WallMode.BREAKABLE and (_break_state != BreakState.INTACT or _restore_pending))
	queue_redraw()

func _draw_moving() -> void:
	for polygon in _collision_polygons():
		var points := _transformed_polygon(polygon)
		_draw_fill(points, fill_color)
		_draw_outline(points, edge_color, outline_width)
		if show_target_preview:
			var target_points := _offset_points(points, target_offset)
			_draw_fill(target_points, target_preview_color)
			_draw_outline(target_points, target_preview_color, maxf(outline_width, 2.0))
	if show_target_preview:
		_draw_target_arrow()

func _draw_breakable() -> void:
	if _break_state == BreakState.INTACT:
		_draw_wall(1.0)
	elif _break_state == BreakState.BROKEN:
		_draw_break_animation()
	else:
		_draw_restore_animation()

func _draw_wall(alpha: float) -> void:
	var color := fill_color
	color.a *= alpha
	for polygon in _collision_polygons():
		var points := _transformed_polygon(polygon)
		_draw_fill(points, color)
		_draw_outline(points, edge_color, outline_width)

func _draw_break_animation() -> void:
	var progress := clampf(_break_elapsed / maxf(break_animation_time, 0.001), 0.0, 1.0)
	var fade := 1.0 - progress
	for shard in _shards:
		var center := shard["center"] as Vector2
		var direction := shard["direction"] as Vector2
		var size := float(shard["size"])
		var offset := direction * shard_spread * progress
		var color := fill_color.lerp(flash_color, 0.35)
		color.a = fade
		draw_circle(center + offset, size * (1.0 + progress), color)
		var edge := edge_color
		edge.a = fade
		draw_circle(center + offset, size * (1.0 + progress), edge, false, 1.5)

func _draw_restore_animation() -> void:
	var progress := clampf(_break_elapsed / maxf(restore_animation_time, 0.001), 0.0, 1.0)
	_draw_wall(progress)
	var flash := flash_color
	flash.a *= 1.0 - progress
	for polygon in _collision_polygons():
		_draw_outline(_transformed_polygon(polygon), flash, outline_width + 2.0)

func _begin_move_to(destination: Vector2) -> void:
	_move_from = _current_world_position()
	global_position = _move_from
	_last_position = _move_from
	_move_to = destination
	_move_elapsed = 0.0
	_moving = true

func _movement_progress(raw_progress: float) -> float:
	if movement_mode == MovementMode.CONSTANT_SPEED:
		return raw_progress
	if _move_to.y > _move_from.y:
		return pow(raw_progress, downward_gravity_acceleration)
	return raw_progress * raw_progress * (3.0 - 2.0 * raw_progress)

func _apply_impact_damage(move_delta: Vector2) -> void:
	if not can_apply_mechanism_crush() or move_delta.length_squared() <= 0.01:
		return
	if _impact_sensor != null:
		for body in _impact_sensor.get_overlapping_bodies():
			var sensor_body := body as Node2D
			if sensor_body != null and sensor_body != self and is_instance_valid(sensor_body):
				_apply_impact_to_body(sensor_body, move_delta.normalized())
	var impact_radius := 140.0
	for group_name in ["players", "enemies"]:
		for body in get_tree().get_nodes_in_group(group_name):
			var body_2d := body as Node2D
			if body_2d == null or body_2d == self or not is_instance_valid(body_2d):
				continue
			if _distance_to_move_segment(body_2d.global_position) > impact_radius:
				continue
			_apply_impact_to_body(body_2d, move_delta.normalized())

func _on_impact_body_entered(body: Node) -> void:
	if not can_apply_mechanism_crush():
		return
	var body_2d := body as Node2D
	if body_2d == null or body_2d == self:
		return
	_apply_impact_to_body(body_2d, (global_position - _last_position).normalized())

func _apply_impact_to_body(body_2d: Node2D, direction: Vector2) -> void:
	var body_id := body_2d.get_instance_id()
	if _impact_cooldowns.has(body_id):
		return
	var did_hit := false
	if body_2d.has_method("take_mechanism_crush"):
		did_hit = bool(body_2d.call("take_mechanism_crush", impact_damage, self, direction, impact_knockback))
	elif body_2d.has_method("take_environment_hit"):
		did_hit = bool(body_2d.call("take_environment_hit", impact_damage, self, direction, impact_knockback))
	elif body_2d.has_method("take_enemy_hit"):
		did_hit = bool(body_2d.call("take_enemy_hit", impact_damage, self))
	if did_hit:
		_impact_cooldowns[body_id] = impact_cooldown

func _distance_to_move_segment(point: Vector2) -> float:
	var segment := global_position - _last_position
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(global_position)
	var amount := clampf((point - _last_position).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(_last_position + segment * amount)

func _update_impact_cooldowns(delta: float) -> void:
	for body_id in _impact_cooldowns.keys().duplicate():
		var remaining := float(_impact_cooldowns[body_id]) - delta
		if remaining <= 0.0:
			_impact_cooldowns.erase(body_id)
		else:
			_impact_cooldowns[body_id] = remaining

func _preview_target_position() -> Vector2:
	if not _moving and not _moved:
		return _current_world_position() + target_offset
	return _target_position

func _current_world_position() -> Vector2:
	var parent_2d := get_parent() as Node2D
	if parent_2d != null:
		return parent_2d.to_global(position)
	return global_position

func _build_shards() -> void:
	_shards.clear()
	var bounds := get_mechanism_rect()
	for index in shard_count:
		var angle := _rng.randf_range(0.0, TAU)
		_shards.append({
			"center": to_local(Vector2(_rng.randf_range(bounds.position.x, bounds.end.x), _rng.randf_range(bounds.position.y, bounds.end.y))),
			"direction": Vector2.RIGHT.rotated(angle),
			"size": _rng.randf_range(3.0, 8.0),
		})

func _set_collision_enabled(enabled: bool) -> void:
	collision_layer = TERRAIN_LAYER if enabled else 0
	for polygon in _collision_polygons():
		polygon.set_deferred("disabled", not enabled)
	if _impact_sensor != null:
		_impact_sensor.monitoring = enabled and wall_mode == WallMode.MOVING
		_impact_sensor.monitorable = enabled and wall_mode == WallMode.MOVING

func _collision_enabled() -> bool:
	if collision_layer == 0:
		return false
	for polygon in _collision_polygons():
		return not polygon.disabled
	return true

func _is_restore_blocked() -> bool:
	var bounds := get_mechanism_rect().grow(8.0)
	for group_name in ["players", "enemies"]:
		for body in get_tree().get_nodes_in_group(group_name):
			var body_2d := body as Node2D
			if body_2d != null and is_instance_valid(body_2d) and bounds.has_point(body_2d.global_position):
				return true
	return false

func _collision_polygons() -> Array[CollisionPolygon2D]:
	var polygons: Array[CollisionPolygon2D] = []
	for child in get_children():
		var polygon := child as CollisionPolygon2D
		if polygon != null and polygon.polygon.size() >= 3:
			polygons.append(polygon)
	return polygons

func _transformed_polygon(collision_polygon: CollisionPolygon2D) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(collision_polygon.polygon.size())
	for index in collision_polygon.polygon.size():
		points[index] = collision_polygon.transform * collision_polygon.polygon[index]
	return points

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

func _draw_target_arrow() -> void:
	var start := Vector2.ZERO
	var end := target_offset
	var color := target_preview_color
	color.a = minf(color.a + 0.35, 1.0)
	draw_line(start, end, color, 3.0, true)
	if end.length_squared() <= 0.001:
		return
	var direction := end.normalized()
	var normal := direction.rotated(PI * 0.5)
	draw_line(end, end - direction * 18.0 + normal * 8.0, color, 3.0, true)
	draw_line(end, end - direction * 18.0 - normal * 8.0, color, 3.0, true)

func _polygon_center(points: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in points:
		center += point
	return center / float(points.size())

func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var shifted := PackedVector2Array()
	shifted.resize(points.size())
	for index in points.size():
		shifted[index] = points[index] + offset
	return shifted
