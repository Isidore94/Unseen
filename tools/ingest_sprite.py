#!/usr/bin/env python3
"""UNSEEN — sprite ingest (ART_PIPELINE.md §4/§5). The ONE post-process every raw PixelLab export
goes through before it enters the engine: trim transparent margins, enforce the master palette,
set the pivot at the feet, and pack frames into the 32x32 sheet the rig expects.

Pipeline position:  PixelLab → Aseprite (hand-finish) → **this script** → Godot import → manifest row.

Usage:
    python tools/ingest_sprite.py <input_frames_dir_or_png> --out <output_sheet.png> [--cols 4 --rows 4]

STATUS: scaffold. The structure + conventions are locked; the two project-specific pieces — the master
palette (§2) and your exact frame-naming — are marked TODO. Requires Pillow:  pip install pillow
This script is intentionally dependency-light and standalone so it runs the same on any machine.
"""
from __future__ import annotations
import argparse
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("ingest_sprite.py needs Pillow:  pip install pillow")

# === locked conventions (ART_PIPELINE.md §2, scripts/character_visual.gd) =========================
FRAME_PX = 32                 # canonical frame size — DO NOT change without re-cutting every asset
DEFAULT_COLS = 4              # walk-cycle frames per direction
DEFAULT_ROWS = 4              # directions: down / up / left / right (matches the rig's row order)

# TODO(§2): the MASTER PALETTE — lock a limited set of RGBA tuples and enforce it on every asset.
# Until it's locked, palette enforcement is a pass-through (raw colours kept). Fill this from the
# style bible, then flip ENFORCE_PALETTE on.
MASTER_PALETTE: list[tuple[int, int, int]] = [
    # STARTING "clean / refined, muted urban" set (ART_PIPELINE.md §2 decision). Refine these from the
    # first hand-finished base civilian + sample tile, then flip ENFORCE_PALETTE on. See style bible.
    (203, 196, 178), (195, 188, 169), (170, 162, 141), (143, 138, 126),  # stone / paving
    (176, 138, 94),  (169, 132, 90),  (143, 111, 72),  (110, 84, 54),    # clay roof / wood
    (205, 169, 120),                                                     # warm highlight
    (111, 102, 120), (74, 82, 90),                                       # slate / shadow accent
    (58, 127, 168),  (79, 147, 188),                                     # water
    (217, 168, 120), (58, 44, 34), (51, 48, 58),                         # skin / hair / outline
    (25, 26, 29),                                                        # void / deep shadow
]
ENFORCE_PALETTE = False       # set True once MASTER_PALETTE is finalized from the style bible


def trim(img: Image.Image) -> Image.Image:
    """Trim fully-transparent margins so the art sits flush in its frame."""
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def enforce_palette(img: Image.Image) -> Image.Image:
    """Snap every pixel to the nearest MASTER_PALETTE colour (§2 cohesion lever). Pass-through until
    the palette is locked, so the script is usable now and tightens later with zero call-site changes."""
    if not ENFORCE_PALETTE or not MASTER_PALETTE:
        return img
    img = img.convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            nearest = min(MASTER_PALETTE, key=lambda c: (c[0] - r) ** 2 + (c[1] - g) ** 2 + (c[2] - b) ** 2)
            px[x, y] = (nearest[0], nearest[1], nearest[2], a)
    return img


def place_in_frame(img: Image.Image) -> Image.Image:
    """Centre horizontally, pivot at the FEET (§3): the art's bottom sits on the frame's bottom edge,
    so position / collision / Y-sort all key off the same ground point. Returns a FRAME_PX square."""
    frame = Image.new("RGBA", (FRAME_PX, FRAME_PX), (0, 0, 0, 0))
    art = trim(img.convert("RGBA"))
    art.thumbnail((FRAME_PX, FRAME_PX), Image.NEAREST)
    x = (FRAME_PX - art.width) // 2
    y = FRAME_PX - art.height          # feet on the floor
    frame.alpha_composite(art, (max(0, x), max(0, y)))
    return frame


def pack_sheet(frame_paths: list[str], cols: int, rows: int) -> Image.Image:
    """Pack ingested frames into a cols×rows grid of FRAME_PX cells — the sheet the rig slices."""
    sheet = Image.new("RGBA", (cols * FRAME_PX, rows * FRAME_PX), (0, 0, 0, 0))
    for i, path in enumerate(frame_paths):
        if i >= cols * rows:
            print(f"  warning: more frames than {cols}x{rows} cells — extra frames dropped")
            break
        cell = enforce_palette(place_in_frame(Image.open(path)))
        sheet.alpha_composite(cell, ((i % cols) * FRAME_PX, (i // cols) * FRAME_PX))
    return sheet


def gather_frames(path: str) -> list[str]:
    if os.path.isfile(path):
        return [path]
    # TODO: match YOUR PixelLab export naming. Convention (PHASE_8_MONETIZATION.md §7.9):
    #   <dir>_<anim>_<frame>.png  → sort so row-major order = direction-major, frame-minor.
    return sorted(os.path.join(path, f) for f in os.listdir(path) if f.lower().endswith(".png"))


def main() -> None:
    ap = argparse.ArgumentParser(description="Ingest raw PixelLab frames into a rig-ready sheet.")
    ap.add_argument("input", help="a PNG, or a folder of frame PNGs")
    ap.add_argument("--out", required=True, help="output sheet path")
    ap.add_argument("--cols", type=int, default=DEFAULT_COLS)
    ap.add_argument("--rows", type=int, default=DEFAULT_ROWS)
    args = ap.parse_args()

    frames = gather_frames(args.input)
    if not frames:
        sys.exit(f"no PNG frames found at {args.input}")
    sheet = pack_sheet(frames, args.cols, args.rows)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    sheet.save(args.out)
    print(f"  wrote {args.out}  ({args.cols}x{args.rows} @ {FRAME_PX}px, {len(frames)} frames)")
    print("  reminder: add a row to assets/generation_manifest.csv for this asset (ART_PIPELINE.md §4).")


if __name__ == "__main__":
    main()
