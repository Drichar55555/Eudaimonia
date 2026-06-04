# Eudaimonia

A Godot 4.6 2D side-scroller game project.

## Run

Open this folder in Godot, or run:

```bash
godot --path /Users/zhanghao/Eudaimonia
```

The starter scene includes a simple platform player, irregular wall/terrain collision, room-based camera bounds, and a camera follow prototype.

Controls:

- Move: `A/D` or arrow keys.
- Jump: `W` or `Space`.
- Throw/recall mask boomerang: `J` or `X`.
- Switch player mask state: `1` no mask, `2` Euda mask, `3` ghost mask, or `Tab` to cycle. Locked mask states cannot be selected.
- Interact: `E` near broken tombstones, key chests, and key doors.

Current prototype notes:

- Gravity is set in `project.godot` under `physics/2d/default_gravity`.
- Player movement lives in `scripts/player.gd`.
- Player movement includes coyote time, jump buffering, variable jump height, faster falling, max fall speed, acceleration/deceleration, and facing-based mask boomerang throwing.
- Player mask states live in `scripts/player.gd`. The initial unlocked state is only `no_mask`. `euda_mask` reveals ghost block areas by making their wall/floor coating blur and flicker, and `ghost_mask` can stand on ghost blocks after it is unlocked.
- Each player mask state has its own health pool with three hearts by default. If `no_mask` has one heart left, switching to `euda_mask` still gives the Euda mask its own current health.
- If the current mask state's health reaches zero, the game loads the current scene checkpoint snapshot. The snapshot is not only player data: it restores every `saveable` object, including player state, enemy state, enemy health, enemy positions, and enemies that were defeated after the save.
- Death respawn uses `DeathRespawnMask` on the `CanvasLayer`: the screen fades to black, the checkpoint snapshot loads while black, then control returns as the screen fades back in.
- The bottom fall/deadline reset uses `reset_below_y`. The old top reset is disabled by default with `reset_above_enabled = false`, so vertical rooms above the starting area do not unexpectedly load the checkpoint.
- The birth point currently has the only save point. Entering its range starts a save in the background while gameplay continues; the lower-left `SaveStatus` label shows `存储中...` during that save.
- Soul lamps live in `scenes/soul_lamp.tscn` and `scripts/soul_lamp.gd`. They are lamp-shaped checkpoint areas with no solid collision; entering their range saves the game with the same cooldown behavior as the birth save point.
- Staying inside a save point does not repeatedly save. After leaving, re-entering within `20` seconds also does not save again; re-entering after the cooldown captures a new scene snapshot.
- The current temporary animator state is exposed by `get_current_animation_name()` and drawn by `scripts/player_visual.gd`. During mask switching it shows `mask_switch_cutscene`; otherwise it shows state-specific placeholders such as `no_mask_idle`, `euda_mask_run`, or `ghost_mask_fall`.
- Story tutorials use `scripts/story_controller.gd` and `scripts/dialogue_box.gd`. The mask speaks the first time the player takes ordinary damage, the first player death sends the player to a separate death space before returning through a door, and the first Euda/ghost-related fall or death shows the ghost-block explanation after returning from death space.
- The mask boomerang lives in `scenes/mask_boomerang.tscn` and `scripts/mask_boomerang.gd`. It is thrown in the player's facing direction, travels outward, returns automatically, and can be recalled by pressing throw again. Each enemy can be hit once on the outbound pass and once again on the return pass.
- Tombstones live in `scenes/tombstone.tscn` and `scripts/tombstone.gd`. A tombstone takes three mask boomerang hits to break. After it breaks, stand near it and press `E` to unlock the configured mask state. `unlock_mask` chooses whether that tombstone unlocks `euda_mask` or `ghost_mask`.
- Tombstones automatically detect their room from the `camera_rooms` group. With `wait_for_player_room_entry` enabled, a tombstone waits until the player first enters that room before its gameplay activation starts.
- Tombstones can spawn monsters before they break. Tune `spawn_monsters_before_break`, `spawn_on_hit_before_break`, `spawn_count_per_hit`, `auto_spawn_before_break`, `auto_spawn_interval`, `auto_spawn_count`, `spawned_enemy_kind`, `max_alive_spawned_enemies`, `spawn_offsets`, and `spawn_parent_path` on the tombstone. By default, non-final hits spawn enemies, the tombstone also spawns a timed wave every second, and the final hit breaks the tombstone instead of spawning more.
- Unlocking a mask shows `UnlockPopup` on the `CanvasLayer`; press any key or mouse button to close it.
- Key doors and key chests live in `scenes/key_door.tscn`, `scenes/key_chest.tscn`, `scripts/key_door.gd`, and `scripts/key_chest.gd`. Open a key chest with `E` to gain `key_reward` keys. Open a key door with `E`; it consumes `keys_required` keys if the player has enough. Player key count, opened chests, and opened doors are saved in checkpoint snapshots.
- Enemy prototypes live in `scenes/enemy.tscn` and `scripts/enemy.gd`. The scene uses a `CharacterBody2D` root with a `Hitbox` `Area2D` in the `boomerang_targets` group.
- Enemies have `max_health = 3` by default and disappear after three mask boomerang hits.
- Enemies move slowly by default, attack in close range for `attack_damage`, and use `attack_cooldown` to avoid draining health every frame.
- Enemies use `queue_spacing` and `queue_vertical_tolerance` to avoid stacking on top of each other. When multiple enemies move in the same direction on the same lane, the one behind pauses and forms a queue.
- `can_touch_ghost_blocks` controls whether an enemy collides with ghost blocks. `EnemyNormal` ignores ghost blocks; `EnemyGhost` can collide with ghost blocks.
- Enemies use a finite state machine with `patrol` and `chase` states. When the player is outside their senses, enemies patrol inside `patrol_distance`; when the player enters their forward vision or close all-direction hearing area, they chase horizontally.
- Enemies do not jump. If the player is above them or across a gap, they keep using ground movement and ledge checks instead of jumping.
- Enemy AI tuning lives in the Inspector on each enemy: `vision_range` is the large forward sight range, `hearing_range` is the smaller all-direction hearing range, and `patrol_distance`, `patrol_speed`, `chase_speed`, `chase_memory_time`, `avoid_ledges`, and `require_line_of_sight` tune movement and pursuit.
- Enable `show_ai_ranges` on an enemy to see the AI visualization: blue means patrol, red means chase, the large forward ellipse is sight, the small centered ellipse is hearing, and the line under the enemy is its patrol span.
- Spike blocks use `scripts/spike_block.gd` in the same object form as ghost blocks and the same collision-driven visual style as walls: a `StaticBody2D` parent such as `Level/SpikeBlocks` with ordinary editable child `CollisionPolygon2D` nodes. The visible shape is filled and outlined directly from those collision polygons. When the player is standing or walking on the top side of the polygon, the first hit happens immediately, repeated contact deals `damage` every `damage_interval` seconds, and `top_walk_speed_multiplier` slows horizontal movement. Side and underside contact do not apply spike damage.
- Pushable boxes live in `scenes/push_box.tscn` and `scripts/push_box.gd`. They use editable child `CollisionPolygon2D` nodes like walls. The player can push them horizontally by walking into their side; while pushing, the player uses the box's `player_push_speed_multiplier` so movement feels heavier and slower. `max_push_speed` controls how quickly the box can slide.
- Mechanisms live in `scenes/mechanism_button.tscn`, `scenes/mechanism_wall.tscn`, `scripts/mechanism_button.gd`, and `scripts/mechanism_wall.gd`. `Level/Mechanisms` in the main scene contains a sample button and moving wall. Older `moving_wall` and `breakable_wall` scenes remain as compatibility wrappers.
- A `MechanismButton` triggers when a player or enemy steps into its detection shape. It links to a `MovingWall` with `moving_wall_path`.
- Buttons have a small flat physical collision surface, so the player can genuinely stand on them like flat ground. Their `PressSensor` detection area remains a horizontal capsule with rounded left/right ends, and the temporary visual uses a rounded capsule plate.
- Buttons render below normal wall/terrain visuals by default (`z_index = -20`), while moving mechanism walls render above normal wall/terrain visuals (`z_index = 20`).
- Button press visuals animate gradually with `press_animation_time` and `press_depth`, so stepping on a button slowly depresses the plate instead of snapping instantly.
- Buttons latch by default with `latch_when_activated`, so once an activated button is pressed it stays down even after the player leaves.
- Button `button_mode` supports `latch`, `hold`, and `shot`. `hold` buttons restore after `release_delay` when the player/enemy leaves. `shot` buttons trigger from `player_weapons` such as the mask boomerang, then restore after `shot_reset_delay`.
- Shot buttons blink while counting down. The final second blinks faster.
- Mechanism screen shake is adjustable on the button with `shake_on_press`, `shake_while_moving`, `moving_shake_interval`, and `shake_on_finish`. The camera's `max_shake_offset`, `shake_decay`, and `shake_trauma_power` control the overall shake feel.
- A `MechanismWall` uses child `CollisionPolygon2D` nodes for the real editable collision. Set `wall_mode` to `moving` or `breakable` to choose behavior. In `moving` mode, `target_offset` defines the target position and is drawn as a preview outline with an arrow.
- Wall movement uses `move_time` and `movement_mode`. `physical` is the default ease-in/ease-out style; downward physical movement accelerates like gravity. `constant_speed` moves linearly.
- Moving walls can deal crush damage with `damage_on_impact`, `impact_damage`, `impact_knockback`, and `impact_cooldown`.
- In `breakable` mode, a `MechanismWall` breaks into temporary shard visuals when activated and restores with a reverse flashing animation when deactivated.
- Broken `MechanismWall` collision is fully disabled while broken: the root collision layer is set to `0`, child `CollisionPolygon2D` nodes are disabled, and crush damage is not applied until the wall restores.
- Buttons can optionally enable `play_cinematic`. Cinematic mode pauses player/enemy movement, moves the camera to frame the mechanism, moves the wall, then returns to normal player camera control. Tune `camera_move_in_time`, `camera_hold_time`, `camera_move_out_time`, `cinematic_view_size`, and `cinematic_padding` on the button.
- Camera follow lives in `scripts/platform_camera.gd` and uses horizontal lookahead, dead zones, room bounds, and smooth room transitions.
- Rooms live in `scenes/main.tscn` under the `Rooms` node. Each room is an `Area2D` with `scripts/room.gd`, a `camera_rect`, `camera_view_mode`, an aspect-locked camera view width control, a `transition_mode`, and a trigger collision shape.
- By default, a room uses its `CollisionShape2D` trigger area as the camera movement bounds. Enable `manual_camera_rect` only when you need custom camera bounds different from the trigger area.
- `camera_rect` is the optional manual camera movement bounds inside the room, not the visible lens size. `camera_view_width` controls the room's visible camera size. If the camera bounds are larger than the visible area, the camera follows inside the room and clamps only at the room edges.
- `camera_view_width` is a slider-style direct camera size control. Larger values show more of the room; smaller values zoom in. Camera height is calculated automatically from the fixed screen aspect ratio.
- The green camera view outline is drawn at the room trigger area's center, so it stays centered on the room you are editing.
- `camera_view_mode` controls view sizing and follow behavior. `free_size` uses the `camera_view_width` slider. `horizontal_follow` makes camera height match the room height and computes width from the screen ratio. `vertical_follow` makes camera width match the room width and computes height from the screen ratio. `no_follow` locks the camera to show the full room instead of following the player.
- In `horizontal_follow`, `vertical_follow`, and `no_follow`, `camera_view_width` is not used because the room dimensions determine the visible camera size.
- Room camera feel can be tuned per room with `camera_profile`, `lookahead_distance`, `vertical_offset`, `dead_zone`, `border_zone`, `follow_damping`, and `border_damping`.
- `camera_profile` provides standard styles: `horizontal`, `vertical_shaft`, `platforming`, `boss`, and `cinematic`. In these modes, the room uses preset lookahead, dead-zone, border-zone, and damping values.
- Set `camera_profile` to `custom` for manual mode. In `custom`, the room reads your handwritten `lookahead_distance`, `vertical_offset`, `dead_zone`, `border_zone`, `follow_damping`, and `border_damping` values.
- `dead_zone` is the inner area where player movement does not move the camera. `border_zone` is the edge safety area; when the player approaches it, the camera uses `border_damping` to catch up faster.
- `follow_damping` controls normal follow softness. Higher values follow faster; lower values feel heavier and smoother.
- `CameraZoneOverlay` draws the tuning zones during development: blue is the dead zone, orange is the hard border zone. Toggle `show_camera_zone_overlay` on `Camera2D` to hide it.
- `transition_mode` supports `smooth` and `fade_to_black`. Room transitions are symmetrical: if either the current room or the next room uses `fade_to_black`, both directions between those rooms fade to black. Only when both rooms use `smooth` will the connection use a smooth slide.
- Smooth room transitions ease from the old camera state to the new room's focus point. Tune `room_transition_duration` in `scripts/platform_camera.gd` for a faster or slower room slide.
- Black-screen room transitions use `RoomTransitionMask` in `scenes/main.tscn`. Tune `fade_out_duration`, `fade_hold_duration`, and `fade_in_duration` in `scripts/platform_camera.gd`.
- The test wall/terrain in `scenes/main.tscn` uses `CollisionPolygon2D`, which is the right direction for hand-drawn, irregular wall shapes.
- Terrain visuals are temporary and collision-driven. `Level/Terrain` uses `scripts/terrain_debug_visual.gd` to draw fill colors directly from child `CollisionPolygon2D` nodes, so you only edit the actual collision polygons.
- The terrain collision polygons use segment build mode. This is better for complex hand-drawn outlines because it avoids convex decomposition failures from large concave solid polygons.
- Ghost blocks use the same editing style as terrain. `Level/GhostBlocks` uses `scripts/ghost_blocks_visual.gd` to draw temporary ghost visuals from child `CollisionPolygon2D` nodes. Edit `GhostBlockCollision` polygons directly.
- At runtime, ghost blocks normally draw as ordinary wall/floor material. When the player wears `euda_mask`, the same collision polygons switch to a blurred flickering coating effect. Collision still exists, but the player only collides with ghost blocks while in `ghost_mask`.

## Project Structure

- `project.godot`: Godot project settings.
- `scenes/main.tscn`: Main scene.
- `scripts/player.gd`: Basic platformer movement.
- `scripts/platform_camera.gd`: Camera follow behavior.
- `scripts/room.gd`: Room trigger and camera bounds definition.
- `scripts/terrain_debug_visual.gd`: Temporary terrain color renderer based on collision polygons.
- `scripts/ghost_blocks_visual.gd`: Temporary ghost block renderer based on collision polygons.
