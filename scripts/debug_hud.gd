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

	var camera_text := "camera: missing"
	if game_camera != null:
		var room_name = game_camera.get("active_room_name")
		camera_text = "camera: %s current=%s room=%s zoom=%s transition=%s" % [
			game_camera.global_position.round(),
			game_camera.is_current(),
			room_name,
			game_camera.zoom.snapped(Vector2(0.01, 0.01)),
			game_camera.get("is_room_transitioning")
		]

	text = "Eudaimonia\nA/D or arrows: move  W/Space: jump\n%s\n%s" % [player_text, camera_text]
