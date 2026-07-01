# UNSEEN — Art Pipeline: PixelLab as the Asset Backbone

Status: foundational. Lock this before scaling content; some prep starts now.
Decision: PixelLab becomes the canonical source for game art — characters, NPCs,
cosmetics, weapons, items, map tiles, UI — with a mandatory hand-finish pass for
ship quality.

> **⚠ AS-BUILT (audit 2026-06-29).** Status updates vs. the original draft below:
> **(1)** The 48px/192×192 grid is **live, not pending** — all 15 body sheets are real 48px PixelLab pixel art and
> the rig's `FRAME_PX` is already 48 (the "still 32 today" notes below are stale; see §2).
> **(2)** The map is **procedurally drawn**, not SVG and not (yet) a `TileMap`: `scripts/test_map_01.gd`
> `_draw_stylized()` renders the stylized streets/roofs in code from the grid `LAYOUT`. A PixelLab cobblestone/roof
> **tileset pass was prototyped and then reverted** on this branch — so "SVG → TileMap" below is best read as
> "procedural `_draw()` → TileMap", a migration still ahead, optional.
> **→ NOW ACTIVE for the CITADEL map: see the full art plan in §10** (branch `claude/citadel-map-art`). §10 is
> the authoritative, executable spec for this migration; the strategic sections (§0–§8) still hold underneath it.
> **(3)** The ingest script **exists** (`tools/ingest_sprite.py`, plus `tools/validate.sh`).
> **(4)** `assets/sprites/README.txt` is **stale** (claims 128×128/32px and old NPC names) and has been corrected.
> The §2/§4/§9 checkboxes have been updated to match.

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

- [x] **Canonical resolution / grid:** **48×48 base** (Aaron's call — chosen for the richer, cleaner
      urban look: more detail headroom per tile + character — skylights, roof trim, defined faces,
      smoother curves). Accepted trade-offs: more credits + hand-finish per asset (fewer anim frames per
      PixelLab request than 32px). **DONE:** the real 48px sheets shipped, so the rig now runs at `FRAME_PX = 48`
      with sheets **4×4 of 48px = 192×192** (frame height is also derived from the texture at runtime, so the
      const is a fallback). Lock 48px before generating at scale; changing it later = regenerate.
- [x] **Tile size + view angle:** **48px square tiles, top-down**, matching the character camera
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

- **Map: procedural `_draw()` → Godot `TileMap` + imported `TileSet`.** This is the single biggest
  change (and still ahead — today the map renders procedurally in `test_map_01.gd::_draw_stylized()`; a PixelLab
  tileset pass was prototyped then reverted on this branch). Keep the `test_map_01` grid `LAYOUT` as the authority —
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
- [x] **Ingestion / post-process script (Python + Pillow)** — `tools/ingest_sprite.py` exists (with
      `tools/validate.sh`): trim/background-removal, palette handling, pivot-at-feet, and pack to the **48×48**
      sheet convention the rig expects. One script, every asset type.
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

- [x] §2 foundations locked and written down (48px grid, top-down, pivot-at-feet, 4-direction).
- [~] Style bible + master palette: `assets/style_bible/README.md` committed; master palette **seeded but not
      finalized/enforced** in the ingest script.
- [x] Ingest script working: `tools/ingest_sprite.py` (raw PixelLab PNG → engine-ready 48px sheet).
- [ ] One district rendering from a PixelLab `TileSet` — **not done** (map is still procedural `_draw()`; the
      tileset prototype was reverted).
- [ ] Generation manifest started and being filled per asset — **header exists (`assets/generation_manifest.csv`); fill a row per generated tile from §10 on.**
- [x] Pixel import defaults set project-wide (`project.godot` → `default_texture_filter=0`).

---

## 10. CITADEL MAP ART PLAN — "AC Rearmed" medieval town (ACTIVE: branch `claude/citadel-map-art`)

The concrete plan to take `maps/test_map_03.tscn` (CITADEL) from procedural `_draw_stylized()` to real
PixelLab tiles + props. This is the §7 "pilot one map" step, scaled up to the whole citadel. Aaron is
OK generating **hundreds** of tiles — so the governing rule here is **§10.1: everything unifies.**

### 10.1 Art direction (the ONE rule: unify feel + saturation)
- **Reference feel:** Assassin's Creed multiplayer ("Rearmed") — a dense, readable-top-down **medieval
  town**. Patchy dirty ground, town roads, tiled roofs, water + bridges, living shopfronts.
- **Muted + low-saturation, clean (not chunky/retro).** Every tile & prop is pinned to the **locked
  master palette** (`assets/style_bible/README.md`) so hundreds of assets read as one place:
  - stone / paving `#cbc4b2 #c3bca9 #aaa28d #8f8a7e` · clay roof / wood `#b08a5e #a9845a #8f6f48 #6e5436`
    (highlight `#cda978`) · slate / shadow `#6f6678 #4a525a` · water `#3a7fa8 #4f93bc` · void `#191a1d`.
  - **Every PixelLab request pins a style-bible reference + this palette** (the §8 style-drift rule). After
    generation, the ingest script clamps saturation so nothing pops out of the world.
- **Ground reads QUIET / non-distracting.** The crowd, roofs and props carry the eye — never the floor.
  Subtle dirt + road, low contrast, gentle noise. (This is a gameplay need: the floor must not compete
  with reading the crowd — Pillar #1.)

### 10.2 Render layers (bottom → top)
1. **GROUND** TileMap — patchy dirt (base) + town roads + plaza/piazza stone + water. Auto-tiled, subtle.
2. **WATER + BRIDGES** — water terrain with shore edges; wooden **bridge** planks over crossings.
3. **BUILDING BODIES** — wall/facade tiles (stone, plaster, timber-frame), doors, windows, shopfronts, awnings.
4. **DECOR / PROPS** (ground level, **Y-sorted** so the player passes in front of/behind) — barrels, crates,
   market stalls, carts, well, lanterns, banners, potted plants, and each building's **hanging shop sign**.
5. **OVERHEAD ROOFS** — tiled roof textures (terracotta / wood shingle / thatch / slate), varied per
   building, drawn **above** the player.
6. **OVERHANGS + ALLEY CUTAWAY** — roof edges that overhang the street (cover), and the few alley roofs
   that fade **translucent** when the local player is underneath (§10.3).

### 10.3 Signature mechanics (art + code — the meaty part)
- **CONCEALMENT ZONES work like SHADOWS (overhangs + alleys, one shared rule).** A concealment zone is a
  roof drawn ON TOP of the characters and **fully OPAQUE**, so on everyone ELSE's screen it **completely
  hides** whoever stands under it — you vanish into it like stepping into shadow. On **YOUR OWN screen**,
  the instant your player is **actually under it** the roof fades **translucent** so you can see out, and
  it snaps back to opaque the moment you step out. **Per-viewer + LOCAL-player-only:** your machine fades
  only the zone your own player occupies; on an opponent's machine that zone stays opaque (hiding you), so
  the reveal can never expose or track an opponent (identity-safe; §5 in spirit). **Purely visual — no
  exposure/detection effect (Aaron's call).** Implemented in `scripts/roof_overlay.gd` (`add_overhang` /
  `add_alley`, `set_local_player`); works with placeholder colours today, real tiles later.
  - **A. Overhangs (EVERY building).** A roof lip reaching over an adjacent **street** cell — **walkable,
    no collision underneath**. Oriented to face the **map centre**, so even outer-ring buildings hang their
    cover **inward over the streets** (see `tools/render_citadel_sketch.py`). This is the main cover web.
  - **B. Alleys (a FEW buildings).** A passable 1-cell cut-through a building (new layout cell type); its
    roof is the same shadow-cover zone, so you can slip through and only you see out while inside.
- **C. Living shopfronts (every building has a purpose).** Each building gets a **hanging sign + matching
  props** at its door: blacksmith (anvil + sign), general wares (crates), tavern (barrels + mug sign),
  bakery (bread), apothecary (herbs), tailor, market stall, etc. Signs are small PixelLab **map-objects**
  on the decor layer. This is what gives the city life.

### 10.4 Asset manifest (PixelLab — 100s of tiles OK, ALL one palette)
> Tools: `create_topdown_tileset` (auto-tiling ground/water/roof terrains), `create_map_object` /
> `create_1_direction_object` (props & signs). Pin the style-bible reference on every call. Log each in
> `assets/generation_manifest.csv`. Raw → `assets/tiles/citadel/raw/`, hand-finished → `.../finished/`.

- **GROUND tilesets** (top-down Wang, 48px): `dirt_patchy` (quiet base) · `road_cobble` (town streets) ·
  `plaza_stone` (piazza + central avenue) · `grass_moss` (accents) — plus **Wang transitions** between each
  (chain via `lower_base_tile_id`/`upper_base_tile_id` so edges blend).
- **WATER:** `water_still` + shore-edge transitions · `bridge_wood` planks.
- **ROOFS** (overhead terrains, varied but unified saturation): `roof_terracotta` · `roof_shingle_wood` ·
  `roof_thatch` · `roof_slate` — plus ridge / edge / **overhang** trim pieces.
- **WALLS / FACADES:** `wall_stone` · `wall_plaster` · `wall_timberframe` — plus doors, windows, awnings,
  shopfront trims.
- **PROPS / map-objects (decor):** signs (`sign_blacksmith`, `sign_general_wares`, `sign_tavern`,
  `sign_bakery`, `sign_apothecary`, `sign_tailor`, `sign_market`) · barrels · crates · `market_stall` ·
  cart · well · lantern · banner · hay_bale · potted_plant · `fountain` (central landmark).
- **DECALS (break repetition on the quiet ground):** `dirt_patch` · `puddle` · `cracks` · `moss_spread`.

### 10.5 Layout / data changes (the grid stays the authority)
The `test_map_01` grid `LAYOUT` (and the citadel `layout_override` in `maps/test_map_03.tscn`) still decides
*where* everything goes. Extend the legend beyond `#`/`.`/`F`:
- `~` water · `=` bridge · `a` alley-through cell · `^` overhang edge (walkable + roofed) · shopfront markers.
Re-author the citadel `layout_override` to place the few alleys, water, bridges and overhang edges, then
**re-run the flood-fill connectivity check** (`scratchpad/gen_citadel.py`) so the map stays fully traversable.

**STREET-WIDTH RULE (Aaron): every gap between buildings fits ≥ 3 character-widths.** The character
collision box is **71 px** wide → 3 widths = **213 px**. So the citadel cell size is set to 213 px:
`maps/test_map_03.tscn` `play_half` is `2880 × 2240` over the 27×21 grid (`2·2880/27 = 213`). That means a
**1-cell street already holds 3 characters** — so the only layout constraint is *keep every street ≥ 1 cell*
(no touching blocks). `tools/render_citadel_sketch.py::check_street_gaps()` verifies this on every render.

### 10.6 Execution order (pilot first — §7)
1. **Style tile:** generate ONE `dirt_patchy` tile + ONE `roof_terracotta` tile, feel-check vs the palette,
   lock saturation clamp in `tools/ingest_sprite.py`.
2. **Pilot ONE building end-to-end** in a scratch scene: ground under it, walls, overhead roof, one sign —
   prove Y-sort, the overhead layer, the overhang cover cell, and the alley cutaway fade on this one block.
3. Generate the full **ground + water + bridge** tilesets; migrate the citadel floor `_draw_stylized()` → a
   GROUND `TileMap`.
4. Generate **roofs / walls / overhangs**; add the OVERHEAD layer + overhang cover cells.
5. Generate **props / signs**; decorate every building with a purpose.
6. Author the **alleys / water / bridges** into the layout; wire the **cutaway** + connectivity check.
7. **Hand-finish pass** (brother, Aseprite) + log every asset in `assets/generation_manifest.csv`.

### 10.7 Blocked-on
PixelLab API returns **401 (invalid token)** as of this session — no generation possible until the token is
refreshed in the **environment / MCP config** (not the repo; keep the key out of git — §8). Everything above
is the ready-to-execute plan; asset folders + manifest are prepped so step 1 starts the moment auth works.
