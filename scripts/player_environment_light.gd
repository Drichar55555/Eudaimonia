extends Node

const TERRAIN_LAYER := 1 << 0

@export var visual_path := NodePath("../Sprite2D")
@export var sunlight_path := NodePath("../../PhysicalSunLight")
@export_flags_2d_physics var occluder_collision_mask := TERRAIN_LAYER
@export var shadow_tint := Color(0.46, 0.50, 0.52, 1.0)
@export var mid_tint := Color(0.72, 0.73, 0.70, 1.0)
@export var lit_tint := Color(1.0, 0.96, 0.84, 1.0)
@export_range(0.0, 1.0, 0.01) var minimum_light := 0.24
@export_range(0.0, 18.0, 0.1) var response_speed := 9.0
@export var sample_offsets := PackedVector2Array([
	Vector2(0.0, -92.0),
	Vector2(0.0, -58.0),
	Vector2(0.0, -24.0),
])

var _visual: CanvasItem
var _sunlight: Node2D
var _light_amount := 1.0

func _ready() -> void:
	_visual = get_node_or_null(visual_path) as CanvasItem
	_sunlight = get_node_or_null(sunlight_path) as Node2D
	set_process(not Engine.is_editor_hint())

func _process(delta: float) -> void:
	if _visual == null:
		return
	var target_light := _sample_environment_light()
	var smoothing := 1.0 - exp(-response_speed * delta)
	_light_amount = lerpf(_light_amount, target_light, smoothing)
	_visual.self_modulate = _tint_for_light(_light_amount)

func _sample_environment_light() -> float:
	if _sunlight == null or sample_offsets.is_empty():
		return 1.0

	var sources := _light_source_positions()
	if sources.is_empty():
		return 1.0

	var visible_samples := 0
	var total_samples := sample_offsets.size()
	var physics := get_viewport().world_2d.direct_space_state
	for offset in sample_offsets:
		var sample_position := (get_parent() as Node2D).global_position + offset
		if _sample_reaches_any_source(physics, sample_position, sources):
			visible_samples += 1

	var visibility := float(visible_samples) / float(total_samples)
	return clampf(lerpf(minimum_light, 1.0, visibility), 0.0, 1.0)

func _sample_reaches_any_source(physics: PhysicsDirectSpaceState2D, sample_position: Vector2, sources: Array[Vector2]) -> bool:
	for source_position in sources:
		var query := PhysicsRayQueryParameters2D.create(source_position, sample_position, occluder_collision_mask)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.hit_from_inside = false
		var hit := physics.intersect_ray(query)
		if hit.is_empty():
			return true
	return false

func _light_source_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var source_handle := _source_handle()
	if source_handle == null:
		return positions
	positions.append(source_handle.global_position)
	var parent := source_handle.get_parent()
	if parent == null:
		return positions
	var source_prefix := "SourceHandle"
	if _sunlight != null:
		source_prefix = str(_sunlight.get("source_handle_prefix"))
	for child in parent.get_children():
		var handle := child as Node2D
		if handle == null or handle == source_handle:
			continue
		if String(handle.name).begins_with(source_prefix):
			positions.append(handle.global_position)
	return positions

func _source_handle() -> Node2D:
	if _sunlight == null:
		return null
	var source_path_value: Variant = _sunlight.get("source_handle_path")
	if source_path_value is NodePath:
		return _sunlight.get_node_or_null(source_path_value) as Node2D
	return null

func _tint_for_light(value: float) -> Color:
	if value < 0.5:
		return shadow_tint.lerp(mid_tint, value * 2.0)
	return mid_tint.lerp(lit_tint, (value - 0.5) * 2.0)