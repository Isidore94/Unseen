# UNSEEN — Art Pipeline: PixelLab as the Asset Backbone

Status: foundational. Lock this before scaling content; some prep starts now.
Decision: PixelLab becomes the canonical source for game art — characters, NPCs,
cosmetics, weapons, items, map tiles, UI — with a mandatory hand-finish pass for
ship quality.

This doc is the architecture underneath everything: the foundational decisions to
lock, what to change in the existing code, what to build new, the workflow going
forward, and the risks to manage. Per-cosmetic generation steps live in
`PHASE_8_MONETIZATION.md` (§7). This doc is the layer beneath that one.

> **Adaptation to UNSEEN's actual code (Phase 11 note).** This doc says "MapBuilder +
> the `DISTRICTS` array" are the layout authority. In *this* repo the equivalent is
> **`scripts/test_map_01.gd`** — its grid `LAYOUT` string (and `layout_override` per
> map, e.g. `maps/rome.tscn`) is the layout authority, and the generator builds the
> walls/floor/nav from it in code. So everywhere this doc says "MapBuilder/DISTRICTS,"
> read "the `test_map_01` grid layout." The SVG→TileMap migration target is: keep that
> grid as the authority, swap the *rendering* (today: `_draw()` + `StaticBody2D` boxes →
> tomorrow: a Godot `TileMap` placed from a PixelLab `TileSet`). See `PHASE_11_TO_MAIN.md`.

---

## 0. The strategic call (read first)

Adopting this means two commitments, stated plainly so you go in with eyes open:

1. **The whole game becomes pixel art, map included.** Right now you have pixel
   characters on an SVG (vector) map — a mixed look. Moving the map to PixelLab
   tiles makes the environment match the characters: one coherent pixel-art
   identity. That's an *art-direction* decision, not just a tooling one.
   > **DECISION — LOCKED (Aaron): YES, full pixel art, map included.** Target the
   > **clean / refined** end of pixel art (muted palette, soft ambient shadows,
   > orderly tiling, mandatory hand-finish) — an "AC-style clean urban" feel, **NOT**
   > chunky/retro/saturated. This is the game's visual identity for good.

2. **PixelLab is the source, not the finish.** "Crutch" is fine — lean on it. But
   what keeps the game from looking generically AI-generated is two things you
   still own: your design/layout authority, and the Aseprite hand-finish pass
   (your brother). Raw PixelLab output is ~80% of a shippable asset. The last 20%
   is hand work, and it's non-negotiable for paid content. Budget for it as a
   permanent step, not an occasional one.

Why this is still the right call for you: commissions don't scale to a
live-service cosmetic cadence on an indie budget, you control iteration speed and
direction, and you own the outputs commercially. The math holds (see §1).

---

## 1. Budget reality

- Baseline: Tier 1, ~$12/mo (toward ~$9 with loyalty). Covers solo 32px work.
- Heavy sprints (new season + map production): expect occasional Tier 2 ($24) or
  pay-per-credit top-ups. Climb only when you actually exhaust monthly credits.
- Max tier ($50/mo) is for constant high-volume production — you likely never
  need it. Don't pre-buy capacity you haven't measured.
- Five-year realistic range: roughly $1,000–1,800 all-in. Cheap against even a
  handful of commissions. Re-confirm tier sizing from real credit burn (Phase 8 §7.8).

---

## 2. Foundational decisions to lock (before generating at scale)

These ripple through every asset. Changing them later means regenerating work.
Status below: **[x] = locked this session**, **[ ] = still to do.**

- [x] **Canonical resolution / grid:** **32×32 base** (matches the current rig — no rework, and
      ~16 anim frames per PixelLab request vs ~4 at 128px, §6 → far cheaper to produce/animate at a
      live-service cadence). The "clean vs blocky" test proved 32px reads **clean** when the craft is
      right (palette + soft shadows + orderly tiling + hand-finish), so clean comes from craft, not
      from going hi-res. *Flippable to 48px ONLY if you want more architectural detail and accept the
      rig rework + higher credit/hand-finish cost per asset — decide before generating at scale.*
- [x] **Tile size + view angle:** **32px square tiles, top-down**, matching the character camera
      angle (the existing top-down view). Tiles + sprites share one perspective.
- [~] **Master palette:** **clean / refined, MUTED urban** (not saturated/retro). Starting set seeded
      in `tools/ingest_sprite.py` + `assets/style_bible/README.md`; **finalize from the first
      hand-finished base civilian + sample tile**, then turn on palette enforcement in the ingest script.
- [ ] **Style bible:** the master reference set — base civilian (front), a sample tile, a sample
      weapon — hand-finished. Generate next (recipe in `assets/style_bible/README.md`). Never regen cold.
- [x] **Character display:** top-down, **pivot at the feet** (the rig's locked centre/feet origin),
      ground shadow on, sprite angle agrees with the tile angle.
- [x] **Direction count:** **4** (start here; go to 8 only if facing-reads feel coarse).
- [x] **Godot import defaults:** **nearest-neighbour filtering set project-wide** this session
      (`project.godot` → `default_texture_filter=0`). Still set per-texture in the editor: mipmaps off,
      compression off (lossless) for pixel assets.

---

## 3. What to change in the existing codebase

- **Map: SVG → Godot `TileMap` + imported `TileSet`.** This is the single biggest
  change. Keep `MapBuilder` and the `DISTRICTS` array as the layout authority —
  they still decide *where* everything goes. Swap only the *rendering* layer:
  instead of building SVG nodes at runtime, place tiles into a `TileMap` from a
  `TileSet` resource generated from PixelLab tilesets. Your data-driven layout
  survives; the art medium underneath it changes.
- **SVG fate:** the map moves to tiles. UI can stay SVG (UI doesn't need to honor
  the pixel grid as strictly), or move to PixelLab UI elements later for full
  coherence — your call, low priority. Don't migrate UI in the same pass as the map.
- **Texture import:** apply the §2 import defaults globally so nothing renders
  blurry or scaled wrong.
- **Pivot convention:** all character art imports with origin at the feet, so
  position, collision, and Y-sort key off the same ground point.

---

## 4. What to build foundationally (new infrastructure)

This is the "bake it into the heart" part: treat generation as documented,
reproducible infrastructure, not one-off prompting.

- [ ] **Asset folder structure + naming convention,** repo-versioned. Source
      (raw PixelLab) and finished assets kept separately, ids matching data arrays.
- [ ] **Style bible as versioned assets** in `assets/style_bible/`.
- [ ] **Generation manifest** — a structured log (CSV or JSON) with one row per
      asset: id, tool/model (PixFlux/BitForge/tileset), reference image used,
      settings/seed, prompt, credit cost, date, hand-finish status. This makes
      generation reproducible, tracks spend, and lets you re-create an asset
      consistently if a model changes under you. This is the backbone that turns a
      "crutch" into a real pipeline.
- [ ] **Ingestion / post-process script (Python + Pillow)** run on every raw
      export: trim/background-removal, palette enforcement to the master palette,
      pivot-at-feet, and pack to the 32×32 sheet convention `MapBuilder` expects.
      One script, every asset type.
- [ ] **Godot `TileSet` resource + terrain/autotile config,** built from PixelLab
      Wang / dual-grid / 3×3 tileset exports so transitions auto-tile.
- [ ] **Asset data layer** (`COSMETICS`, weapons, etc.) mirroring the `DISTRICTS`
      pattern — see Phase 8.
- [ ] **Optional MCP integration** so Claude/Codex drives generation from VS Code.
      Always pin the style bible reference in the call.

---

## 5. The pipeline (every asset goes through this)

```
PixelLab (generate from style bible)
  → Aseprite (hand-finish — brother)
  → Pillow ingest script (palette + pivot + pack)
  → Godot import (pixel defaults)
  → in-engine test (actual zoom, in context)
  → log row in generation manifest
```

One loop, every asset type. Cosmetic-specific steps: `PHASE_8_MONETIZATION.md` §7.

---

## 6. Division of labor

- **PixelLab:** raw art generation only.
- **You:** design, layout, map topology, what gets made, the quality bar.
- **Brother (Aseprite):** hand-finish to ship quality — the 20% that de-AIs it.
- **Claude / Codex:** wire assets into the engine, build the ingest + data +
  TileSet layers, drive MCP generation.

PixelLab does not design your game. It skins decisions you make.

---

## 7. Rollout order (don't rip everything out at once)

Lowest-risk, highest-validation first. Validate each step in-engine before the next.

1. **Lock §2 foundations** (resolution, palette, style bible, camera). No
   production art until these are set — everything inherits from them.
2. **Pilot one map district** as a pixel tileset. Prove the SVG → `TileMap`
   migration end to end on a small scope before committing the whole map. If it
   looks wrong here, you've learned it cheaply.
3. **Migrate characters / NPCs** fully onto the PixelLab + ingest pipeline.
4. **Build the cosmetic pipeline** (Phase 8) on top.
5. **Migrate the full map**, district by district, using the proven pilot path.
6. **UI / banners last** (lowest coupling, least urgent).

---

## 8. Risks & mitigations

- **Single point of failure.** Your whole visual identity depends on one vendor.
  Mitigation: you own the outputs (commercial license) — commit every raw *and*
  finished asset to the repo, and keep the style bible. If PixelLab changes
  pricing, deprecates a model, or shuts down, you still have your full asset
  library and can hand-edit or commission from a stable base. Never let the only
  copy of an asset live on their servers.
- **Style drift over years** as their models update. Mitigation: style bible +
  always-pass-a-reference + the manifest (recorded settings) keep new assets
  matching old ones.
- **"Looks AI" risk.** Mitigated only by the hand-finish pass and your design
  authority. The day you skip Aseprite to save time is the day quality slips.
- **License terms.** Don't train other models on the outputs (PixelLab forbids
  it). Commercial use is allowed on paid plans — re-confirm at ship.
- **Steam disclosure.** Pre-generated AI content must be disclosed in the content
  survey. Keep the manifest as your record of what's AI-assisted.
- **Tier over-buy.** Start Tier 1; scale only on measured credit exhaustion.

---

## 9. Definition of done (foundation in place)

- [ ] §2 foundations locked and written down.
- [ ] Style bible + master palette committed to the repo.
- [ ] Ingest script working: raw PixelLab PNG → engine-ready asset.
- [ ] One district rendering from a PixelLab `TileSet` via `MapBuilder` / `DISTRICTS`.
- [ ] Generation manifest started and being filled per asset.
- [ ] Pixel import defaults set project-wide.
