@tool
extends CharacterBody2D

enum NpcKind { DUNGEON_RESIDENT, ELDER }
enum FsmState { IDLE, WALK }

const TERRAIN_LAYER := 1 << 0
const MIN_WALK_RANGE_WIDTH := 16.0
const WALK_RANGE_GUIDE_Y := 30.0
const WALK_RANGE_COLOR := Color(0.1, 0.9, 1.0, 0.95)
const WALK_RANGE_HANDLE_COLOR := Color(1.0, 0.72, 0.08, 1.0)

@export var npc_kind := NpcKind.DUNGEON_RESIDENT:
	set(value):
		npc_kind = value
		queue_redraw()
@export var player_path: NodePath
@export var dialogue_box_path: NodePath
@export var interaction_prompt := "按E对话"
@export var resident_name := "NPC"
@export var elder_name := "老人"
@export var ui_font: Font

@export_group("FSM")
@export var movement_enabled := true
@export var start_with_idle := true
@export_range(0.0, 240.0, 1.0) var walk_speed := 42.0
@export_range(0.0, 2400.0, 10.0) var walk_acceleration := 520.0
@export_range(0.0, 2400.0, 10.0) var walk_deceleration := 760.0
@export_range(0.1, 3.0, 0.05) var gravity_scale := 1.0
@export_range(120.0, 1800.0, 10.0) var max_fall_speed := 900.0
@export var avoid_ledges := true

@export_group("Walk Range")
@export_range(0.0, 2000.0, 1.0) var walk_left_offset := 160.0:
	set(value):
		walk_left_offset = maxf(absf(value), maxf(MIN_WALK_RANGE_WIDTH - walk_right_offset, 0.0))
		queue_redraw()
@export_range(0.0, 2000.0, 1.0) var walk_right_offset := 160.0:
	set(value):
		walk_right_offset = maxf(value, maxf(MIN_WALK_RANGE_WIDTH - walk_left_offset, 0.0))
		queue_redraw()

@export_group("Pseudo Random Idle")
@export_range(0.0, 1.0, 0.01) var idle_probability := 0.28
@export_range(0.1, 4.0, 0.05) var idle_decision_interval := 0.65
@export_range(0.0, 10.0, 0.1) var minimum_walk_before_idle := 1.4
@export_range(0.2, 30.0, 0.1) var maximum_walk_without_idle := 7.0
@export_range(0.0, 1.0, 0.01) var pseudo_random_strength := 0.42
@export_range(0.1, 20.0, 0.1) var idle_duration_min := 1.0
@export_range(0.1, 20.0, 0.1) var idle_duration_max := 2.8

@export_group("Animation Placeholders")
@export var animation_player_path := NodePath("AnimationPlayer")
@export var visual_root_path := NodePath("VisualRoot")
@export var idle_animation: StringName = &"idle"
@export var walk_animation: StringName = &"walk"

@export_group("Player Collision")
@export_range(0.05, 1.0, 0.01) var collision_recoil_duration := 0.3
@export_range(0.05, 2.0, 0.01) var collision_cooldown := 0.65
@export_range(0.0, 500.0, 5.0) var collision_recoil_speed := 125.0
@export_range(0.0, 3000.0, 10.0) var collision_recoil_deceleration := 760.0
@export_range(0.05, 1.0, 0.01) var collision_animation_duration := 0.34
@export var collision_animation: StringName = &"bump"
@export_range(0.1, 5.0, 0.1) var collision_speech_duration := 1.5
@export_range(0.0, 1000.0, 0.1) var silence_weight := 1.0
@export var collision_responses: Array[Dictionary] = []

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
var current_fsm_state := FsmState.IDLE
var _walk_origin_global_x := 0.0
var _walk_direction := 1.0
var _idle_timer := 0.0
var _walk_elapsed := 0.0
var _decision_timer := 0.0
var _failed_idle_rolls := 0
var _rng := RandomNumberGenerator.new()
var _animation_player: AnimationPlayer
var _visual_root: Node2D
var _floor_probe: RayCast2D
var _collision_recoil_timer := 0.0
var _collision_cooldown_timer := 0.0
var _collision_animation_timer := 0.0
var _collision_recoil_direction := 0.0
var _collision_speech_timer := 0.0
var _collision_speech_label: Label

func _ready() -> void:
	z_index = 80 if Engine.is_editor_hint() else 1
	z_as_relative = false
	add_to_group("saveable")
	add_to_group("dialogue_npcs")
	add_to_group("editable_dialogue_npcs")
	_connect_interaction_area()
	_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	_visual_root = get_node_or_null(visual_root_path) as Node2D
	_floor_probe = get_node_or_null("FloorProbe") as RayCast2D
	_collision_speech_label = get_node_or_null("CollisionSpeech") as Label
	_resolve_ui_font()
	_walk_origin_global_x = global_position.x
	_rng.randomize()
	if not Engine.is_editor_hint():
		_enter_fsm_state(FsmState.IDLE if start_with_idle else FsmState.WALK)
	_sync_walk_range_preview()
	set_process(true)
	set_physics_process(not Engine.is_editor_hint())
	queue_redraw()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_walk_range_preview()
		return
	_update_collision_speech(delta)
	_handle_interaction_input()
	if _player_inside != null:
		queue_redraw()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var collision_animation_was_active := _collision_animation_timer > 0.0
	_collision_cooldown_timer = maxf(_collision_cooldown_timer - delta, 0.0)
	_collision_animation_timer = maxf(_collision_animation_timer - delta, 0.0)
	if collision_animation_was_active:
		queue_redraw()
	_apply_gravity(delta)
	if _collision_recoil_timer > 0.0:
		_collision_recoil_timer = maxf(_collision_recoil_timer - delta, 0.0)
		velocity.x = move_toward(velocity.x, 0.0, collision_recoil_deceleration * delta)
		_play_fsm_animation(collision_animation)
		queue_redraw()
	elif not movement_enabled or _dialogue_active:
		velocity.x = move_toward(velocity.x, 0.0, walk_deceleration * delta)
		_play_fsm_animation(idle_animation)
	else:
		match current_fsm_state:
			FsmState.IDLE:
				_update_idle_state(delta)
			FsmState.WALK:
				_update_walk_state(delta)
	move_and_slide()
	_handle_player_body_collisions()
	_enforce_walk_bounds()
	if current_fsm_state == FsmState.WALK and is_on_wall():
		_walk_direction *= -1.0
		_update_facing()

func _handle_player_body_collisions() -> void:
	if _collision_cooldown_timer > 0.0 or _dialogue_active:
		return
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var player_body := collision.get_collider() as CharacterBody2D
		if player_body == null or not player_body.is_in_group("players"):
			continue
		if player_body.has_method("handle_dialogue_npc_collision"):
			# This collision normal points away from the player for the NPC body;
			# invert it to obtain the player's outward recoil direction.
			player_body.call(
				"handle_dialogue_npc_collision",
				self,
				absf(player_body.velocity.x),
				-collision.get_normal().x
			)
		return

func receive_player_collision(_player_body: CharacterBody2D, recoil_direction: float, _impact_speed: float) -> bool:
	if Engine.is_editor_hint() or _dialogue_active or _collision_cooldown_timer > 0.0:
		return false
	_collision_recoil_direction = -1.0 if recoil_direction < 0.0 else 1.0
	_collision_recoil_timer = maxf(collision_recoil_duration, 0.0)
	_collision_cooldown_timer = maxf(collision_cooldown, _collision_recoil_timer)
	_collision_animation_timer = maxf(collision_animation_duration, 0.0)
	velocity.x = _collision_recoil_direction * collision_recoil_speed
	_walk_direction = _collision_recoil_direction
	_update_facing()
	_play_fsm_animation(collision_animation)
	_show_weighted_collision_line()
	queue_redraw()
	return true

func _show_weighted_collision_line() -> void:
	if _collision_speech_label == null:
		return
	var total_weight := maxf(silence_weight, 0.0)
	for entry in collision_responses:
		var content := str(entry.get("content", "")).strip_edges()
		if not content.is_empty():
			total_weight += maxf(float(entry.get("weight", 1.0)), 0.0)
	if total_weight <= 0.0:
		_hide_collision_speech()
		return
	var roll := _rng.randf() * total_weight
	if roll < maxf(silence_weight, 0.0):
		_hide_collision_speech()
		return
	roll -= maxf(silence_weight, 0.0)
	for entry in collision_responses:
		var content := str(entry.get("content", "")).strip_edges()
		if content.is_empty():
			continue
		var entry_weight := maxf(float(entry.get("weight", 1.0)), 0.0)
		if roll < entry_weight:
			_collision_speech_label.text = content
			_collision_speech_label.visible = true
			_collision_speech_timer = maxf(collision_speech_duration, 0.1)
			return
		roll -= entry_weight
	_hide_collision_speech()

func _update_collision_speech(delta: float) -> void:
	if _collision_speech_timer <= 0.0:
		return
	_collision_speech_timer = maxf(_collision_speech_timer - delta, 0.0)
	if _collision_speech_timer <= 0.0:
		_hide_collision_speech()

func _hide_collision_speech() -> void:
	_collision_speech_timer = 0.0
	if _collision_speech_label != null:
		_collision_speech_label.visible = false
		_collision_speech_label.text = ""

func get_save_state() -> Dictionary:
	return {
		"elder_first_dialogue_done": _elder_first_dialogue_done,
		"position": global_position,
		"velocity": velocity,
		"fsm_state": current_fsm_state,
		"walk_origin_global_x": _walk_origin_global_x,
		"walk_direction": _walk_direction,
		"idle_timer": _idle_timer,
		"walk_elapsed": _walk_elapsed,
		"decision_timer": _decision_timer,
		"failed_idle_rolls": _failed_idle_rolls,
	}

func apply_save_state(state: Dictionary) -> void:
	_elder_first_dialogue_done = bool(state.get("elder_first_dialogue_done", _elder_first_dialogue_done))
	global_position = state.get("position", global_position)
	velocity = state.get("velocity", velocity)
	_walk_origin_global_x = float(state.get("walk_origin_global_x", _walk_origin_global_x))
	_walk_direction = float(state.get("walk_direction", _walk_direction))
	_idle_timer = float(state.get("idle_timer", _idle_timer))
	_walk_elapsed = float(state.get("walk_elapsed", _walk_elapsed))
	_decision_timer = float(state.get("decision_timer", _decision_timer))
	_failed_idle_rolls = int(state.get("failed_idle_rolls", _failed_idle_rolls))
	_collision_recoil_timer = 0.0
	_collision_cooldown_timer = 0.0
	_collision_animation_timer = 0.0
	_hide_collision_speech()
	current_fsm_state = clampi(int(state.get("fsm_state", current_fsm_state)), FsmState.IDLE, FsmState.WALK)
	_play_fsm_animation(idle_animation if current_fsm_state == FsmState.IDLE else walk_animation)
	_update_facing()

func get_walk_range_points() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-walk_left_offset, WALK_RANGE_GUIDE_Y),
		Vector2(walk_right_offset, WALK_RANGE_GUIDE_Y),
	])

func set_walk_range_endpoint_from_editor(index: int, local_position: Vector2) -> void:
	if index == 0:
		walk_left_offset = maxf(-local_position.x, maxf(MIN_WALK_RANGE_WIDTH - walk_right_offset, 0.0))
	elif index == 1:
		walk_right_offset = maxf(local_position.x, maxf(MIN_WALK_RANGE_WIDTH - walk_left_offset, 0.0))
	_sync_walk_range_preview()
	queue_redraw()

func is_point_near_walk_range(local_position: Vector2, tolerance: float = 14.0) -> bool:
	var left := Vector2(-walk_left_offset, 0.0)
	var right := Vector2(walk_right_offset, 0.0)
	var segment := right - left
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return local_position.distance_to(left) <= tolerance
	var progress := clampf((local_position - left).dot(segment) / length_squared, 0.0, 1.0)
	return local_position.distance_to(left + segment * progress) <= tolerance

func _enter_fsm_state(next_state: FsmState) -> void:
	current_fsm_state = next_state
	match current_fsm_state:
		FsmState.IDLE:
			velocity.x = 0.0
			_idle_timer = _rng.randf_range(minf(idle_duration_min, idle_duration_max), maxf(idle_duration_min, idle_duration_max))
			_failed_idle_rolls = 0
			_play_fsm_animation(idle_animation)
		FsmState.WALK:
			_walk_elapsed = 0.0
			_schedule_next_idle_decision()
			_choose_walk_direction()
			_play_fsm_animation(walk_animation)

func _update_idle_state(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, walk_deceleration * delta)
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_enter_fsm_state(FsmState.WALK)

func _update_walk_state(delta: float) -> void:
	_walk_elapsed += delta
	_decision_timer -= delta
	var left_bound := _walk_origin_global_x - walk_left_offset
	var right_bound := _walk_origin_global_x + walk_right_offset
	if global_position.x <= left_bound:
		_walk_direction = 1.0
	elif global_position.x >= right_bound:
		_walk_direction = -1.0
	if _should_turn_at_ledge():
		_walk_direction *= -1.0
	velocity.x = move_toward(velocity.x, _walk_direction * walk_speed, walk_acceleration * delta)
	_update_facing()

	if _walk_elapsed >= maxf(maximum_walk_without_idle, minimum_walk_before_idle):
		_enter_fsm_state(FsmState.IDLE)
		return
	if _walk_elapsed < minimum_walk_before_idle or _decision_timer > 0.0:
		return
	if _roll_pseudo_random_idle():
		_enter_fsm_state(FsmState.IDLE)
	else:
		_failed_idle_rolls += 1
		_schedule_next_idle_decision()

func _roll_pseudo_random_idle() -> bool:
	return _rng.randf() < _current_pseudo_random_idle_probability()

func _current_pseudo_random_idle_probability() -> float:
	var min_walk := maxf(minimum_walk_before_idle, 0.0)
	var max_walk := maxf(maximum_walk_without_idle, min_walk + 0.001)
	var time_pressure := clampf((_walk_elapsed - min_walk) / (max_walk - min_walk), 0.0, 1.0)
	var miss_pressure := 0.0
	if pseudo_random_strength > 0.0 and _failed_idle_rolls > 0:
		miss_pressure = 1.0 - pow(1.0 - pseudo_random_strength, _failed_idle_rolls)
	var effective_probability := 1.0 - (1.0 - idle_probability) * (1.0 - miss_pressure) * (1.0 - time_pressure * time_pressure)
	return clampf(effective_probability, 0.0, 1.0)

func _schedule_next_idle_decision() -> void:
	_decision_timer = maxf(idle_decision_interval, 0.05) * _rng.randf_range(0.85, 1.15)

func _choose_walk_direction() -> void:
	var left_bound := _walk_origin_global_x - walk_left_offset
	var right_bound := _walk_origin_global_x + walk_right_offset
	if global_position.x <= left_bound + 4.0:
		_walk_direction = 1.0
	elif global_position.x >= right_bound - 4.0:
		_walk_direction = -1.0
	else:
		_walk_direction = -1.0 if _rng.randf() < 0.5 else 1.0
	_update_facing()

func _should_turn_at_ledge() -> bool:
	if not avoid_ledges or not is_on_floor() or _floor_probe == null:
		return false
	_floor_probe.position.x = _walk_direction * 24.0
	_floor_probe.force_raycast_update()
	return not _floor_probe.is_colliding()

func _enforce_walk_bounds() -> void:
	if not movement_enabled:
		return
	var left_bound := _walk_origin_global_x - walk_left_offset
	var right_bound := _walk_origin_global_x + walk_right_offset
	var clamped_x := clampf(global_position.x, left_bound, right_bound)
	if is_equal_approx(clamped_x, global_position.x):
		return
	global_position.x = clamped_x
	if (clamped_x <= left_bound and velocity.x < 0.0) or (clamped_x >= right_bound and velocity.x > 0.0):
		velocity.x = 0.0

func _apply_gravity(delta: float) -> void:
	if is_on_floor() and velocity.y > 0.0:
		velocity.y = 0.0
	else:
		var gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 1350.0))
		velocity.y = minf(velocity.y + gravity * gravity_scale * delta, max_fall_speed)

func _play_fsm_animation(animation_name: StringName) -> void:
	if _animation_player == null or animation_name.is_empty() or not _animation_player.has_animation(animation_name):
		return
	if _animation_player.current_animation != animation_name:
		_animation_player.play(animation_name)

func _update_facing() -> void:
	if _visual_root == null or is_zero_approx(_walk_direction):
		return
	var visual_scale := _visual_root.scale
	visual_scale.x = absf(visual_scale.x) * signf(_walk_direction)
	_visual_root.scale = visual_scale

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

func _resolve_ui_font() -> void:
	if Engine.is_editor_hint():
		return
	if ui_font == null:
		_resolve_dialogue_box()
		if _dialogue_box != null and _dialogue_box.has_method("get_ui_font"):
			ui_font = _dialogue_box.call("get_ui_font") as Font
	if ui_font != null and _collision_speech_label != null:
		_collision_speech_label.add_theme_font_override("font", ui_font)

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
	_apply_collision_draw_transform()
	_draw_character()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_walk_range_editor_guide()
	if _player_inside != null and not _dialogue_active:
		_draw_interaction_prompt()

func _apply_collision_draw_transform() -> void:
	var strength := _collision_visual_strength()
	var visual_offset := Vector2(_collision_recoil_direction * 7.0, 4.0) * strength
	var visual_rotation := _collision_recoil_direction * 0.1 * strength
	var visual_scale := Vector2(1.0 + strength * 0.14, 1.0 - strength * 0.16)
	draw_set_transform(visual_offset, visual_rotation, visual_scale)

func _collision_visual_strength() -> float:
	if _collision_animation_timer <= 0.0 or collision_animation_duration <= 0.0:
		return 0.0
	var progress := 1.0 - _collision_animation_timer / collision_animation_duration
	return sin(clampf(progress, 0.0, 1.0) * PI)

func _draw_walk_range_editor_guide() -> void:
	if not Engine.is_editor_hint():
		return
	var left := Vector2(-walk_left_offset, WALK_RANGE_GUIDE_Y)
	var right := Vector2(walk_right_offset, WALK_RANGE_GUIDE_Y)
	draw_line(left, right, WALK_RANGE_COLOR, 4.0, true)
	draw_line(left + Vector2(0.0, -13.0), left + Vector2(0.0, 13.0), WALK_RANGE_COLOR, 3.0, true)
	draw_line(right + Vector2(0.0, -13.0), right + Vector2(0.0, 13.0), WALK_RANGE_COLOR, 3.0, true)
	draw_circle(left, 8.0, WALK_RANGE_HANDLE_COLOR)
	draw_circle(right, 8.0, WALK_RANGE_HANDLE_COLOR)
	draw_circle(Vector2(0.0, WALK_RANGE_GUIDE_Y), 5.0, Color.WHITE)

func _sync_walk_range_preview() -> void:
	var preview := get_node_or_null("WalkRangePreview") as Node2D
	if preview == null:
		return
	preview.visible = Engine.is_editor_hint()
	var range_line := preview.get_node_or_null("RangeLine") as Line2D
	var left_stem := preview.get_node_or_null("LeftStem") as Line2D
	var right_stem := preview.get_node_or_null("RightStem") as Line2D
	var left_handle := preview.get_node_or_null("LeftHandle") as Polygon2D
	var right_handle := preview.get_node_or_null("RightHandle") as Polygon2D
	if range_line != null:
		range_line.points = get_walk_range_points()
	if left_stem != null:
		left_stem.position = Vector2(-walk_left_offset, WALK_RANGE_GUIDE_Y)
	if right_stem != null:
		right_stem.position = Vector2(walk_right_offset, WALK_RANGE_GUIDE_Y)
	if left_handle != null:
		left_handle.position = Vector2(-walk_left_offset, WALK_RANGE_GUIDE_Y)
	if right_handle != null:
		right_handle.position = Vector2(walk_right_offset, WALK_RANGE_GUIDE_Y)

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
	var font := ui_font if ui_font != null else ThemeDB.fallback_font
	if font == null:
		return
	draw_rect(Rect2(Vector2(-52.0, -140.0), Vector2(104.0, 24.0)), Color(0.02, 0.025, 0.035, 0.78), true)
	draw_rect(Rect2(Vector2(-52.0, -140.0), Vector2(104.0, 24.0)), Color(prompt_color.r, prompt_color.g, prompt_color.b, 0.55), false, 1.5)
	draw_string(font, Vector2(-48.0, -122.0), interaction_prompt, HORIZONTAL_ALIGNMENT_CENTER, 96.0, 14, prompt_color)