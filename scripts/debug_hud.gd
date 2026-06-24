extends Label

@export var player_path: NodePath
@export var camera_path: NodePath
@export var visible_by_default := false
@export var toggle_key := KEY_H
@export var panel_offset := Vector2(18.0, 18.0)
@export var panel_size := Vector2(1060.0, 128.0)

var player: Node2D
var game_camera: Camera2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = get_node_or_null(player_path) as Node2D
	game_camera = get_node_or_null(camera_path) as Camera2D
	_setup_panel_style()
	_set_debug_visible(visible_by_default)
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == toggle_key or event.physical_keycode == toggle_key):
		_set_debug_visible(not visible)
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	_update_debug_text()

func _setup_panel_style() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = panel_offset.x
	offset_top = panel_offset.y
	offset_right = panel_offset.x + panel_size.x
	offset_bottom = panel_offset.y + panel_size.y
	z_index = 120
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vertical_alignment = VERTICAL_ALIGNMENT_TOP
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
	add_theme_constant_override("outline_size", 5)
	add_theme_font_size_override("font_size", 16)

func _set_debug_visible(value: bool) -> void:
	visible = value
	set_process(value)
	if game_camera != null:
		game_camera.set("show_camera_zone_overlay", value)
	get_tree().call_group("camera_rooms", "set_debug_guides_visible", value)
	get_tree().call_group("save_debug_areas", "set_debug_visuals_visible", value)
	if value:
		_update_debug_text()

func _update_debug_text() -> void:
	var player_text := "player: missing"
	if player != null:
		player_text = "player: %s" % player.global_position.round()
		if player.has_method("get_mask_state_name") and player.has_method("get_current_animation_name") and player.has_method("get_current_mask_health") and player.has_method("get_max_mask_health"):
			player_text = "player: %s mask=%s hp=%s/%s anim=%s" % [
				player.global_position.round(),
				player.get_mask_state_name(),
				player.get_current_mask_health(),
				player.get_max_mask_health(),
				player.get_current_animation_name()
			]

	var camera_text := "camera: missing"
	if game_camera != null:
		var room_name = game_camera.get("active_room_name")
		camera_text = "camera: %s current=%s room=%s profile=%s view=%s no_follow=%s zoom=%s transition=%s" % [
			game_camera.global_position.round(),
			game_camera.is_current(),
			room_name,
			game_camera.get("active_camera_profile"),
			game_camera.get("active_camera_view_mode"),
			game_camera.get("active_no_follow"),
			game_camera.zoom.snapped(Vector2(0.01, 0.01)),
			game_camera.get("is_room_transitioning")
		]

	text = "Eudaimonia Debug  H: hide  FPS=%s\nA/D or arrows: move  W/Space: jump  J/X: throw mask  1/2/3 or Tab: switch mask\n%s\n%s" % [
		Engine.get_frames_per_second(),
		player_text,
		camera_text
	]
