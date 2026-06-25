# UNSEEN — BUILD PLAN
### Source-of-truth build plan for Claude Code

> **How to use this file:** This is the master plan for the whole project. Work one phase at a time, top to bottom. When I say "expand Phase X," read this whole file for context, then produce the detailed implementation for that phase only. After each task, tell me exactly what to click/test in the Godot editor, wait for my confirmation, then continue. Never skip the test checkpoints. Always remind me to commit to git at the end of each working session.

---

## 0. PROJECT CONTEXT (read this first, every time)

**What we're building:** A top-down 2D online competitive social-stealth game. Players are visually identical to a crowd of AI NPCs. Each player must reach 1–2 objective locations to kill NPC marks, then hunt and kill an assigned human target — while being hunted themselves. Lowest exposure + fastest clean kills wins.

**Reference games:** Hidden in Plain Sight (the loop), Assassin's Creed Brotherhood multiplayer (the fantasy), Murderous Pursuits (the format). Our differentiators: online + open maps + secret passages/trapdoors + a limited "tools" resource for map control + a PvE-into-PvP objective structure that forces engagement.

**Engine:** Godot 4.7 stable. Language: GDScript. Renderer: Compatibility (OpenGL3). Target platforms eventually: PC (Steam) → console → mobile, so design for controller + low-end hardware from day one.

**Team:** Solo developer (me) using Claude/Claude Code as primary engineering. ~10 focused hrs/week. One part-time artist (brother) joining heavily at the art phase. I am a beginner — explain *why*, not just *what*, and keep me from building myself into corners.

**Current state (as of starting this plan):**
- Godot project created, Compatibility renderer, Git initialized.
- Folders exist: `res://scenes`, `res://scripts`, `res://assets`, `res://maps`.
- Root scene is a `Node2D`. A `Player` (CharacterBody2D) child exists with a placeholder visual and a CollisionShape2D being set up.
- We are at the very start of **Phase 0**.

---

## 1. ARCHITECTURE PRINCIPLES (enforce these in every phase)

These exist to keep a beginner's project from turning into spaghetti and to protect future options (2.5D upgrade, online, console).

1. **Separate logic from visuals.** Gameplay logic (movement, exposure, objectives, kills) must never depend on specific sprites or art. The visual layer is a swappable child node. This preserves the 2D → 2.5D upgrade path and lets us prototype with grey boxes.
2. **Never hardcode input keys.** Use Godot's Input Map with abstract action names only: `move_up`, `move_down`, `move_left`, `move_right`, `action_primary` (kill), `action_secondary` (use tool/secure), `blend_walk` (hold to walk slowly). Every action must be bound to BOTH keyboard and a gamepad button. This is non-negotiable for the console/mobile roadmap.
3. **One responsibility per script.** A script does one job. `player.gd` handles player movement/state. Exposure lives in its own component. NPC AI is its own script. Don't let files balloon.
4. **Composition via child nodes / components.** Prefer small reusable nodes (e.g. an `ExposureComponent`) over giant monolithic scripts. The player and NPCs may share components.
5. **Signals over polling.** Use Godot signals for events (`kill_performed`, `exposure_changed`, `objective_reached`). Don't have nodes constantly reach into each other.
6. **Server-authoritative mindset, early.** Even in single-player phases, write gameplay logic as if a server will validate it later (kills, scores). This makes the Phase 6 online port dramatically less painful. Avoid logic that only works because it's local.
7. **Constants and tuning values in one place.** Speeds, exposure rates, timers go in an exported/config file or `@export` variables — never magic numbers buried in functions. I need to tune these constantly.
8. **Commit often.** Every working session ends with a git commit. Every phase ends with a tagged commit (`phase-0-complete`, etc.).

**Naming conventions:**
- Files: `snake_case.gd`, `snake_case.tscn`
- Nodes: `PascalCase` (Player, ExposureBar, CrowdManager)
- Variables/functions: `snake_case`
- Constants: `ALL_CAPS`
- Signals: past tense (`kill_performed`, `target_assigned`)

**Folder structure to maintain:**
```
res://
  scenes/        # .tscn scene files (main, player, npc, ui, maps)
  scripts/       # .gd scripts, mirrored to scenes where it helps
  assets/
    sprites/
    audio/
    fonts/
  maps/          # map scenes and tilesets
  components/    # reusable component nodes/scripts (exposure, health, etc.)
```

---

## 2. PHASES

Each phase below has: **Goal**, **Prerequisites**, **Tasks** (what Claude Code should implement, in order), **Test checkpoint** (what I verify before moving on), and **Done =** (the milestone). Expand each phase into full implementation detail when I ask.

---

### PHASE 0 — FOUNDATION (Weeks 1–2)
**Goal:** A controllable player rectangle moving smoothly around a 2D canvas with keyboard and controller, camera following.

**Prerequisites:** Godot project + folders + git (done).

**Tasks:**
1. Finish the Player node: `CharacterBody2D` named `Player`, with:
   - A placeholder visual child (use a `Polygon2D` or `Sprite2D` with a generated texture — NOT a ColorRect, which is a UI node). A 40×40 square centered on origin.
   - A `CollisionShape2D` child with a `CapsuleShape2D` or `RectangleShape2D` (~32–40px).
   - Motion Mode = **Floating** (top-down, no gravity).
2. Set up the **Input Map** in Project Settings with the abstract actions from Principle #2, each bound to keyboard AND gamepad.
3. Write `scripts/player.gd`:
   - `@export var walk_speed` and `@export var run_speed`.
   - Read input via `Input.get_vector("move_left","move_right","move_up","move_down")`.
   - Hold `blend_walk` = move at walk_speed, otherwise run_speed.
   - Use `velocity` + `move_and_slide()`.
4. Add a `Camera2D` as a child of Player. Enable position smoothing. Set a sensible zoom.
5. Configure Project Settings → Display → Window: 1920×1080, stretch mode `canvas_items`, aspect `keep`.
6. Save scene as `scenes/main.tscn`. Make `main.tscn` the project's main scene (Project Settings → Application → Run → Main Scene).
7. Commit: `phase-0-complete`.

**Test checkpoint:** Press Play. The square moves with WASD and with a gamepad stick. Holding the blend key slows it. Camera follows smoothly. No errors in Output.

**Done =** A rectangle moves around a grey canvas with WASD and a controller, camera following.

---

### PHASE 1 — CORE MECHANIC: EXPOSURE (Weeks 3–8)
**Goal:** The blend/exposure system exists and feels meaningful. This is the heart of the game.

**Prerequisites:** Phase 0 complete.

**Design intent:** Exposure is a 0–100 value. Running and erratic movement raise it fast. Walking calmly lowers it. Standing still lowers it slowly. High exposure = easier for hunters to spot you. This is the tension engine of the whole game.

**Tasks:**
1. Create a reusable `components/exposure_component.gd` (extends Node). Responsibilities:
   - `var exposure: float` (0–100), `@export var rise_rate`, `@export var fall_rate`, `@export var idle_fall_rate`.
   - Method `update(is_running: bool, is_moving: bool, delta)` adjusts exposure.
   - Emits `signal exposure_changed(new_value)`.
   - Clamp 0–100.
2. Attach an `ExposureComponent` to the Player. Wire player movement state into it each physics frame.
3. Build a minimal HUD: a `CanvasLayer` → `ExposureBar` (a `ProgressBar` or `TextureProgressBar`). Connect to `exposure_changed`. Color shifts green→yellow→red as it rises.
4. Tune `walk_speed`, `run_speed`, and exposure rates so the *feel* is right (I will iterate — expose all as `@export`).
5. Build a flat greybox test map in `maps/test_map.tscn`: a few `StaticBody2D` walls + open areas using simple rectangles. No art.
6. Finalize the abstract input map and confirm controller parity.

**Test checkpoint:** Walking keeps the bar low; sprinting spikes it; stopping bleeds it down. The numbers feel tunable and the tension is readable.

**Done =** I can walk around and feel the tension of exposure rising when I move carelessly.

---

### PHASE 2 — THE CROWD (Weeks 9–16) ⚠ HIGHEST TECHNICAL RISK
**Goal:** 20–30 NPCs fill the map, move believably, and I can genuinely hide among them. One bot hunter searches for me.

**Prerequisites:** Phase 1 complete. This phase killed predecessor games (AC Rearmed died on bad NPC pathing). Spend extra time here. Do not rush to Phase 3.

**Design intent:** NPCs must be visually identical to the player and move naturally enough that a watching human cannot trivially distinguish player from NPC. The hunter bot models the future human hunter.

**Tasks:**
1. Set up navigation: a `NavigationRegion2D` baked over the test map so agents can path.
2. Create `scenes/npc.tscn`: `CharacterBody2D` named `NPC`, identical placeholder visual to the Player, a `NavigationAgent2D`, and `scripts/npc.gd`.
3. `npc.gd` wandering behavior:
   - Pick a random reachable point, path to it via `NavigationAgent2D`, pause briefly, repeat.
   - Add light variation: differing pause times, slightly varied speeds, occasional direction changes, small clustering near "points of interest."
   - Movement speed must match the player's WALK speed (so a walking player blends; a running player stands out).
4. Create `components/crowd_manager.gd`: spawns N NPCs at valid nav points, maintains the population, exposes density queries (how many NPCs near a position).
5. Wire crowd density into exposure: standing in a dense cluster lowers exposure faster (you're camouflaged); being alone in the open is exposing.
6. Build the **hunter bot** (`scripts/hunter_ai.gd`): wanders like crowd, but scans for the player. Detection probability scales with the player's exposure and proximity/line-of-sight. On "lock," it pursues. Keep detection logic in its own tunable function — I will rewrite this repeatedly.
7. Make player and NPC share the same visual/scale exactly so they're indistinguishable at rest.

**Test checkpoint:** I stand still in a crowd and feel hidden; I run and the hunter finds me. Watching the screen, it's genuinely hard to instantly pick the player out of the crowd.

**Done =** The cat-and-mouse loop exists and feels good. **If this is fun, we have a game.**

---

### PHASE 3 — OBJECTIVES & THE KILL (Weeks 17–24)
**Goal:** A complete single-player loop: do objectives, get a target, kill, win/lose, score. Add the first trapdoor + secret passage.

**Prerequisites:** Phase 2 complete and fun.

**Tasks:**
1. **Objective system** (`scripts/objective_manager.gd`): place 1–2 NPC "marks" at fixed, intentionally exposed map locations. Track completion. After marks done, designate the final target.
2. **Kill mechanic** (`components/kill_component.gd`): when within range of a valid target and `action_primary` is pressed, run a brief kill (lock both actors, short timer, success). Validate target validity in a server-authoritative style (Principle #6).
3. **Kill consequence:** performing a kill spikes the killer's exposure for 2–3s (you're momentarily obvious). This is core risk/reward.
4. **Win/lose + score:** round ends on contract complete or player death. Score rewards low average exposure + fast clean kills. Show an end screen.
5. **Trapdoor (first map-control mechanic):** a node you can enter to teleport to a linked exit. Add the limited **tools** resource: `@export var max_tools`, securing a trapdoor costs 1 tool. Securing lasts a short, tunable duration and emits a subtle tell to nearby actors (counterplay — Principle: every advantage needs an answer). A watching hunter can break a secured door by spending their own tool.
6. **Secret passage:** a hidden one-way or two-way route connecting two areas, visually subtle, no resource cost — pure map knowledge.

**Test checkpoint:** I can start a round, complete marks, get my target, kill, and win or lose. The trapdoor and passage work and feel like secrets. Tools are limited and meaningful.

**Done =** A complete playable loop with secrets in the map.

---

### PHASE 4 — LOCAL MULTIPLAYER (Weeks 25–32)
**Goal:** Two humans on one machine, each with their own contract, hunting each other plus bots. This is the FUN TEST and the project's go/no-go gate.

**Prerequisites:** Phase 3 complete.

**Tasks:**
1. Add a second local player: controller 2, or keyboard-vs-arrows. Reuse the same Player scene/components; parameterize the input device.
2. Independent exposure, tools, and target assignment per player. Players can be each other's targets.
3. Split or shared-screen handling appropriate to top-down (likely shared screen with a wide camera, or split — prototype shared first).
4. End-of-round summary comparing both players' scores.
5. **Playtest relentlessly** with my brother. Tune everything. Cut what isn't fun.

**Test checkpoint:** My brother and I play ~10 rounds back to back.

**Done = THE GO/NO-GO DECISION.** If it's fun with two humans + bots, proceed to art + online. If not, fix the core design *before* spending months on art and netcode. Be honest here.

---

### PHASE 5 — ART PASS 1 (Weeks 33–44)
**Goal:** Looks like a real game, not a prototype. Brother's peak workload.

**Prerequisites:** Phase 4 passed the fun test.

**Tasks (mostly art, code supports it):**
1. Real character sprite (single cloaked top-down figure used by player AND all NPCs — sameness is the point), with walk-cycle animation (`AnimatedSprite2D` or `AnimationPlayer`), idle, and kill animation.
2. First real tileset + one polished map (stone plaza, market stalls, alleys) replacing greyboxes. Use a `TileMapLayer`.
3. Crowd-density zones and sightlines designed into the map (brother as level designer — this is where the skill ceiling lives).
4. SFX: footsteps, crowd ambience, kill stinger, UI clicks. Music: one atmospheric loop (royalty-free or commissioned).
5. HUD art pass: exposure meter, tool pips, contract tracker.
6. Keep the logic/visual separation — swapping art must not require touching gameplay scripts.

**Budget:** $200–800 on asset/sound/music packs to fill gaps.

**Done =** A trailer-worthy screenshot exists; the Steam capsule is imaginable.

---

### PHASE 6 — ONLINE MULTIPLAYER (Weeks 45–70) ⚠ HARDEST PHASE
**Goal:** Players on different machines complete a stable match. Budget DOUBLE the time you expect.

**Prerequisites:** Phase 5 (or at least Phase 4) complete. Game proven fun.

**Approach decision:** Start with **Godot's built-in high-level multiplayer** (`MultiplayerSpawner`, `MultiplayerSynchronizer`, RPCs, `ENetMultiplayerPeer`) using a player-hosted/listen-server model and Steam relay for connectivity. This can be near-zero server cost. Only move to Photon if Godot's stack proves insufficient at our scale. Keep gameplay server-authoritative (we designed for this since Phase 0).

**Tasks (expand carefully when we get here):**
1. Lobby: host game / join game (friend invite via Steam first; matchmaking later).
2. Replicate player position/state with `MultiplayerSynchronizer`; spawn players with `MultiplayerSpawner`.
3. Authoritative kill validation via server RPC (never trust the client).
4. Exposure + tools state sync.
5. Crowd sync strategy: either (a) server-simulated NPCs replicated to clients, or (b) deterministic seeded simulation per client. Decide based on performance; document the choice.
6. Lag handling: interpolation for remote actors; test at simulated 80–150ms; decide if any prediction is needed.
7. Steam integration via GodotSteam (Steamworks): identity, lobbies, relay.
8. Stable 4-player match end-to-end.

**Test checkpoint:** Four people on four machines finish a match with no desync or crash, at realistic ping.

**Done =** A real online match works.

---

### PHASE 7 — STEAM EARLY ACCESS LAUNCH (Weeks 71–80)
**Goal:** A live product with a community.

**Tasks:**
1. Steam store page: trailer, capsule art, screenshots, copy.
2. Steam achievements (≥10), Steam Deck verification, GodotSteam wired for stats.
3. Pricing: Free-to-Play recommended; build a minimal cosmetic shop (3–5 skins) if F2P.
4. Community: Discord (≥200 members BEFORE launch), dev posts on TikTok/Reddit throughout, Steam Next Fest demo for wishlists, press kit to ~20 creators 2 weeks pre-launch.
5. Pay the $100 Steam Direct fee. Ship Early Access.

**Done =** Strangers are playing the game.

---

## 3. STANDING INSTRUCTIONS FOR CLAUDE CODE

- Work in **small, testable increments**. After each meaningful change, give me exact editor steps to verify it, and wait.
- When writing GDScript, **explain the why** in comments and in chat — I'm learning.
- Surface **every value I'll want to tune** as `@export` variables; never bury magic numbers.
- Respect the **architecture principles** in section 1 on every task. If a quick hack would violate them, flag it and propose the clean version.
- When a task touches the **future online port** (kills, scoring, state), implement it server-authoritative-ready even in single-player.
- At the end of each session, give me a **git commit message** and remind me to push.
- If something is **above my current skill to debug**, say so plainly and give me a way to isolate the problem rather than guessing.
- Keep a short **CHANGELOG.md** updated as we go so we never lose the thread between sessions.

## 4. CURRENT NEXT ACTION
We are mid **Phase 0**. The immediate next step: finish the Player node (placeholder visual + CapsuleShape2D collision, Motion Mode = Floating), set up the Input Map with controller + keyboard parity, then write `scripts/player.gd` for movement with walk/run + blend. Expand Phase 0 into step-by-step editor instructions and code now.
