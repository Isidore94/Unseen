# UNSEEN — Changelog

Short, session-by-session log so we never lose the thread between sessions.

## Phase 0 — Foundation (in progress)

### Session: Phase 0 implementation
- **Project layout:** Created `scripts/`, `components/`, `maps/`, and
  `assets/{sprites,audio,fonts}/` to match the build plan's folder structure.
- **Cleanup:** Removed the duplicate `scenes/game1.tscn`. Renamed the main scene
  `node_2d.tscn` → `scenes/main.tscn` (kept its UID so `run/main_scene` still
  resolves).
- **Player node (`scenes/main.tscn`):** Fixed three bugs from the starter scene:
  - `Polygon2D` now has a real 40×40 square (was empty/invisible).
  - `CollisionShape2D` reparented to be a direct child of `Player` (was wrongly
    nested under `Polygon2D`, so the body had no collider).
  - `RectangleShape2D` given a real 36×36 size (was zero-size).
  - Added a `Camera2D` child with position smoothing and a 1.5× zoom.
  - Motion Mode left as Floating (top-down, no gravity).
- **Input Map (`project.godot`):** Defined the abstract actions `move_up`,
  `move_down`, `move_left`, `move_right`, `action_primary`, `action_secondary`,
  `blend_walk` — each bound to BOTH keyboard and gamepad (Principle #2).
  WASD use physical keycodes so non-QWERTY layouts still work physically.
- **`scripts/player.gd`:** Walk/run movement via `Input.get_vector` +
  `move_and_slide()`. `walk_speed` / `run_speed` exported for tuning.
- **Display:** `stretch/aspect = keep`, windowed mode for dev.

### Pending your verification
- Open the project in Godot 4.7 and press Play. Confirm the test checkpoint
  (move with WASD + gamepad, blend key slows you, camera follows, no errors).
- After it passes, tag the commit `phase-0-complete`.
