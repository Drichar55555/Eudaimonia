@tool
extends Node2D
class_name PhysicalSunLight2D

const TERRAIN_LAYER := 1 << 0

@export var camera_group := "room_cameras"
@export var enabled := true
@export var runtime_enabled_by_default := false
@export var runtime_toggle_key := KEY_G
@export var light_color := Color(1.0, 0.84, 0.46, 0.24)
@export_range(0.0, 2.0, 0.02) var intensity := 1.0
@export var light_direction := Vector2(0.30, 1.0):
	set(value):
		light_direction = value if value.length_squared() > 0.001 else Vector2(0.30, 1.0)
		queue_redraw()
@export_range(-1.5, 1.5, 0.01) var source_screen_x := -0.20
@export_range(-1.5, 0.2, 0.01) var source_screen_y := -0.72
@export_range(80.0, 1800.0, 10.0) var source_width := 900.0
@export_range(12, 160, 1) var ray_count := 72
@export_range(220.0, 2600.0, 10.0) var ray_length := 1400.0
@export_flags_2d_physics var occluder_collision_mask := TERRAIN_LAYER
@export_range(0.0, 48.0, 1.0) var hit_padding := 6.0
@export_range(1.0, 36.0, 1.0) var ray_visual_width := 16.0
@export_range(1, 12, 1) var soft_edge_layers := 5
@export_range(1, 12, 1) var scatter_steps := 7
@export_range(0.0, 2.0, 0.02) var fog_density := 0.95
@export_range(0.0, 240.0, 1.0) var edge_noise := 34.0
@export_range(0.0, 2.0, 0.02) var shimmer_speed := 0.16
@export var cover_margin := Vector2(260.0, 200.0)
@export var runtime_z_index := -8
@export var editor_z_index := 1024

@export_group("Editor Handles")
@export var use_handles := true
@export var source_handle_path := NodePath("SourceHandle")
@export var direction_handle_path := NodePath("DirectionHandle")
@export var discover_sibling_source_handles := true
@export var source_handle_prefix := "SourceHandle"
@export var direction_handle_prefix := "DirectionHandle"
@export var show_handle_guides := true

var _time := 0.0
var _runtime_rendering_enabled := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_as_relative = false
	_apply_editor_layering()
	material = CanvasItemMaterial.new()
	(material as CanvasItemMaterial).blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_runtime_rendering_enabled = runtime_enabled_by_default
	set_process_unhandled_input(not Engine.is_editor_hint())
	_apply_runtime_rendering_state()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == runtime_toggle_key or event.physical_keycode == runtime_toggle_key):
		_runtime_rendering_enabled = not _runtime_rendering_enabled
		_apply_runtime_rendering_state()
		queue_redraw()

func _process(delta: float) -> void:
	_apply_editor_layering()
	if Engine.is_editor_hint():
		_sync_fallback_values_from_handles()
		queue_redraw()
		return
	if not _should_render_runtime():
		return
	_time += delta
	var camera := _current_camera()
	if camera != null:
		global_position = camera.global_position
	queue_redraw()

func _draw() -> void:
	if not enabled or (not Engine.is_editor_hint() and not _runtime_rendering_enabled):
		return
	var camera := _current_camera()
	if camera == null:
		return
	var view_size := _camera_view_size(camera) + cover_margin * 2.0
	var physics := get_world_2d().direct_space_state
	var light_sources := _current_light_sources(camera, view_size)
	for source_index in light_sources.size():
		var light_source := light_sources[source_index]
		var source_center := light_source.get("center", camera.global_position) as Vector2
		var direction := (light_source.get("direction", light_direction.normalized()) as Vector2).normalized()
		var normal := direction.orthogonal().normalized()
		var width := maxf(float(light_source.get("width", source_width)), 1.0)
		var count := maxi(ray_count, 2)
		var spacing := width / float(count - 1)
		var visual_width := maxf(ray_visual_width, spacing * 0.74)
		for ray_index in count:
			var fraction := float(ray_index) / float(count - 1)
			var aperture_offset := (fraction - 0.5) * width
			var broken_edge := _edge_breakup(ray_index + source_index * count, fraction)
			var origin := source_center + normal * (aperture_offset + broken_edge)
			var end := _ray_end(physics, origin, direction, ray_length)
			_draw_scattered_ray(origin, end, direction, normal, visual_width, fraction, ray_index + source_index * count)
		if Engine.is_editor_hint() and show_handle_guides:
			_draw_handle_guides(source_center, direction, normal, width)

func _apply_editor_layering() -> void:
	z_as_relative = false
	z_index = editor_z_index if Engine.is_editor_hint() else runtime_z_index

func _apply_runtime_rendering_state() -> void:
	visible = Engine.is_editor_hint() or _runtime_rendering_enabled
	set_process(Engine.is_editor_hint() or _should_render_runtime())

func _should_render_runtime() -> bool:
	return enabled and _runtime_rendering_enabled

func _current_source_center(camera: Camera2D, view_size: Vector2) -> Vector2:
	var source_handle := _source_handle()
	if use_handles and source_handle != null:
		return source_handle.global_position
	return camera.global_position + Vector2(source_screen_x * view_size.x, source_screen_y * view_size.y)

func _current_light_sources(camera: Camera2D, view_size: Vector2) -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	var primary_direction := _current_light_direction()
	var source_handles := _source_handles()
	if use_handles and not source_handles.is_empty():
		for source_handle in source_handles:
			var source_direction := _direction_for_source_handle(source_handle, primary_direction)
			sources.append({
				"center": source_handle.global_position,
				"direction": source_direction,
				"width": source_width * _source_width_scale(source_handle),
			})
		return sources
	sources.append({
		"center": _current_source_center(camera, view_size),
		"direction": primary_direction,
		"width": source_width,
	})
	return sources

func _current_light_direction() -> Vector2:
	var source_handle := _source_handle()
	var direction_handle := _direction_handle()
	if use_handles and source_handle != null and direction_handle != null:
		var handle_direction := direction_handle.global_position - source_handle.global_position
		if handle_direction.length_squared() > 0.001:
			return handle_direction.normalized()
	return light_direction.normalized()

func _source_handle() -> Node2D:
	return get_node_or_null(source_handle_path) as Node2D

func _source_handles() -> Array[Node2D]:
	var handles: Array[Node2D] = []
	var primary_handle := _source_handle()
	if primary_handle != null:
		handles.append(primary_handle)
	if not discover_sibling_source_handles or primary_handle == null or primary_handle.get_parent() == null:
		return handles
	for child in primary_handle.get_parent().get_children():
		var source_handle := child as Node2D
		if source_handle == null or source_handle == primary_handle:
			continue
		if not source_handle.name.begins_with(source_handle_prefix):
			continue
		handles.append(source_handle)
	return handles

func _direction_handle() -> Node2D:
	return get_node_or_null(direction_handle_path) as Node2D

func _direction_for_source_handle(source_handle: Node2D, fallback_direction: Vector2) -> Vector2:
	var matching_direction_handle := _matching_direction_handle(source_handle)
	if matching_direction_handle != null:
		var handle_direction := matching_direction_handle.global_position - source_handle.global_position
		if handle_direction.length_squared() > 0.001:
			return handle_direction.normalized()
	return fallback_direction.normalized()

func _matching_direction_handle(source_handle: Node2D) -> Node2D:
	var suffix := source_handle.name.trim_prefix(source_handle_prefix)
	if suffix.is_empty():
		return _direction_handle()
	if source_handle.get_parent() == null:
		return null
	return source_handle.get_parent().get_node_or_null("%s%s" % [direction_handle_prefix, suffix]) as Node2D

func _source_width_scale(source_handle: Node2D) -> float:
	var scale := source_handle.global_scale
	return maxf((absf(scale.x) + absf(scale.y)) * 0.5, 0.1)

func _sync_fallback_values_from_handles() -> void:
	if not use_handles:
		return
	var source_handle := _source_handle()
	var direction_handle := _direction_handle()
	if source_handle != null and direction_handle != null:
		var handle_direction := direction_handle.position - source_handle.position
		if handle_direction.length_squared() > 0.001:
			light_direction = handle_direction.normalized()

func _draw_handle_guides(source_center: Vector2, direction: Vector2, normal: Vector2, width: float) -> void:
	var source_local := to_local(source_center)
	var direction_local := to_local(source_center + direction * 180.0)
	var left_local := to_local(source_center - normal * width * 0.5)
	var right_local := to_local(source_center + normal * width * 0.5)
	var guide_color := Color(1.0, 0.78, 0.24, 0.72)
	draw_line(left_local, right_local, guide_color, 3.0, true)
	draw_line(source_local, direction_local, guide_color, 2.0, true)
	draw_circle(source_local, 9.0, Color(1.0, 0.78, 0.24, 0.55))
	draw_circle(direction_local, 5.0, Color(1.0, 0.94, 0.45, 0.75))

func _ray_end(physics: PhysicsDirectSpaceState2D, origin: Vector2, direction: Vector2, length: float) -> Vector2:
	var target := origin + direction * length
	var query := PhysicsRayQueryParameters2D.create(origin, target, occluder_collision_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = false
	var hit := physics.intersect_ray(query)
	if hit.is_empty():
		return target
	var hit_position := hit.get("position", target) as Vector2
	return hit_position - direction * hit_padding

func _draw_scattered_ray(origin: Vector2, end: Vector2, direction: Vector2, normal: Vector2, base_width: float, fraction: float, index: int) -> void:
	var length := origin.distance_to(end)
	if length < 20.0:
		return
	var center_fade := sin(fraction * PI)
	var wave := 0.86 + 0.14 * sin(_time * shimmer_speed + float(index) * 0.47)
	var ray_alpha := light_color.a * intensity * fog_density * center_fade * wave
	for layer in soft_edge_layers:
		var layer_fraction := float(layer) / float(maxi(soft_edge_layers - 1, 1))
		var width := base_width * lerpf(2.8, 0.42, layer_fraction)
		var alpha := ray_alpha * lerpf(0.065, 0.38, layer_fraction * layer_fraction)
		_draw_ray_segments(origin, end, direction, normal, width, alpha)

func _draw_ray_segments(origin: Vector2, end: Vector2, direction: Vector2, normal: Vector2, width: float, alpha: float) -> void:
	var total := origin.distance_to(end)
	if total <= 0.0:
		return
	var steps := maxi(scatter_steps, 1)
	for step in steps:
		var start_t := float(step) / float(steps)
		var end_t := float(step + 1) / float(steps)
		var mid_t := (start_t + end_t) * 0.5
		var distance_fade := sin(mid_t * PI)
		var depth_fade := lerpf(0.62, 1.0, mid_t)
		var color := light_color
		color.a = alpha * distance_fade * depth_fade
		if color.a <= 0.001:
			continue
		var start := origin.lerp(end, start_t)
		var finish := origin.lerp(end, end_t)
		var start_width := width * lerpf(0.62, 1.0, start_t)
		var finish_width := width * lerpf(0.62, 1.0, end_t)
		_draw_ray_quad(to_local(start), to_local(finish), normal, start_width, finish_width, color)

func _draw_ray_quad(start: Vector2, finish: Vector2, global_normal: Vector2, start_width: float, finish_width: float, color: Color) -> void:
	var local_normal := (to_local(global_position + global_normal) - to_local(global_position)).normalized()
	var points := PackedVector2Array([
		start - local_normal * start_width,
		start + local_normal * start_width,
		finish + local_normal * finish_width,
		finish - local_normal * finish_width,
	])
	draw_colored_polygon(points, color)

func _edge_breakup(index: int, fraction: float) -> float:
	if edge_noise <= 0.0:
		return 0.0
	var edge_weight := 1.0 - sin(fraction * PI)
	var wave_a := sin(float(index) * 1.37 + _time * shimmer_speed)
	var wave_b := cos(float(index) * 0.61 - _time * shimmer_speed * 0.7)
	return (wave_a * 0.65 + wave_b * 0.35) * edge_noise * (0.30 + edge_weight * 0.70)

func _camera_view_size(camera: Camera2D) -> Vector2:
	var viewport_size := get_viewport_rect().size
	return Vector2(
		viewport_size.x / maxf(camera.zoom.x, 0.001),
		viewport_size.y / maxf(camera.zoom.y, 0.001)
	)

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
