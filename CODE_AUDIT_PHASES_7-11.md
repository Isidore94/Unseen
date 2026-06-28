# UNSEEN — Code Audit (Phases 7–11)

> A full read-through of every script across the unmerged phase branches and `main`,
> graded against the project's own rules in `CLAUDE.md` (separate logic from visuals,
> one responsibility per script, signals over polling, server-authoritative, no magic
> numbers, readable for a beginner). Written to be acted on phase-by-phase, not all at once.

## How the branches fit together

The phase branches are a **linear stack** — each is built on the one before:

```
main → phase-7 → phase-7-online-integration → phase-8 → phase-9 → phase-10 → phase-11
```

`phase-11-art-pipeline` is the **cumulative tip**: it contains everything in phases 7–11.
A key thing to know: **the integration branch retired split-screen local co-op** —
`local_coop_game.gd` / `local_match_manager.gd` were replaced by `single_player_game.gd`.
So a few problems that exist on `main` (the local-coop "god builder", the duplicated
score block between `round_manager` and `local_match_manager`) are already partly gone on
the tip — but the *shape* of those problems came back bigger inside `online_match.gd`.

## The headline verdict

**This is a strong, professional foundation — well above typical solo/first-game code.**
The teaching comments, unit-bearing names (`run_rise_per_second`, not `r`), the
server-authority discipline, and the component split are genuinely good and worth
protecting. Grades: **architecture B, readability A−, performance B−, security/monetization C+
(fixable), online-correctness B+.**

There are **four things that matter before Phase 8 ships money or Phase 11 ships art.**
Everything else is polish. The four are below; the full list follows.

---

## The four that matter

### 1. The cosmetics ownership gate is client-side only — a free-items exploit the day a shop exists
*(Phase 8 — `online_match.gd:596-604` `_submit_loadout`, `cosmetic_inventory.gd:11-13`)*

The host accepts whatever loadout id-payload a client sends and renders it on every
screen. Ownership (`CosmeticInventory.owns()`) is only ever checked **locally on the
equipping machine** — the host never re-checks it. A modified client can hand-craft a
payload containing any paid item and the host will replicate it to everyone. The code's
own comment calls this gate "the ONLY thing standing between free items and a shop" — but
because the gate lives client-side, against a hostile client **it is not a gate at all.**

This is fine *today* (nothing is paid, the host is just a peer). The risk is that the
comment tells a beginner the security boundary is already built, so the shop bolts on here
without adding a host-side check. **Fix:** when real accounts exist, the host (or a backend
it trusts) must validate every id in the payload against that account's server-held
ownership, replacing any unowned id with its slot default. **Do now:** add an honest
`# TODO(monetization): validate payload ids against server-side inventory` at
`_submit_loadout` so the local gate isn't mistaken for the security boundary.

### 2. Paid cosmetics are currently a "tell" — they break the hidden-identity pillar
*(Phase 8 — `online_match.gd:1421-1422` `_look_key()`, `cosmetic_registry.gd:133-141`)*

The whole game rests on "you look identical to the crowd." The per-viewer crowd reskin
that protects this only matches on the **BODY slot**. Outfits, hats, weapons, and palette
recolors are **not** folded into the camouflage:

- A player in a paid crimson coat is, on an opponent's screen, likely the *only* crimson
  coat near their body type → **pay-to-be-spotted / pay-to-lose** (the most expensive
  cosmetics become the ones a competitive player must never wear).
- Nothing in the data model forbids a future cosmetic that NPCs can't also wear. A
  season "glowing hat" that only buyers own makes **every glowing hat on screen a human** —
  a direct identity leak.
- Palette recolor (`cosmetic_inventory.gd:111-114`) has *no* gate and is ignored by the
  camouflage entirely.

**Fix:** before selling any visual cosmetic, fold all four visual slots + palette into
`_look_key()`, and make it a written **invariant** that every equippable visual item is
densely drawable on the NPC crowd (an explicit `crowd_safe` flag, or an assert that every
BODY/OUTFIT/HEAD/WEAPON id appears in `npc_pool_by_slot()`). This is where the store design
and the core pillar collide — it deserves an invariant, not a buried "later" comment.

### 3. `online_match.gd` is a 1,706-line god object
*(Phase 7→11 — `scripts/online_match.gd`)*

It is the match referee **and** the network transport **and** a HUD builder **and** a
per-frame visibility renderer **and** the cosmetics plumbing **and** the scoring system
**and** the end-screen UI **and** the experiment loader. This is the clearest violation of
"one responsibility per script," and it's the root cause of most other smells (duplicated
HUD code, per-frame costs, hard-to-trace state).

The good news: the natural fault line is **host-authority logic vs. local-view rendering**,
and they're already cleanly separated by `multiplayer.is_server()` guards. Recommended split:

- **Host-only:** `HostMatchReferee` (spawn/readiness/peer-left), `TargetRing` (the
  hunter→prey state machine — pure logic, unit-testable), `ContractDirector` (mark
  selection/spacing), `ScoreKeeper` (the scoring math — share this with offline).
- **Per-machine view:** `PlayerHud` (make it a real `.tscn` scene, not 200 lines of
  `Label.new()`), `LocalMatchView`, `VisibilityView`, `CrowdAppearanceService`,
  `AccessPointSync`, `MatchEndScreen` (a scene), `NetDebugOverlay`.

`OnlineMatch` then shrinks to a ~120-line composition root that builds the world and wires
signals — exactly the philosophy `single_player_game.gd` already follows. **Do this
incrementally**, one extraction per commit, testing in the editor between each — never one
big-bang refactor.

### 4. The art pipeline has a 32px/48px split-brain — a silent time bomb
*(Phase 11 — `tools/ingest_sprite.py:26` vs `character_visual.gd:46`)*

You just changed base art resolution to 48px. The ingest script packs sheets at
`FRAME_PX = 48`, but the rig still slices at `const FRAME_PX := 32`, and there is **no
single source of truth** linking them. The day a real 48px sheet lands next to the 32px
placeholders, the rig will mis-slice it and `scale = display_height / FRAME_PX` will render
characters ~1.5× the intended size — with no error, just wrong-looking art.

**Fix (removes the whole class of bug):** have the rig **derive** frame size from the
texture (`texture.get_width() / hframes`) instead of a hardcoded const, so 32 and 48 both
just work and the two files can never disagree. Also note `display_height = 80.0` is coupled
to `FRAME_PX` and will need re-confirming on the flip.

Related pipeline robustness (a beginner will run `ingest_sprite.py` dozens of times):
- **No input-dimension validation** — oversized art is silently downscaled and clipped
  (`place_in_frame`, `:72-81`). Validate and fail loudly instead.
- **Silent overwrite** — `sheet.save(args.out)` clobbers existing files with no `--force`
  (`:117`). You could lose hand-corrected art.
- **Frame-count mismatch is silent** — too few frames leaves invisible cells and still
  prints "success" (`:87-92`); plain `sorted()` puts `frame_10` before `frame_2`
  (`:96-101`). Error on `len(frames) != cols*rows` and use a natural sort.

---

## Performance — invisible at N=1, lethal at N=180

The code is explicitly built for 60–180 NPCs on low-end hardware, so these count:

| Where | Issue | Fix |
|---|---|---|
| `online_match.gd:1307` `_update_visibility` | **Runs every frame over all ~180 NPCs**, doing a string `get_node_or_null("LayerComponent")` per NPC — pure waste (crowd has no layer component). The single biggest per-frame cost. | Make it signal-driven: recompute only on the local player's `layer_changed` and on smoke on/off. Skip the lookup for `Npc` (always ground). |
| `hunter_ai.gd:169-173` | Per-frame raycast for line-of-sight **plus** a new query object allocated every frame. Fine at 1 hunter, lethal at many. | Throttle to ~10 Hz (imperceptible, 6× cheaper); reuse one cached `PhysicsRayQueryParameters2D`. |
| `crowd_thinning.gd:144` (Phase 9) | O(n²) neighbor scan with a `sqrt` per pair (~3,600 sqrts/tick at 60 NPCs). | `distance_squared_to` vs a precomputed squared radius. |
| `behavior_history.gd:75` (Phase 9) | Per-NPC per-physics-frame `velocity.length()` (sqrt). | `length_squared()` vs squared thresholds. |
| `crowd_manager.gd:60` `count_npcs_near` | `distance_to` (sqrt) in a linear scan; destined to be called per-frame by exposure. **No live callers yet** — clean window to fix. | `distance_squared_to`; plan a spatial grid before wiring it hot. |
| `hunter_ai.gd:192`, `player.gd:491` | `distance_to` for pure threshold checks. | `distance_squared_to`. |
| Phase 9 experiment loader (`online_match.gd:1652`) | Instantiates **all six** experiments unconditionally; their `_process` runs every frame even with flags off — dead code shipping to players. | Skip instantiating an experiment whose flag is false (the flag autoload is available at spawn). |
| `test_map_01.gd` | `_building_rects` / `_has_fountain` / `_fountain_center` recomputed on every call, including inside `_draw`. | Compute once in `_ready`, cache. |

**The lesson worth internalizing:** every one of these is cheap at N=1 and written to run
across the whole crowd. The `sqrt → squared-distance` swaps are free and safe; the
signal-driven visibility and the spatial grid are the ones to design in *before* the systems
go hot, not after.

---

## Correctness & online-readiness

- **`online_match.gd:807` kill attribution** reads `last_attacker_peer` off the victim to
  award the contract bonus. That's only safe if `KillComponent` stamps it **host-side
  only** — confirm a client can never write it, or a client could mis-attribute a kill.
- **`online_match.gd:442` `_hunter_of` fallback** can crown the wrong winner if a player
  dies before anyone entered the hunt phase (it falls back to "the other player wins").
  Only declare a winner when a real hunter exists, or document the assumption.
- **`item_component` vs `kill_component` handle online authority oppositely** —
  `kill_component` defaults its control flag `false` and the player enables it;
  `item_component` defaults `true` and the player never calls its enable method (it disables
  remote items a third way, `set_physics_process(false)`). Works today, but it's a trap for
  the online port. Unify the pattern; the unused `enable_network_local_control()` on
  `item_component` is dead/misleading.
- **`whiff_recovery.gd:63-69` (Phase 9)** never restores `exposure_penalty_multiplier` to
  `1.0` when its flag is toggled off mid-session — a stuck multiplier. Add a reset.
- **Identity *data* still leaks even though the visual disguise is sound:** a cheating
  client can read `controlling_peer_id` / `loadout_payload` off the replicated `Player`
  nodes to tell which on-screen body is human. Already noted in-code as a 6.1 follow-up;
  make these fields host-only before competitive play matters.

---

## Readability & your own rules (small, safe fixes)

- **Hardcoded keys** `KEY_ESCAPE` / `KEY_F3` (`online_match.gd:1621/1624`) — a direct
  break of Rule #2 (never hardcode keys). Use Input Map actions (`ui_cancel`,
  `toggle_net_debug`) so controller players can exit/toggle.
- **`HOST_PEER_ID`** — the literal `1` for "the host" appears ~6× across the net layer;
  make it one named constant.
- **`collision_mask = 6`** (`kill_component.gd:201`) — magic number; name the layer bits.
- **Duplicated sender-auth block** — the security-critical "did this peer puppet a
  character they don't own" check is copy-pasted 4× in `player.gd` (`_receive_input`,
  `_request_claim`, `_request_set_layer`, `_request_item`). Extract one
  `_is_authorized_sender()` — DRY *and* a smaller anti-cheat surface.
- **Duplicated kill-resolution** in `kill_component` (`_resolve_on` offline vs
  `request_kill` host) — same clean-kill/wrong-commit logic written twice.
- **HUD + scoring duplicated** between `online_match.gd` and `single_player_game.gd`
  (exposure bar, mini-map, item readout, faceplates, the scoring formula). A shared
  `PlayerHud` scene + `ScoreFormula` helper removes ~200 lines and keeps the modes identical.
- **Magic numbers that should be documented `@export`s**: ping interval `0.5`, wander
  radius, the `954`/`1080` split-view sizes, death-fade `0.4` (duplicated npc+hunter),
  portal radii, the strike/smoke feel constants in `character_visual.gd`.
- **Dead state** `_active_peer` in `network_manager` (written everywhere, read nowhere).
- **`player.gd` is drifting from single-responsibility** — the access-point / claim / layer
  cluster (~145 lines) is a clean candidate for an `AccessInteractionComponent`, matching
  the existing component split.
- **Maps are built by a 619-line script** (`test_map_01.gd`), not authored as scenes. Fine
  for greybox, wrong foundation for AI-art maps. Before art lands, plan the migration to
  `.tscn` + `TileMapLayer` (art + merged collision + baked nav, painted in the editor). The
  public API (`get_player_spawns()` etc.) is clean and survives the migration unchanged —
  that seam makes the switch cheap *if done first*.

---

## What's genuinely strong (keep doing this)

- **Server-authority discipline is the best part of the codebase.** Every state-mutating
  `any_peer` RPC is `is_server()`-guarded; clients only receive `authority` broadcasts;
  marks/exposure/items are sent owner-only via `rpc_id` (no leaks). Clients cannot
  self-confirm kills, scoring, or phase transitions.
- **Client-side prediction + replay** (`player.gd`) is correctly scoped to the owned
  character, reuses the shared movement rule, and deliberately keeps exposure out of
  prediction so it can't double-count. Subtle and correct.
- **The exposure component** (the core tension system) is a model of the project's ideals —
  one hub, three clear "doors", recoverable vs. committed split, every tunable documented.
- **The Phase 9 experiment isolation** (one-way dependency, folder-scan loader, neutral core
  hooks) is a disciplined A/B pattern most production teams get wrong.
- **The cosmetics architecture** (stable never-reused ids, one rig entry point
  `apply_loadout`, centralized equip gate) is extensible toward a real store — the gaps are
  in *enforcement*, not *shape*.
- **Doc-comments throughout** explain *why*, with units — exactly the beginner-traceability
  the project demands.

---

## Suggested order of operations

1. **Two one-line safety comments now** (zero risk): the `_submit_loadout` ownership TODO,
   and the `crowd_safe` invariant note in the cosmetics spec — so the two existential Phase 8
   issues can't be forgotten when the shop/art lands.
2. **Free performance pass**: all the `distance_to → distance_squared_to` swaps. Pure speed,
   no behavior change.
3. **Readability pass**: `HOST_PEER_ID`, named collision mask, dead-code removal, extract the
   sender-auth helper and the kill-resolution helper, magic-numbers → exports.
4. **Make `_update_visibility` signal-driven** — the biggest single per-frame win.
5. **Derive `FRAME_PX` from the texture** + harden `ingest_sprite.py` — before the first real
   48px sheet.
6. **Incrementally decompose `online_match.gd`** — start by extracting `PlayerHud` as a scene
   (also kills the online/offline HUD duplication), one component per commit.
7. **Plan (don't yet execute) the map → TileMap migration** and the server-side cosmetics
   ownership check — schedule them into the build plan as Phase 8/10 prep.
