#!/usr/bin/env python3
"""UNSEEN — CITADEL map design sketch (ART_PIPELINE.md §10). Renders a top-down MOCKUP of the proposed
citadel layout as an SVG, in the locked muted palette, so the design reads before any PixelLab art
exists. NOT the real map data — a design reference to react to. Regenerate after tweaking the layout.

    python tools/render_citadel_sketch.py  ->  assets/tiles/citadel/citadel_map_sketch.svg
"""
from __future__ import annotations

CELL = 40
COLS, ROWS = 27, 21
MARGIN = 22
TITLE_H = 66
LEGEND_H = 196
MAP_W, MAP_H = COLS * CELL, ROWS * CELL
CANVAS_W = MAP_W + 2 * MARGIN
CANVAS_H = MARGIN + TITLE_H + MAP_H + 12 + LEGEND_H + MARGIN
MAP_X0 = MARGIN
MAP_Y0 = MARGIN + TITLE_H

# --- locked palette (assets/style_bible/README.md) ---
GROUND = "#b3a487"      # quiet muted dirt/street — reads non-distracting
PIAZZA = "#c6bfad"      # flagstone plaza
WATER = "#3a7fa8"; RIPPLE = "#4f93bc"
BRIDGE = "#8f6f48"; PLANK = "#6e5436"
OUTLINE = "#4a453d"
SIGN_POST = "#6e5436"; SIGN_BOARD = "#cbb98d"; INK = "#33303a"
ROOFS = ["#a9613f", "#b08a5e", "#8a857a", "#6f6678", "#8f6f48"]  # terracotta, tan, weathered, slate, ochre


def shade(hex_color: str, factor: float) -> str:
    r = int(hex_color[1:3], 16); g = int(hex_color[3:5], 16); b = int(hex_color[5:7], 16)
    r = max(0, min(255, int(r * factor))); g = max(0, min(255, int(g * factor))); b = max(0, min(255, int(b * factor)))
    return f"#{r:02x}{g:02x}{b:02x}"


def gx(c: float) -> float: return MAP_X0 + c * CELL
def gy(r: float) -> float: return MAP_Y0 + r * CELL


# Each building: c,r,w,h (cells); roof index; optional shop label; optional alley 'h'/'v'; overhang edges.
BUILDINGS = [
    dict(c=1, r=2, w=3, h=2, roof=1, overhang=["S"]),
    dict(c=5, r=2, w=2, h=3, roof=0),
    dict(c=8, r=2, w=2, h=2, roof=2),
    dict(c=1, r=6, w=2, h=3, roof=4),
    dict(c=4, r=6, w=3, h=2, roof=2, overhang=["S"]),
    dict(c=8, r=5, w=2, h=4, roof=0, alley="v"),
    dict(c=1, r=10, w=2, h=3, roof=3),
    dict(c=4, r=10, w=2, h=4, roof=1, alley="h"),
    dict(c=8, r=11, w=2, h=3, roof=4),
    dict(c=1, r=15, w=3, h=3, roof=0, shop="Blacksmith"),
    dict(c=5, r=15, w=3, h=3, roof=2, shop="Tailor"),
    dict(c=11, r=2, w=3, h=2, roof=3, overhang=["S"]),
    dict(c=15, r=2, w=3, h=3, roof=1, shop="Apothecary"),
    dict(c=10, r=15, w=3, h=3, roof=4, alley="h"),
    dict(c=14, r=15, w=5, h=3, roof=0, shop="General Wares"),
    dict(c=17, r=6, w=2, h=2, roof=2),
    dict(c=17, r=10, w=2, h=2, roof=1, overhang=["E"]),
    dict(c=22, r=2, w=3, h=3, roof=1, shop="Bakery"),
    dict(c=22, r=6, w=3, h=3, roof=3),
    dict(c=21, r=10, w=4, h=3, roof=0, alley="h"),
    dict(c=22, r=14, w=3, h=3, roof=2, shop="Tavern"),
]

# Central piazza (open) + fountain, and the canal + its bridges.
PIAZZA_RECT = (11, 8, 6, 5)            # c,r,w,h
FOUNTAIN = (13.5, 10.0)                # cell centre
CANAL_COL = 20; CANAL_R0, CANAL_R1 = 2, 14
BRIDGES = [5, 11]                       # rows where a bridge crosses the canal


def svg_rect(x, y, w, h, fill, stroke=None, sw=1.0, rx=0.0, opacity=1.0):
    s = f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" fill="{fill}"'
    if rx: s += f' rx="{rx:.1f}"'
    if stroke: s += f' stroke="{stroke}" stroke-width="{sw:.1f}"'
    if opacity != 1.0: s += f' opacity="{opacity:.2f}"'
    return s + "/>"


def svg_text(x, y, txt, size=13, fill=INK, anchor="start", weight="normal"):
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-family="Verdana,Segoe UI,sans-serif" '
            f'font-size="{size}" fill="{fill}" text-anchor="{anchor}" font-weight="{weight}">{txt}</text>')


def draw_building(b) -> list[str]:
    out = []
    x, y = gx(b["c"]), gy(b["r"]); w, h = b["w"] * CELL, b["h"] * CELL
    roof = ROOFS[b["roof"] % len(ROOFS)]
    out.append(svg_rect(x + 4, y + 5, w, h, "rgba(0,0,0,0.13)", rx=4))          # soft drop shadow
    out.append(svg_rect(x, y, w, h, roof, stroke=shade(roof, 0.7), sw=2.0, rx=4))  # roof block
    # ridge lines so it reads as a TILED roof
    ridge = shade(roof, 0.86)
    step = CELL * 0.5
    yy = y + step
    while yy < y + h - 2:
        out.append(f'<line x1="{x+3:.1f}" y1="{yy:.1f}" x2="{x+w-3:.1f}" y2="{yy:.1f}" stroke="{ridge}" stroke-width="1"/>')
        yy += step
    # lit top edge
    out.append(f'<line x1="{x+3:.1f}" y1="{y+2:.1f}" x2="{x+w-3:.1f}" y2="{y+2:.1f}" stroke="{shade(roof,1.18)}" stroke-width="1.5"/>')

    # OVERHANG bands (visual cover) — a translucent roof lip reaching 1 cell into the street.
    for edge in b.get("overhang", []):
        if edge == "S":
            ox, oy, ow, oh = x, y + h, w, CELL * 0.6
        elif edge == "E":
            ox, oy, ow, oh = x + w, y, CELL * 0.6, h
        elif edge == "N":
            ox, oy, ow, oh = x, y - CELL * 0.6, w, CELL * 0.6
        else:  # W
            ox, oy, ow, oh = x - CELL * 0.6, y, CELL * 0.6, h
        out.append(svg_rect(ox, oy, ow, oh, roof, opacity=0.5, rx=3))
        out.append(svg_rect(ox, oy, ow, oh, "none", stroke=shade(roof, 0.7), sw=1.0, rx=3))

    # ALLEY cut-through — a walkable slot; drawn as ground with a translucent 'cutaway' overlay.
    if b.get("alley") == "v":
        ax = x + (w - CELL) / 2
        out.append(svg_rect(ax, y - 1, CELL, h + 2, GROUND, rx=2))
        out.append(svg_rect(ax, y - 1, CELL, h + 2, "#ffffff", opacity=0.14))
        out.append(f'<rect x="{ax:.1f}" y="{y-1:.1f}" width="{CELL}" height="{h+2:.1f}" fill="none" stroke="{shade(roof,0.7)}" stroke-width="1" stroke-dasharray="4 3"/>')
    elif b.get("alley") == "h":
        ay = y + (h - CELL) / 2
        out.append(svg_rect(x - 1, ay, w + 2, CELL, GROUND, rx=2))
        out.append(svg_rect(x - 1, ay, w + 2, CELL, "#ffffff", opacity=0.14))
        out.append(f'<rect x="{x-1:.1f}" y="{ay:.1f}" width="{w+2:.1f}" height="{CELL}" fill="none" stroke="{shade(roof,0.7)}" stroke-width="1" stroke-dasharray="4 3"/>')
    return out


def draw_sign(b) -> list[str]:
    # A little hanging shop sign at the building's front (south edge), plus its label.
    if "shop" not in b:
        return []
    x, y = gx(b["c"]), gy(b["r"]); w, h = b["w"] * CELL, b["h"] * CELL
    sx = x + w / 2; sy = y + h + 6
    out = [f'<line x1="{sx:.1f}" y1="{sy:.1f}" x2="{sx:.1f}" y2="{sy+8:.1f}" stroke="{SIGN_POST}" stroke-width="2"/>']
    out.append(svg_rect(sx - 15, sy + 8, 30, 14, SIGN_BOARD, stroke=SIGN_POST, sw=1.5, rx=2))
    out.append(svg_text(sx, sy + 36, b["shop"], size=12, anchor="middle", weight="bold"))
    return out


def build_svg() -> str:
    p: list[str] = []
    p.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS_W}" height="{CANVAS_H}" viewBox="0 0 {CANVAS_W} {CANVAS_H}">')
    p.append(svg_rect(0, 0, CANVAS_W, CANVAS_H, "#e9e4d6"))                       # paper
    # title
    p.append(svg_text(MARGIN, MARGIN + 26, "CITADEL — proposed map sketch", size=24, weight="bold"))
    p.append(svg_text(MARGIN, MARGIN + 48, "AC-Rearmed medieval town · top-down · muted palette · quiet ground · tiled roofs · canal + bridges · a few roofed alleys that fade for you · living shopfronts",
                      size=12.5, fill="#5c554a"))
    # map ground
    p.append(svg_rect(MAP_X0, MAP_Y0, MAP_W, MAP_H, GROUND, stroke=OUTLINE, sw=2.0))
    # faint street grid (subtle, non-distracting)
    for c in range(1, COLS):
        p.append(f'<line x1="{gx(c):.1f}" y1="{MAP_Y0}" x2="{gx(c):.1f}" y2="{MAP_Y0+MAP_H}" stroke="#a89a7e" stroke-width="0.5" opacity="0.35"/>')
    for r in range(1, ROWS):
        p.append(f'<line x1="{MAP_X0}" y1="{gy(r):.1f}" x2="{MAP_X0+MAP_W}" y2="{gy(r):.1f}" stroke="#a89a7e" stroke-width="0.5" opacity="0.35"/>')
    # outer wall ring
    p.append(svg_rect(MAP_X0, MAP_Y0, MAP_W, CELL, shade(GROUND, 0.7)))
    p.append(svg_rect(MAP_X0, MAP_Y0 + MAP_H - CELL, MAP_W, CELL, shade(GROUND, 0.7)))
    p.append(svg_rect(MAP_X0, MAP_Y0, CELL, MAP_H, shade(GROUND, 0.7)))
    p.append(svg_rect(MAP_X0 + MAP_W - CELL, MAP_Y0, CELL, MAP_H, shade(GROUND, 0.7)))

    # piazza flagstone
    px, py, pw, ph = PIAZZA_RECT
    p.append(svg_rect(gx(px), gy(py), pw * CELL, ph * CELL, PIAZZA, rx=10))
    p.append(svg_text(gx(px + pw / 2), gy(py) + 16, "PIAZZA", size=12, fill="#7a7263", anchor="middle", weight="bold"))

    # canal water + ripples
    for rr in range(CANAL_R0, CANAL_R1):
        p.append(svg_rect(gx(CANAL_COL), gy(rr), CELL, CELL, WATER))
        p.append(f'<path d="M{gx(CANAL_COL)+6:.1f},{gy(rr)+14:.1f} q9,-6 18,0 q9,6 18,0" fill="none" stroke="{RIPPLE}" stroke-width="1.5" opacity="0.7"/>')
        p.append(f'<path d="M{gx(CANAL_COL)+6:.1f},{gy(rr)+26:.1f} q9,-6 18,0 q9,6 18,0" fill="none" stroke="{RIPPLE}" stroke-width="1.5" opacity="0.5"/>')
    # bridges
    for br in BRIDGES:
        bx, by = gx(CANAL_COL) - 4, gy(br)
        p.append(svg_rect(bx, by, CELL + 8, CELL, BRIDGE, stroke=PLANK, sw=1.5, rx=2))
        for k in range(1, 5):
            p.append(f'<line x1="{bx:.1f}" y1="{by+k*CELL/5:.1f}" x2="{bx+CELL+8:.1f}" y2="{by+k*CELL/5:.1f}" stroke="{PLANK}" stroke-width="1"/>')

    # buildings, then signs on top
    for b in BUILDINGS:
        p.extend(draw_building(b))
    for b in BUILDINGS:
        p.extend(draw_sign(b))

    # fountain (landmark)
    fx, fy = gx(FOUNTAIN[0]), gy(FOUNTAIN[1])
    p.append(f'<circle cx="{fx:.1f}" cy="{fy:.1f}" r="26" fill="#b9b2a1" stroke="{OUTLINE}" stroke-width="2"/>')
    p.append(f'<circle cx="{fx:.1f}" cy="{fy:.1f}" r="15" fill="{WATER}" stroke="{RIPPLE}" stroke-width="1.5"/>')
    p.append(f'<circle cx="{fx:.1f}" cy="{fy:.1f}" r="4" fill="{RIPPLE}"/>')
    p.append(svg_text(fx, fy + 44, "fountain", size=11, fill="#7a7263", anchor="middle"))

    # a couple of callouts so the two signature mechanics are obvious
    p.append(callout(gx(8.5) + 4, gy(7), "alley — roof fades\nfor you inside"))
    p.append(callout(gx(19.4), gy(10.5), "overhang —\nvisual cover"))

    # legend
    p.extend(legend())
    p.append("</svg>")
    return "\n".join(p)


def callout(x, y, txt) -> str:
    lines = txt.split("\n")
    tspans = "".join(f'<tspan x="{x:.1f}" dy="{0 if i==0 else 12}">{ln}</tspan>' for i, ln in enumerate(lines))
    return (f'<g><rect x="{x-3:.1f}" y="{y-12:.1f}" width="112" height="{12*len(lines)+8}" fill="#ffffff" opacity="0.82" rx="3"/>'
            f'<text font-family="Verdana,sans-serif" font-size="10.5" fill="{INK}" y="{y:.1f}">{tspans}</text></g>')


def legend() -> list[str]:
    y0 = MAP_Y0 + MAP_H + 22
    out = [svg_text(MARGIN, y0 - 4, "LEGEND", size=13, weight="bold")]
    items = [
        (ROOFS[0], "Building roof (tiled; varied per block)"),
        (GROUND, "Street / ground (quiet, non-distracting)"),
        (PIAZZA, "Piazza flagstone"),
        (WATER, "Canal water"),
        (BRIDGE, "Wooden bridge (walkable)"),
        ("alley", "Alley through building — roof goes translucent for YOUR player inside (cutaway)"),
        ("overhang", "Roof overhang — walkable, PURELY VISUAL cover (hides who's under it)"),
        (SIGN_BOARD, "Shop sign — every building gets a purpose (blacksmith, tavern, bakery…)"),
    ]
    row_h = 20
    for i, (swatch, label) in enumerate(items):
        col = i // 4; row = i % 4
        lx = MARGIN + col * (MAP_W / 2)
        ly = y0 + 12 + row * row_h
        if swatch == "alley":
            out.append(svg_rect(lx, ly - 11, 22, 14, GROUND, rx=2))
            out.append(svg_rect(lx, ly - 11, 22, 14, "#ffffff", opacity=0.14))
            out.append(f'<rect x="{lx:.1f}" y="{ly-11:.1f}" width="22" height="14" fill="none" stroke="{OUTLINE}" stroke-width="1" stroke-dasharray="3 2"/>')
        elif swatch == "overhang":
            out.append(svg_rect(lx, ly - 11, 22, 14, ROOFS[0], opacity=0.5, rx=2))
            out.append(svg_rect(lx, ly - 11, 22, 14, "none", stroke=shade(ROOFS[0], 0.7), sw=1))
        else:
            out.append(svg_rect(lx, ly - 11, 22, 14, swatch, stroke=OUTLINE, sw=1, rx=2))
        out.append(svg_text(lx + 30, ly, label, size=12))
    return out


def main() -> None:
    out_path = "assets/tiles/citadel/citadel_map_sketch.svg"
    with open(out_path, "w") as f:
        f.write(build_svg())
    print("wrote", out_path)


if __name__ == "__main__":
    main()
