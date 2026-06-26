# UNSEEN — BUILD PLAN
### Source-of-truth build plan for Claude Code

> **How to use this file:** This is the master plan for the whole project. Work one phase at a time, top to bottom. When I say "expand Phase X," read this whole file for context, then produce the detailed implementation for that phase only. After each task, tell me exactly what to click/test in the Godot editor, wait for my confirmation, then continue. Never skip the test checkpoints. Always remind me to commit to git at the end of each working session.

---

## 0. PROJECT CONTEXT (read this first, every time)

**What we're building:** A top-down 2D online competitive social-stealth game. Players are visually identical to a crowd of AI NPCs. Each player must reach 1–2 objective locations to kill NPC marks, then hunt and kill an assigned human target — while being hunted themselves. Lowest exposure + fastest clean kills wins.

**Mechanics (full intent lives in `master_plan.md` — section numbers below point straight to it):**
1. **Sameness (`master_plan` §2, §4, §12).** Players and NPCs share one identical top-down sprite. You are never visually marked; you are read by *behavior*. This is Pillar #1 and it constrains everything — no feature may visually distinguish a player.
2. **Two movement modes (`§2`).** *Blend-walk* (default) = exactly NPC walk speed, low exposure, how you disappear. *Run* (hold the run button) = faster than any NPC, the single most exposing action. Walking is the safe default; running is a deliberate held choice.
3. **Exposure 0–100 (`§3`).** The core tension value. Running / erratic movement / kills / being alone / using tools raise it; blend-walking, standing still, and being inside a dense NPC cluster lower it. Drives detection speed (not a literal visibility toggle). HUD shows green→yellow→red to *you only* — never to opponents.
4. **Exposure arc (`§3` pacing model).** Rounds are designed to start stealthy and end loud: exposure accumulates, the arrow threshold tightens over the round, converging on an everyone-visible PvP climax. Careful play is what lets you arrive at PvP still hidden.
5. **Exposure arrow (`§3.1`).** Cross a high exposure threshold and other players see a color-coded directional arrow toward your *area* — which vanishes the moment you're on the hunter's screen, dropping back to a pure read-the-crowd identification. The arrow guides; it never gifts the kill or reveals which figure is you.
6. **The crowd (`§4`).** 20–30+ NPCs wandering believably (natural pathing is the make-or-break technical risk that sank AC Rearmed). NPC speed = player blend-walk speed. Density zones (markets/plazas) = best cover + fastest exposure bleed.
7. **Hunters & detection (`§5`).** Everyone hunts someone and is hunted. Detection scales with the target's exposure + proximity + line-of-sight + behavioral tells; enough suspicion = a *lock*. Prey can shed a lock by re-blending. Bots stand in for humans in solo phases.
8. **The kill (`§6`).** In range of a *valid* target + `action_primary` → brief locked kill sequence. Kills spike the killer's exposure ~2–3s. Wrong-target kills (civilian / non-target) are heavily punished. Always server-authoritative — clients never self-confirm. **No respawns** (`§6.1`); ranked scores performance, not survival.
9. **The contract — PvE→PvP (`§7`).** Reach 1–2 NPC *marks* at intentionally exposed locations and kill them, then get assigned a real *player target* to hunt. Finishing marks fast earns *pings* on your target (`§7.1`, the aggression incentive). *How* you kill a mark is a micro risk/budget choice (stealth tool vs. free-but-loud knife, `§7.2`).
10. **Map control & knowledge (`§8`).** Secret passages (free, pure knowledge), trapdoors (teleport node with a tell on use), single-occupancy underground rule ("Something lurks in the darkness", `§8.1a`), crowd-density zones, choke points, sound tells, and teleport pads with exposure-scaled cast time + the *earned free teleport* reward for clean play (`§8.5`).
11. **Tools resource (`§9`).** Small fixed consumable count per round (e.g. 3), not a regenerating pool. Spend to secure a passage/door for you only (emits a tell); a witness can spend their own tool to break the lock. Economy rewards engagement, punishes turtling.
12. **Classes/kits (`§9A`) — DO NOT BUILD until after the Phase 4 fun test.** Asymmetric archetypes (Bomber, Poisoner, Crossbow, Trapper), each balanced on commitment-vs-vulnerability, all visually identical to the crowd. Prototype the entire game with ONE shared kit first.
13. **Scoring (`§10`).** Rewards low average exposure + fast + clean kills; penalizes wrong-target kills, prolonged high exposure, and dying. The winner is the most invisible/efficient assassin, not the twitchiest.

**The 7 design pillars (`master_plan` §16) — non-negotiable; if a feature breaks one, the feature is wrong:** ①Sameness is sacred ②Acting is exposing ③The map is the skill ④Every advantage has a counter ⑤Reward engagement, punish turtling ⑥Readability is fairness ⑦Power is bought with vulnerability.

**Reference games:** Hidden in Plain Sight (the loop), Assassin's Creed Brotherhood multiplayer (the fantasy), Murderous Pursuits (the format). Our differentiators: online + open maps + secret passages/trapdoors + a limited "tools" resource for map control + a PvE-into-PvP objective structure that forces engagement.

**Engine:** Godot 4.7 stable. Language: GDScript. Renderer: Compatibility (OpenGL3). Target platforms eventually: PC (Steam) → console → mobile, so design for controller + low-end hardware from day one.

**Team:** Solo developer (me) using Claude/Claude Code as primary engineering. ~10 focused hrs/week. One part-time artist (brother) joining heavily at the art phase. I am a beginner — explain *why*, not just *what*, and keep me from building myself into corners.

**Current state (updated June 2026):**
- Godot project created (renamed to UNSEEN), Compatibility renderer, Git initialized.
- Folders exist: `res://scenes`, `res://scripts`, `res://assets`, `res://maps`.
- **Phase 0 is COMPLETE and committed** (commit `Phase 0: foundation — player movement, input map, camera, project layout`): `Player` (CharacterBody2D, Floating motion mode) with placeholder visual + collision moves via WASD/controller, blend-walk vs run, Camera2D follows smoothly, Input Map set with keyboard+gamepad parity, `main.tscn` is the run scene.
- **We are now starting Phase 1 (Exposure).** Codex should begin here. See §4 "Current Next Action."

---

## 1. ARCHITECTURE PRINCIPLES (enforce these in every phase)

These exist to keep a beginner's project from turning into spaghetti and to protect future options (2.5D upgrade, online, console).

1. **Separate logic from visuals.** Gameplay logic (movement, exposure, objectives, kills) must never depend on specific sprites or art. The visual layer is a swappable child node. This preserves the 2D → 2.5D upgrade path and lets us prototype with grey boxes.
2. **Never hardcode input keys.** Use Godot's Input Map with abstract action names only: `move_up`, `move_down`, `move_left`, `move_right`, `action_primary` (kill), `action_secondary` (use tool/secure), `run` (hold to sprint — walking is the default pace). Every action must be bound to BOTH keyboard and a gamepad button. This is non-negotiable for the console/mobile roadmap.
3. **One responsibility per script.** A script does one job. `player.gd` handles player movement/state. Exposure lives in its own component. NPC AI is its own script. Don't let files balloon.
4. **Composition via child nodes / components.** Prefer small reusable nodes (e.g. an `ExposureComponent`) over giant monolithic scripts. The player and NPCs may share components.
5. **Signals over polling.** Use Godot signals for events (`kill_performed`, `exposure_changed`, `objective_reached`). Don't have nodes constantly reach into each other.
6. **Server-authoritative mindset, early.** Even in single-player phases, write gameplay logic as if a server will validate it later (kills, scores). This makes the Phase 6 online port dramatically less painful. Avoid logic that only works because it's local.
7. **Constants and tuning values in one place.** Speeds, exposure rates, timers go in an exported/config file or `@export` variables — never magic numbers buried in functions. I need to tune these constantly.
8. **Commit often.** Every working session ends with a git commit. Every phase ends with a tagged commit (`phase-0-complete`, etc.).
9. **Readability and traceability over cleverness.** The developer is a beginner who will debug this code for years — clarity is a feature, not a nicety. Enforce:
   - **Descriptive, self-documenting names.** A variable says what it holds and its unit: `exposure_rise_per_second`, not `r` or `rate1`. A function says what it does: `apply_kill_exposure_spike()`, not `doSpike()`. Never use single-letter names except a loop index `i`. If a name needs a comment to explain *what* it is, the name is wrong.
   - **One concept per line.** Avoid clever one-liners that pack three operations together. A beginner should be able to read top-to-bottom and follow every step. Prefer an extra named variable over a dense expression — e.g. `var is_running := Input.is_action_pressed("run")` then use `is_running`, rather than burying the condition inline.
   - **Comments explain *why*, not *what*.** The code shows what; comments explain the reason a value or branch exists (as `player.gd` already does). Every `@export` tunable gets a `##` doc-comment stating what it controls and its unit.
   - **Make state easy to trace when debugging.** Any value that matters (exposure, tool count, lock state, current target) must be inspectable at runtime — surfaced as an `@export`/visible property, emitted via a signal, or printed through one consistent debug helper — never hidden inside a function's local scope where you can't watch it change. When in doubt, make it traceable.
   - **No surprises.** A function does only what its name says and changes only the state you'd expect. Avoid hidden side effects that make a bug hard to locate.

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

### PHASE 0 — FOUNDATION (Weeks 1–2) ✅ COMPLETE
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
   - Default = walk_speed (calm blend-walk); hold `run` = run_speed.
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

**Prerequisites:** Phase 0 complete. ✅

**Reads from master plan:** `§3` (exposure system), `§3` exposure-arc pacing model, and Pillar #2 (acting is exposing) / Pillar #6 (readability is fairness). Build the system to match `§3` intent, not just the bullet list below.

**Design intent:** Exposure is a 0–100 value — the heartbeat of the game. Running and erratic/sharp direction changes raise it fast; performing a kill (Phase 3) spikes it; being alone in open space raises it slowly. Blend-walking lowers it; standing still bleeds it slowly; standing in a dense NPC cluster bleeds it fastest (Phase 2 wires density in). It is **not** a literal visibility toggle — it's a speed/probability modifier on being detected (Phase 2/5). Exposure is shown to *you* on the HUD and **never** to opponents.

**Architecture — build exposure as a HUB, not just a movement counter.** Many systems will move exposure (movement, kills, wrong-target penalties, crowd density, being alone, tool tells, teleport channel). They must NOT each edit the exposure math. The component is the single owner of the value and exposes three "doors" so any future system integrates with one call (Principles #3/#4/#9). **This is the priority of this phase — get the framework extensible; the rate *values* are tuned later.**

**Tasks:**
1. Create a reusable `components/exposure_component.gd` (extends Node). Responsibilities:
   - State: `var exposure: float = 0.0`, changed in ONE private place (`_set_exposure`) that clamps 0–100 and emits the signal. ✅ done.
   - **Door 1 — `update(is_running, is_moving, direction, delta)`:** the movement source, called every frame by the actor. Computes a per-second rate from the movement tunables below, adds the continuous modifiers (Door 3), applies for the frame. ✅ done.
   - **Door 2 — `add_exposure(amount, reason="")`:** instant one-off change (a kill spike `+`, a penalty `+`, a drop `-`). Phase 3's kill calls this. ✅ done.
   - **Door 3 — `set_continuous_modifier(name, rate_per_second)` / `remove_continuous_modifier(name)`:** ongoing per-second pushes from other systems, summed each frame. Phase 2 crowd density wires in here as `set_continuous_modifier("crowd_density", -X)` (this replaces the old `in_crowd` parameter idea — cleaner and open-ended). Being-alone, teleport channel, etc. all plug in the same way. ✅ done.
   - Movement tunables (all `@export`, units in their names, tuned later): `run_rise_per_second`, `erratic_rise_per_second`, `walk_fall_per_second`, `idle_fall_per_second`, `erratic_angle_threshold_degrees`. Plus `debug_print_changes: bool` to print instant changes for tracing.
   - `signal exposure_changed(new_value: float)` (Principle #5). **Server-authoritative-ready (Principle #6):** computes from inputs passed in; never reads Input or reaches into the player.
2. Attach an `ExposureComponent` to the Player; player feeds movement state into Door 1 each `_physics_process`. No exposure math inside `player.gd` (Principle #3). ✅ done.
3. Minimal HUD: a `CanvasLayer` (`scripts/hud.gd`) → `ExposureBar` (`ProgressBar`). Connect to `exposure_changed` (component reference set via an `@export` NodePath so the HUD is reusable per-player in Phase 4). Color shifts green→yellow→red as it rises. The bar is the only exposure feedback; resist any temptation to mark the player sprite (Pillar #1). ✅ done (built into `main.tscn`; a standalone `hud.tscn` can wait).
4. **Exposure-arc hook (`§3` pacing model) — scaffold only, don't fully tune yet:** add an `@export var arrow_threshold: float` constant on a round/config object and an `@export` curve or simple "threshold falls over round time" stub. We don't build the arrow (`§3.1`) until there are other players/hunters to see it (Phase 2+), but reserve the threshold value here so later systems reference one source of truth. A short comment should note that this threshold is "the most important number in the game" (`§15`).
5. Tune `walk_speed`, `run_speed`, and the exposure rates so the *feel* is right — solo iteration. All values stay `@export`.
6. Build a flat greybox test map in `maps/test_map.tscn`: a few `StaticBody2D` walls + open areas using simple rectangles/`Polygon2D`. No art. Make `test_map.tscn` (with the Player instanced) the run scene for this phase.
7. Confirm the abstract input map still has full controller + keyboard parity (Principle #2).

**Test checkpoint:** Walking keeps the bar low and green; running spikes it toward red fast; jittering the stick back and forth (erratic) raises it noticeably faster than smooth movement; stopping bleeds it down slowly. Every rate is editable live in the Inspector and the tension is readable at a glance.

**Done =** I can walk around the greybox map and *feel* the tension of exposure rising when I move carelessly, with every number tunable.

---

### PHASE 2 — THE CROWD (Weeks 9–16) ⚠ HIGHEST TECHNICAL RISK
**Goal:** 20–30 NPCs fill the map, move believably, and I can genuinely hide among them. One bot hunter searches for me.

**Prerequisites:** Phase 1 complete. This phase killed predecessor games (AC Rearmed died on bad NPC pathing). Spend extra time here. Do not rush to Phase 3.

**Reads from master plan:** `§4` (the crowd), `§5` (hunters & detection), `§3` (density lowers exposure), Pillars #1 (sameness) and #3 (map is the skill).

**Design intent:** NPCs must be visually identical to the player and move naturally enough that a watching human cannot trivially distinguish player from NPC (`§4` — "they must NOT look robotic or grid-aligned; believability is everything — this is what sank AC Rearmed"). NPC speed = player **blend-walk** speed exactly — the linchpin that makes a walking player indistinguishable and a running player obvious. The hunter bot models the future human hunter; keep its detection in a tunable function you'll rewrite repeatedly (`§5`): chance/speed of a lock scales with target exposure + proximity + line-of-sight + behavioral tells (running/erratic/beelining reads as a player). Prey can shed a lock by re-blending (`§5` counterplay) — getting spotted starts a survivable chase, never an automatic death.

**Tasks:**
0. **(done) Stage the map + reusable Player.** `scenes/player.tscn` extracted (instance-able); `maps/test_map.tscn` greybox plaza with perimeter walls + a `NavigationRegion2D`; `scripts/test_map.gd` builds a rectangular nav floor at runtime; `scenes/main.tscn` is now a composition root (map + player + HUD). Crowd density (task 5) will plug into the exposure HUB via `set_continuous_modifier("crowd_density", …)`.
1. Set up navigation: a `NavigationRegion2D` over the test map so agents can path. ✅ (rectangular nav built in `test_map.gd`; real maps bake in-editor later).
2. Create `scenes/npc.tscn`: `CharacterBody2D` named `NPC`, identical placeholder visual to the Player, a `NavigationAgent2D`, and `scripts/npc.gd`. ✅ Sameness enforced via a shared `scenes/character_visual.tscn` instanced by BOTH player and NPC (Pillar #1) — done as task 7 at the same time.
3. `npc.gd` wandering behavior:
   - Pick a random reachable point (`NavigationServer2D.map_get_random_point`), path to it via `NavigationAgent2D`, pause a random time, repeat. ✅ done.
   - Movement speed matches the player's WALK/blend speed (`move_speed` default 90). ✅ done.
   - **Still TODO (polish pass):** slightly varied speeds, occasional direction changes, and small clustering near "points of interest" for extra believability.
4. Create `components/crowd_manager.gd`: spawns N NPCs at valid nav points, maintains the population, exposes density queries (how many NPCs near a position). ✅ done (spawns `npc_count`, `count_npcs_near()` density query). Collision layers named (world/player/npc) and kept for future detection, but **no physical actor collision** — players and NPCs pass through each other and the crowd; only walls block (master_plan §4 design decision). **Still TODO:** population maintenance (respawn) if/when needed.
5. Wire crowd density into exposure: standing in a dense cluster lowers exposure faster (you're camouflaged); being alone in the open is exposing.
6. Build the **hunter bot** (`scripts/hunter_ai.gd`): wanders like crowd, but scans for the player. Detection probability scales with the player's exposure and proximity/line-of-sight. On "lock," it pursues. Keep detection logic in its own tunable function — I will rewrite this repeatedly. ✅ done (suspicion meter from exposure×proximity×LOS, lock/unlock thresholds, raycast LOS through crowd, all `@export`, dev state tint). **TODO later:** detection should treat the hunter's own facing/FOV, behavioural tells (beelining), and shed-lock counterplay polish (§5).
7. Make player and NPC share the same visual/scale exactly so they're indistinguishable at rest.

**Test checkpoint:** I stand still in a crowd and feel hidden; I run and the hunter finds me. Watching the screen, it's genuinely hard to instantly pick the player out of the crowd.

**Done =** The cat-and-mouse loop exists and feels good. **If this is fun, we have a game.**

---

### PHASE 3 — OBJECTIVES & THE KILL (Weeks 17–24)
**Goal:** A complete single-player loop: do objectives, get a target, kill, win/lose, score. Add the first trapdoor + secret passage.

**Prerequisites:** Phase 2 complete and fun.

**Reads from master plan:** `§6` (the kill + wrong-target penalty + no respawns), `§7` (contract PvE→PvP), `§7.2` (how-you-kill micro-decision), `§8.1`–`§8.2` (passages/trapdoors), `§9` (tools), `§10` (scoring), Pillars #2/#4/#5/#7.

**Owner's design decisions for this phase (June 2026 — honor these):**
- **Unmarked NPCs are UNKILLABLE.** Civilians not on your contract simply cannot be killed at all (the kill does nothing on them) — not a wrong-target *penalty*, an outright block. Only valid contract targets accept a kill. (This overrides the §6 "wrong-target penalty" model for civilians; revisit only if playtest wants the social-deduction risk back.)
- **Current test target = the hunter.** Until the contract/marks exist, the only killable entity is the hunter bot.
- **The kill is a click → animation → exposure spike.** `action_primary` triggers a brief kill animation that raises the killer's exposure (Door 2: `add_exposure`). The spike is permanent (exposure is one-way now).
- **Exposure already started (done):** one-way exposure + exposure arrow (§3.1) are built; the kill spike rides on the same exposure hub.
- **Exposure feed status:** arrow currently points at the hunter (group "hunter"); generalize to all over-exposed actors later.

**Tasks:**
1. **Objective system** (`scripts/contract_manager.gd`): place 1–2 NPC "marks" at fixed, intentionally **exposed** map locations (`§7`). Track completion. After marks done, designate the final target. ✅ done — spawns marks at the map's `get_mark_locations()` (exposed side lanes); marks are killable, crowd is not; finishing marks makes the hunter the killable target; HUD label tracks progress. **TODO:** marks could wander a little / be harder to ID (currently they stand at the gold dot).
2. **Kill mechanic** (`components/kill_component.gd`): within range of a *valid* target + `action_primary` → kill. ✅ basic version done — kills nearest actor in the "killable" group within `kill_range`, strike-pulse animation. Unmarked NPCs are unkillable (owner's rule, replaces the wrong-target *penalty* for civilians). **TODO:** lock both actors + short timer (currently instant); server-authoritative validation for the online port.
3. **Kill consequence:** performing a kill adds a PERMANENT committed exposure spike (`kill_exposure_spike`, Door 2). ✅ done. (Two-part exposure model means this is a floor you can't walk off — §3.)
4. **No respawns (`§6.1`):** a killed player/bot is out for the round.
5. **Win/lose + score (`§10`):** round ends on contract complete, player death, or timer. Score rewards low **average** exposure across the round + fast + clean kills; penalizes prolonged high exposure and dying. ✅ done — `round_manager.gd` (avg-exposure sampling, time, kills, win/death bonuses, all `@export`) + `end_screen.tscn` (result + breakdown + Play Again). Hunter now catches the player (`catch_distance`). **TODO:** persist/rank scores later (the §6.1 ranked spine).
6. **How-you-kill micro-decision (`§7.2`):** support both taking a mark with a stealth tool (lower exposure, spends a tool) and walking up to knife it (free, bigger exposure spike). Every mark is a small risk/budget choice.
7. **Trapdoor + teleporter + underground passage (`§8.1`/`§8.2`/`§8.5`):** ✅ travel built — one reusable `Portal` (Area2D) powers all three: teleporter pads (cross-map, exposure cost), a trapdoor (medium hop, small exposure tell), an underground passage (free). The map spawns the pairs. **Still TODO:** the limited **tools** resource (`§9`, `max_tools` consumable), *securing* a passage for yourself + the break-it counter, cast time/cooldown (`§8.5`), single-occupancy rule (`§8.1a`), and a visible use-tell.
8. **Secret passage (`§8.1`):** ✅ covered by the free underground passage portal (no resource cost — pure map knowledge). Visual subtlety / hidden entrances are a later art-pass concern.

**Test checkpoint:** I can start a round, complete marks, get my target, kill, and win or lose. The trapdoor and passage work and feel like secrets. Tools are limited and meaningful.

**Done =** A complete playable loop with secrets in the map.

---

### PHASE 4 — LOCAL MULTIPLAYER (Weeks 25–32)
**Goal:** Two humans on one machine, each with their own contract, hunting each other plus bots. This is the FUN TEST and the project's go/no-go gate.

**Prerequisites:** Phase 3 complete.

**Reads from master plan:** `§7.1` (speed-reward target pings), `§3.1` (exposure arrow — now there are real opponents to see it), `§11` (match structure / FFA contract web), `§15` (the open balance risks to watch in playtest). **Note:** classes/kits (`§9A`) are still NOT built — prove the single shared kit is fun first.

**Tasks:**
1. Add a second local player: controller 2, or keyboard-vs-arrows. Reuse the same Player scene/components; parameterize the input device. DONE for first local fun test - P1/P2 inputs and two Player instances.
2. Independent exposure, tools, and target assignment per player. Players can be each other's targets (FFA contract web, `§11`). PARTIAL - exposure + target assignment are independent; tools still wait for the paused Phase 3 map-control pass.
3. **Now wire the exposure arrow (`§3.1`):** when a player crosses the arrow threshold, the *other* player sees a color-coded directional arrow toward their area that **vanishes once that player is on-screen** (back to read-the-crowd). The arrow carries the color; the character stays visually identical (Pillar #1 guardrail). DONE for the two-player fun test.
4. **Speed-reward target pings (`§7.1`):** the player who finishes their NPC marks first earns pings on their PvP target; the slower player relies only on the arrow. Verify both aggressive and cautious playstyles stay viable (`§15`).
5. Split or shared-screen handling appropriate to top-down (likely shared screen with a wide camera, or split — prototype shared first). DONE as split private SubViewports; true no-peek needs physical separation or a second-display/window pass.
6. End-of-round summary comparing both players' scores. DONE.
7. **Playtest relentlessly** with my brother. Tune everything. Cut what isn't fun.

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
- **Write for a beginner to read and debug (Principle #9).** Use long, descriptive, self-documenting names with units (`exposure_rise_per_second`, not `r`); one concept per line over clever one-liners; comments that explain *why*. Make any value that matters traceable at runtime (an `@export`/visible property, a signal, or a consistent debug print) so I can watch it change while hunting a bug — never bury important state in a local variable I can't see.
- Surface **every value I'll want to tune** as `@export` variables; never bury magic numbers.
- Respect the **architecture principles** in section 1 on every task. If a quick hack would violate them, flag it and propose the clean version.
- When a task touches the **future online port** (kills, scoring, state), implement it server-authoritative-ready even in single-player.
- At the end of each session, give me a **git commit message** and remind me to push.
- If something is **above my current skill to debug**, say so plainly and give me a way to isolate the problem rather than guessing.
- Keep a short **CHANGELOG.md** updated as we go so we never lose the thread between sessions.

## 4. CURRENT NEXT ACTION
**Phase 0 is complete and committed.** We are now starting **Phase 1 — Exposure**, the core tension system (`master_plan.md` §3).

The immediate next step for Codex: build `components/exposure_component.gd` exactly per the Phase 1 tasks above — a reusable `Node` holding a 0–100 `exposure` value with all rates as `@export`, an `update(is_running, is_moving, direction, in_crowd, delta)` method, and an `exposure_changed` signal — then attach it to the Player, feed it the player's movement state each `_physics_process` (without computing exposure inside `player.gd`), build the `hud.tscn` exposure bar (green→yellow→red), and lay down the `maps/test_map.tscn` greybox. Reserve the `arrow_threshold` config value but do not build the arrow yet (no opponents until Phase 2+).

Work in small testable increments (§3 Standing Instructions): after each meaningful change, give exact Godot-editor steps to verify, wait for confirmation, explain the *why* of the GDScript, keep all tunables as `@export`, update `CHANGELOG.md`, and end the session with a commit message (tag `phase-1-complete` when the test checkpoint passes).
