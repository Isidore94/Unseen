# UNSEEN — MAP DESIGN SPEC
### First playtest map (`test_map_01`) + general map-building method

> **Purpose:** How to design and greybox the first playable map. Pairs with `master_plan.md` (mechanics) and `UNSEEN_BUILD_PLAN.md` (build order). This map is a **Phase 1–2 deliverable** — a functional greybox space for the exposure and crowd systems to live in. It is NOT meant to be pretty or final. Good map design emerges through Phase 4 playtesting, not before.

---

## 0. GOLDEN RULES (apply to every map)

1. **Greybox first, art never (yet).** Build entirely from plain shapes and collision boxes. No sprites, no tiles, no art. You are testing *spatial design*, and art only slows iteration. The artist (brother) does not touch this phase.
2. **Small in area, dense in ideas.** A compact map packed with mechanics teaches more than a big empty one. Tension comes from forced proximity. Start cramped; expand only if it feels claustrophobic.
3. **Design as a loop, never a line.** No dead ends. Everything connects back. Prey must always have a route; hunters must never trap someone in a one-exit corner. Think ring or figure-eight.
4. **The map must express the mechanics.** This isn't a generic arena — every feature in the design doc needs a place to happen (density zones, exposed stretches, marks, passages, trapdoor, teleports).
5. **Paper before Godot.** Sketch the top-down layout on paper first. Iterate the drawing until the flow feels right. Five minutes sketching saves an hour dragging rectangles.
6. **Build maps as standalone scenes.** Each map is its own `.tscn` under `res://maps/`, modular and swappable without touching player or game logic. Game systems find map features via marker nodes, never hardcoded coordinates.

---

## 1. SIZE & SHAPE TARGET (test_map_01)

- **Player count it serves:** 2–4 humans + bots (early playtest). 
- **Area:** roughly **2–3 screens wide × 2–3 screens tall**. Big enough to lose someone briefly, small enough that you keep colliding. If nothing happens for 10+ seconds of movement, it's too big.
- **Overall shape:** a **rough ring / figure-eight** of connected spaces so movement flows continuously and never dead-ends.

---

## 2. REQUIRED FEATURES (the first map must contain all of these)

Each exists to exercise a specific system from `master_plan.md`:

| Feature | Count | Tests / serves | Notes |
|---|---|---|---|
| Crowd-density zone | 1–2 | §4 blending, fast exposure bleed | Market / plaza — where crowds clump and you hide |
| Open exposed stretch | 2–3 | §3 exposure, risk gradient | Connective streets where you stand out crossing them |
| NPC mark location | 1–2 | §7 contract, §7.2 risk | Place in **deliberately exposed** spots — reaching them must cost safety |
| Secret passage | 1 | §8.1 map knowledge | Hidden route linking two distant areas; subtle, no cost |
| Trapdoor / underground space | 1 | §8.1a single-occupancy "something lurks" | Sub-level the occupancy rule can be tested in |
| Teleport pad | 2 | §8.5 repositioning | Opposite ends of the map, so cross-map travel is testable |
| Choke point | 1–2 | §8.4 sightlines | Narrow funnels where players collide |
| Player spawn points | 4+ | match start | Spread around the ring, away from marks |
| NPC spawn points | several | §4 crowd | Inside/around density zones |

---

## 3. THE PAPER SKETCH CHECKLIST

Before opening Godot, draw the map top-down and mark:

- [ ] The outer **loop** — confirm you can trace a path all the way around with no dead ends
- [ ] **2 density zones** (shade them) — your safe blending areas
- [ ] **Exposed connectors** between zones — the risky crossings
- [ ] **Mark locations** (✕) — in exposed spots, not tucked away safe
- [ ] **Secret passage** (dashed line) — connecting two areas a normal route doesn't
- [ ] **Trapdoor + its underground space** — and where it exits
- [ ] **2 teleport pads** (◎) — opposite ends
- [ ] **Choke points** (><) — where you expect collisions
- [ ] **Spawn points** — players spread out, NPCs near density
- [ ] Walk it in your head: where do I feel safe? where exposed? any boring empty stretch? (cut it) any spot where everyone funnels? (good — keep)

Iterate the **drawing** 3–5 times before building. The sketch is cheap; the build is not.

---

## 4. GODOT SCENE STRUCTURE (`maps/test_map_01.tscn`)

Build the greybox with plain nodes. Suggested tree:

```
TestMap01 (Node2D)
├── Floor              (Polygon2D / ColorRect zones — purely visual greybox floor)
├── Walls              (Node2D container)
│   ├── Wall_x         (StaticBody2D + CollisionShape2D rectangles)
│   └── ...
├── DensityZones       (Node2D container)
│   ├── Market         (Area2D — marks a density region; crowd_manager reads it)
│   └── Plaza          (Area2D)
├── NavRegion          (NavigationRegion2D — baked over walkable floor for NPC pathing)
├── Markers            (Node2D container of position references)
│   ├── PlayerSpawns   (Marker2D × 4+)
│   ├── NpcSpawns      (Marker2D × several)
│   ├── MarkLocations  (Marker2D × 1–2)
│   ├── TeleportPads   (Marker2D × 2, paired)
│   ├── PassageEnds    (Marker2D × 2, paired)
│   └── TrapdoorEnds   (Marker2D × 2, paired)
└── Features           (Node2D container)
    ├── SecretPassage  (Area2D entrance + linked exit)
    ├── Trapdoor       (Area2D + single-occupancy logic hook)
    └── Teleports      (Area2D pads referencing TeleportPads markers)
```

**Greybox primitives to use:**
- **Walls / obstacles:** `StaticBody2D` + `CollisionShape2D` (RectangleShape2D). Give them a visible child shape so you can see them.
- **Floor / zone visualization:** `Polygon2D` or `ColorRect` in distinct flat colors (e.g. density zones tinted differently from exposed streets) so the risk geography is readable at a glance while testing.
- **Position references:** `Marker2D` nodes for every spawn, mark, pad, and passage endpoint. **Game systems read these markers** — never hardcode coordinates. This is what keeps maps swappable.
- **Trigger regions:** `Area2D` for density zones, passage entrances, trapdoor entrances, teleport pads — anything code needs to detect a player entering.

**Why markers matter:** `objective_manager`, `crowd_manager`, and teleport/passage logic should locate features by querying these marker/Area nodes in the loaded map. That way a new map "just works" with the same systems — drop in `test_map_02.tscn` with the same marker structure and nothing else changes.

---

## 5. COLOR KEY FOR GREYBOXING (readability while testing)

Tint the flat floor shapes so the tactical geography is obvious during playtests:

- **Density / safe zones:** one calm color (e.g. muted blue) — "exposure bleeds here"
- **Exposed connectors:** a warmer/brighter floor (e.g. pale red) — "you stand out here"
- **Passage / trapdoor / underground:** dark grey — "hidden / sub-level"
- **Teleport pads:** a distinct bright accent (e.g. teal) — easy to spot and run to
- **Mark locations:** a gold marker — visible to you the designer (not necessarily in-game)

This is a *designer aid*, not final art. It lets you SEE the risk gradient while you tune.

---

## 6. THE ITERATION LOOP (how to make it good)

The first version will be wrong. That's expected and cheap to fix — which is the whole reason to start small and grey.

1. Build the greybox layout from your sketch.
2. Walk it with **one bot hunter** active.
3. Ask, every pass:
   - Where do I feel safe? Where exposed? (Is the gradient working?)
   - Is there a boring empty stretch where nothing happens? → **cut it / shrink it.**
   - Is there a spot where players funnel and chaos happens? → **keep it, maybe lean in.**
   - Can I always keep moving (no dead ends)? Can a hunter corner me unfairly? → **fix the loop.**
   - Do the marks force me into the open? → if not, **move them.**
4. Redesign and repeat. Expect **5+ iterations** on this one small map. Each is cheap because it's grey boxes.

Then — and only then, once a layout is genuinely fun with bots and in Phase 4 with your brother — hand it to art for a tile pass.

---

## 7. SCOPE DISCIPLINE

- **One** small map until the core loop is proven fun (Phase 4). Do not build a second map before then. A second map is wasted effort if the first proves the loop doesn't work yet.
- The first map only needs to be **functional enough to test mechanics**, not balanced or beautiful. Perfection here is procrastination.
- Marks, passages, and teleports can be **stubbed** early (a passage that just teleports you, a mark that's just a killable NPC) and refined as the matching systems come online in Phases 2–3.

---

*Map spec v0.1 — June 2026. Pairs with master_plan.md and UNSEEN_BUILD_PLAN.md.*
