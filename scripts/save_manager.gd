extends Node

signal save_started(checkpoint_position: Vector2)
signal save_finished(checkpoint_position: Vector2)
signal checkpoint_loaded(checkpoint_position: Vector2)

@export var save_duration := 0.75
@export var saveable_group := "saveable"
@export var transient_group := "save_transients"

var current_snapshot := {}
var is_saving := false
var current_checkpoint_position := Vector2.ZERO
var _save_timer := 0.0

func _ready() -> void:
	add_to_group("save_managers")

func _process(delta: float) -> void:
	if not is_saving:
		return

	_save_timer = maxf(_save_timer - delta, 0.0)
	if _save_timer <= 0.0:
		is_saving = false
		save_finished.emit(current_checkpoint_position)

func request_save(checkpoint_position: Vector2) -> void:
	current_checkpoint_position = checkpoint_position
	current_snapshot = _capture_scene_snapshot(checkpoint_position)
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
