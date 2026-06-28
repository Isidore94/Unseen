# CLAUDE.md — UNSEEN

> Keep this file SHORT. It loads into every session, so bloat here is paid on every turn.
> It points to the real docs; it does not duplicate them.

## What this is
An **online-multiplayer-first** top-down 2D competitive social-stealth game. Players are visually
identical to a crowd of AI NPCs; you complete a contract (kill NPC marks, then hunt a human target)
while being hunted, and the lowest-exposure, fastest-cleanest assassin wins. **Server-authoritative:**
the host owns every outcome, and a client never receives data that reveals which character is human
(except the deliberate reveals) — see the server-authoritative rule (#5 below).

## Source-of-truth docs (read the relevant one before working — don't guess intent)
- **`master_plan.md`** — *what the game is and how it plays.* Every mechanic, numbered by section
  (§3 exposure, §5 detection, §6 kill, §7 contract, §8 map control, §9/§9A tools & classes, §16 pillars).
- **`COSMETIC_SYSTEM_SPEC.md`** — the cosmetic/identity rig (body/outfit/head/weapon layers, loadouts,
  inventory). **`ART_PIPELINE.md`** — the PixelLab art pipeline + 48px rig format.
- **`CHANGELOG.md`** — detailed running log; update it as we go so sessions don't lose the thread.
  **`changelogsimple.md`** — the brief player-facing devlog.
- *No build-plan doc right now* — the old `buildplan.md`/phase docs were removed; a fresh plan for the
  next stage is incoming. Until then, the cross-cutting online rules live in #1–#7 below.

## Engine & stack
- Godot **4.7 stable**, **GDScript**, **Compatibility (OpenGL3)** renderer. Windows dev machine.
- Target roadmap: PC (Steam) → console → mobile. Design for **controller + low-end hardware** from day one.

## Current state (branch `prayer`)
- Phases 0–7 done (foundation → exposure → crowd → kill → art → online/Steam → 4-zone map, layers,
  claims/cooldowns, reveals, rematch, smoke/cloak), then phases 8–11 integrated.
- **`prayer` shipped a big art + identity update:** real PixelLab pixel art (4 end-game assassin
  player skins with walk+attack anims, 11 Roman commoner crowd looks); all maps reskinned to a clean
  stylized look; crowd overhaul (50/50 commoner/assassin mix, movement variety, 6s panic on kills);
  lobby **character select** (pick your assassin, privately) + **NPC-disguise** option; per-viewer
  hidden-identity crowd. See CHANGELOG.md for the full list.
- **Not yet verified:** the lobby/disguise/rematch-to-lobby **online** paths are compile-checked but
  need a 2-instance playtest before merging `prayer` → `main`.
- **Next:** a fresh plan doc for the next stage is coming. Tag milestones as we go.

## Who I'm working with (matters for how to respond)
- **Solo developer, brand-new coder.** Explain the *why*, not just the *what*. Keep them from building
  into corners. One part-time artist (their brother) joined at the art phase (Phase 5).
- **ALWAYS explain every change as if to someone who knows little about coding.** After any edit, walk
  through what each new file/function/variable does in plain language and *why* it exists — assume terms
  like "signal", "node", "@export", "lerp" need a one-line explanation the first time they appear. Teaching
  is part of every task, not an add-on.
- After each meaningful change: give **exact Godot-editor steps to test**, then **wait** for confirmation.
- End each session with a **git commit message** and a reminder to push. Tag phase completions
  (`phase-1-complete`, …).

## Non-negotiable coding rules (online-first)
1. **Separate logic from visuals** — gameplay logic never depends on specific art; visuals are swappable child nodes.
2. **Never hardcode input keys** — abstract Input Map actions only (`move_*`, `action_primary`,
   `action_secondary`, `run` = hold to sprint, walking is default), bound to keyboard AND gamepad.
3. **One responsibility per script**; prefer small reusable components (e.g. `ExposureComponent`).
4. **Signals over polling** (past-tense names: `exposure_changed`, `kill_performed`).
5. **Server-authoritative is law** — the host validates and owns every outcome (kills, scores, layer,
   claims, reveals); clients send *intent* only and never self-confirm. Send clients the least data
   that works — never anything that reveals which character is human.
6. **No magic numbers** — every tunable is an `@export` with a `##` doc-comment stating what it controls + its unit.
7. **Readable & traceable for a beginner debugging later** — long self-documenting names with units
   (`exposure_rise_per_second`, not `r`), one concept per line over clever one-liners, important state
   inspectable at runtime (visible property / signal / debug print), comments explain *why*.

## Naming
- Files `snake_case.gd` / `snake_case.tscn` · Nodes `PascalCase` · vars/funcs `snake_case`
- Constants `ALL_CAPS` · Signals past tense.

## Folder layout
`scenes/` (.tscn) · `scripts/` (.gd) · `components/` (reusable nodes) · `assets/` · `maps/`

## Working efficiently (context discipline)
- Work **one phase / one task at a time**; only read the files that task needs (small focused scripts
  make this cheap — that's the point of Principle #3).
- Don't re-read whole docs you've already seen this session; reference them.
- For unrelated new tasks, prefer a fresh session over piling onto a long one.
