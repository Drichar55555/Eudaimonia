@tool
extends Node2D

enum NpcKind { DUNGEON_RESIDENT, ELDER }

@export var npc_kind := NpcKind.DUNGEON_RESIDENT:
	set(value):
		npc_kind = value
		queue_redraw()
@export var player_path: NodePath
@export var dialogue_box_path: NodePath
@export var interaction_prompt := "按E对话"
@export var resident_name := "NPC"
@export var elder_name := "老人"

@export_group("Visual")
@export var body_color := Color(0.28, 0.42, 0.56, 1.0):
	set(value):
		body_color = value
		queue_redraw()
@export var robe_color := Color(0.35, 0.28, 0.45, 1.0):
	set(value):
		robe_color = value
		queue_redraw()
@export var edge_color := Color(0.06, 0.07, 0.08, 0.95):
	set(value):
		edge_color = value
		queue_redraw()
@export var prompt_color := Color(1.0, 0.9, 0.36, 1.0):
	set(value):
		prompt_color = value
		queue_redraw()

var _player_inside: Node
var _player_physics_was_enabled := true
var _dialogue_active := false
var _interact_was_down := false
var _elder_first_dialogue_done := false
var _dialogue_box: Node
var _player: Node

func _ready() -> void:
	z_index = 1
	z_as_relative = false
	add_to_group("saveable")
	add_to_group("dialogue_npcs")
	_connect_interaction_area()
	set_process(not Engine.is_editor_hint())
	queue_redraw()

func _process(_delta: float) -> void:
	_handle_interaction_input()
	if _player_inside != null:
		queue_redraw()

func get_save_state() -> Dictionary:
	return {"elder_first_dialogue_done": _elder_first_dialogue_done}

func apply_save_state(state: Dictionary) -> void:
	_elder_first_dialogue_done = bool(state.get("elder_first_dialogue_done", _elder_first_dialogue_done))

func _handle_interaction_input() -> void:
	var interact_down := Input.is_physical_key_pressed(KEY_E)
	if interact_down and not _interact_was_down and _player_inside != null and not _dialogue_active:
		_begin_dialogue()
	_interact_was_down = interact_down

func _begin_dialogue() -> void:
	_resolve_dialogue_box()
	if _dialogue_box == null or not _dialogue_box.has_method("show_dialogue"):
		return
	if _dialogue_box.has_method("is_dialogue_active") and bool(_dialogue_box.call("is_dialogue_active")):
		return
	_dialogue_active = true
	_pause_player(true)
	_run_dialogue()

func _run_dialogue() -> void:
	if npc_kind == NpcKind.ELDER:
		if _elder_first_dialogue_done:
			await _run_elder_repeat_dialogue()
		else:
			await _run_elder_first_dialogue()
			_elder_first_dialogue_done = true
	else:
		await _run_resident_dialogue()
	_finish_dialogue()

func _finish_dialogue() -> void:
	_pause_player(false)
	_dialogue_active = false
	_interact_was_down = true
	queue_redraw()

func _run_resident_dialogue() -> void:
	var dungeon_topic_done := false
	var below_topic_done := false
	await _say(resident_name, [
		"你好，我貌似没见过你。你是谁？",
	])
	await _say("Euda", ["我不知道。"])
	await _say(resident_name, [
		"没事，谁在乎这个呢。话说你是从哪里来到地下城的？",
	])
	var opening_choice := await _choose("Euda", "怎么回答？", ["地下城？", "从下面来的。"])
	if opening_choice == 0:
		await _resident_dungeon_topic()
		dungeon_topic_done = true
	else:
		await _resident_below_topic()
		below_topic_done = true
	while not (dungeon_topic_done and below_topic_done):
		if dungeon_topic_done:
			await _choose(resident_name, "还有什么别的想说的吗？", ["我是从下面来的。"])
			await _resident_below_topic()
			below_topic_done = true
		else:
			await _choose(resident_name, "还有什么别的想问的？", ["地下城是什么？地上世界又是什么？"])
			await _resident_dungeon_topic()
			dungeon_topic_done = true
	await _choose(resident_name, "还有什么别的想说的吗？", ["没什么了。"])
	await _say(resident_name, ["那就再见了！"])

func _resident_dungeon_topic() -> void:
	await _say(resident_name, [
		"这里被称为地下城。因为在这个世界的上面，还有另一个世界：地上世界。",
		"这个世界的天，就是地上世界的地。很多人都想到地上世界，因为据说在那里人人都能获得幸福。",
	])
	await _say("Euda", ["地上世界到底是什么？"])
	await _say(resident_name, [
		"具体是什么样，我也不知道。但城中最高的楼顶上住着一位老人，他毕生都在研究地上世界。",
		"你可以去问问他。",
	])

func _resident_below_topic() -> void:
	await _say(resident_name, [
		"下面？！那可是荆棘之地，非常危险。你为什么会出现在那里？",
	])
	await _say("Euda", ["不知道。"])
	await _say(resident_name, [
		"你是刚出生吗？生在那种地方可太不幸了。",
		"在地下世界，每个人都可能在任何地方出生。如果出生在城里，就能过上稍微好一点的生活。",
		"不过也没有好到哪里去。这里物质条件好一些，但大家还是都在追求进入地上世界。毕竟在那里才是真正的幸福。",
	])

func _run_elder_first_dialogue() -> void:
	await _say(elder_name, [
		"你找我有什么事吗？已经有103天3个小时没有人找我了。",
		"是想跟我聊聊地上世界的最新研究？",
	])
	await _say("Euda", ["嗯。"])
	await _say(elder_name, [
		"经过我上一个月的观测，我发现地上世界岩层的最下端，在这栋楼顶上有一块突兀的花岗岩。",
		"我正在研究它可能的来历。",
		"等等，你好像也没来找过我啊。我刚刚是不是说得有点复杂了？",
		"话说，你为什么要来找我？",
	])
	await _say("Euda", ["我听说你对地上世界有很多研究，想问问地上世界到底是什么。"])
	await _elder_world_lore(false)
	await _say("Euda", ["那你为什么不去呢？"])
	await _elder_personal_reason(false)
	await _say(elder_name, ["对呀，你是面具使用者，你应该挑战一下的。"])
	await _say("Euda", ["面具能干什么？"])
	await _elder_mask_lore(false)
	var resolve_choice := await _choose("Euda", "你怎么回答？", ["好。", "我不想……"])
	if resolve_choice == 1:
		await _say(elder_name, [
			"但你到了地上世界之后会获得幸福啊。",
			"我知道这很难，但你今天的所有努力，都是为了以后的荣光，为了未来的幸福。",
		])
		await _choose("Euda", "最后还是要回答。", ["我愿意尝试。", "我愿意尝试。"])
	await _elder_encouragement()

func _run_elder_repeat_dialogue() -> void:
	while true:
		var choice := await _choose(elder_name, "你想了解什么？", [
			"地上世界是什么？",
			"你为什么不去地上世界？",
			"面具能干什么？",
		])
		match choice:
			0:
				await _elder_world_lore(true)
			1:
				await _elder_personal_reason(true)
			2:
				await _elder_mask_lore(true)
		var next_choice := await _choose(elder_name, "还有什么想听的？", ["再见。", "我还想听其他的。"])
		if next_choice == 0:
			await _say(elder_name, ["再见。"])
			return

func _elder_world_lore(include_followup: bool) -> void:
	await _say(elder_name, [
		"哦，那是一个很好的地方。",
		"但我一生都没有去过。",
		"看到这里的岩石柱了吗？那就是地上世界的底端。",
		"而我们生活的地方，则是在暗无光日的地下世界。",
		"据说在很久之前的古代，神明对世界万物下达了一次审判。",
		"那些高人一等的生物，可以生活在地上世界。",
		"根据古籍记载，他们可以享受阳光、草地和幸福。虽然我并不知道那是什么，但一定是好东西。",
		"而我们，则是被审判的低等物种，只能在地下受罪。",
		"但我们中有一群勇士不服这样的审判，硬生生地日复一日，终于挖通了两个世界。",
		"这样的举动激怒了神明。",
		"但勇士们表示，如果再次封住入口，他们还会世世代代地挖掘。",
		"最后，这份坚韧也打动了神明。但不能违背自然之道，所以神明留下了一个试炼。",
		"凡是经过试炼的人，才得以进入地上世界。",
		"以前我有一些朋友就通过试炼进入了地上世界。",
		"可能是过得太幸福了，他们都不愿意回来了。",
		"也正因如此，地上世界的消息已经几百年没有更新了。",
	])
	if include_followup:
		return

func _elder_personal_reason(_include_followup: bool) -> void:
	await _say(elder_name, [
		"我吗……哎，我年轻时也挑战过试炼。",
		"但我没有天赋。我没有面具，不能使用特殊能力。",
	])

func _elder_mask_lore(_include_followup: bool) -> void:
	await _say(elder_name, [
		"面具是灵魂的容器。只要戴上，你就能模仿面具中盛放的别人的灵魂。",
		"虽然那只是拙劣的模仿，但拙劣的模仿也是模仿，你仍然能获得更强的能力。",
		"而你自己的灵魂可以被保护。",
		"正因如此，每个面具形态都能抵挡两次灵魂伤害。受伤后切换到其他面具，就能恢复灵魂的能量。",
		"而当你戴着面具时，也没人会看到你的灵魂，甚至你自己都看不到了。",
	])

func _elder_encouragement() -> void:
	await _say(elder_name, [
		"对。为了以后的幸福，现在辛苦一下，忍一下。",
		"你现在的一切，都应该可以为接下来地上世界的幸福生活牺牲。",
		"加油，我的孩子。",
	])

func _say(speaker: String, lines: Array[String]) -> void:
	_resolve_dialogue_box()
	if _dialogue_box == null:
		return
	_dialogue_box.call("show_dialogue", speaker, lines)
	await _dialogue_box.dialogue_finished

func _choose(speaker: String, prompt: String, choices: Array[String]) -> int:
	_resolve_dialogue_box()
	if _dialogue_box == null:
		return 0
	if not _dialogue_box.has_method("show_choice_dialogue") or not _dialogue_box.has_signal("choice_selected"):
		_dialogue_box.call("show_dialogue", speaker, [prompt])
		await _dialogue_box.dialogue_finished
		return 0
	var selected_index := 0
	var selected_callable := func(index: int) -> void:
		selected_index = index
	_dialogue_box.choice_selected.connect(selected_callable, CONNECT_ONE_SHOT)
	_dialogue_box.call("show_choice_dialogue", speaker, prompt, choices)
	await _dialogue_box.choice_selected
	return selected_index

func _pause_player(paused: bool) -> void:
	_resolve_player()
	if _player == null or not is_instance_valid(_player):
		return
	if paused:
		_player_physics_was_enabled = _player.is_physics_processing()
		_player.set_physics_process(false)
		if _player is CharacterBody2D:
			(_player as CharacterBody2D).velocity = Vector2.ZERO
	else:
		_player.set_physics_process(_player_physics_was_enabled)

func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	if not player_path.is_empty():
		_player = get_node_or_null(player_path)
	if _player == null and get_tree() != null:
		_player = get_tree().get_first_node_in_group("players")

func _resolve_dialogue_box() -> void:
	if _dialogue_box != null and is_instance_valid(_dialogue_box):
		return
	if not dialogue_box_path.is_empty():
		_dialogue_box = get_node_or_null(dialogue_box_path)
	if _dialogue_box == null and get_tree() != null:
		_dialogue_box = get_tree().get_first_node_in_group("dialogue_boxes")

func _connect_interaction_area() -> void:
	var interaction_area := get_node_or_null("InteractionArea") as Area2D
	if interaction_area == null:
		return
	if not interaction_area.body_entered.is_connected(_on_interaction_body_entered):
		interaction_area.body_entered.connect(_on_interaction_body_entered)
	if not interaction_area.body_exited.is_connected(_on_interaction_body_exited):
		interaction_area.body_exited.connect(_on_interaction_body_exited)

func _on_interaction_body_entered(body: Node) -> void:
	if body != null and body.is_in_group("players"):
		_player_inside = body
		queue_redraw()

func _on_interaction_body_exited(body: Node) -> void:
	if body == _player_inside:
		_player_inside = null
		queue_redraw()

func _draw() -> void:
	_draw_character()
	if _player_inside != null and not _dialogue_active:
		_draw_interaction_prompt()

func _draw_character() -> void:
	var is_elder := npc_kind == NpcKind.ELDER
	var main_color := robe_color if is_elder else body_color
	draw_circle(Vector2(0.0, -88.0), 22.0, Color(0.72, 0.62, 0.48, 1.0))
	draw_circle(Vector2(0.0, -88.0), 22.0, edge_color, false, 2.0)
	draw_rect(Rect2(Vector2(-22.0, -68.0), Vector2(44.0, 68.0)), main_color, true)
	draw_rect(Rect2(Vector2(-22.0, -68.0), Vector2(44.0, 68.0)), edge_color, false, 2.0)
	draw_line(Vector2(-14.0, -4.0), Vector2(-28.0, 20.0), edge_color, 3.0)
	draw_line(Vector2(14.0, -4.0), Vector2(28.0, 20.0), edge_color, 3.0)
	draw_circle(Vector2(-8.0, -92.0), 2.2, edge_color)
	draw_circle(Vector2(8.0, -92.0), 2.2, edge_color)
	if is_elder:
		draw_arc(Vector2(0.0, -83.0), 12.0, 0.0, PI, 12, Color(0.86, 0.86, 0.78, 1.0), 5.0)
		draw_line(Vector2(-16.0, -111.0), Vector2(16.0, -111.0), Color(0.86, 0.86, 0.78, 1.0), 7.0)
		draw_line(Vector2(20.0, -68.0), Vector2(38.0, 12.0), Color(0.55, 0.42, 0.24, 1.0), 4.0)
	else:
		draw_arc(Vector2(0.0, -85.0), 9.0, 0.15, PI - 0.15, 12, edge_color, 2.0)

func _draw_interaction_prompt() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	draw_rect(Rect2(Vector2(-52.0, -140.0), Vector2(104.0, 24.0)), Color(0.02, 0.025, 0.035, 0.78), true)
	draw_rect(Rect2(Vector2(-52.0, -140.0), Vector2(104.0, 24.0)), Color(prompt_color.r, prompt_color.g, prompt_color.b, 0.55), false, 1.5)
	draw_string(font, Vector2(-48.0, -122.0), interaction_prompt, HORIZONTAL_ALIGNMENT_CENTER, 96.0, 14, prompt_color)