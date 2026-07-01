# Citadel map tiles (ART_PIPELINE.md §10)

Raw PixelLab output and hand-finished tiles for the CITADEL map (`maps/test_map_03.tscn`),
the "AC Rearmed" medieval town. See ART_PIPELINE.md §10 for the full plan.

- `raw/`      — untouched PixelLab exports (the source of truth; never delete). One subject per file.
- `finished/` — Aseprite hand-finished, palette/saturation-clamped, engine-ready tiles.

RULES (do not skip):
- Every tile is pinned to the LOCKED master palette (assets/style_bible/README.md) — unify saturation.
- Log EVERY generated asset as a row in assets/generation_manifest.csv (id, prompt, seed, credits, date).
- Ground reads QUIET (non-distracting); roofs/props/crowd carry the eye.
