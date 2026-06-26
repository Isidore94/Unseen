# CLAUDE.md — UNSEEN

> Keep this file SHORT. It loads into every session, so bloat here is paid on every turn.
> It points to the real docs; it does not duplicate them.

## What this is
A top-down 2D online competitive social-stealth game. Players are visually identical to a
crowd of AI NPCs; you complete a contract (kill NPC marks, then hunt a human target) while
being hunted, and the lowest-exposure, fastest-cleanest assassin wins.

## The two source-of-truth docs (read the relevant one before working — don't guess intent)
- **`master_plan.md`** — *what the game is and how it plays.* Every mechanic, numbered by section
  (§3 exposure, §5 detection, §6 kill, §7 contract, §8 map control, §9 tools, §9A classes, §16 pillars).
  Read the relevant § for design intent.
- **`UNSEEN_BUILD_PLAN.md`** — *how and when to build.* Phased plan, architecture principles,
  standing instructions. **This is the master plan for the work.** Read §1 (principles) and the
  current phase before coding.
- **`CHANGELOG.md`** — running log; update it as we go so sessions don't lose the thread.

## Engine & stack
- Godot **4.7 stable**, **GDScript**, **Compatibility (OpenGL3)** renderer. Windows dev machine.
- Target roadmap: PC (Steam) → console → mobile. Design for **controller + low-end hardware** from day one.

## Current state
- **Phase 0 (foundation) is COMPLETE & committed.** Player square moves (WASD + controller),
  blend-walk vs run, camera follows, Input Map has keyboard+gamepad parity, `scenes/main.tscn` is the run scene.
- **Next: Phase 1 — Exposure** (the core tension system, `master_plan.md` §3). See build plan §4.

## Who I'm working with (matters for how to respond)
- **Solo developer, brand-new coder.** Explain the *why*, not just the *what*. Keep them from building
  into corners. One part-time artist (their brother) joins at the art phase (Phase 5).
- **ALWAYS explain every change as if to someone who knows little about coding.** After any edit, walk
  through what each new file/function/variable does in plain language and *why* it exists — assume terms
  like "signal", "node", "@export", "lerp" need a one-line explanation the first time they appear. Teaching
  is part of every task, not an add-on.
- After each meaningful change: give **exact Godot-editor steps to test**, then **wait** for confirmation.
- End each session with a **git commit message** and a reminder to push. Tag phase completions
  (`phase-1-complete`, …).

## Non-negotiable coding rules (full versions in build plan §1)
1. **Separate logic from visuals** — gameplay logic never depends on specific art; visuals are swappable child nodes.
2. **Never hardcode input keys** — abstract Input Map actions only (`move_*`, `action_primary`,
   `action_secondary`, `run` = hold to sprint, walking is default), bound to keyboard AND gamepad.
3. **One responsibility per script**; prefer small reusable components (e.g. `ExposureComponent`).
4. **Signals over polling** (past-tense names: `exposure_changed`, `kill_performed`).
5. **Server-authoritative-ready** even in single-player (kills, scores) — eases the Phase 6 online port.
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
