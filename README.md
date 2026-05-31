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

Current prototype notes:

- Gravity is set in `project.godot` under `physics/2d/default_gravity`.
- Player movement lives in `scripts/player.gd`.
- Camera follow lives in `scripts/platform_camera.gd` and uses horizontal lookahead, dead zones, room bounds, and smooth room transitions.
- Rooms live in `scenes/main.tscn` under the `Rooms` node. Each room is an `Area2D` with `scripts/room.gd`, a `camera_rect`, and a trigger collision shape.
- When the player enters a new room, the camera pauses normal follow and eases from the old camera state to the new room's clamped focus point. Tune `room_transition_duration` in `scripts/platform_camera.gd` for a faster or slower room slide.
- `RoomTransitionMask` in `scenes/main.tscn` adds a subtle dark overlay during room transitions. This reduces the feeling of seeing intermediate space while the prototype still uses one continuous test level.
- The test wall/terrain in `scenes/main.tscn` uses `CollisionPolygon2D`, which is the right direction for hand-drawn, irregular wall shapes.

## Project Structure

- `project.godot`: Godot project settings.
- `scenes/main.tscn`: Main scene.
- `scripts/player.gd`: Basic platformer movement.
- `scripts/platform_camera.gd`: Camera follow behavior.
- `scripts/room.gd`: Room trigger and camera bounds definition.
