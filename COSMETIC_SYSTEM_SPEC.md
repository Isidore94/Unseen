# UNSEEN — Cosmetic & Identity System (as-built architecture)

> **Status:** the foundational plumbing described here is **built**; cosmetic *content* is mostly placeholder.
> This doc was originally a build brief; it has been rewritten (audit 2026-06-29) to describe **what the code
> actually does today**, so it can be trusted as ground truth. Source: `scripts/character_visual.gd`,
> `scripts/cosmetics/*`, `scripts/faceplate_row.gd`, `scenes/character_visual.tscn`, `assets/sprites/*`.
>
> **The success test (still the design north star):** adding a new hat should be *one art file + one data entry*,
> with no change to the rig, the netcode, or the gameplay loop. The architecture below holds that line.

---

## 0. The one invariant: sameness is sacred (Pillar #1)

**Every person in the game is drawn by the same rig** — local player, remote players, NPC crowd, menu preview,
results portraits. There is **no separate NPC art path**. A cosmetic is pure data applied to that shared rig. This
is what makes a human indistinguishable from a civilian. The crowd-safe veto (§7) and the per-viewer reskin (§6)
exist to defend it.

---

## 1. The character rig (`CharacterVisual`, the foundation)

`scripts/character_visual.gd` (`class_name CharacterVisual`, scene `scenes/character_visual.tscn`). Built **in code**
(via `_make_layer`) so every layer is pixel-aligned to one origin — not hand-authored in a `.tscn`.

**Four stacked layers, one locked origin (the character's centre / hips):**

| z | layer | what it is | animates? |
|---|---|---|---|
| 0 | `body` | the animated base sprite sheet (walk + attack) | yes (walk cycle) |
| 1 | `outfit` | recolourable overlay (top/bottom) | yes — in lockstep with body |
| 2 | `head` | recolourable overlay (head/hat) | yes — in lockstep with body |
| 3 | `weapon` | holstered weapon, a static 1×1 frame | no — rides the body |

- **Locked anchor.** Every layer uses the same `sprite_offset` + `centered = true` and composites against the one
  origin, so swapping a cosmetic can never shift the character by a pixel. (The single most painful thing to fix
  later — it is fixed now. Don't unpick it.)
- **One animation clock.** The body advances its walk frame; `outfit.frame` and `head.frame` are copied from the
  body each frame, so overlays can never desync. Attack: if an `ATTACK_SHEETS` entry exists for the current body,
  the body swaps to the attack texture, plays 4 swing frames over ~0.5s, and reverts.
- **One entry point.** `apply_loadout(loadout)` is the **only** place cosmetics touch the rig (used identically by
  players, NPCs, and previews). It reads body id → registry index → `set_appearance(index)`, then applies the
  outfit/head/weapon overlays. Gameplay never reaches into visuals (coding rule #1).

**Frame grid:** sheets are **4×4 of 48px frames = 192×192px**. `SHEET_COLUMNS = 4` (walk-cycle frames),
`SHEET_ROWS = 4` (facings: row 0 down, 1 up, 2 left, 3 right). `FRAME_PX = 48` is only a fallback — the real frame
height is derived from the texture at runtime (`texture.height / vframes`) and the layer is scaled to a fixed
`display_height`, so 32px or 48px art both render correctly without a second constant.

> **⚠ DRIFT CORRECTED:** an earlier version of this spec said assets are **SVG, recoloured via `modulate`**.
> Ground truth: the **body sheets are full pixel-art PNGs** (the PixelLab pipeline, `ART_PIPELINE.md`), already
> 48px/192×192. `modulate` recolour still applies to the **overlay** layers — but the outfit/head/weapon cosmetics
> currently have **empty `art_path`**, so overlays are invisible placeholders until real art lands.

---

## 2. Cosmetic items as data (`CosmeticItem`)

`scripts/cosmetics/cosmetic_item.gd` — a pure `Resource`, never draws. Fields:

- `id` (StringName, stable, never reused) · `slot` · `display_name` · `art_path` · `default_palette` (Color)
- `acquisition` (DEFAULT / EARNABLE / PURCHASE — metadata only, no logic yet)
- `bucket` (CROWD_SAFE / REVEAL_MOMENT / OUT_OF_MATCH — the monetization safety class; only CROWD_SAFE may appear
  in-match, enforced by `is_crowd_safe()`), `rarity`, `season`.
- **Slots:** `BODY, OUTFIT, HEAD, WEAPON, KILL_ANIM, WIN_ANIM, EMOTE, BANNER, BADGE, TITLE`.
- `CosmeticItem.make(...)` builds placeholder items in code, so the registry is seedable without `.tres` files.

---

## 3. The registry (`CosmeticRegistry`, autoload)

`scripts/cosmetics/cosmetic_registry.gd` — the global lookup (`CosmeticRegistry.get_item(id)`) and the crowd pool.

- **Body roster (15 sheets), id ↔ index kept in sync** with `CharacterVisual.SHEET_TEXTURES`:
  - indices **0–10** = commoner looks (`body_civilian`, `body_com_brown`, … `body_com_water`),
  - indices **11–14** = premium assassin skins (`body_norse_hammer`, `body_crusader`, `body_revolution`,
    `body_egyptian`) — these have attack sheets; the commoners (except `civilian_base`) do not.
  - `COMMONER_BODY_IDS` (0–10) and `ASSASSIN_BODY_IDS` (11–14) split the roster.
- **Crowd pool config:** `active_filler_bodies` (3–5 commoner looks chosen per match), `active_assassin_bodies`
  (the 4 assassin skins), `assassin_crowd_fraction` 0.5 (the 50/50 commoner/assassin crowd mix). `npc_pool()`
  returns commoner bodies + `outfit_none`/`hat_none`/`weapon_none` (no overlay art stacked on filler).
- **Crowd-safe veto:** `_crowd_safe_ids_in_slot()` ensures NPCs can only wear registry-marked safe cosmetics — the
  enforcement point for Pillar #1 against future paid cosmetics.

---

## 4. Loadout (`Loadout`, pure data + wire format)

`scripts/cosmetics/loadout.gd` — `equipped` (slot → cosmetic id) and `palettes` (slot → Color override; a
`NO_RECOLOR` sentinel clears it). `to_payload()` / `from_payload()` give the **compact wire format**
(`{items:{…}, palettes:{…}}`) — **ids only, never textures or node refs**. `Loadout.randomized(pool, rng)` builds a
deterministic NPC loadout from a seeded RNG. This is what crosses the network (see §6).

---

## 5. Inventory & profile (account level)

- **`CosmeticInventory`** (autoload) — `_owned` set (all DEFAULT items granted at start), `_equipped` Loadout, and
  `decoy_body_id` (the NPC-disguise seam, see §6). `equip(slot, id)` **refuses unless `owns(id)`** — the single
  ownership gate the future shop bolts onto. Emits `loadout_changed`.
- **`PlayerProfile`** (`banner` / `badge` / `title`, StringName ids) — account identity, **separate from the
  in-world rig**; surfaces in menus/scoreboard. Display hooks exist; content is placeholder.

---

## 6. Identity hiding (per-viewer) — how a human disappears

- **`set_appearance(index:int)`** stays an int (a shim for the existing int-based crowd netcode); `apply_loadout`
  bridges StringName ids → that index via the registry.
- **NPC-disguise seam:** a player can equip a commoner body publicly while their real assassin id is stashed in
  `decoy_body_id`; `equipped_payload()` ships that decoy id, and the match clones it into the crowd.
- **Per-viewer crowd reskin (online):** on **each machine**, the crowd is rebuilt from copies of the *other*
  players' looks + filler, with **your own look explicitly excluded** — so on every screen the humans blend into
  look-alikes and your own body is never duplicated near you. This runs **locally, after replication** (see
  `MULTIPLAYER_PLAN.md` §8/§9); it does not change what's on the wire.
- **`FaceplateRow`** renders the deliberate reveal plates (red = your target, blue = a 100-exposure opponent) by
  cropping frame 0 of the revealed body sheet. Reveals can return "?" when the subject is disguised.

> **Identity-leak caveat (out of scope for this doc, tracked in `MULTIPLAYER_PLAN.md`):** the per-viewer reskin
> masks looks *visually and locally*, but `controlling_peer_id` is still replicated per player, which is the real
> over-the-wire identity leak. The cosmetic layer can't fix that; the netcode layer must.

---

## 7. Animation hooks & monetization safety (built as plumbing)

- Event hooks exist and are wired: `KILL_ANIM` (on assassination), `WIN_ANIM` (on results), `EMOTE` (on input), and
  a `kill_card` stub (the brief visual the **victim** sees). The animations themselves are stubs — dropping in real
  ones is content-only.
- **In-match cosmetics must be `CROWD_SAFE`** (§2). This is the rule that stops a future paid cosmetic from making a
  player spottable — pay-to-be-seen is a Pillar #1 violation and the registry vetoes it.

**Out of scope (deliberately not built):** shop/store UI, currency, battle pass / unlock logic, real overlay art,
the lobby-sourced NPC cosmetic pool (the hook exists; the implementation is the per-viewer reskin in the match).

---

*Cosmetic & identity spec — rewritten as-built 2026-06-29. Pairs with `ART_PIPELINE.md` (how the sheets are made)
and `MULTIPLAYER_PLAN.md` (how looks replicate and how identity leaks).*
