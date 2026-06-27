# UNSEEN — Playtest Refinement Build Plan (Phase 7)

> **Source:** `thingstochange.md`, written after the first online playtests (2–3 players,
> all seamless). This document refines those raw notes into a buildable, ordered plan.
> Read `master_plan.md` for design intent and `CLAUDE.md` §"coding rules" before coding.
>
> **Big shift since the old plan:** we are now **online and server-authoritative**. Every
> feature below must be built with that in mind — the single-player assumptions are gone.

---

## 0. Cross-cutting rules (apply to EVERY feature here — read once)

These are the constraints that turn "an idea" into "an idea that won't break online." They
repeat for a reason: each playtest item silently depends on all of them.

1. **Server owns the truth.** The host decides every outcome: which layer you're on, who
   owns a claimed entrance, whether an item fired, who has how many points, who is revealed.
   Clients send *intent* ("I want to enter this sewer"); the host validates and applies.
2. **The hidden-identity rule still governs everything.** A client may never receive data
   that reveals which character is a human — *except* the specific reveals we deliberately
   grant (item 8). Those go to the **one client that earned them**, via a targeted RPC —
   never broadcast. When in doubt, send less.
3. **Per-viewer rendering is now a first-class system — in TWO dimensions. Build both once,
   host-authoritative, and route every feature through them.**
   - **Visibility ("can I see this character?")** — rooftops, sewers, and smoke all need
     "player A sees this character, player B does not." One host-driven, per-character,
     per-viewer "visible to me?" decision; every feature plugs into it.
   - **Appearance ("what does this character look like to me?")** — *this is a core pillar.*
     The crowd a player sees is assembled from the **other** players' looks (plus filler) and
     **never the viewer's own look**. Human players blend because NPCs share their appearance;
     your own appearance is deliberately **absent** from the crowd you see, so you are never
     fooled by a copy of yourself and your own look never becomes a "tell." This is the seam
     the **identity reveals (7.4)** read from and the future **cosmetics/skins store** sits on:
     players will buy skins, but a player only ever sees their own skin on **their own
     character**, never out in the crowd. Build the per-viewer appearance map now (host → each
     client, owner-aware, excluding that client's own look); the store is just content on top.
4. **No magic numbers.** Every value below ships as an `@export` with a `##` doc-comment
   stating what it controls and its unit. The notes already ask for this ("easily fine
   tunable with obvious variables") — it's a rule, not a nicety.
5. **Components, not god-scripts.** New behaviour goes in small reusable nodes:
   `LayerComponent`, `ItemComponent`, `ClaimComponent`, `RevealComponent`. The player scene
   composes them; none of them know about each other.
6. **New inputs via the Input Map only** (keyboard **and** gamepad): `item_primary`,
   `item_secondary`, `interact` (claim / enter / exit an access point), `drop_down`
   (rooftop → ground). Never read a hardcoded key.
7. **Signals, past tense:** `layer_changed`, `item_used`, `points_changed`,
   `identity_revealed`, `access_claimed`, `player_eliminated`.

---

## Phase 7.0 — Quick wins (low risk, high feel) — *do this first*

Small, independent tweaks. They validate the loop and build momentum before the big systems.

- **Camera zoom (note 1).** Tighten the view to ~75% of its current span (a modest zoom-in
  so the tighter new map reads well). One `@export var camera_zoom` on the follow camera,
  applied on **both** the online camera and the offline split-screen cameras. Exact value is
  a feel tune — start where the view shows ¾ of today's area.
- **Spawn spacing (note 12).** At round start, no two players spawn within
  `min_player_spawn_distance` (default = one screen-width in world px). The host assigns the
  four corner spawns and re-rolls/reorders if any pair is too close. *Why:* spawning next to
  an opponent ruins the "find them in the crowd" tension.
- **Two NPC marks (note 9).** Contract = kill **2** marks before the human-hunt phase
  (`marks_per_player = 2`). The host secretly designates 2 distinct crowd NPCs per player.
- **Marks stay local + spaced (note 13).** Marked NPCs are forced **homebodies** (no
  map-crossing) with a small `mark_wander_radius`, so they loiter in one area you can learn.
  A player's two marks must spawn **≥ `mark_min_separation` (2 screens)** apart, so you can't
  scoop both at once — it forces movement across the map.
- **Teleporter raises exposure (note 10).** Confirm/ensure teleporter use adds
  `teleporter_cost` to **committed** exposure on the host (it's defined; verify it actually
  fires on the online path). Note the contrast set up in 7.3: **teleporters cost exposure,
  sewers/rooftops do not.**
- **Teleporter placement (note 2).** One teleporter pair connects **top ↔ bottom** of the
  map (a vertical cross-map jump), placed by the new map's zone layout (7.1).

**Done when:** the view feels tighter, players never start adjacent, you hunt 2 well-separated
loitering marks, and teleporting visibly costs exposure.

---

## Phase 7.1 — The new main map: four zones, tighter streets (notes 3, 4, 5a, 2)

**Goal:** retire the big repetitive map; the **compact, tight scale becomes the main map**
(note 3), expanded into **four visually + functionally distinct corner zones** (note 4) so the
arena stops feeling same-y. Tighter overall, with **long streets flanked by long buildings**
and **small alleys** branching to side streets (note 5a).

**The four corners (this is also the spatial setup for 7.2):**

- **2 "street + rooftop" corners** — long straight streets, long unbroken buildings on each
  side, side streets reached only through small alleys. These get **rooftop access** (7.2).
  Long sightlines reward the rooftop vantage.
- **2 "sewer" corners** — tighter than open ground but **a bit more open than the street
  corners**; these get **sewer entrances** (7.2). The play here is stalking via the sewer
  arrow, not sightlines.
- **Centre** — the fountain plaza as the shared hub that wires the four zones together.

**Architecture:** keep the proven **grid-LAYOUT + flood-fill-verified** approach (it caught
every dead-end so far). Extend it so each cell carries a **zone id** (NW/NE/SW/SE/centre); the
zone id drives (a) themed floor colours so corners read differently and (b) where the map
spawns rooftop stairs vs sewer entrances. Connectivity is verified before commit, as always.

**Decision (confirm):** the new 4-zone map **replaces** `test_map_01` as the default; keep the
old maps only as offline test scenes. The "compact arena" lobby toggle is retired (the main map
is already tight).

**Risk:** medium-high — balancing 4 distinct zones, tight connectivity, and feature placement
in one layout. Build the geometry first with **no** roofs/sewers, playtest the flow, *then* add
7.2 on top.

---

## Phase 7.2 — Verticality & the underground: rooftops + sewers (notes 5, 5a)

**The headline feature, and the highest-risk one.** It introduces **layers**: every character
is on **GROUND**, **ROOFTOP**, or **SEWER**, and the layer rewrites the rules of *seeing* and
*killing*. This is what makes UNSEEN's stealth three-dimensional.

### 7.2a — Layer state (server-authoritative)
- New **`LayerComponent`** on each player: `current_layer` (GROUND default), server-owned,
  replicated, emits `layer_changed`.
- **Access points** are map objects (Area2D, like portals):
  - **Rooftop stairs** (only the 2 street corners): step on → move to **ROOFTOP** at that spot.
  - **Sewer entrances** (only the 2 sewer corners): step on → enter **SEWER**.
  - **Exits:** a ROOFTOP player presses **`drop_down`** to return to **GROUND** at their
    current position (to commit a kill). A SEWER player exits at any sewer entrance → GROUND.
- **Using an access point does NOT raise exposure by itself** (note 5b) — claiming does (7.3).

### 7.2b — Visibility rules (built on the §0.3 per-viewer system)
- **GROUND** player: sees ground characters; **cannot** see rooftop or sewer players.
- **ROOFTOP** player: **hidden** from ground; **can see the ground below** (vantage). Reads as
  a safe stalking perch you watch from, then drop from.
- **SEWER** player: **cannot see** the map or anyone — the screen is obscured — **but** gets
  the arrow buff in 7.2c. Blind stalking by the arrow alone.

> *Implementation note:* this is the hard part. Each client hides characters its local player
> shouldn't see (per the host's layer truth). **Prototype the visibility culling offline first**
> (one screen, fake "layers") before wiring it to the network, so we de-risk the rendering
> separately from the netcode.

### 7.2c — Kill rules
- You may only kill a player **on your own layer and in range** — and in practice kills happen
  on **GROUND**: ROOFTOP players must **drop down** first; the **SEWER is a strict no-kill zone**
  (note 5a — no killing or being killed while underground).
- So each layer has a clean identity: **Ground** = the kill floor. **Rooftop** = hide, watch,
  reposition, drop for the ambush. **Sewer** = blind-stalk by arrow, surface at an entrance to
  ambush.

### 7.2d — The sewer arrow buff
- While in a SEWER, the player gets **100% arrow uptime** pointing at their tracked target,
  ignoring the normal exposure/off-screen gating (note 5). That's the whole trade: you give up
  sight for a perfect bearing, follow it underground, and pop out next to your prey.

**Risk:** **high.** Sequence it: (1) layer state + kill rules + sewer no-kill + arrow buff
[testable with simple tints], then (2) the real per-viewer visibility culling, then (3) feel
polish (rooftop overlay, sewer screen treatment).

---

## Phase 7.3 — Map-control: claiming & global cooldowns (notes 5b, 10)

Stops access points from being spammed and adds a risk/reward ownership layer.

- **Global per-access cooldown.** Each teleporter, sewer entrance, and rooftop stair is usable
  **once every `access_global_cooldown` (15s) by *any* player** (not per-player — a true global
  lockout) so nobody can camp/chain an entrance during a chase. The host tracks each access
  point's last-use time and rejects-with-feedback during cooldown.
- **Claim for exclusive use.** Right after using an access point, a player may press
  **`interact`** to **claim** it **for the rest of the match**, paying `claim_exposure_cost`
  (**20%**) to *committed* exposure. While claimed, **only that player** may use it. *Plain use
  is free; claiming is the exposing, permanent commitment* — it carves out private map control
  at a lasting cost to your stealth.
- **Teleporters** share the global cooldown **and** cost exposure on every use (7.0/ note 10),
  unlike sewers/rooftops which are free to use.

**Architecture:** a `ClaimComponent` / per-access host state; replicate `owner` + `cooldown`
remaining so each player's HUD can show "claimed by you / on cooldown / available".

---

## Phase 7.4 — Identity reveals & faceplates (note 8)

Turns the disguise into an *information economy* — and rewards fast, clean play.

- **Target reveal (RED faceplate).** The **first** player to finish their NPC contract (before
  anyone else) is told **what their human target looks like** (appearance index) — a real edge
  for moving fast. Shown as a **red faceplate** at the top of their HUD.
- **Exposure reveal (BLUE faceplate).** When any player hits **100% exposure**, that player's
  appearance is revealed **to the others** — but only shown **alongside the arrow when that
  player's location is being displayed**. Up to 3 of these (the other players), shown as **blue
  faceplates** at the top.
- **Faceplate HUD:** a top-of-screen row — **red = your post-contract target**, **blue =
  exposure-revealed identities** — built per-machine from owner-only data.

**Architecture:** a reveal is just an **appearance index** sent by targeted RPC to the client
that earned it; it drives that client's faceplate and (later) which crowd-member it highlights.
Reuses the `set_appearance` / per-viewer seam.

**Decision (locked): ship it now.** Today the crowd shares only **5 sprite sheets**, so a
revealed look is a *soft* narrowing rather than a unique ID — that's acceptable. It reads
straight from the **per-viewer appearance system (§0.3)**: a reveal hands you an opponent's look,
and you scan the crowd — which wears the *other* players' looks, never your own — for it. The
feature sharpens automatically as the **cosmetics/skins** content lands on that same seam, with
no rework.

---

## Phase 7.5 — Match flow: last-one-standing & rematch (notes 6, 7)

- **3–4 player win condition (note 6).** The round runs until **one player is left standing**
  (eliminated players spectate); last-standing simply **ends** the round — it is *not* a win by
  itself. **The winner is whoever has the most points, full stop** — so a cautious, low-exposure
  assassin can win without the final kill, while being eliminated caps what you can still earn.
  Extend the existing scoring (ghostliness from low average exposure + speed + clean mark kills +
  player kills + completion bonuses) to N players, and add the **elimination → spectate** flow.
  **Tie-break:** lowest average exposure wins — ghostliness is the core fantasy (kept as a
  tunable rank order in case we revise it).
- **Rematch (note 7).** The end screen gets a host **"Rematch"** button that returns everyone to
  the lobby (or restarts a fresh round with the same players/settings) together, via RPC —
  reusing the lobby/`begin_match` plumbing we already have.

---

## Phase 7.6 — The class kit: first two items (note 11)

The start of the class/tool system (`master_plan` §9 / §9A). Build the **framework** so future
items plug in cleanly; ship two items in it.

- **`ItemComponent`** on the player: a base kit of **2 slots**, fired via `item_primary` /
  `item_secondary`. Items are **charge-based — a fixed number of uses per match (`charges`),
  no cooldown reuse**; once spent, they're gone for the round (so using one is a real decision).
  **Server-authoritative:** client requests → host validates (charges left, alive, not
  mid-action) → applies effect → tells the right clients. Each item is a tiny script with
  **obvious `@export` tunables** (per the note).
- **Smoke grenade (slot 1).** On use, the player becomes **invisible to others** (plugs into the
  §0.3 visibility system) for up to `smoke_duration` (**10s**) and **cannot attack** during it
  (`kill` disabled). Pure escape/reposition. Tunables: duration, charges, can-move (yes).
- **Cloaking device (slot 2).** On use, turns off **all non-exposure arrow systems** that point
  at the user — specifically the **NPC-completion "hunt" arrow** opponents get after finishing
  their marks — for `cloak_duration` (**15s**). Your **exposure-based** arrows still fire (run
  loud and you still light up). Tunables: duration, charges.

**Why this comes last:** both items act through systems built earlier — smoke through the
**visibility** system (7.2), cloak through the **arrow** system (7.4). Build them on top of
finished seams instead of inventing one-offs.

---

## Decisions — locked vs still open

**Locked (your calls):**
- **Win = most points, full stop.** Last-standing only *ends* the round. Tie-break = lowest
  average exposure.
- **Claim = rest of the match**, paid for with exposure (20% committed).
- **Items = charges per match** (no cooldown reuse).
- **Per-viewer appearance is law (§0.3):** a player never sees their own look in the crowd — only
  the other players' looks, duplicated among NPCs. Identity reveals (7.4) ship **now** as a soft
  hint and sharpen automatically when the cosmetics/skins store lands on the same seam.

**Still open (confirm when we reach them):**
1. **Camera zoom** exact value — tune by feel once the tight map exists.
2. **Zone themes** — what makes each of the 4 corners visually distinct beyond roof vs sewer
   (palette / density / a signature landmark)?
3. **Rooftop ↔ rooftop visibility** — can rooftop players see each other? Can ground see a player
   mid-drop?
4. **Sewer arrow target** — only your post-NPC human target, or your nearest opponent generally?

---

## Suggested build order & why

```
7.0 quick wins        (independent; ships value immediately, low risk)
   ↓
7.1 four-zone map      (foundation — rooftops/sewers need these zones to live in)
   ↓
7.2 layers             (the big system; build state+rules first, visibility culling second)
   ↓
7.3 claim + cooldowns  (rides on the access points created in 7.2)
   ↓
7.4 reveals + faceplates (independent of layers, but shares the per-viewer seam)
   ↓
7.5 match flow         (last-standing + rematch; touches scoring + lobby)
   ↓
7.6 items              (built last — smoke uses 7.2's visibility, cloak uses 7.4's arrows)
```

The throughline: **build the per-viewer visibility system once (7.2) and the reveal/arrow
system once (7.4), then everything else plugs into them.** That keeps the codebase small and
honors the "components, not god-scripts" rule even as the feature set grows.
