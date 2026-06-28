# UNSEEN — Everything added in Phases 7 → 11

A single index of what this body of work delivers, by phase. Integration order is
**7 → 8 → 9 → 10 → 11 → main** (each phase has its own `PHASE_N_TO_MAIN.md`). "Player-facing"
= you'd see/feel it in a match; "Under the hood" = systems/infrastructure it rides on.

---

## Phase 7 — Online, server-authoritative match (`phase-7-online-integration`, v0.7.1)
The full Phase 7 game brought onto the **online, host-authoritative** path (the real test surface).

**Player-facing**
- **Up to 4 players online** — Steam relay / ENet lobby, host + join.
- **Target ring** — each player hunts exactly one other and is hunted by one other; re-links if your target dies.
- **Two NPC marks** per player before the human-hunt phase opens; marks loiter locally, spaced apart.
- **Layers — rooftops & sewers** with a true per-viewer hidden view: rooftop = hide/watch/drop; sewer =
  blind-stalk by a 100%-uptime arrow, no killing; ground = the kill floor.
- **Map-control** — claim an access point for the match (costs exposure) + a 15s global anti-camp cooldown;
  teleporters cost exposure.
- **Class items** — Smoke (go invisible, can't attack) + Cloak (kills the hunt arrow on you).
- **Identity reveals + faceplates** — RED (your target's look after you finish your contract), BLUE
  (a player who hit 100% exposure), shown only with the arrow.
- **Last-one-standing + points** — death eliminates (you spectate); winner = **most points**, not the
  survivor; points scoreboard + **Rematch**.
- **Single-player (offline)** — one human vs a bot hunter, for quick feel checks (split-screen retired).
- **Tighter camera + spaced spawns** so no two players start adjacent.

**Under the hood**
- Server-authoritative everywhere (host validates kills/layer/claims/reveals; clients send intent only).
- Per-viewer **visibility** system (who can I see) — the seam Phase 9's appearance system builds on.
- Kill attribution, smoke kill-lockout + claim-cooldown authority fixes.
- `tools/validate.sh` — headless GDScript compile-checker.

---

## Phase 8 — Cosmetic & identity foundation (`claude/phase-8-monetization-oqu6sd`, v0.8.0)
The plumbing all monetization sits on. **No shop / currency yet — foundation only.**

**Player-facing (today: invisible by design)**
- One **shared character rig** (`CharacterVisual`) draws every person (player, remote, NPC, previews) from
  4 composited layers (body / outfit / head / weapon) on a locked feet origin.

**Under the hood**
- **Data-driven cosmetics:** `CosmeticItem` (id/slot/palette/**bucket**/**rarity**/**season**), `Loadout`
  (compact id-only payload), `CosmeticRegistry`. Adding a cosmetic later = one art file + one data row.
- **Crowd-safe taxonomy** (the §0 veto): `Bucket {CROWD_SAFE, REVEAL_MOMENT, OUT_OF_MATCH}` decides what a
  cosmetic may touch in-match.
- **Network replication** of looks as id-only payloads (once on join, never per-frame).
- **Animation hooks** wired to real events (kill / win / emote / kill-card) — stubs ready for real anims.
- **`PlayerProfile`** (banner/badge/title) + **`CosmeticInventory`** (owned-set, ownership-gated equip — the
  seam a shop bolts onto).
- **Monetization + PixelLab specs** (`PHASE_8_MONETIZATION.md`), style-bible anchor, secure PixelLab MCP config.

---

## Phase 9 — Hidden-identity pillar + endgame experiments (`phase-9`)
The §0.3 pillar the cosmetics store depends on, plus a toolbox of opt-in tuning experiments.

**Player-facing**
- **Per-viewer crowd appearance (§0.3):** on your screen the crowd is rebuilt so you **never see your own
  look** — a tunable share (`clone_crowd_fraction`, default 25%) are **clones of the other players** (each
  opponent hidden in a pocket of look-alikes), the rest generic filler. Your skin only ever shows on you.
- **Smaller, readable crowd** (npc_count 60 / small maps 40).
- **Six endgame EXPERIMENTS — all OFF by default** (flip one at a time to playtest):
  9A whiff-recovery · 9B crowd-thinning · 9C earned-read pulse · 9D mutual-proximity · 9E crowd-reaction ·
  9F behavioral-flag. (`PHASE_9_EXPERIMENTS.md`.)

**Under the hood**
- `ExperimentFlags` autoload + folder-scan loader (each experiment self-contained, removable — the delete test).
- `behavior_history` component (rolling tells) + neutral core hooks (`kill_resolved`, `can_kill`,
  `Npc.react_to_kill`/`walk_off_to`, `OnlineMatch.host_kill_resolved`) — core never references an experiment.

---

## Phase 10 — Maps (`phase-10-maps`)
A home for map design; first content + lobby selection.

**Player-facing**
- **Rome** — a small, street-only map: a warren of tight 1-cell lanes between insulae blocks, a central
  fountain piazza, two markets. **No rooftops / sewers / portals** — just roads. (Flood-fill verified.)
- **Lobby map picker** — Four Zones / Compact / **Rome** (host picks; everyone loads the same map).

**Under the hood**
- `enable_portals` map toggle; `NetworkManager.selected_map` plumbing (survives lobby→match).

---

## Phase 11 — Art pipeline (`phase-11-art-pipeline`)
PixelLab locked as the canonical art backbone for **sprites and maps**. Foundations only (map→TileMap
migration sequenced later, per `ART_PIPELINE.md` §7).

**Decisions LOCKED**
- **Full pixel art**, map included — **clean / refined urban** (muted palette, soft shadows, orderly
  tiling, mandatory hand-finish), **48×48** base, top-down, 4-direction, feet pivot.

**Under the hood**
- Project-wide Nearest texture filter; `assets/source` ↔ `assets/finished` split; generation manifest
  (reproducibility + spend + AI-disclosure log); `tools/ingest_sprite.py` (Pillow ingest scaffold) + a
  starting muted-urban master palette.

---

*Status: all five phases are built and pending integration to `main`. They have NOT been compile-tested
or playtested in Godot yet (built in a cloud env without Godot) — `tools/validate.sh` + the per-phase
runtime gates are the verification step. Tags on completion: `phase-7-complete` … `phase-11-…-complete`.*
