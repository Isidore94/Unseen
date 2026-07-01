#!/usr/bin/env python3
"""UNSEEN — tile / map-object ingest (ART_PIPELINE.md §10, sibling of tools/ingest_sprite.py).

The one post-process every raw PixelLab TILE or PROP goes through before it enters the engine:
trim transparent margins, and (with --snap) clamp every pixel to the LOCKED master palette so hundreds
of citadel assets share one saturation and read as a single place.

Pipeline position:  PixelLab -> Aseprite (hand-finish) -> **this script** -> Godot import -> manifest row.

Usage:
    python tools/ingest_tile.py raw/roof_fills.png --out finished/roof_fills.png --snap
    python tools/ingest_tile.py raw/prop_barrel.png --out finished/prop_barrel.png          # trim only

Standalone + dependency-light (only Pillow). Runs the same on any machine.  pip install pillow
"""
from __future__ import annotations
import argparse
import sys

# Pillow is imported lazily so --help works without it installed.
Image = None


def _require_pillow() -> None:
    global Image
    try:
        from PIL import Image as PILImage
    except ImportError:
        sys.exit("ingest_tile.py needs Pillow:  pip install pillow")
    Image = PILImage


# === LOCKED master palette (assets/style_bible/README.md §2 / ART_PIPELINE.md §10.1) ===============
# Every citadel tile/prop is snapped to these with --snap. Same set the sprite ingest will enforce, so
# the map and the characters share one world palette. Add tones here ONLY by updating the style bible.
_MASTER_PALETTE_HEX = [
    "#cbc4b2", "#c3bca9", "#aaa28d", "#8f8a7e",   # stone / paving
    "#b08a5e", "#a9845a", "#8f6f48", "#6e5436", "#cda978",  # clay roof / wood (+ highlight)
    "#6f6678", "#4a525a",                         # slate / shadow
    "#3a7fa8", "#4f93bc",                         # water
    "#d9a878", "#3a2c22", "#33303a",              # skin / hair / outline (props that need them)
    "#191a1d",                                    # void / deepest shadow
]


def _hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


_PALETTE_RGB = [_hex_to_rgb(h) for h in _MASTER_PALETTE_HEX]


def _nearest_palette(rgb: tuple[int, int, int]) -> tuple[int, int, int]:
    """Closest master-palette colour to `rgb` by squared RGB distance (cheap, good enough for a clamp)."""
    best = _PALETTE_RGB[0]
    best_d = 1 << 30
    for p in _PALETTE_RGB:
        d = (rgb[0] - p[0]) ** 2 + (rgb[1] - p[1]) ** 2 + (rgb[2] - p[2]) ** 2
        if d < best_d:
            best_d, best = d, p
    return best


def _trim(img: "Image.Image") -> "Image.Image":
    """Crop away the fully-transparent border so tiles/props pack tight and pivot cleanly."""
    bbox = img.getbbox()  # None if the image is entirely empty
    return img.crop(bbox) if bbox is not None else img


def _snap_to_palette(img: "Image.Image", alpha_cutoff: int = 8) -> "Image.Image":
    """Replace every opaque pixel with its nearest master-palette colour. Pixels below `alpha_cutoff`
    stay transparent (untouched), so soft edges don't get painted in."""
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    cache: dict[tuple[int, int, int], tuple[int, int, int]] = {}  # memoise the nearest lookup per colour
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < alpha_cutoff:
                continue
            key = (r, g, b)
            snapped = cache.get(key)
            if snapped is None:
                snapped = _nearest_palette(key)
                cache[key] = snapped
            px[x, y] = (snapped[0], snapped[1], snapped[2], a)
    return img


def main() -> None:
    ap = argparse.ArgumentParser(description="Ingest a raw PixelLab tile/prop into an engine-ready PNG.")
    ap.add_argument("input", help="Raw PixelLab PNG (e.g. assets/tiles/citadel/raw/roof_fills.png)")
    ap.add_argument("--out", required=True, help="Output PNG (e.g. assets/tiles/citadel/finished/roof_fills.png)")
    ap.add_argument("--snap", action="store_true", help="Clamp every pixel to the locked master palette")
    ap.add_argument("--no-trim", action="store_true", help="Skip the transparent-border trim")
    args = ap.parse_args()

    _require_pillow()
    img = Image.open(args.input).convert("RGBA")
    if not args.no_trim:
        img = _trim(img)
    if args.snap:
        img = _snap_to_palette(img)
    img.save(args.out)
    print(f"ingest_tile: {args.input} -> {args.out}  ({img.size[0]}x{img.size[1]}, snap={args.snap})")


if __name__ == "__main__":
    main()
