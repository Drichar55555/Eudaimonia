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

Current prototype notes:

- Gravity is set in `project.godot` under `physics/2d/default_gravity`.
- Player movement lives in `scripts/player.gd`.
- Player movement includes coyote time, jump buffering, variable jump height, faster falling, max fall speed, acceleration/deceleration, and facing-based mask boomerang throwing.
- The mask boomerang lives in `scenes/mask_boomerang.tscn` and `scripts/mask_boomerang.gd`. It is thrown in the player's facing direction, travels outward, returns automatically, and can be recalled by pressing throw again.
- Enemy prototypes live in `scenes/enemy.tscn` and `scripts/enemy.gd`. The scene uses a `CharacterBody2D` root with a `Hitbox` `Area2D` in the `boomerang_targets` group.
- Enemies have `max_health = 3` by default and disappear after three mask boomerang hits.
- `can_touch_ghost_blocks` controls whether an enemy collides with ghost blocks. `EnemyNormal` ignores ghost blocks; `EnemyGhost` can collide with ghost blocks.
- Enemies use a finite state machine with `patrol` and `chase` states. When the player is outside their senses, enemies patrol inside `patrol_distance`; when the player enters their forward vision or close rear hearing area, they chase horizontally.
- Enemies do not jump. If the player is above them or across a gap, they keep using ground movement and ledge checks instead of jumping.
- Enemy AI tuning lives in the Inspector on each enemy: `vision_range` is the forward sight range, `rear_hearing_range` is the shorter rear hearing range, and `patrol_distance`, `patrol_speed`, `chase_speed`, `chase_memory_time`, `avoid_ledges`, and `require_line_of_sight` tune movement and pursuit.
- Enable `show_ai_ranges` on an enemy to see the AI visualization: blue means patrol, red means chase, the large forward ellipse is sight, the small rear ellipse is hearing, and the line under the enemy is its patrol span.
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

## Project Structure

- `project.godot`: Godot project settings.
- `scenes/main.tscn`: Main scene.
- `scripts/player.gd`: Basic platformer movement.
- `scripts/platform_camera.gd`: Camera follow behavior.
- `scripts/room.gd`: Room trigger and camera bounds definition.
- `scripts/terrain_debug_visual.gd`: Temporary terrain color renderer based on collision polygons.
- `scripts/ghost_blocks_visual.gd`: Temporary ghost block renderer based on collision polygons.
