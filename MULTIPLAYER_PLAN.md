# UNSEEN — MULTIPLAYER PLAN (as-built netcode reference)

> **Purpose.** This is the single source of truth for *how the online game actually works in code today* —
> the host-authoritative architecture, the match lifecycle, the kill path, contracts, death/respawn,
> spawning, identity replication, and the feature-flag gate. It is **reverse-engineered from the code**
> (`scripts/online_match.gd`, `scripts/net/network_manager.gd`, `scripts/lobby.gd`, the components) and is
> meant to be ground truth where `master_plan.md` (design intent) and the code disagree. Pairs with
> `master_plan.md` (what the game *should* be) and `COSMETIC_SYSTEM_SPEC.md` (the identity rig).
>
> **Audited:** 2026-06-29, branch `angel` (art reverted to `prayer`). Line numbers are a guide, not a contract —
> they drift as the file changes; search by function name.
>
> **Reading note for a new coder:** "host-authoritative" means **one machine (the host) decides every
> outcome**. Clients press buttons and send *requests* ("I want to kill that one"); the host checks the
> request and tells everyone what really happened. A client can never confirm its own kill. This is rule #5
> in `CLAUDE.md` and it is the spine of everything below.

---

## 1. Architecture at a glance

- **Engine:** Godot 4.7, GDScript, Compatibility (GL3) renderer.
- **Transport:** Godot high-level multiplayer over **ENet** (localhost today, port `24565`); **Steam** relay/lobby
  is the shipping path (friends-only lobby, `STEAM_LOBBY_TYPE = 1`). `network_manager.gd`.
- **Authority model:** **Host = peer id 1 = the referee.** `multiplayer.is_server()` gates every outcome.
- **Player cap:** `MAX_PLAYERS = 4`.
- **Autoload singletons** (`project.godot`): `NetworkManager`, `CosmeticRegistry`, `CosmeticInventory`,
  `ExperimentFlags`. These exist on every machine; only the host's copies *decide* gameplay.
- **Replication primitive:** a `MultiplayerSpawner` replicates spawned bodies (players and NPCs) to all peers;
  the host owns their movement and pushes positions out. Clients render/interpolate; they do not simulate.

The two big scripts:
- **`network_manager.gd`** (~392 lines) — connection, lobby membership, ping, scene handoff. Transport layer.
- **`online_match.gd`** (~2564 lines) — the entire authoritative match: spawn, contracts, kills, exposure,
  reveals, death, scoring, rematch, per-viewer crowd, tools. This is where almost all online gameplay lives.

---

## 2. Connection & lobby flow

1. `NetworkManager` hosts or joins (ENet today; Steam lobby on ship). Host is peer 1; clients get peer ids.
2. **Lobby** (`lobby.gd`, `scenes/lobby.tscn`): each player privately picks their assassin skin, two tools, an
   optional NPC-disguise, and a nickname (Steam-prefilled). Taken skins **grey out anonymously** (you never see
   *who* took one); the host bumps collisions; a full 4-player lobby self-locks.
3. Host calls `_begin_match` (RPC, authority→all) → everyone loads `scenes/online_match.tscn` and records the map.

**What crosses the wire from the lobby (client→host, once, reliable):**
- `_submit_loadout(payload)` — compact cosmetic ids (never textures). See `COSMETIC_SYSTEM_SPEC.md`.
- `_submit_tools([a, b])` — the two equipped tool enum ints.
- `_submit_nickname(name)` — the public name shown on roster / scoreboard / death screen.

---

## 3. Match lifecycle (the spine)

```
load online_match.tscn
   → each client RPCs _request_spawn(...) to host          (handshake: "I'm here, here's my loadout/tools/name")
   → host waits until all expected peers have requested     (_maybe_begin_match)
   → host spawns players (shuffled order) + crowd
   → host builds the target ring (_build_target_ring)
   → host assigns each player their NPC marks (_assign_mark_for_peer)
   → host privately tells each peer their target + marks    (owner-only RPCs)
   → _start_round_countdown ("3 / 2 / 1 / GO") with a start freeze
   → PLAY: continuous round clock (round_time_limit, default 300s)
   → a player dies → eliminated + spectate + hunters re-link (_on_player_killed)
   → round ends on time-out OR ≤1 alive → _end_match → scoreboard
   → rematch vote → _do_rematch → back to lobby (re-shuffle, new ring, new marks)
```

Spawn order is **shuffled each match**, and a player's 1-based **number → fixed colour** comes from that order
(`_color_for_num`). The number/colour is the player's identity on the roster and scoreboard.

---

## 4. The authoritative kill path  ⭐ (the central hook point)

This is the most important section for any new mode: **contracts, exposure, death, scoring, and respawn all
hang off kill resolution.** There are **three** kill code paths in the repo, and they are *not* unified — this is
a known landmine. Hook new logic into the **online authoritative path only**.

### 4.1 The online blade kill (host-validated)
1. **Client (killer's machine):** `KillComponent._network_kill_input()` locks the best suspect in its facing
   cone, and *only if* within `kill_range` (90px) sends `request_kill(target_path)` to the host. It plays the
   strike animation **locally for feel** — but that animation is not authoritative.
2. **Host:** `KillComponent.request_kill()` (`@rpc("any_peer","call_local","reliable")`) re-validates **everything**:
   - sender actually controls the killer body (anti-hijack),
   - attacks not disabled (smoke stun / round-start freeze / Phase-9 gate),
   - distance ≤ `kill_range`, layers allow the kill (sewer is a no-kill zone),
   - target validity: `is_in_group("player")` **or** `is_in_group("killable_for_<controller>")`.
   - Valid → `_apply_clean_kill(target, controller)`; invalid → `_apply_whiff(target)`.
3. **Clean kill** (`_apply_clean_kill`): `+kill_exposure_spike` (22) committed exposure on the killer,
   emits `kill_landed` (scoring) and `kill_resolved(...,true)` (Phase-9 experiments), stamps
   `last_attacker_peer` + `last_attacker_method="blade"` on the victim (death attribution), then `target.die()`.
   The host relays `host_kill_resolved` and **scatters the nearby crowd**.
4. **Whiff** (`_apply_whiff`, wrong target): `+wrong_commit_exposure` (40 × `exposure_penalty_multiplier`),
   victim dies anyway, **no crowd scatter** (it deliberately doesn't emit the panic signal).

### 4.2 Poison (silent, delayed)
`KillComponent.host_poison(target, delay)` — triggered via the POISON tool. It is the deliberately deniable kill:
**no strike animation, no crowd panic** (sets `is_poisoned=true`, never emits `kill_resolved`), strips the target
from killable groups so it can't be double-killed, and on the timer fires the death. The **exposure cost is paid
up-front at tool use** (`poison_exposure_cost` 12, in `ItemComponent`), not at the kill; a wrong-target poison adds
the whiff penalty when the body finally drops.

### 4.3 The offline path (NOT authoritative — test harness only)
`single_player_game.gd` + `KillComponent` resolve kills **locally** with no host round-trip, against the `"killable"`
group (vs. the online per-peer `"killable_for_N"` groups). Notable divergences to be aware of:
- offline blade has **no double-kill strip**; offline poison pays **no up-front exposure cost**;
- offline has **no crowd scatter**.
These are intentional (single-player is a dev harness) but they are why "kill rules" feel inconsistent across the
codebase. **Do not try to unify all three in a feature pass — extend the online path and flag the rest.**

> **Civilian-killable status (resolves a master_plan question):** civilians *can* be struck, the body dies, and
> you eat the **+40 wrong-target penalty** (+ crowd scatter online). NPCs are only a *clean* kill if they're in
> your `killable_for_<you>` mark group. Code and `master_plan.md` §4/§6 agree here — **no reversal exists**.

---

## 5. Contracts: marks → the target ring → re-link on death

The online contract is a **one-hunter / one-prey ring**, and it **already re-assigns on death** — this is built in
`online_match.gd` (NOT in `contract_manager.gd`, which is the simpler *offline* marks→single-target system).

- **Marks (PvE phase).** `_assign_mark_for_peer()` secretly tags `marks_per_player` (2) wandering NPCs as that
  peer's `killable_for_<peer>` group, pins them as homebodies, spaces them `mark_min_separation` (1400px) apart,
  and tells **only that peer** their node names (`_receive_marks`, owner-only). Killing all marks →
  `_begin_target_phase()` → the peer's human target becomes killable and their arrow switches to hunt/flash mode.
- **The ring (PvP phase).** `_build_target_ring()` forms a single cycle over the shuffled peer list:
  peer *i* hunts peer *i+1*, last wraps to first. So **everyone has exactly one target and is exactly one other's
  prey** — no mutual pairs, no free-for-all, nobody targetless (for ≥2 players). Each hunter is told only their
  own target's node name (`_receive_target`, owner-only).
- **Re-link on death.** `_relink_hunters_of(dead_peer)` finds any living hunter whose target just died and
  re-points them to `_next_living_target(...)`, adds the new prey to their killable group, and re-sends the target
  (arrow repoints). **This is the seed a respawn mode would extend** — today it walks the ring among the *living*;
  a respawn loop would instead keep the ring intact as players come back.

> **master_plan drift:** §11 lists a "free-for-all contract web" as the intended mode and §7 describes marks→target.
> The **online** code implements exactly the ring + re-link; the **offline** `contract_manager.gd` does not (no ring).
> That offline/online split is the contract instance of the "multiple versions" landmine.

---

## 6. Death, elimination & spectate (current mode = NO respawn)

`_on_player_killed(loser_peer)` (host):
- marks `_dead_by_peer[loser] = true` (idempotent), clears their exposure reveal,
- `_freeze_player.rpc(name)` freezes the corpse on every screen,
- sends the loser a death screen (`_receive_eliminated`, killer name + method) → they enter **free-fly spectate**
  (`_enter_spectate`, a pannable `Camera2D` at `spectate_camera_speed` 900px/s); the host handles its own death inline,
- credits the killer (`_player_kills_by_peer`, contract-complete flag), re-links hunters,
- ends the match when `_alive_count() ≤ 1` (`_end_match("last_standing")`).

**Winner ≠ last survivor.** `_end_match` ranks **all** players by total score (ties broken by lower average
exposure); the highest score wins even if they died. Scoring spine (`_score_for_peer`): `(100−avgExposure)×exposure_weight`
+ speed bonus (bleeds with time) + `npc_kills×kill_points` + `player_kills×player_kill_points` + `contract_bonus` − `death_penalty`.

> This is the loop a respawn-based mode inverts. The pieces a respawn mode must add/replace: a respawn trigger on
> death (instead of `_dead_by_peer` being terminal), a per-life reset of exposure/tools/arrow, a spawn picker
> (§8), a grace period, and keeping the ring whole across deaths (§5). Everything should sit behind a **feature
> flag** (§11) so it A/B's against this elimination loop.

---

## 7. Spawning (current) & the spawn-time identity risk

- **Player spawns:** `_spawn_position_for_index(i)` → `map.get_player_spawns()[i]` (authored per map in
  `test_map_01.gd:159`), assigned by **shuffled index**. Fallback staggers along x if the map has none.
- **No safety/relevance weighting today.** There is no "spawn in the crowd," no "away from your killer," no
  density query at spawn. A respawn picker is net-new.
- **The crowd has a queryable density method already:** `CrowdManager.count_npcs_near(world_pos, radius)`
  (host-side, O(n) over NPC children — no spatial index, fine at 55–78 NPCs). A density-weighted spawn picker can
  call this directly; it does not need new plumbing, only a candidate-point set to score.

> **LANDMINE — identity leak is worst at spawn.** A freshly-spawned player is a known-new entity that hasn't
> blended (see §9). Any respawn placement must drop the player *into* crowd density and respect the position-source
> rules below, or new lives are trivially spottable.

---

## 8. Position & identity replication (the leak)  ⚠

**The split:** players replicate through a host-owned `_net_position` (clients interpolate toward it via
`remote_follow_per_second`); NPCs are moved by the host and their raw `position` is replicated by the spawner.
Both players and NPCs spawn with a `"pos"` field, so *position* alone is not the tell — but:

- **`controlling_peer_id` / `player_id` are stamped on each player at spawn and replicated.** That is a direct,
  over-the-wire "this body is human, owned by peer N" marker. Anyone inspecting the replicated scene can separate
  players from NPCs. **This is the core identity leak.** (Report-only — do not refactor it as a side effect of a
  feature; it needs its own pass.)
- **Per-viewer crowd reskin is local-only.** `_apply_morph` / the per-viewer pass rebuild *your* screen's crowd
  from copies of **other** players' looks + filler, explicitly excluding your own look, so on each screen the
  humans blend into look-alikes. But this runs **after** replication, **on the local machine**, and never touches
  the wire. The replicated truth (peer ids, host's crowd roll) is unchanged.
- **Reveals are deliberate, targeted leaks:**
  - **Red plate** (`_receive_target_reveal`, owner-only): the *first* player to finish their marks is shown their
    target's body index — a reward, sent only to them.
  - **Blue plate** (`_receive_exposure_reveal`, to every living *other* peer): when a player crosses 100 exposure,
    their look is revealed once. `_revealed_look()` returns `-1` ("?") if they're currently disguised, and reveals
    are re-sent when disguise toggles so plates always match current disguise state.

---

## 9. Crowd replication & bandwidth

- Host spawns the crowd (`_spawn_crowd`, host-only): `compact_npc_count` (55, small arenas) or `npc_count` (78),
  each NPC's **whole look rolled once** into a compact loadout payload (ids only) and replicated verbatim by the
  spawner — *near-zero ongoing bandwidth* for appearance. `traveler_fraction` (0.25) cross the map; the rest are
  homebodies with a random `wander_radius`.
- Clients **freeze** crowd AI; the host simulates movement and pushes positions (`net_send_interval` 0.05 =
  20 Hz; clients smooth via `remote_follow_per_second` 18). NPCs equal player blend-walk speed (90px/s) and have
  **no collision** with actors — blending is the player's job, not the NPCs'.
- **No per-frame appearance replication, no per-NPC state spam.** This is the "bandwidth-optimized crowd netcode"
  the cosmetic spec must stay compatible with.

---

## 10. Tools / abilities over the wire

Two tools per player (lobby pick), fired by `item_primary` / `item_secondary`. Pool: **SMOKE, DISGUISE, MORPH,
DECOY, POISON** (`ItemComponent`). Online flow: client press → `item_requested` signal → `Player` relays to host
with the highlighted ring target → host `server_activate()` validates and applies the world effect, then pushes
authoritative tool state back (`_receive_item_state`: tool, charges, cooldown, active-left). Each tool is
charge-based, most have a cooldown, and **using one pays committed exposure** (10/14/16/8/12) — server-side, so it's
authoritative. There is **no mid-match ability upgrade / progression system today** (the `earned_read` experiment
is the only "earn a one-shot ability" precedent).

---

## 11. The feature-flag gate (how to A/B a new mode)

`ExperimentFlags` (autoload) is the established pattern for gating mechanics: a flat list of `@export bool` flags,
each defaulting such that **all-false = the base game runs exactly as before** (the "delete test"). Each experiment
node early-returns unless its flag is true, runs its real logic **only on the host**, and sends cues to clients
(clients render cues regardless of their own flag — you only flip flags on the host). Current flags: `whiff_recovery`
(on), `crowd_thinning` (off), `earned_read` (on), `mutual_proximity` (off), `crowd_reaction` (on), `behavioral_flag` (on).

**A new respawn mode / PvE ladder should add flags here** (e.g. `respawn_mode_enabled`, `pve_ladder_enabled`,
`density_spawn_enabled`) so it can be toggled host-side and fun-tested against the current elimination loop without
forking the code.

---

## 12. RPC reference (online_match.gd + components)

Authority/reliability shorthand: `auth`=host→peers, `any`=client→host, `local`=runs on caller too, `own`=owner-only.

| RPC | Dir / mode | Purpose |
|---|---|---|
| `_begin_match` | auth, local, reliable | all peers load the match scene + record map |
| `_request_spawn` | any, reliable | client handshake; host runs `_maybe_begin_match` |
| `_submit_loadout` / `_submit_tools` / `_submit_nickname` | any, reliable | lobby data → host (once) |
| `_start_round_countdown` | auth, local, reliable | "3/2/1/GO" + start freeze |
| `_receive_target` | auth, local, **own** | tells a peer their hunt target's node name |
| `_receive_marks` / `_notify_mark_down` / `_enter_hunt_phase` | auth, local, **own** | per-peer contract progression |
| `_receive_hunted` | auth, local, **own** | "you are now being hunted" (HUD red) |
| `_receive_exposure` / `_receive_opponent_exposure` | auth, local, **own**, unreliable | authoritative exposure to HUD / arrow |
| `_receive_target_reveal` / `_receive_exposure_reveal` | auth, local, **own** | red / blue identity plates |
| `request_kill` (KillComponent) | any, local, reliable | **the kill request** → host validates |
| `_freeze_player` | auth, local, reliable | freeze a corpse on all screens |
| `_receive_eliminated` | auth, **remote**, reliable | death screen → loser enters spectate |
| `_relink…`/`_send_target_to` (via `_receive_target`) | auth, **own** | re-point a hunter after their target dies |
| `_receive_roster` | auth, local, reliable | ~1 Hz live roster (names, scores, colours) |
| `_spawn_smoke_cloud` / `_apply_morph` / `_set_opponent_arrow_suppressed` | auth, local, reliable | tool/disguise world effects |
| `_receive_item_state` | auth, local, **own** | authoritative tool charges/cooldown |
| `_declare_match_over` / `_request_rematch` / `_do_rematch` | auth/any, local, reliable | scoreboard, rematch votes, back to lobby |

---

## 13. Key tunables (online_match.gd unless noted)

Crowd: `compact_npc_count` 55, `npc_count` 78, `traveler_fraction` 0.25, `clone_crowd_fraction` 0.25,
`per_viewer_crowd_enabled` true, `placeholder_distinct_bodies` false, `crowd_panic_radius_px` 560,
`crowd_panic_seconds` 6, `crowd_panic_speed_scale` 2.2.
Contract: `marks_per_player` 2, `mark_wander_radius` 220, `mark_min_separation` 1400.
Round/scoring: `round_time_limit` 300, `round_start_countdown` 3, `exposure_weight` 5, `speed_bonus_cap` 500,
`speed_bleed_per_second` 2, `kill_points` 100, `player_kill_points` 1000, `contract_bonus` 500, `death_penalty` 300,
`spectate_camera_speed` 900, `rooftop_sees_rooftop` true.
Kill (`kill_component.gd`): `kill_range` 90, `prime_range` 520, `prime_cone_degrees` 70, `lose_range` 800,
`kill_exposure_spike` 22, `wrong_commit_exposure` 40.
Exposure (`exposure_component.gd`): `run_rise_per_second` 28, `erratic_rise_per_second` 18, `walk_fall_per_second` 16,
`idle_fall_per_second` 8, `erratic_angle_threshold_degrees` 75. Movement part recovers; committed part is a permanent floor.

---

## 14. Known issues / landmines (carry these into any new-mode plan)

1. **Three kill versions** (online blade, online poison, offline) with real behavioural differences (§4). Hook new
   logic into the **online authoritative** path; flag the others, don't unify in a feature pass.
2. **Over-the-wire identity leak** via `controlling_peer_id` on players; per-viewer reskin only masks it locally
   (§8). Worst at spawn (§7). Needs its own pass — report, don't silently "fix."
3. **No safety/relevance-weighted spawn picker** — current spawns are authored points by shuffled index (§7). The
   density query (`count_npcs_near`) exists; the picker does not.
4. **Current loop is elimination, not respawn** (§6). A respawn mode replaces the terminal `_dead_by_peer`
   handling, adds per-life reset + grace + the density spawn picker, and keeps the ring whole across deaths.
5. **Exposure / tools / arrow have no per-life reset path** because nothing respawns yet — a respawn mode must add one.

---

*MULTIPLAYER_PLAN v1.0 — 2026-06-29. Reverse-engineered from code as ground truth. Update this whenever the
authoritative match flow changes.*
