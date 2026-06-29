# UNSEEN — RESPAWN MODE: implementation plan & tracker

> The inverted core loop: **5-minute rounds with continuous RESPAWNS** (no elimination). Each player
> hunts exactly one player and is hunted by exactly one (a maintained one-hunter/one-prey chain).
> **Death keeps nothing** — arrow precision, abilities, and exposure all wipe to base. An **optional
> per-life PvE ladder** (kill NPC marks) upgrades the current life only. Everything is gated behind
> feature flags so it A/B's against today's elimination loop. Ground-truth code reference:
> `MULTIPLAYER_PLAN.md`. Design intent: `master_plan.md`.

## Locked decisions (2026-06-29)
- **Design target = 4 players.** 2p is a feature-test harness only. (Confirms the `MAX_PLAYERS = 4` cap.)
- **PvE ladder = player chooses the axis** per NPC kill (sharpen arrow *or* gain a tool), capped per axis.
- **Base ability per life = the lobby-picked tool** (your loadout identity; not earned-power persistence).
- **2-alive mutual pair = accepted** as a transient, test-only artifact (the only valid chain for two players);
  at 3–4 active the chain has no mutual pairs.
- **Hook everything into the online authoritative kill path only**; the offline harness is left as-is and flagged.

## Feature flags (`scripts/game_mode_flags.gd`, autoload, host-authoritative)
- `respawn_mode_enabled` — master switch. **ON by default (the active mode):** PvP-first respawns.
  Flip OFF for the classic elimination A/B baseline.
- `pve_ladder_enabled` — the per-life PvE upgrade ladder. (Next increment.)
- `density_spawn_enabled` — crowd-density-weighted respawn picker (else authored-spawn fallback).

## Dependency-ordered stages & status
| # | Stage | Status |
|---|---|---|
| 0 | Feature flags + respawn tunables | ✅ done |
| 1 | Authoritative death hook + contract chain re-assignment (stable seat-order ring) | ✅ done (core) |
| 2 | Per-life state reset (wipe exposure + tools to base on death/respawn) | ✅ done (core) |
| 3 | Spawn candidates + live query surface (density/exclusion) | ✅ done (samples walkable points + crowd density) |
| 4 | Respawn system: weighted picker + grace + death→respawn wiring | ✅ done (core) |
| 5 | Arrow tiering (per-life precision 4-dir → 8-way → precise) | ⬜ next |
| 6 | PvE ladder (player chooses axis; capped) | ⬜ next |
| 7 | Exposure-cliff reconciliation (cliff precision distinct from ladder precision) | ⬜ |
| 8 | Identity-leak-at-spawn hardening + crowd-netcode reconcile | ⬜ (partly mitigated: spawn into density) |
| 9 | Tuning / telemetry / A-B (avg life length, no-PvE viability, spawn-camp rate) | ⬜ |

## What the CORE increment does (Stages 0–4)
When `respawn_mode_enabled` is on (host):
- **No mandatory marks** — every life starts straight in the PvP hunt (marks become optional ladder content later).
- **The chain** is a stable cycle over a fixed seat order: `target = next LIVING player`. Re-formed on every death and
  respawn (`_recompute_ring_from_seats`), so it's always one valid loop — no self-target (≥2 alive), no targetless
  player (≥2 alive), no mutual pair (≥3 alive). The 2-alive mutual pair is accepted (test-only).
- **On death:** the authoritative kill hook (`_on_player_killed`) re-forms the chain, schedules a respawn after
  `respawn_delay_seconds`, and **does not** spectate or end the round. The round ends only on the clock.
- **On respawn:** the same Player node is revived in place (`Player.revive`) — exposure wiped (`ExposureComponent.reset`),
  tools restocked to the lobby loadout (`ItemComponent.reset_to_base`), body un-faded/re-enabled on every machine
  (`_revive_player` RPC). The player is re-spliced into the chain and given a `respawn_grace_seconds` immunity.
- **Spawn picker** (`_pick_spawn`, host): samples walkable points, **hard-excludes** any near a live player or near
  your killer (anti-farm), **scores** survivors by crowd density (respawn already blended) + closeness to your new
  target, and picks with **mild randomization** among the top-K. Falls back to an authored spawn if everywhere is
  excluded (small map / full lobby) — never inside a kill zone.
- **Grace** = host-side kill immunity (`Player.grace_active`, checked in `KillComponent.request_kill`); it **breaks
  when the graced player lands a kill** (no shielded pushes).

## Known limitations carried forward (flagged, not yet addressed)
- **Grace breaks on kill only**, not on tool use (defensive tools during grace are allowed) — revisit in Stage 8.
- **`controlling_peer_id` over-the-wire identity leak** is unchanged (out of scope here); spawning into crowd density
  reduces but does not remove its exploitability. Own pass.
- **Per-viewer crowd reskin is "run once, frozen"** — a respawned life's look may not be re-cloned into each viewer's
  crowd; verify/fix in Stage 8.
- **Contract churn:** re-forming the ring each death is correct but reassigns more than a minimal splice would; a
  minimal-churn refinement is possible later.
- Offline `single_player_game.gd` / `contract_manager.gd` get **no** respawn (harness) — the 3-kill-path split persists.

*Plan v1.0 — 2026-06-29. Update the status table and limitations as stages land.*
