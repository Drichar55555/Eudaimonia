@tool
extends "res://scripts/save_point.gd"

enum SoulMask { EUDA_MASK = 1, GHOST_MASK = 2 }

@export_group("Soul")
@export_enum("Euda Mask", "Ghost Mask") var soul_mask_state := 0:
	set(value):
		soul_mask_state = value
		_update_soul_colors()
		queue_redraw()

@export_group("Soul Lamp Visual")
@export var lamp_color := Color(0.22, 0.28, 0.26, 1.0):
	set(value):
		lamp_color = value
		queue_redraw()
@export var lamp_edge_color := Color(0.07, 0.09, 0.08, 0.9):
	set(value):
		lamp_edge_color = value
		queue_redraw()
@export var flame_color := Color(0.56, 0.92, 1.0, 0.9):
	set(value):
		flame_color = value
		queue_redraw()
@export var glow_color := Color(0.42, 0.82, 1.0, 0.18):
	set(value):
		glow_color = value
		queue_redraw()
@export_group("Lighting")
@export var emit_blue_light := true:
	set(value):
		emit_blue_light = value
		_update_light()
@export var soul_light_color := Color(0.36, 0.72, 1.0, 1.0):
	set(value):
		soul_light_color = value
		_update_light()
@export_range(0.0, 4.0, 0.05) var soul_light_energy := 1.45:
	set(value):
		soul_light_energy = maxf(value, 0.0)
		_update_light()
@export_range(0.2, 8.0, 0.05) var soul_light_scale := 2.6:
	set(value):
		soul_light_scale = maxf(value, 0.01)
		_update_light()
@export_range(-4096, 4096, 1) var soul_light_z_min := -100:
	set(value):
		soul_light_z_min = value
		_update_light()
@export_range(-4096, 4096, 1) var soul_light_z_max := 1:
	set(value):
		soul_light_z_max = value
		_update_light()
@export var base_height := 88.0:
	set(value):
		base_height = maxf(value, 24.0)
		_update_light_position()
		queue_redraw()
@export var lamp_width := 36.0:
	set(value):
		lamp_width = maxf(value, 14.0)
		queue_redraw()
@export_group("Healing Particles")
@export var healing_particle_color := Color(0.34, 0.78, 1.0, 0.95)
@export_range(40.0, 520.0, 5.0) var healing_particle_speed := 85.0
@export_range(0.05, 1.2, 0.01) var healing_particle_interval := 0.34
@export_range(2.0, 24.0, 0.5) var healing_particle_radius := 5.5
@export_range(0.0, 3.0, 0.05) var healing_particle_light_energy := 0.85
@export_range(0.2, 5.0, 0.05) var healing_particle_light_scale := 0.8

var _soul_light: PointLight2D
var _soul_light_texture: Texture2D
var _healing_particle_light_texture: Texture2D
var _healing_particle_visual_texture: Texture2D
var _inside_player: Node2D
var _healing_player: Node2D
var _heal_queue: Array[int] = []
var _heal_particles: Array[Dictionary] = []
var _heal_emit_timer := 0.0

func _ready() -> void:
	_update_soul_colors()
	super._ready()
	_ensure_soul_light()
	set_process(true)

func _process(delta: float) -> void:
	super._process(delta)
	if Engine.is_editor_hint():
		return
	_try_start_inside_heal()
	_update_healing_particles(delta)

func _try_start_save(player: Node) -> void:
	_inside_player = player as Node2D
	if _player_inside:
		_try_start_inside_heal()
		return
	_player_inside = true
	if not _has_active_heal_sequence() and _start_heal_sequence(player):
		return
	if _now_seconds() - _last_exit_time < reenter_cooldown:
		return
	_request_save()

func _on_body_exited(body: Node) -> void:
	if Engine.is_editor_hint() or not _is_player(body):
		return
	if body == _inside_player:
		_inside_player = null
	_player_inside = false
	_last_exit_time = _now_seconds()

func _restore_player_energy(player: Node) -> void:
	if player != null and player.has_method("restore_soul_lamp_energy"):
		player.call("restore_soul_lamp_energy", _mask_state_value())

func _start_heal_sequence(player: Node) -> bool:
	if player == null or not player.has_method("get_soul_lamp_missing_energy_states"):
		return false
	var missing_states := player.call("get_soul_lamp_missing_energy_states", _mask_state_value()) as Array
	if missing_states.is_empty():
		return false
	_healing_player = player as Node2D
	_clear_healing_particles()
	_heal_queue.clear()
	for state in missing_states:
		_heal_queue.append(int(state))
	_heal_emit_timer = 0.0
	_update_light()
	return true

func _try_start_inside_heal() -> void:
	if _has_active_heal_sequence():
		return
	var player := _refresh_inside_player()
	if player == null:
		return
	if _start_heal_sequence(player):
		_player_inside = true

func _has_active_heal_sequence() -> bool:
	return _healing_player != null or not _heal_queue.is_empty() or not _heal_particles.is_empty()

func _refresh_inside_player() -> Node2D:
	var bodies := get_overlapping_bodies()
	if _inside_player != null and is_instance_valid(_inside_player):
		for body in bodies:
			if body == _inside_player:
				return _inside_player
	for body in bodies:
		if _is_player(body):
			_inside_player = body as Node2D
			return _inside_player
	_inside_player = null
	return null

func _request_save() -> void:
	if _save_manager == null:
		_save_manager = get_node_or_null(save_manager_path)
	if _save_manager != null and _save_manager.has_method("request_save"):
		_save_manager.request_save(global_position)

func _mask_state_value() -> int:
	return SoulMask.GHOST_MASK if soul_mask_state == 1 else SoulMask.EUDA_MASK

func _update_soul_colors() -> void:
	if soul_mask_state == 1:
		flame_color = Color(0.72, 0.92, 1.0, 0.95)
		glow_color = Color(0.50, 0.72, 1.0, 0.18)
		return
	flame_color = Color(0.64, 0.90, 1.0, 0.95)
	glow_color = Color(0.42, 0.82, 1.0, 0.18)

func _ensure_soul_light() -> void:
	_soul_light = get_node_or_null("SoulLight") as PointLight2D
	if _soul_light == null:
		_soul_light = PointLight2D.new()
		_soul_light.name = "SoulLight"
		add_child(_soul_light)
	_update_light_position()
	_update_light()

func _update_light_position() -> void:
	if _soul_light != null:
		_soul_light.position = Vector2(0.0, -base_height - 8.0)

func _update_light() -> void:
	if _soul_light == null:
		return
	_soul_light.enabled = emit_blue_light
	_soul_light.color = soul_light_color
	_soul_light.energy = soul_light_energy
	_soul_light.texture_scale = soul_light_scale
	_soul_light.range_z_min = soul_light_z_min
	_soul_light.range_z_max = soul_light_z_max
	_soul_light.z_index = 1
	_soul_light.z_as_relative = false
	if _soul_light_texture == null:
		_soul_light_texture = _make_radial_light_texture(256)
	_soul_light.texture = _soul_light_texture

func _make_radial_light_texture(size: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var radius := float(size) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(x, y).distance_to(center) / radius
			var alpha := pow(clampf(1.0 - distance, 0.0, 1.0), 1.8)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)

func _make_particle_visual_texture(size: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var radius := float(size) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(x, y).distance_to(center) / radius
			var edge := clampf(distance, 0.0, 1.0)
			var alpha := pow(1.0 - edge, 1.7)
			var white_weight := pow(1.0 - edge, 4.0)
			var color := healing_particle_color.lerp(Color(1.0, 1.0, 1.0, 1.0), white_weight)
			color.a = alpha
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

func _draw() -> void:
	_draw_lamp()
	_draw_healing_particles()
	_draw_save_radius()

func _draw_lamp() -> void:
	var post_top := Vector2(0.0, -base_height)
	var post_bottom := Vector2(0.0, 0.0)
	draw_line(post_bottom, post_top, lamp_edge_color, 6.0, true)
	draw_line(post_bottom + Vector2(-16.0, 0.0), post_bottom + Vector2(16.0, 0.0), lamp_edge_color, 5.0, true)
	draw_line(post_bottom + Vector2(-10.0, -10.0), post_bottom + Vector2(10.0, -10.0), lamp_color, 7.0, true)

	var head_center := post_top + Vector2(0.0, -12.0)
	var half_width := lamp_width * 0.5
	var lamp_points := PackedVector2Array([
		head_center + Vector2(-half_width, -10.0),
		head_center + Vector2(half_width, -10.0),
		head_center + Vector2(half_width * 0.72, 16.0),
		head_center + Vector2(-half_width * 0.72, 16.0),
	])
	draw_colored_polygon(lamp_points, lamp_color)
	var closed := PackedVector2Array(lamp_points)
	closed.append(lamp_points[0])
	draw_polyline(closed, lamp_edge_color, 3.0, true)

	var flame_center := head_center + Vector2(0.0, 4.0)
	var flame_points := PackedVector2Array([
		flame_center + Vector2(0.0, -half_width * 0.7),
		flame_center + Vector2(half_width * 0.38, -half_width * 0.08),
		flame_center + Vector2(half_width * 0.16, half_width * 0.52),
		flame_center + Vector2(-half_width * 0.22, half_width * 0.48),
		flame_center + Vector2(-half_width * 0.4, -half_width * 0.04),
	])
	draw_colored_polygon(flame_points, flame_color)

func _draw_save_radius() -> void:
	if Engine.is_editor_hint():
		if not show_editor_visual:
			return
	elif not show_runtime_visual:
		return
	var outline := debug_color
	outline.a = minf(debug_color.a + 0.45, 1.0)
	draw_circle(Vector2.ZERO, debug_radius, debug_color)
	draw_arc(Vector2.ZERO, debug_radius, 0.0, TAU, 48, outline, 3.0, true)

func _update_healing_particles(delta: float) -> void:
	if _healing_player != null and is_instance_valid(_healing_player) and _heal_queue.size() > 0:
		_heal_emit_timer -= delta
		if _heal_emit_timer <= 0.0:
			_emit_healing_particle(_healing_player, int(_heal_queue.pop_front()))
			_heal_emit_timer = healing_particle_interval
	for index in range(_heal_particles.size() - 1, -1, -1):
		var particle := _heal_particles[index]
		var target := particle.get("target") as Node2D
		if target == null or not is_instance_valid(target):
			_free_particle_light(particle)
			_heal_particles.remove_at(index)
			continue
		var target_position := to_local(target.global_position + Vector2(0.0, -38.0))
		var position_value := particle.get("position") as Vector2
		position_value = position_value.move_toward(target_position, healing_particle_speed * delta)
		particle["position"] = position_value
		particle["age"] = float(particle.get("age")) + delta
		_update_particle_light(particle)
		_heal_particles[index] = particle
		if position_value.distance_to(target_position) <= maxf(healing_particle_radius * 1.4, 8.0):
			var did_restore := false
			if target.has_method("restore_mask_health_step"):
				did_restore = bool(target.call("restore_mask_health_step", int(particle.get("mask_state"))))
			if did_restore and target.has_method("play_soul_heal_flash"):
				target.call("play_soul_heal_flash", healing_particle_color)
			_free_particle_light(particle)
			_heal_particles.remove_at(index)
	if _healing_player != null and _heal_queue.is_empty() and _heal_particles.is_empty():
		_request_save()
		_healing_player = null
	queue_redraw()

func _emit_healing_particle(target: Node2D, mask_state: int) -> void:
	var particle := {
		"position": Vector2(0.0, -base_height - 8.0),
		"target": target,
		"mask_state": mask_state,
		"age": 0.0,
		"light": _make_healing_particle_light(),
	}
	_update_particle_light(particle)
	_heal_particles.append(particle)

func _make_healing_particle_light() -> PointLight2D:
	var particle_light := PointLight2D.new()
	particle_light.name = "HealingParticleLight"
	if _healing_particle_light_texture == null:
		_healing_particle_light_texture = _make_radial_light_texture(128)
	particle_light.texture = _healing_particle_light_texture
	particle_light.color = healing_particle_color
	particle_light.energy = healing_particle_light_energy
	particle_light.texture_scale = healing_particle_light_scale
	particle_light.range_z_min = -100
	particle_light.range_z_max = 100
	particle_light.z_index = 6
	particle_light.z_as_relative = false
	add_child(particle_light)
	return particle_light

func _update_particle_light(particle: Dictionary) -> void:
	var particle_light := particle.get("light") as PointLight2D
	if particle_light == null:
		return
	var age := float(particle.get("age"))
	var pulse := 0.92 + 0.08 * sin(age * 7.0)
	particle_light.position = particle.get("position") as Vector2
	particle_light.color = healing_particle_color
	particle_light.energy = healing_particle_light_energy * pulse
	particle_light.texture_scale = healing_particle_light_scale * pulse
	particle_light.enabled = true

func _free_particle_light(particle: Dictionary) -> void:
	var particle_light := particle.get("light") as PointLight2D
	if particle_light != null and is_instance_valid(particle_light):
		particle_light.queue_free()

func _clear_healing_particles() -> void:
	for particle in _heal_particles:
		_free_particle_light(particle)
	_heal_particles.clear()

func _draw_healing_particles() -> void:
	if _healing_particle_visual_texture == null:
		_healing_particle_visual_texture = _make_particle_visual_texture(96)
	for particle in _heal_particles:
		var position_value := particle.get("position") as Vector2
		var visual_size := Vector2.ONE * healing_particle_radius * 5.0
		var rect := Rect2(position_value - visual_size * 0.5, visual_size)
		draw_texture_rect(_healing_particle_visual_texture, rect, false)
