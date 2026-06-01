extends Node2D

@export var duration := 0.22
@export var ring_radius := 34.0
@export var spark_count := 10
@export var spark_length := 24.0
@export var primary_color := Color(1.0, 0.92, 0.42, 1.0)
@export var secondary_color := Color(1.0, 0.36, 0.18, 1.0)
@export var core_color := Color(1.0, 1.0, 1.0, 1.0)

var direction := Vector2.RIGHT
var _age := 0.0
var _rng := RandomNumberGenerator.new()
var _sparks: Array[Dictionary] = []

func _ready() -> void:
	z_index = 220
	z_as_relative = false
	_rng.randomize()
	_build_sparks()
	queue_redraw()

func setup(hit_direction: Vector2, color: Color, is_finisher: bool = false) -> void:
	if hit_direction.length_squared() > 0.001:
		direction = hit_direction.normalized()
	primary_color = color
	if is_finisher:
		duration = 0.32
		ring_radius = 48.0
		spark_count = 16
		spark_length = 36.0

	_sparks.clear()
	_build_sparks()
	queue_redraw()

func _process(delta: float) -> void:
	_age += delta
	if _age >= duration:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := clampf(_age / maxf(duration, 0.001), 0.0, 1.0)
	var fade := 1.0 - progress
	var burst := sin(progress * PI)
	var ring_color := primary_color
	ring_color.a = 0.7 * fade
	var arc_width := 3.0 + 3.0 * fade
	draw_arc(Vector2.ZERO, ring_radius * progress, 0.0, TAU, 32, ring_color, arc_width, true)

	var core := core_color
	core.a = fade
	draw_circle(Vector2.ZERO, 5.5 + 3.0 * burst, core)

	var slash_color := secondary_color
	slash_color.a = fade
	var slash_normal := direction.rotated(PI * 0.5)
	draw_line(-direction * 14.0 - slash_normal * 8.0, direction * 22.0 + slash_normal * 8.0, slash_color, 4.0 * fade + 1.0)
	draw_line(-direction * 8.0 + slash_normal * 10.0, direction * 16.0 - slash_normal * 10.0, ring_color, 2.0 * fade + 1.0)

	for spark in _sparks:
		var spark_direction := spark["direction"] as Vector2
		var spark_speed := float(spark["speed"])
		var spark_size := float(spark["size"])
		var spark_color := primary_color.lerp(secondary_color, float(spark["warmth"]))
		spark_color.a = fade
		var end := spark_direction * spark_speed * progress
		var start := end - spark_direction * spark_length * spark_size * fade
		draw_line(start, end, spark_color, maxf(1.0, 3.0 * spark_size * fade), true)

func _build_sparks() -> void:
	if not _sparks.is_empty():
		return

	var base_angle := direction.angle()
	for index in spark_count:
		var angle := base_angle + _rng.randf_range(-1.15, 1.15)
		_sparks.append({
			"direction": Vector2.RIGHT.rotated(angle),
			"speed": _rng.randf_range(70.0, 190.0),
			"size": _rng.randf_range(0.65, 1.2),
			"warmth": _rng.randf_range(0.0, 1.0),
		})
