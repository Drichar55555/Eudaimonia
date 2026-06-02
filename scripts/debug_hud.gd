extends Label

@export var player_path: NodePath
@export var camera_path: NodePath

var player: Node2D
var game_camera: Camera2D

func _ready() -> void:
	player = get_node_or_null(player_path) as Node2D
	game_camera = get_node_or_null(camera_path) as Camera2D

func _process(_delta: float) -> void:
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

		text = "Eudaimonia\nA/D or arrows: move  W/Space: jump  J/X: throw mask  1/2/3 or Tab: switch mask\n%s\n%s" % [player_text, camera_text]
