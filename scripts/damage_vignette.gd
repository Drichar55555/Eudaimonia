extends Control

@export var player_path: NodePath
@export_range(0.1, 2.0, 0.05) var flash_strength := 1.0
@export_range(0.1, 2.0, 0.05) var fade_duration := 0.58
@export_range(24.0, 320.0, 1.0) var edge_width := 150.0
@export_range(4, 40, 1) var vein_count := 18
@export var blood_color := Color(0.92, 0.02, 0.04, 1.0)

var _intensity := 0.0
var _player: Node
var _veins: Array[Dictionary] = []

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	_build_veins()
	call_deferred("_connect_player")

func _process(delta: float) -> void:
	_intensity = move_toward(_intensity, 0.0, delta / maxf(fade_duration, 0.001))
	visible = _intensity > 0.01
	set_process(visible)
	queue_redraw()

func flash(damage: int = 1, _cause: String = "") -> void:
	var damage_boost := 0.76 + float(maxi(damage, 1)) * 0.22
	_intensity = clampf(maxf(_intensity, flash_strength * damage_boost), 0.0, 1.0)
	visible = true
	set_process(true)
	queue_redraw()

func _draw() -> void:
	if _intensity <= 0.01 or size.x <= 1.0 or size.y <= 1.0:
		return
	_draw_edge_haze()
	_draw_blood_veins()

func _connect_player() -> void:
	if not player_path.is_empty():
		_player = get_node_or_null(player_path)
	if _player == null:
		_player = get_tree().get_first_node_in_group("players")
	if _player == null or not _player.has_signal("player_damaged"):
		return
	var callback := Callable(self, "_on_player_damaged")
	if not _player.is_connected("player_damaged", callback):
		_player.connect("player_damaged", callback)

func _on_player_damaged(damage: int, cause: String) -> void:
	flash(damage, cause)

func _draw_edge_haze() -> void:
	var layer_count := 10
	for index in layer_count:
		var progress := float(index) / float(layer_count)
		var alpha := pow(1.0 - progress, 1.55) * _intensity * 0.2
		var band := edge_width * (1.0 - progress * 0.76)
		var color := Color(blood_color.r, blood_color.g * 0.35, blood_color.b * 0.35, alpha)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, band)), color)
		draw_rect(Rect2(Vector2(0.0, size.y - band), Vector2(size.x, band)), color)
		draw_rect(Rect2(Vector2.ZERO, Vector2(band, size.y)), color)
		draw_rect(Rect2(Vector2(size.x - band, 0.0), Vector2(band, size.y)), color)

func _draw_blood_veins() -> void:
	for vein in _veins:
		_draw_vein(vein)

func _draw_vein(vein: Dictionary) -> void:
	var edge := int(vein.get("edge", 0))
	var t := float(vein.get("t", 0.5))
	var depth_factor := float(vein.get("depth", 0.25))
	var bend := float(vein.get("bend", 0.0))
	var wobble := float(vein.get("wobble", 0.0))
	var base_width := float(vein.get("width", 2.0))
	var phase := float(vein.get("phase", 0.0))

	var start := Vector2.ZERO
	var inward := Vector2.ZERO
	var tangent := Vector2.ZERO
	match edge:
		0:
			start = Vector2(size.x * t, 0.0)
			inward = Vector2.DOWN
			tangent = Vector2.RIGHT
		1:
			start = Vector2(size.x, size.y * t)
			inward = Vector2.LEFT
			tangent = Vector2.DOWN
		2:
			start = Vector2(size.x * t, size.y)
			inward = Vector2.UP
			tangent = Vector2.RIGHT
		_:
			start = Vector2(0.0, size.y * t)
			inward = Vector2.RIGHT
			tangent = Vector2.DOWN

	var depth := minf(size.x, size.y) * depth_factor
	var points := PackedVector2Array()
	var segment_count := 6
	for index in segment_count:
		var progress := float(index) / float(segment_count - 1)
		var taper := 1.0 - progress
		var offset := bend * depth * progress + sin(progress * TAU * 1.35 + phase) * wobble * taper
		points.append(start + inward * depth * progress + tangent * offset)

	var alpha := _intensity * 0.45
	var color := Color(blood_color.r, blood_color.g, blood_color.b, alpha)
	draw_polyline(points, color, base_width, true)

	if bool(vein.get("branch", false)):
		var branch_start := points[2]
		var branch_end := branch_start + inward * depth * 0.22 - tangent * bend * depth * 0.36
		draw_line(branch_start, branch_end, Color(blood_color.r, blood_color.g, blood_color.b, alpha * 0.58), maxf(base_width * 0.55, 1.0), true)

func _build_veins() -> void:
	_veins.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 244613
	for index in vein_count:
		_veins.append({
			"edge": index % 4,
			"t": rng.randf_range(0.08, 0.92),
			"depth": rng.randf_range(0.12, 0.34),
			"bend": rng.randf_range(-0.16, 0.16),
			"wobble": rng.randf_range(5.0, 18.0),
			"width": rng.randf_range(1.2, 3.2),
			"phase": rng.randf_range(0.0, TAU),
			"branch": rng.randf() > 0.48,
		})