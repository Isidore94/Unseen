# UNSEEN — PHASE 11 → MAIN  (integration plan, step 5 of 5)

> **Branch:** `phase-11-art-pipeline` (stacked on `phase-10-maps`)
> **Integration order:** 7 → 8 → 9 → 10 → **11 → main (this file)**.
> Do **NOT** start until Phase 10 is on `main` and verified (see §1).

---

## 0. What Phase 11 is

**Phase 11 is the ART PIPELINE foundation** — it hardlines **PixelLab** as the canonical art source
for sprites *and* maps (`ART_PIPELINE.md`). This phase locks the *foundations + scaffolding only* — per
the doc's own rollout (§7), the big SVG→TileMap map migration is piloted and done **later**, district by
district, NOT in this integration.

What's on this branch beyond the Phase 10 tip:
- **`ART_PIPELINE.md`** — the canonical spec (with an adaptation note: the doc's "MapBuilder/DISTRICTS"
  ≙ this repo's `test_map_01.gd` grid layout).
- **Project-wide pixel import default** — `project.godot` sets `default_texture_filter=0` (Nearest) so
  2D art renders crisp, not blurry (§2/§3).
- **Pipeline infrastructure (§4):** `assets/source/` (raw PixelLab) + `assets/finished/` split,
  `assets/generation_manifest.csv` (the reproducibility + spend + AI-disclosure log), and
  `tools/ingest_sprite.py` (the Pillow ingest scaffold: trim → palette → pivot-at-feet → pack to the
  32×32 / 4×4 sheet). The master palette + exact frame-naming are marked TODO in the script.
- (The style bible `assets/style_bible/` arrives from Phase 8 via the re-sync below.)

**You are the VS Code Claude** with Godot 4.7 + (later) PixelLab. Aaron is a brand-new coder
(`CLAUDE.md`): explain plainly, give editor steps, wait for confirmation.

---

## 1. Prerequisite — Phase 10 on `main`

```bash
git fetch origin && git checkout main && git pull
git merge-base --is-ancestor "$(git rev-parse origin/phase-10-maps)" main 2>/dev/null && echo "OK: Phase 10 on main" || echo "STOP: do Phase 10 first"
```

## 1.5 Re-sync + forward-propagation (do not skip)
This branch is stacked on 10→9→8→7 and holds frozen copies of all of them. Pull in every earlier fix:
```bash
git checkout phase-11-art-pipeline
git merge main          # absorbs Phase 7/8/9/10 fixes (incl. the Phase 8 style_bible + Phase 9 crowd knobs)
tools/validate.sh
git push origin phase-11-art-pipeline
```
Keep the fix on conflict; re-check Phase 11's own edits for the same bug; log it. Likely conflict file:
`project.godot` (Phase 8 added an autoload + input action; Phase 11 adds a render setting — keep both).

---

## 2. Golden rules
1. **`tools/validate.sh` passes before you advance main.**
2. **No gameplay regression.** This phase is docs + scaffolding + one render setting; the game must play
   exactly as Phase 10 did. (The map is still the code-built renderer — TileMap migration is later.)
3. **Keep `main` releasable** — verify on a scratch branch, advance only when green.

---

## 3. Integrate + gates
```bash
git checkout main && git pull
git checkout -b integrate/phase-11
git merge origin/phase-11-art-pipeline
tools/validate.sh                 # COMPILE GATE → exit 0
```
Runtime gate (light): the project opens with no errors; a match plays as before; pixel art (characters,
Rome tiles) renders **crisp, not blurry** (the Nearest filter took effect). `python tools/ingest_sprite.py
--help` runs (after `pip install pillow`).

## 4. Advance `main` + tag
```bash
git checkout main && git merge integrate/phase-11 && tools/validate.sh
git tag phase-11-art-pipeline-complete && git push origin main --tags
```

---

## 5. AFTER integration — the real art work (the doc's §7 rollout, in order)
This is where PixelLab actually gets used. Don't rip everything out at once:
1. **Lock §2 foundations** — resolution (32px ✓), tile size + view angle, **master palette** (fill it in
   `ingest_sprite.py` + the style bible), camera/pivot, direction count. Write them down.
2. **Pilot ONE thing** — migrate a single map's floor to a PixelLab `TileSet` + Godot `TileMap`, keeping
   `test_map_01`'s grid as the layout authority (swap only the render layer). Prove it on small scope.
3. **Migrate characters/NPCs** onto PixelLab + `ingest_sprite.py` (start with the base civilian, §3 of
   `assets/style_bible/README.md`).
4. **Cosmetic pipeline** (Phase 8 §7) on top.
5. **Full map**, then **UI** last.
Every asset: generate from the style bible → Aseprite hand-finish → ingest → import → **log a manifest row**.

---

## 6. Rollback
Nothing touches `main` until §4. Abort: `git checkout main`; `git branch -D integrate/phase-11`. Report
the failing gate + output.
