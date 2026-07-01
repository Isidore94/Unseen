# Cranking out the CITADEL assets — runbook

The step-by-step loop for generating every citadel asset in `tools/citadel_assets.json` so they land
in the repo, unified. Plan/why: `ART_PIPELINE.md` §10. This is written for **Claude to execute** (the
PixelLab generators are MCP tools only the agent can call — there is no shell script that calls them).

## 0. Preconditions (do these once)
1. **Token works.** Call `get_balance`. If it 401s, the PixelLab token is bad — refresh it in the
   ENVIRONMENT / MCP config (never in the repo) and start a fresh session. Do not proceed on a 401.
2. **Know the spend.** Note the balance. Ground tilesets are ~100s each; `create_tiles_pro` and
   `create_map_object` are ~15–30s and cheap. Full list ≈ 28 calls.

## 1. Lock the STYLE ANCHOR first (this is what unifies everything)
Order matters — every later call references the anchor, so its palette/saturation propagates.
1. Generate `td_dirt_road` (first entry). Poll `get_topdown_tileset(id)` until `completed`; download.
2. Pull ONE clean tile out of it, run it through `tools/ingest_tile.py` (palette snap on), and save it as
   `assets/tiles/citadel/finished/_style_anchor.png`. *(Ideally the brother hand-finishes this one tile —
   it sets the bar for the whole map.)*
3. From here, **every** `create_tiles_pro` / `create_map_object` call passes the anchor as its style
   reference (`style_images` / `background_image`). Every `create_topdown_tileset` call **chains** base
   tile IDs (below) instead — that tool has no style-image input, so chaining is its unifier.

## 2. The generation loop (per asset in the spec)
For each entry in `citadel_assets.json` with `status: "pending"`, in list order:
1. **Substitute placeholders:**
   - `{style_anchor}` → `assets/tiles/citadel/finished/_style_anchor.png`.
   - `{td_dirt_road.upper_base_tile_id}` etc. → the real base-tile UUIDs from the completed tileset
     (returned by `get_topdown_tileset`). This is how ground/water tilesets share exact terrain edges.
2. **Call the `tool`** with `params` (+ `style_ref`/`chain` mapped to the tool's real args:
   `create_tiles_pro` → `style_images`; `create_map_object` → `background_image` as
   `{"type":"path","path":"<anchor>"}`; tilesets → `lower_base_tile_id`/`upper_base_tile_id`).
3. **Poll** the matching getter (`get_topdown_tileset` / `get_tiles_pro` / `get_map_object`) until done.
   These are async: tilesets ~100s, objects/tiles ~15–30s. Fire several, then poll — don't block on one.
4. **Download** the result PNG to the entry's `out` path under `assets/tiles/citadel/raw/`.
5. **Ingest:** `python tools/ingest_tile.py raw/<file>.png --out finished/<file>.png --snap` → trims,
   snaps to the locked palette, saves engine-ready to `finished/`.
6. **Log a manifest row** in `assets/generation_manifest.csv`: `id, tile, <tool>, _style_anchor.png,
   <seed>, "<prompt>", <credits>, <date>, no, <notes>`. (No row = it didn't happen — §8 Steam disclosure.)
7. Flip that entry's `status` to `"done"` (edit the JSON) so a resumed run skips it.

## 3. Batch tips
- **Fire in waves.** Kick off all 4 ground tilesets' *non-chained* ones first, then the chained ones once
  their base IDs exist; meanwhile fire the cheap objects/signs/decals in parallel and poll them as they land.
- **Re-roll cheap.** If a tile reads wrong, delete it (`delete_*`) and regenerate with a tweaked prompt or
  a new `seed` — cheaper than hand-fixing a bad base.
- **Keep saturation honest.** If anything comes back louder than the world, the ingest `--snap` pass pulls
  it back to the master palette; if it's still off, regenerate rather than ship a color that pops.

## 4. Wiring the finished tiles into the map
Once `finished/` has the ground + roof + wall tiles:
- Build a Godot `TileSet` resource from them (48/64px cell to match the map scale) and migrate the citadel
  floor from `test_map_01.gd::_draw_stylized()` to a GROUND `TileMap`. Keep the grid `LAYOUT` as authority.
- Roofs/overhangs/alley-cutaway go on the overhead layer via `scripts/roof_overlay.gd` (already stubbed —
  it takes textures and does the translucency fade). Signs/props are Y-sorted `Sprite2D`s on the decor layer.
- Author the new layout legend (`~` water, `=` bridge, `a` alley, `^` overhang) into
  `maps/test_map_03.tscn`'s `layout_override`, then re-run the flood-fill check (`scratchpad/gen_citadel.py`).

## 5. The 48px caveat (don't trip on it)
`create_topdown_tileset` standard = 16 or 32px only (64 needs pro). The §2 "48px lock" is for CHARACTERS.
Generate tiles at **32px native** and let Godot scale them to the map cell size — ground is meant to read
quiet, so 32px is plenty. Bump a hero piece (fountain, a feature roof) to 64px via `create_tiles_pro` if it
needs the detail. Keep character sprites at 48px regardless.
