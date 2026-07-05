extends Node

signal save_started(checkpoint_position: Vector2)
signal save_finished(checkpoint_position: Vector2)
signal checkpoint_loaded(checkpoint_position: Vector2)

@export var save_duration := 0.75
@export var saveable_group := "saveable"
@export var transient_group := "save_transients"
@export_range(1, 6, 1) var max_rollback_entries := 3
@export var default_checkpoint_name := "初始洞穴"
@export var screenshot_size := Vector2i(320, 180)

var current_snapshot := {}
var is_saving := false
var current_checkpoint_position := Vector2.ZERO
var rollback_entries: Array[Dictionary] = []
var _save_timer := 0.0
var _initial_snapshot := {}
var _initial_checkpoint_position := Vector2.ZERO

func _ready() -> void:
	add_to_group("save_managers")
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_capture_initial_snapshot")

func _process(delta: float) -> void:
	if not is_saving:
		return

	_save_timer = maxf(_save_timer - delta, 0.0)
	if _save_timer <= 0.0:
		is_saving = false
		save_finished.emit(current_checkpoint_position)

func request_save(checkpoint_position: Vector2, checkpoint_name: String = "") -> void:
	current_checkpoint_position = checkpoint_position
	current_snapshot = _capture_scene_snapshot(checkpoint_position)
	var entry := _make_rollback_entry(current_snapshot, checkpoint_position, checkpoint_name)
	rollback_entries.push_front(entry)
	_trim_rollback_entries()
	_capture_rollback_thumbnail(entry)
	is_saving = true
	_save_timer = save_duration
	save_started.emit(checkpoint_position)

func has_checkpoint() -> bool:
	return not current_snapshot.is_empty()

func load_checkpoint() -> void:
	if current_snapshot.is_empty():
		return

	_remove_transient_nodes()
	_restore_scene_snapshot(current_snapshot)
	checkpoint_loaded.emit(current_checkpoint_position)

func get_rollback_entries() -> Array[Dictionary]:
	return rollback_entries.duplicate()

func get_rollback_entry_count() -> int:
	return rollback_entries.size()

func load_rollback_entry(index: int) -> bool:
	if index < 0 or index >= rollback_entries.size():
		return false
	var entry := rollback_entries[index]
	var snapshot := entry.get("snapshot", {}) as Dictionary
	if snapshot.is_empty():
		return false
	current_snapshot = snapshot.duplicate(true)
	current_checkpoint_position = entry.get("checkpoint_position", Vector2.ZERO)
	_remove_transient_nodes()
	_restore_scene_snapshot(current_snapshot)
	checkpoint_loaded.emit(current_checkpoint_position)
	return true

func reset_to_initial_state() -> bool:
	if _initial_snapshot.is_empty():
		_capture_initial_snapshot()
	if _initial_snapshot.is_empty():
		return false
	current_snapshot.clear()
	rollback_entries.clear()
	current_checkpoint_position = _initial_checkpoint_position
	is_saving = false
	_save_timer = 0.0
	_remove_transient_nodes()
	_restore_scene_snapshot(_initial_snapshot)
	checkpoint_loaded.emit(current_checkpoint_position)
	return true

func has_initial_snapshot() -> bool:
	return not _initial_snapshot.is_empty()

func _capture_initial_snapshot() -> void:
	_initial_checkpoint_position = _initial_player_checkpoint_position()
	_initial_snapshot = _capture_scene_snapshot(_initial_checkpoint_position)

func _initial_player_checkpoint_position() -> Vector2:
	var player := get_tree().get_first_node_in_group("players")
	if player != null:
		var spawn_value: Variant = player.get("spawn_position")
		if spawn_value is Vector2:
			return spawn_value
		if player is Node2D:
			return (player as Node2D).global_position
	return Vector2.ZERO

func _make_rollback_entry(snapshot: Dictionary, checkpoint_position: Vector2, checkpoint_name: String) -> Dictionary:
	var resolved_name := checkpoint_name.strip_edges()
	if resolved_name.is_empty():
		resolved_name = default_checkpoint_name
	var now := Time.get_datetime_dict_from_system()
	return {
		"snapshot": snapshot.duplicate(true),
		"checkpoint_position": checkpoint_position,
		"checkpoint_name": resolved_name,
		"saved_at": now,
		"saved_at_text": _format_datetime_minute(now),
		"thumbnail": null,
	}

func _trim_rollback_entries() -> void:
	var limit := maxi(max_rollback_entries, 1)
	while rollback_entries.size() > limit:
		rollback_entries.pop_back()

func _format_datetime_minute(datetime: Dictionary) -> String:
	return "%04d-%02d-%02d %02d:%02d" % [
		int(datetime.get("year", 0)),
		int(datetime.get("month", 0)),
		int(datetime.get("day", 0)),
		int(datetime.get("hour", 0)),
		int(datetime.get("minute", 0)),
	]

func _capture_rollback_thumbnail(entry: Dictionary) -> void:
	_capture_rollback_thumbnail_async(entry)

func _capture_rollback_thumbnail_async(entry: Dictionary) -> void:
	var hidden_layers := _set_canvas_layers_visible(false)
	await RenderingServer.frame_post_draw
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture != null:
		var image := viewport_texture.get_image()
		if image != null and not image.is_empty():
			var target_size := _thumbnail_size_for_image(image.get_size())
			image.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
			entry["thumbnail"] = ImageTexture.create_from_image(image)
	_set_canvas_layers_from_records(hidden_layers)

func _thumbnail_size_for_image(source_size: Vector2i) -> Vector2i:
	if source_size.x <= 0 or source_size.y <= 0:
		return screenshot_size
	var max_size := Vector2(maxi(screenshot_size.x, 1), maxi(screenshot_size.y, 1))
	var source := Vector2(source_size)
	var scale := minf(max_size.x / source.x, max_size.y / source.y)
	return Vector2i(maxi(roundi(source.x * scale), 1), maxi(roundi(source.y * scale), 1))

func _set_canvas_layers_visible(is_visible: bool) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for layer in _find_canvas_layers(get_tree().current_scene):
		var canvas_layer := layer as CanvasLayer
		if canvas_layer == null or not is_instance_valid(canvas_layer):
			continue
		records.append({"layer": canvas_layer, "visible": canvas_layer.visible})
		canvas_layer.visible = is_visible
	return records

func _find_canvas_layers(root: Node) -> Array[CanvasLayer]:
	var layers: Array[CanvasLayer] = []
	if root == null:
		return layers
	if root is CanvasLayer:
		layers.append(root as CanvasLayer)
	for child in root.get_children():
		layers.append_array(_find_canvas_layers(child))
	return layers

func _set_canvas_layers_from_records(records: Array[Dictionary]) -> void:
	for record in records:
		var canvas_layer := record.get("layer") as CanvasLayer
		if canvas_layer != null and is_instance_valid(canvas_layer):
			canvas_layer.visible = bool(record.get("visible", true))

func _capture_scene_snapshot(checkpoint_position: Vector2) -> Dictionary:
	var saved_nodes := {}
	for node in get_tree().get_nodes_in_group(saveable_group):
		if node == null or not is_instance_valid(node):
			continue
		var node_path := str(node.get_path())
		var state := {}
		if node.has_method("get_save_state"):
			state = node.get_save_state()
		saved_nodes[node_path] = {
			"path": node_path,
			"parent_path": str(node.get_parent().get_path()) if node.get_parent() != null else "",
			"name": node.name,
			"scene_path": _scene_path_for_node(node),
			"state": state,
		}

	return {
		"checkpoint_position": checkpoint_position,
		"saved_nodes": saved_nodes,
	}

func _restore_scene_snapshot(snapshot: Dictionary) -> void:
	var saved_nodes: Dictionary = snapshot.get("saved_nodes", {})
	for node in get_tree().get_nodes_in_group(saveable_group).duplicate():
		if node != null and is_instance_valid(node) and not saved_nodes.has(str(node.get_path())):
			node.queue_free()

	for node_path in saved_nodes.keys():
		var record: Dictionary = saved_nodes[node_path]
		var node := get_node_or_null(NodePath(str(record.get("path", ""))))
		if node == null:
			node = _recreate_node(record)
		if node != null and node.has_method("apply_save_state"):
			node.apply_save_state(record.get("state", {}))

func _recreate_node(record: Dictionary) -> Node:
	var scene_path := str(record.get("scene_path", ""))
	var parent_path := str(record.get("parent_path", ""))
	if scene_path.is_empty() or parent_path.is_empty():
		return null

	var parent := get_node_or_null(NodePath(parent_path))
	if parent == null:
		return null

	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		return null

	var node := packed_scene.instantiate()
	if node == null:
		return null

	node.name = str(record.get("name", node.name))
	parent.add_child(node)
	return node

func _scene_path_for_node(node: Node) -> String:
	if node.has_method("get_save_scene_path"):
		return str(node.get_save_scene_path())
	return node.scene_file_path

func _remove_transient_nodes() -> void:
	for node in get_tree().get_nodes_in_group(transient_group):
		if node != null and is_instance_valid(node):
			node.queue_free()
