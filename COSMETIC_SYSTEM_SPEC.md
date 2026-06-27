# Unseen — Cosmetic & Identity System Architecture

## Goal of this task

Lay the **foundational architecture** for cosmetics, animations, and profile
identity so these can be added later as **data + art only**, with no code
changes. Do **not** build the shop, currency, or any store UI in this pass.

The test of success: after this task, adding a new hat = adding one art file
and one data entry. Adding the shop later = building UI on top of an inventory
system that already exists. If adding cosmetics later requires touching the
character rig, the netcode, or the gameplay loop, this task failed.

Build the plumbing. Leave the content empty (or placeholder).

## Constraints / respect existing patterns

- Godot 4.7, GDScript.
- Keep it **data-driven** (same pattern as the `DISTRICTS` array). Cosmetics
  are data, never hardcoded.
- Prefer **runtime construction** over hand-authored `.tscn` trees, consistent
  with `MapBuilder.gd`.
- Assets are **SVG**, recolored at runtime via `modulate`. The rig must support
  per-layer palette swaps with no extra art.
- Do not over-build. No shop, no currency, no unlock progression logic, no
  rarity-based store sorting. Placeholder art is fine and expected.

---

## 1. Composable character rig (the foundation everything depends on)

Build a single `PlayerCharacter` scene/script used by **everything that draws a
person**: local player, remote players, NPC crowd, menu preview, results
screen, scoreboard portraits. One rig, every context. No separate NPC art path.

Four stacked layers, composited against **one shared origin**:

1. `body`   — legs / base
2. `outfit` — top + bottom (one layer for now)
3. `head`   — head / hat
4. `weapon` — static, holstered on back or hip (`Sprite2D`, not animated
   independently — it rides the body)

Requirements:

- All animated layers share **one animation clock** — they play the same
  animation name in lockstep. A single `AnimationPlayer` driving the layers, or
  synced `AnimatedSprite2D`s — your call, but they must never desync.
- **Anchor/origin is standardized and locked now.** Pick one origin (feet or
  hips), document it in a reference comment, and make every layer composite
  against it. Swapping a hat must not shift the character by a pixel. This is
  the single most painful thing to fix later — get it right first.
- Z-order is fixed and explicit per layer.
- Define a single function `apply_loadout(loadout)` that sets the texture and
  `modulate` on each layer from a loadout. This is the **only** place cosmetics
  touch the rig. Used identically by players, NPCs, and previews.

---

## 2. Cosmetic items as data

Define a `CosmeticItem` resource (`class_name CosmeticItem extends Resource`)
with at minimum:

- `id` (stable string, never reused)
- `slot` (enum: BODY, OUTFIT, HEAD, WEAPON, KILL_ANIM, WIN_ANIM, EMOTE,
  BANNER, BADGE, TITLE)
- `display_name`
- `art_path` (SVG, or animation reference for the anim slots)
- `default_palette` (for modulate-based recoloring; null = no recolor)
- `acquisition` (enum stub: DEFAULT, EARNABLE, PURCHASE — just metadata for now,
  no logic behind it)

Build a central **registry** that loads all `CosmeticItem`s into a lookup by id
(dictionary or array of `.tres`, matching the `DISTRICTS` style). Seed it with
2–3 placeholder items per slot so the system is testable. Nothing more.

---

## 3. Loadout abstraction

A `Loadout` is just the set of equipped cosmetic ids per slot, plus any palette
choices. It is **pure data, fully separable from the rig**, and must be:

- Constructible from a **compact payload** (ints/ids only — no textures, no
  node references). This matters for netcode (see §5).
- Serializable to/from that payload both directions.

Player has a loadout. NPCs get **randomized** loadouts assembled from the
available cosmetic pool (see §4). `apply_loadout` consumes a `Loadout` and
nothing else.

---

## 4. NPC crowd uses the same rig + pool

NPCs are player-sprite instances. The crowd spawner should:

- Use the `PlayerCharacter` rig (not a separate NPC sprite).
- Build each NPC's loadout by **randomly combining** items from the cosmetic
  pool, so no NPC is guaranteed to mirror any one player's exact outfit.
- Leave a clean hook / config flag for where the pool comes from (global default
  pool now; "lobby players' cosmetics" later). Don't implement the lobby-sourced
  version yet — just don't wall it off.

---

## 5. Network replication (do this now, not later)

Remote clients must render each other's cosmetics. Design so a player's
appearance replicates as a **small loadout payload (ids/ints only)**, and the
remote rig is reconstructed via `apply_loadout`. Never replicate textures or
node state.

- Sync the loadout payload **once on join / on change**, not per-frame. It's
  static during a match.
- Keep it consistent with the existing bandwidth-optimized crowd netcode — this
  should add near-zero ongoing bandwidth.
- Confirm NPC loadouts are derived deterministically (shared seed) or replicated
  compactly, so all clients see the same crowd without per-NPC state spam.

---

## 6. Animation trigger hooks (slots, not content)

Wire the **event plumbing** for three animation cosmetic types, with
placeholder/no-op animations behind them:

- `KILL_ANIM`  — fired on successful assassination
- `WIN_ANIM`   — fired on match win / results screen
- `EMOTE`      — fired on player input, mid-match, manually triggered

Expose one entry point, e.g. `play_cosmetic_animation(type)`, wired to the
actual game events now (`on_kill`, `on_match_won`, emote input). The animation
itself can be a stub. The point is the **trigger path exists and is connected**
so dropping in real animations later is content-only.

Add a stubbed `kill_card` hook too (the brief visual the **victim** sees on
death) — just the event fire + a no-op handler. Cheap to stub now, annoying to
thread through later.

---

## 7. Profile identity (account metadata, separate from rig)

Define a `PlayerProfile` structure holding `banner`, `badge`, `title` (each a
cosmetic id). This is **account-level**, fully separate from the character rig.
Add display hooks where identity surfaces: scoreboard, results screen, player
name tag. Placeholder art/text is fine.

---

## 8. Ownership / inventory (minimal)

Add an account-level **inventory**: a set of owned cosmetic ids. The equip path
must check ownership before equipping (everyone owns the DEFAULT items at start).

- No shop, no currency, no purchase flow, no unlock conditions.
- Just: an owned-set, defaults granted to all, and equip gated on ownership.
- This is the seam the shop and progression bolt onto later without touching
  anything else.

---

## Out of scope (do not build)

- Shop / store UI
- Currency or premium currency
- Battle pass / progression / unlock conditions
- Real cosmetic art or real animations (placeholders only)
- Lobby-sourced NPC cosmetic pool (leave the hook, don't implement)

## Suggested order

1. Character rig + locked anchor/origin + `apply_loadout`
2. `CosmeticItem` resource + registry + placeholder items
3. `Loadout` + compact serialization
4. NPC crowd on the shared rig with randomized loadouts
5. Loadout network replication
6. Animation trigger hooks + kill_card stub
7. `PlayerProfile` + display hooks
8. Inventory + ownership-gated equip

Commit after each step so the integration is reviewable in isolation.
