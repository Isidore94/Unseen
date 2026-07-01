#!/usr/bin/env python3
"""UNSEEN — CITADEL style board (ART_PIPELINE.md §10.1). Renders the INTENDED look — the locked palette
plus mock ground/roof/wall/water tiles drawn as pixel grids at the target saturation — so the art
direction can be approved BEFORE spending a single PixelLab credit. These are hand-drawn approximations
of what PixelLab will generate against the same palette; they set the bar, they are not final tiles.

    python tools/render_citadel_styleboard.py  ->  assets/tiles/citadel/citadel_styleboard.svg
"""
from __future__ import annotations
import random

PX = 8               # mock "pixel" size
TILE = 96            # tile = 12x12 mock pixels
N = TILE // PX
MARGIN = 24

INK = "#33303a"
PAPER = "#e9e4d6"

# --- locked master palette (assets/style_bible/README.md) ---
PALETTE = {
    "stone / paving": ["#cbc4b2", "#c3bca9", "#aaa28d", "#8f8a7e"],
    "clay roof / wood": ["#b08a5e", "#a9845a", "#8f6f48", "#6e5436", "#cda978"],
    "slate / shadow": ["#6f6678", "#4a525a"],
    "water": ["#3a7fa8", "#4f93bc"],
    "skin / hair / outline": ["#d9a878", "#3a2c22", "#33303a"],
    "void": ["#191a1d"],
}


def hx(h): return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16))
def rgb(t): return f"#{t[0]:02x}{t[1]:02x}{t[2]:02x}"
def mix(a, b, t):
    ca, cb = hx(a), hx(b)
    return rgb(tuple(int(ca[i] + (cb[i] - ca[i]) * t) for i in range(3)))
def shade(h, f):
    c = hx(h); return rgb(tuple(max(0, min(255, int(c[i] * f))) for i in range(3)))


def rect(x, y, w, h, fill, stroke=None, sw=1.0, rx=0.0, op=1.0):
    s = f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" fill="{fill}"'
    if rx: s += f' rx="{rx:.1f}"'
    if stroke: s += f' stroke="{stroke}" stroke-width="{sw:.1f}"'
    if op != 1.0: s += f' opacity="{op:.2f}"'
    return s + "/>"


def text(x, y, t, size=13, fill=INK, anchor="start", weight="normal"):
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-family="Verdana,Segoe UI,sans-serif" '
            f'font-size="{size}" fill="{fill}" text-anchor="{anchor}" font-weight="{weight}">{t}</text>')


def tile(x, y, name, fn) -> list[str]:
    """Draw a mock pixel tile at (x,y): fn(ix,iy,rng)->hex per mock-pixel. Seeded by name = reproducible."""
    rng = random.Random(hash(name) & 0xffffffff)
    out = []
    for iy in range(N):
        for ix in range(N):
            out.append(rect(x + ix * PX, y + iy * PX, PX, PX, fn(ix, iy, rng)))
    out.append(rect(x, y, TILE, TILE, "none", stroke=INK, sw=1.2))
    out.append(text(x + TILE / 2, y + TILE + 15, name, size=11.5, anchor="middle"))
    return out


# === material pixel rules (muted, low-saturation; ground quiet, roofs carry variety) ===============
def dirt(ix, iy, r):
    base = ["#ab9c7e", "#a59677", "#b0a184"]
    c = r.choice(base)
    if r.random() < 0.16: c = r.choice(["#8f8a7e", "#948a72"])   # scuffed darker patch
    elif r.random() < 0.10: c = "#c3bca9"                         # dry lighter fleck
    return c

def cobble(ix, iy, r):
    # 2x2 stones with mortar lines between them
    if ix % 3 == 2 or iy % 3 == 2: return "#8f8a7e"              # mortar
    return r.choice(["#aaa28d", "#b3ab95", "#a29a86"])

def flagstone(ix, iy, r):
    if ix % 4 == 3 or iy % 4 == 3: return "#aaa28d"             # grout
    return r.choice(["#c3bca9", "#cbc4b2", "#bcb5a2"])

def water(ix, iy, r):
    c = "#3a7fa8"
    if iy % 4 == (ix // 2) % 4: c = "#4f93bc"                   # ripple highlight rows
    if r.random() < 0.08: c = "#5ea0c7"
    return c

def roof_terracotta(ix, iy, r):
    row = "#b08a5e" if iy % 2 == 0 else "#a9845a"
    if ix % 3 == 2: row = shade(row, 0.82)                     # tile seam shadow
    if iy % 2 == 0 and ix % 3 == 0: row = "#cda978"           # lit tile lip
    return row

def roof_shingle(ix, iy, r):
    off = (iy // 1) % 2
    row = "#a9845a" if iy % 2 == 0 else "#8f6f48"
    if (ix + off) % 2 == 0: row = shade(row, 0.9)
    if iy % 2 == 1 and ix % 2 == off: row = "#6e5436"          # shingle bottom edge
    return row

def roof_thatch(ix, iy, r):
    base = ["#b0a06b", "#a89860", "#9c8c58"]                    # straw (muted ochre accent)
    c = r.choice(base)
    if ix % 3 == r.randint(0, 2): c = shade(c, 0.85)           # vertical straw streaks
    return c

def roof_slate(ix, iy, r):
    off = (iy // 2) % 2
    row = "#6f6678" if iy % 2 == 0 else "#5f5768"
    if (ix + off) % 3 == 0: row = "#4a525a"                    # slate gaps
    if iy % 2 == 0 and ix % 3 == 1: row = "#8a8494"           # lit edge
    return row

def wall_stone(ix, iy, r):
    off = (iy // 2) % 2
    if iy % 2 == 1 or (ix + off * 2) % 4 == 3: return "#8f8a7e"  # mortar courses
    return r.choice(["#aaa28d", "#b3ab95"])

def wall_plaster(ix, iy, r):
    c = r.choice(["#c6bfad", "#cbc4b2", "#c3bca9"])
    if r.random() < 0.05: c = "#aaa28d"                        # hairline crack / stain
    return c

def wall_timber(ix, iy, r):
    # cream plaster panels framed by dark timber beams (Tudor)
    if ix in (0, N - 1) or iy in (0, N - 1) or ix == N // 2 or iy == N // 2:
        return "#6e5436"
    return r.choice(["#cbc4b2", "#c6bfad"])


TILE_SECTIONS = [
    ("GROUND — reads QUIET (non-distracting)", [("dirt (base)", dirt), ("cobble road", cobble), ("plaza flagstone", flagstone)]),
    ("WATER", [("canal water", water)]),
    ("ROOFS — carry the variety (one per building)", [("terracotta", roof_terracotta), ("wood shingle", roof_shingle), ("thatch", roof_thatch), ("slate", roof_slate)]),
    ("WALLS / FACADES", [("stone", wall_stone), ("plaster", wall_plaster), ("timber-frame", wall_timber)]),
]


def build() -> str:
    W = 1060
    p: list[str] = []
    # measure height as we place
    y = MARGIN + 30
    body: list[str] = []

    # palette
    body.append(text(MARGIN, y - 8, "MASTER PALETTE (locked — every tile is pinned to these)", size=15, weight="bold"))
    sw = 40
    gx = MARGIN
    for group, cols in PALETTE.items():
        gy = y + 6
        for i, c in enumerate(cols):
            body.append(rect(gx + i * (sw + 2), gy, sw, sw, c, stroke=INK, sw=1))
            body.append(text(gx + i * (sw + 2) + sw / 2, gy + sw + 11, c, size=8.5, anchor="middle", fill="#5c554a"))
        body.append(text(gx + (len(cols) * (sw + 2)) / 2 - 1, gy + sw + 24, group, size=10.5, anchor="middle", weight="bold"))
        gx += len(cols) * (sw + 2) + 22
    y += 6 + sw + 40

    # tile sections
    body.append(text(MARGIN, y + 6, "MOCK TILES @ target saturation (approximations — PixelLab generates the real ones vs the same palette)", size=15, weight="bold"))
    y += 24
    for title, tiles in TILE_SECTIONS:
        body.append(text(MARGIN, y + 14, title, size=12, weight="bold", fill="#5c554a"))
        ty = y + 24
        tx = MARGIN
        for name, fn in tiles:
            body.extend(tile(tx, ty, name, fn))
            tx += TILE + 26
        y = ty + TILE + 28

    # value hierarchy panel
    body.append(text(MARGIN, y + 8, "VALUE PLAN — ground stays darkest/quietest so the CROWD reads against it (Pillar #1)", size=13, weight="bold"))
    y += 18
    ladder = [("ground", "#a59677"), ("wall / prop", "#b3ab95"), ("character (crowd)", "#8f6f48"), ("roof (varied)", "#b08a5e"), ("sign / accent", "#cda978")]
    lx = MARGIN
    for label, c in ladder:
        body.append(rect(lx, y, 150, 30, c, stroke=INK, sw=1))
        body.append(text(lx + 75, y + 20, label, size=11, anchor="middle", fill=INK if c != "#8f6f48" else "#f0ead9"))
        lx += 158
    y += 52

    # assembled vignette — one block on the street with roof, sign, overhang shadow, 3 characters
    body.append(text(MARGIN, y + 8, "HOW IT COMPOSES — a shopfront on a 3-character street (overhang shadow + hanging sign)", size=13, weight="bold"))
    y += 16
    vx, vy, vw, vh = MARGIN, y, 520, 150
    body.append(rect(vx, vy, vw, vh, "#ab9c7e", stroke=INK, sw=1.2))          # quiet ground
    for i in range(0, vw, PX):                                                 # faint dirt speckle
        if (i // PX) % 5 == 0:
            body.append(rect(vx + i, vy + (i % 40), PX, PX, "#948a72", op=0.5))
    # building (wall + roof) on the upper part
    bwx, bwy, bww, bwh = vx + 30, vy + 12, 300, 70
    body.append(rect(bwx, bwy + bwh - 26, bww, 26, "#aaa28d", stroke="#8f8a7e", sw=1))   # wall strip
    for k in range(0, bww, 26):
        body.append(rect(bwx + k, bwy + bwh - 26, 1, 26, "#8f8a7e"))
    body.append(rect(bwx, bwy, bww, bwh - 22, "#b08a5e", stroke=shade("#b08a5e", 0.7), sw=1.5))  # roof
    for k in range(0, bwh - 22, 10):
        body.append(rect(bwx + 2, bwy + k, bww - 4, 1, shade("#b08a5e", 0.86)))
    # overhang shadow reaching down over the street (visual cover)
    body.append(rect(bwx + 40, bwy + bwh, 120, 18, "#000000", op=0.20))
    body.append(rect(bwx + 40, bwy + bwh - 2, 120, 8, shade("#b08a5e", 0.82)))
    # hanging sign
    body.append(rect(bwx + bww - 60, bwy + bwh, 2, 12, "#6e5436"))
    body.append(rect(bwx + bww - 78, bwy + bwh + 12, 36, 16, "#cbb98d", stroke="#6e5436", sw=1.2, rx=2))
    body.append(text(bwx + bww - 60, bwy + bwh + 24, "shop", size=9, anchor="middle"))
    # 3 characters on the street (shows the >=3-char width + crowd value against quiet ground)
    for i in range(3):
        cxp = vx + 120 + i * 60
        body.append(rect(cxp, vy + vh - 40, 20, 30, "#8f6f48", stroke=INK, sw=1, rx=4))  # body (mid value)
        body.append(rect(cxp + 4, vy + vh - 46, 12, 10, "#d9a878", stroke=INK, sw=0.8, rx=3))  # head
    body.append(text(vx + 180, vy + vh - 46, "crowd reads against the quiet ground", size=10, fill="#5c554a"))
    y = vy + vh + 26

    body.append(text(MARGIN, y, "Unifiers: one hand-finished style-anchor tile + reference-on-every-call + ingest palette-snap. Hand-finish (Aseprite) is the last 20% that de-AIs it.",
                     size=11, fill="#5c554a"))
    y += 22

    H = y + MARGIN
    head = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
            rect(0, 0, W, H, PAPER),
            text(MARGIN, MARGIN + 12, "CITADEL — style board", size=22, weight="bold"),
            text(MARGIN, MARGIN + 30, "the intended look, to approve before generating · muted / low-saturation / clean 'AC clean-urban' (not chunky-retro)", size=11.5, fill="#5c554a")]
    return "\n".join(head + body + ["</svg>"])


def main() -> None:
    out = "assets/tiles/citadel/citadel_styleboard.svg"
    with open(out, "w") as f:
        f.write(build())
    print("wrote", out)


if __name__ == "__main__":
    main()
