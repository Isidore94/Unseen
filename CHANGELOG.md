# UNSEEN — Changelog

Short, session-by-session log so we never lose the thread between sessions.

## Phase 7 — Playtest refinement (started)  ·  buildplan.md

### Session: 7-online — verifying the integration (two server-authority fixes)
Reviewed the online port (slices A–E) for server-authority + hidden-identity correctness. The
architecture held up; found and fixed two authority gaps:
- **Smoke now actually stops a CLIENT from killing (§7.6).** Smoke sets `attacks_disabled` on the
  HOST's copy of the killer's `KillComponent`, but that flag isn't replicated, so a client's own
  copy never learned it — and the host's `KillComponent.request_kill` never re-checked it. A smoked
  client could still land a kill. Fix: `request_kill` now refuses while `attacks_disabled` (one
  guard, on the only machine whose answer counts). Offline + host-player paths were already correct.
- **Claiming an access point is now independent of the transit cooldown (§7.3, note 5b).** The
  offline `_try_claim` only blocked if a point was already owned, but the online `_request_claim`
  also rejected points on their 15s global cooldown — so you couldn't claim a point right after
  using it. Made online match offline: the 15s lockout governs UNCLAIMED pass-through only; claiming
  is permanent ownership bought with exposure and ignores the cooldown.

### Session: 7-online — porting Phase 7 onto the ONLINE match (server-authoritative)
Phase 7 was built/tested on the OFFLINE split-screen path; online (`online_match.gd`) was
still Phase 6. Online is the primary test surface (each player on a separate machine = a true
hidden view), so we're porting the features there in slices (plan: 5 slices, A–E). Each slice
is server-authoritative (host owns truth, clients send intent) and independently testable
across a host + a 127.0.0.1 client.

- **Slice A — quick wins (§7.0):**
  - **Camera zoom online:** new `Player.network_camera_zoom` (`@export`, default 1.1) applied to
    the locally-controlled player's embedded camera in `_setup_network_role`. Offline split-screen
    (its own follow camera) is untouched.
  - **Teleporter exposure cost:** confirmed it ALREADY fires online — the host applies the portal's
    `exposure_cost` (the map sets it = `teleporter_cost`) and clients have portal monitoring off, so
    only the host (referee) teleports + charges. No code change; verified by reading.
  - **Two marks per peer:** `online_match._assign_mark_for_peer` now designates `marks_per_player`
    (=2) crowd NPCs via `_pick_spaced_marks` (≥ `mark_min_separation`, ~2 screens apart), forces each
    into a homebody (`is_traveler=false`, small `mark_wander_radius`), tells the owner BOTH names
    (`_receive_marks`), and opens the hunt phase only after both die (`_marks_remaining_by_peer`). The
    owner is told per-mark when one dies (`_notify_mark_down`) so the client drops its highlight and
    the mini-map re-points at what's left.
- **Slice B — per-viewer VISIBILITY, the hidden view (§7.2b/§0.3):** `online_match._update_visibility()`
  runs per frame and toggles each character's `visible` for THIS machine from the host-replicated layer
  (`LayerComponent.current_layer`, mirrored from `_net_layer`): GROUND sees ground only; ROOFTOP sees the
  ground below (+ other rooftops, `rooftop_sees_rooftop` default on); SEWER sees no one. Local-only — it
  never touches the host's sim, so it's a true hidden view (each peer is a separate machine). Ported the
  sewer screen overlay + arrow 100% uptime (`_build_layer_feedback` / `_on_local_layer_changed`).
- **Slice C — claim + global cooldown, server-authoritative (§7.3):** `player._try_claim` routes to the
  host (`_request_claim` RPC — host finds the point you're on, validates, charges 20% committed exposure).
  Access-point USE is host-validated in `_request_set_layer` (right kind + available + correct transition →
  `mark_used()`), so the 15s global lockout is host-owned. New `AccessPoint.access_index` + `claim_changed`/
  `cooldown_started` signals; the host broadcasts via `OnlineMatch._apply_access_claim`/`_apply_access_cooldown`
  so every client's marker shows claimed/cooldown. (Late-joiner snapshot of claim state = a known small gap.)
- **Slice D — items smoke + cloak, server-authoritative (§7.6):** `ItemComponent` split into `local_input`
  (reads keys) / `server_authoritative` (owns charges + timers) / `network_mode`. The controlling client
  emits `item_requested` -> `player._request_item` RPC -> host `server_activate`. Smoke sets the player's
  replicated `_net_smoked` (others hide it via Slice B; smoker sees self) + disables their kill; cloak makes
  the host suppress the OPPONENT's hunt arrow (`_set_opponent_arrow_suppressed`, targeted) while the exposure
  arrow still fires. Charges readout pushed owner-only (`_push_item_state_to` / `_receive_item_state`).
- **Slice E — identity reveals + faceplates (§7.4):** `FaceplateRow` built per machine. RED = first peer to
  finish its marks is told its target's appearance (`_begin_target_phase` -> `_receive_target_reveal`, once).
  BLUE = a player hitting 100% exposure reveals their look to the others (`_on_player_exposure_changed` ->
  `_receive_exposure_reveal`, once each). Reveals are targeted owner-only RPCs carrying an appearance index.
- **Compiles clean** (headless full-project boot, rc=0). **Untested in live play** — built on the integration
  branch `phase-7-online-integration` for a 2-instance playtest. Deferred (next pass): §7.5 N-player
  last-standing + rematch online, and the §0.3 per-viewer APPEARANCE swap.

### Session: 7.2–7.6 — layers, items, claim/cooldown, match flow, reveals (v0.7.0)
A full methodical pass over the rest of the Phase 7 plan. Built logic-first and committed
phase-by-phase; **all of it is UNTESTED in-editor** (no Godot on the build machine) — the
next step is a play-test. New reusable components per "components, not god-scripts."

- **7.0 (rest):** `marks_per_player` → 2; ContractManager forces marks HOMEBODY when tagged
  and picks them `mark_min_separation` (~2 screens) apart.
- **7.2 layers — rooftops & sewers (`LayerComponent`, `AccessPoint`):** GROUND/ROOFTOP/SEWER
  per character; stairs/entrances spawned by the map; `interact` climbs/enters, `drop_down`
  leaves a rooftop. Kill rules = same-layer only, sewer = no-kill. Sewer = 100% arrow uptime
  + a darkened own-view overlay. Bodies tinted per layer. New Input Map actions (interact/
  drop_down/item_primary/item_secondary, base+p1+p2, keyboard+gamepad). **Built with tints,
  NOT real per-viewport culling** — that's the deferred rendering pass (build plan step 2).
- **7.3 claim + cooldown:** access points + the teleporter pair share a 15s global lockout;
  `action_secondary` claims a point for the match (pays 20% committed exposure). Offline.
- **7.4 reveals + faceplates (`FaceplateRow`):** red plate = your target's look (first to
  finish marks), blue plates = opponents who hit 100% exposure.
- **7.5 match flow:** winner = MOST POINTS (a death only ends the round); tie-break = lowest
  average exposure. `win_bonus` → `contract_bonus` (no longer circular). "Rematch" button.
- **7.6 items (`ItemComponent`):** 2 charge-based slots — smoke grenade (fade + can't attack)
  and cloaking device (kills the opponent's hunt arrow on you; exposure arrow still fires).
- **Bumped `config/version` → 0.7.0.**
- **Known limitations / TODO (be honest with the play-test):** real per-viewer visibility
  culling (§0.3/§7.2 step 2) is NOT built — smoke/sewer/rooftop use shared-world tints, so
  both viewers see them; ONLINE paths for claim, items, and N-player last-standing are stubs/
  TODOs (offline local co-op is the tested surface). Everything is `@export`-tunable.

### Session: 7.1 — the four-zone main map + first quick wins
- **`scripts/test_map_01.gd` reworked into the FOUR-ZONE main map** (buildplan §7.1,
  incorporating the concept I mocked up). The default map is now a tight city arena
  split into four corner ZONES around the central fountain:
  - **NW + SE = "street + rooftop"** (paired on a diagonal): long parallel buildings,
    tight one-cell N–S streets, a single mid-alley → long sightlines. Marked with the
    rooftop-stair locations (orange ▲).
  - **NE + SW = "sewer"**: more open, scattered blocks. Marked with sewer-entrance
    locations (green grates).
  - A 1-cell **hub cross** of streets joins all four to the fountain.
- **Tighter main roads (your note):** denser 25×19 grid → 1-cell streets are genuinely
  tight, but the arena stays the same size so the crowd still spreads.
- **Zones are derived from grid position** (`_cell_zone`), so floor colour and access-point
  placement come free from the layout. Per-zone muted floor colours read as four distinct
  corners while keeping characters readable (Pillar #6). All colours are `@export`.
- **Access-point locations exposed for §7.2:** `get_rooftop_stairs()` / `get_sewer_entrances()`
  (placed farthest-first, off the perimeter ring). Drawn as greybox markers only — NO layer
  mechanics yet (the build plan says build geometry first, add layers on top).
- **Teleporters now TOP ↔ BOTTOM** (note 2), still costing exposure (note 10). Trapdoor +
  a FREE underground passage linking the two sewer corners round out the portals.
- **Spawns** = the four ring corners (far apart, note 12); **marks** = one per quarter,
  farthest-first so any two are screens apart (note 13).
- **`_verify_connectivity()`** flood-fills at runtime and warns if a future LAYOUT edit
  walls off a pocket (the flood-fill guarantee, now a live tripwire). Offline generator +
  preview in scratchpad confirmed 0 unreachable cells before commit.
- **Camera zoom quick win (note 1):** local co-op `camera_zoom` 0.85 → 1.1 (tighter view
  suits the tighter map). Pure feel — still `@export`.
- Public API (`get_player_spawns/_mark_locations/_teleport_pads/_portal_links/
  _building_rects`) unchanged, so crowd / contract / mini-map / online all keep working.
- **Not done yet (awaiting in-editor test):** the layer mechanics (§7.2), 2-marks-per-player
  contract change (§7.0), and the per-viewer rendering system (§0.3).

## Phase 6 — Online multiplayer (started)  ·  version 0.6.0

### Session: 6.2 — crowd netcode + compact arena (host perf) (v0.6.5)
- Test result: prediction is working (player movement smooth both ways). The remaining
  problem is the **crowd as seen by the JOINER when the host has a weaker uplink**: the
  host simulates NPCs locally (so the host's own view is fine), but pushing 180 NPCs ×
  ~60 updates/sec over the wire starves the joiner's copy → the joiner sees a laggy
  crowd. Fixed by slashing the crowd's upload cost.
- **`npc.gd` — throttled + interpolated crowd replication** (same shadow-field pattern as
  the player): NPCs now publish `_net_position`/`_net_velocity` at `net_send_interval`
  (0.05s = 20/sec, was every frame) and clients **interpolate** toward them
  (`_follow_net`, `remote_follow_per_second`) instead of snapping. Net effect with the
  count drop below: roughly **~75% less crowd upload** AND smoother NPCs. Clients no
  longer freeze NPC processing — they run a cheap follow-lerp only.
- **`npc.tscn`** avoidance eased to cut host CPU per agent: `neighbor_distance` 220→170,
  `max_neighbors` 12→8.
- **Compact arena (your request):** new `maps/test_map_02.tscn` reuses the WHOLE
  `test_map_01.gd` via a new `layout_override` export — same features (solid ring, inner
  road, building blocks, central fountain) on a 9×7 grid, ~62% less area. Portal spawns
  now skip any endpoint that lands in a wall, so the script is layout-agnostic. The
  **lobby has a host "Compact arena" checkbox**; the choice rides the `_begin_match` RPC
  into `NetworkManager.small_arena`, and the match picks the small map + `compact_npc_count`
  (120). Verified: both maps build at runtime, all scripts compile, offline boots.
- Bumped `config/version` → **0.6.5**.

### Session: 6.2 — prediction fix: input replay (v0.6.4)
- The v0.6.3 prediction *eased* toward the host's position every frame, but that
  position is always latency-old, so it **fought** the prediction — "wall on start,
  glide on stop" (felt worse than before). Replaced the easing with proper
  **input-replay reconciliation**.
- **`player.gd`:** each input now carries a sequence id (`_input_seq`); the owner keeps
  the un-acked ones in `_pending_inputs`. The host echoes the last id its position
  reflects (`_net_ack_seq`, replicated alongside `_net_position`/`_net_velocity`). When
  a fresh host snapshot arrives, the owner drops acked inputs, **snaps to the host's
  position, and replays the rest on top** — landing exactly where prediction had it,
  with zero tug toward the stale position. Between snapshots it just predicts forward.
  Teleports/knockbacks fall out for free (replay starts from the host's new position).
- Removed the old easing tunables (`reconcile_per_second`, deadzone, snap distance);
  kept `remote_follow_per_second` for non-owned characters.
- **Added an in-match network debug overlay (toggle F3)** so internet tests give real
  numbers instead of "it's laggy": shows role, FPS, **ping** (round-trip, measured by a
  twice-a-second timestamp bounce in `network_manager.gd` → `ping_ms()`), and **pending
  predicted inputs** (`player.get_pending_input_count()` — a connection-health proxy:
  steady single digits = healthy, a growing number = congestion/loss).
- Parse + offline boot + in-project compile of all touched scripts verified. Bumped
  `config/version` → **0.6.4**.

### Session: 6.2 — client-side prediction (own-avatar input feel) (v0.6.3)
- **Fixed laggy own-character input over the relay.** Movement was fully
  server-authoritative: you pressed → host moved you → position came back → you
  saw it (one round-trip of input delay over real internet). Added the planned
  **local prediction** feel pass (MULTIPLAYER_PLAN.md §2) WITHOUT going
  client-authoritative (which would leak who's human — the load-bearing rule).
- **`player.gd`:** the host still simulates every character and is the authority,
  but now publishes each character's truth into replicated `_net_position` /
  `_net_velocity` (the synchronizer ships those instead of the live `position`, so it
  no longer fights local prediction). On a client:
  - **your own** character runs `_predict_local()` — it moves from your input the same
    frame (instant), then eases toward the host's position (deadzone so it doesn't
    micro-tug; snaps past `prediction_snap_distance_px` for teleports/knockbacks);
  - **everyone else's** character runs `_follow_server()` — smoothly lerps toward the
    host's latest position + copies velocity for the visual.
  - Exposure stays host-owned: prediction calls a new movement-only `_move_with()`
    (split out of `_apply_movement`) so the client never double-counts exposure.
  - New tunables: `reconcile_per_second`, `prediction_deadzone_px`,
    `prediction_snap_distance_px`, `remote_follow_per_second`.
- **NOTE (future hardening):** players now replicate `_net_position` while NPCs still
  replicate raw `position` — a minor property-name difference a cheater could read.
  It's dwarfed by the existing player-vs-NPC scene differences; unify both when we do
  the real "indistinguishable on clients" anti-cheat pass. Core rule intact: uniform
  server authority (peer 1), clients send input only, prediction is purely local.
- Parse + offline-scene boot verified; real feel needs a 2-machine relay test.
- Bumped `config/version` → **0.6.3** (so the menu shows which build has prediction).

### Session: 6.2 — Steam relay transport + friend invites (v0.6.2)
- **Verified the GodotSteam build first** with a throwaway probe: it exposes
  `SteamMultiplayerPeer` (`create_host`/`create_client`/`getLobbyOwner`/…) and the
  lobby + invite functions, and inits fine (`ready as <persona>`). So the relay
  transport is fully available — no extra add-on needed.
- **`network_manager.gd` gained the Steam transport**, sitting behind the same clean
  signals as ENet so the lobby/match code is untouched:
  - `host_steam()` → `Steam.createLobby(friends-only)`; on `lobby_created` it stamps
    the host's Steam id into lobby data and builds a host `SteamMultiplayerPeer`.
  - `join_steam(lobby_id)` → `Steam.joinLobby`; on `lobby_joined` it reads the lobby
    owner and builds a client peer to them.
  - `invite_friends()` → opens the Steam overlay invite dialog; `join_requested`
    (friend accepts) auto-joins.
  - New signals `steam_lobby_ready` / `steam_lobby_failed`; `steam_lobby_code()` /
    `is_using_steam()` for the UI; `leave()` now also leaves the Steam lobby.
  - **Parse-safe:** the peer is built via `ClassDB.instantiate("SteamMultiplayerPeer")`
    (never named directly), so the script still loads in stock Godot.
  - **Bug caught in testing:** Steam fires `lobby_joined` for the lobby *creator* too,
    which was overwriting the host peer with a client one (self-connect errors). Now
    we ignore `lobby_joined` when we're the lobby owner.
- **`main_menu.gd`:** when Steam is up, shows **Host online (invite friends)** +
  **Join by code**; always keeps **Host (LAN)** / **Join IP** for local testing.
  Waits for `steam_lobby_ready` before entering the lobby (lobby creation is async).
- **`lobby.gd`:** the host on Steam gets an **Invite friends** button (overlay) and a
  **Copy join code** button, and the code label shows the Steam lobby id.
- **Tested:** host path drives end-to-end on one machine (lobby created, peer id 1,
  `is_host=true`); boots clean in BOTH stock Godot (Steam off → LAN-only menu) and the
  GodotSteam editor (Steam on). Real 2-machine join still needs a friend/2nd account.
- Bumped `config/version` → **0.6.2**.

### Session: Map redesign — tight alleys + central fountain plaza
- **`scripts/test_map_01.gd` relaid out** to a denser **15×11** grid (was 7×5).
  A **solid building ring hugs the outer wall** (no open border — buildings start
  ~120px from the wall instead of ~510px, the thing that felt too empty), an inner
  ring road runs just inside it, and a tight one-cell alley grid carves chunky
  2-wide building blocks. Alleys narrowed from ~685px to ~320px; the map is now 46%
  open (was 70%).
- **Central fountain plaza:** the dead centre opens into a wide plaza/avenue with a
  new **`'F'` cell type** = a solid circular fountain (`fountain_radius`, drawn as a
  stone basin + water + spout). New `_is_solid()` (building OR fountain) feeds nav +
  walkability so nobody paths into the basin; the fountain cell is fully excluded
  from navigation and its collision circle sits safely inside that empty cell.
- **Connectivity verified before committing** via a flood-fill script: one connected
  network, all four player spawns open, zero dead ends.
- Feature positions moved to valid cells (spawns at near-corner alley junctions,
  marks on the central avenue, teleport pads on the inner ring mid-sides, density
  zone = the plaza). The three Portal pairs re-pointed to open cells.
- Headless `--check-only` parse passes. **NEXT:** convert the underground passage to
  the single-occupancy outer-alley connector with two-way "someone's in there"
  messaging.

### Session: 6.2 — lobby + start gate (v0.6.1 merged to main first)
- Merged the full online match to `main` and tagged **v0.6.1**.
- **`scripts/lobby.gd` + `scenes/lobby.tscn` (new):** a waiting room between menu and
  match. Host/Join now land here. Shows the player roster (n/MAX) and, for the host, a
  **Start button that's disabled until `MIN_PLAYERS_TO_START` (2)** are present. Host
  start does `_begin_match.rpc()` so all peers load the match together. Shows the host's
  LAN IP as a join code (internet code via Steam comes next).
- **`online_match.gd` readiness gate:** because the lobby makes all peers transition at
  once, the host now waits until every expected client reports its scene ready
  (`_request_spawn`) before spawning ANYTHING — players, crowd, and marks are all spawned
  together in `_maybe_begin_match`, so no spawn outruns a client's spawners. Added a
  client-side `_request_spawn` retry as a belt-and-suspenders.
- **`main_menu.gd`:** Host/Join route to the lobby instead of straight into a match.

### Session: 6.1 — networked crowd + private marks (in progress, on `phase-6-online`)
- **6.1a crowd:** `npc.gd` gained online mode — host runs the wandering AI, clients show
  a replicated puppet (code-built `MultiplayerSynchronizer`, position+velocity). A second
  `CrowdSpawner` in `online_match.gd` spawns `npc_count` NPCs with shared appearance.
- **6.1b private marks + per-client mini-map + highlight:** host secretly picks a random
  crowd NPC as each peer's mark (`killable_for_<peer>` + "mark") and tells ONLY that peer
  (owner-only RPC of the mark's node name). Each machine builds its own HUD: a mini-map
  (you + gold mark dot, reused `mini_map.gd` via new `track_objective()`) and a gold
  highlight ring on the mark — drawn ONLY on the owner's screen, so the split-screen
  highlight leak is gone online. Lazy per-frame resolution avoids spawn/RPC races.
- **6.1c server-validated kills + private exposure bar:** the kill component gained an
  online path — on the controlling machine it picks the suspect in front (within range)
  and sends `request_kill(target_path)` to the host; the host re-checks sender, range,
  and whether the target is in `killable_for_<peer>`, then kills the mark or applies a
  wrong-commit exposure penalty (never client-trusted). Host relays each player's
  exposure to its OWNER only (`exposure_changed` → owner RPC → private bar). Killing
  your mark shows "Mark eliminated".
- **6.1d PvP endgame (full loop):** killing your mark now moves you to the "target"
  phase — the host makes your human opponent killable by you and privately tells you
  who they are. Your view switches to PvP tracking: the mini-map shows delayed **pings**
  (`track_objective_pinged`) and a fading **exposure arrow** points at them when they're
  exposed (host forwards the opponent's exposure to you — the §7.1 reward). Killing your
  target ends the round: the host declares the winner and every machine shows a
  **YOU WIN / YOU LOSE** end overlay (pause + back-to-menu). Returning to the menu now
  clears pause. Offline split-screen path unchanged.
- **6.1e tracking redesign (replaces opponent pings with arrows):** dropped the
  mini-map opponent pings. Your opponent is now known from match start (owner-only),
  and an **exposure arrow** tracks them: a steady arrow whenever they run past 50%
  exposure and are off-screen (host forwards each player's exposure to their opponent),
  fading on view transitions. Once your mark is dead, the same arrow flips to a
  **flashing** style (`set_flashing`) that pulses toward them every ~2.5s when
  off-screen, ignoring exposure. `exposure_arrow.gd` gained the flashing mode +
  `_compute_offscreen_arrow` split; mini-map keeps only self + the gold mark dot.
- **6.1f crowd + map + mini-map tweaks:** crowd tripled (`npc_count` 30 → 90); map play
  area enlarged (`play_half_width/height` → 2400/1750, ~2.5× area) so the bigger crowd
  spreads out instead of clumping. Mini-map now draws the **teleporters/passages
  colour-coded** — each pair shares a colour with a thin line linking its two ends
  (`test_map_01.get_portal_links()` + mini-map drawing).
- **6.1g crowd behaviour + 180 NPCs:** fixed the whole crowd drifting to the centre
  (wander used the nav server's origin-biased random point → now uses the map's even
  sampler). Added two NPC types: **homebodies** (most of the crowd) that make short
  trips around their spawn (`random_walkable_point_near`), and **travelers**
  (`traveler_fraction`, ~25%) that cross the map and spawn from the edges
  (`random_edge_walkable_point`). Bumped `npc_count` to 180 (FPS headroom).
- 6.1 complete pending verification → then merge `phase-6-online` to `main` + tag v0.6.1.

### Session: 6.0 loopback spike (ENet) + versioning
- **Plan:** added `MULTIPLAYER_PLAN.md` — the detailed netcode plan (server-authoritative
  listen-server, clients send INPUT only, uniform server authority to hide who's human,
  ENet-loopback first then Steam relay). Read it before touching netcode.
- **`scripts/net/network_manager.gd` (new, autoload):** connectivity only — host/join over
  ENet, clean `player_joined`/`player_left`/`connection_*` signals. Transport is isolated
  here so Steam relay can slot in at 6.2 without touching the game.
- **`scenes/main_menu.tscn` + `main_menu.gd` (new):** the new default scene — Host / Join /
  Local-AI-test (the kept split-screen). Shows the build version bottom-left.
- **`scenes/online_match.tscn` + `online_match.gd` (new):** networked run shell. Builds the
  map locally on each peer; host spawns one character per player via `MultiplayerSpawner`;
  host/client `_request_spawn` handshake avoids spawn races. Portals disabled on clients
  (host-authoritative). 6.0 scope = players only (no crowd/kills yet).
- **`scripts/player.gd`:** added server-authoritative ONLINE mode (`network_controlled`).
  The controlling machine reads input and `rpc`s it to the host; the host moves every
  character; a `MultiplayerSynchronizer` (built in code) replicates position+velocity to
  all. Offline path unchanged. Kill component disabled online until 6.1.
- **`scripts/portal.gd`:** joins group `"portal"` so clients can switch teleporting off.
- **`project.godot`:** registered the `NetworkManager` autoload; default scene → main menu;
  added `config/version="0.6.0"` as the single source of truth for the build number.
- **Test:** Debug → Run Multiple Instances (2); F5; one window Host, one Join 127.0.0.1;
  both characters should move in sync.

## Phase 4 - Local two-player fun test (started)

### Session: Character sprite sheets + crowd avoidance + mark highlight
- **Sprites in (`character_visual.gd` rewritten):** the greybox circle is gone.
  CharacterVisual now builds a `Sprite2D` in code and renders one of 5 sheets
  (villager/merchant/guard/mage/townswoman, 32px frames, 4x4 grid). It picks the
  facing ROW (down/up/left/right) from the parent's velocity and steps the walk
  COLUMN while moving (NEAREST filtering for crisp pixels). Player + every NPC get
  a random sheet on spawn.
- **Appearance is data, not identity (cosmetics-ready):** look is set via
  `set_appearance(index)`, not baked in. `randomize_on_ready` self-assigns for now;
  a `## FUTURE` seam marks where the online per-viewer system (show each player the
  OTHER players' looks, never their own) will drive it instead. Keeps Pillar #1.
- **Crowd avoidance (`npc.gd` + `npc.tscn`):** NavigationAgent2D avoidance turned ON
  (was off — the cause of clumping). Movement now routes desired velocity through
  the agent (`set_velocity` → `velocity_computed` → move), so NPCs steer around each
  other instead of piling into a blob. Agent `radius=40`, `max_speed=90`.
- **Wall clipping fix (`test_map_01.gd`):** `solid_clearance` 45 → 60, so a body on
  the nav edge keeps ~24px of air before a wall and avoidance jostling can't shove
  it through a corner.
- **Mark highlight (`contract_manager.gd` + `character_visual.gd`):** your mark gets
  a pulsing gold ring via `set_highlight(true)`. KNOWN LIMIT: drawn in the shared
  world, so split-screen opponents can also see it — private-view fix (per-viewport
  canvas cull mask, the same tech cosmetics needs) is the planned follow-up.
- **Cleanup:** `npc.tscn` pointed at a stale CharacterVisual UID (resolved by path,
  logged a warning each load) — corrected to `uid://f287ld01dvlg`.

### Session: Random marks + per-player mini-map + tracking pings + lock HUD
- **Random predetermined mark:** `contract_manager.gd` no longer spawns a stationary
  mark — at round start it secretly designates a RANDOM wandering crowd NPC (from
  the "npc" group) as your mark (killable_for_N + "mark"). Each player gets a
  different one. `npc.gd` joins group "npc". Exposed `get_objective()` / `get_phase()`.
- **Per-player mini-map (`scripts/mini_map.gd`, new):** a private HUD map in each
  player's viewport. PvE → a live dot tracks your wandering mark; PvP → the opponent
  is revealed only as a periodic PING (every `ping_interval`) — intel with delay,
  the §7.1 reward for finishing your mark first. Sketches buildings via the map's
  new `get_building_rects()`.
- **"Locked" indicator:** `kill_component.gd` emits `lock_changed`; each HUD shows
  "SUSPECT LOCKED" while you have a suspect locked.
- **`local_coop_game.gd`:** spawns a mini-map + lock label per player and wires them.

### Pending your verification (locator layer)
- Mini-map (top-right of each view) shows your dot + a gold dot for your mark
  (it moves — the mark wanders). Follow it, lock the right civilian, kill it.
- After your mark dies, the map switches to red opponent PINGS every few seconds.
- "SUSPECT LOCKED" shows on your HUD while a suspect is locked.

### Session: Aim & commit kill (suss-out targeting, controller-first)
- **`components/kill_component.gd` rewritten** from "press = kill nearest" to
  "press = LOCK the suspect you're facing":
  - `_best_suspect_in_front()` physics-queries nearby characters (player + npc
    layers) and locks the one most in front within `prime_range`/`prime_cone_degrees`.
  - As you approach, it auto-resolves at `kill_range`: a real target → clean kill
    (+`kill_exposure_spike`); a civilian → you misread and pay `wrong_commit_exposure`.
  - Lock drops if the suspect dies or gets past `lose_range` (a screen-leave proxy
    that works for both split-screen players without needing their camera).
  - Kept the co-op exports (`action_primary_action`, `valid_target_group_name`) and
    `kill_landed`, so the bootstrap/scoring still wire up.
- Chosen over literal mouse-click to fit the controller-first design (§13).

### Pending your verification (aim & commit)
- Face a mark and press the kill button to lock it, then walk in → it should
  auto-kill when you're close. Lock a civilian and walk into them → exposure spike,
  no kill. Walk far from a locked suspect → lock drops.
- STILL TODO (next): mouse-free is done, but no on-screen "locked" feedback yet,
  and reset uses distance not true off-screen.

### Session: Exposure arrow now fades (no more hard on/off)
- **`scripts/exposure_arrow.gd`:** the arrow no longer snaps on the instant a
  target leaves view (which revealed exactly who left). It now waits `appear_delay`
  (~2.5s) off-screen, then FADES in (`fade_in_time`), and fades out smoothly when
  on-screen (`fade_out_time`). By the time it shows, they've moved — a fuzzy hint,
  not a precise pointer. Public API (`track_target`, `arrow_color`, paths) unchanged,
  so the co-op HUD wiring still works.

### Session: Readability pass — facing direction, walk bob, strike feedback
- **Not the art phase** — greybox legibility so the social-stealth loop is actually
  playable/judgeable (you can't read a behaviour game when nobody has a face).
- **`scripts/character_visual.gd` (new) + `character_visual.tscn` rebuilt:** the
  shared body is now script-driven. It reads its parent's velocity each frame and:
  (1) points a "nose" wedge the way it's MOVING (facing — the big readability win),
  (2) bobs subtly while walking, (3) pops + flashes on a strike via `play_strike()`.
  Still one identical body for everyone (Pillar #1); all tunable via `@export`.
  Drives itself from velocity, so movement scripts stay untouched/decoupled.
- **`components/kill_component.gd`:** strike now calls `visual.play_strike()` instead
  of tweening scale (which would fight the per-frame bob/facing).

### Pending your verification (readability pass)
- Every character (you + crowd) should now visibly FACE the way it moves, bob while
  walking, and you can read a beelining player vs a wandering civilian. Killing
  should give a clear pop/flash. Confirm both co-op players read correctly.

### Session: Varied map + map-control features (trapdoor/teleporter/passage)
- **`scripts/test_map_01.gd` rebuilt** into a more varied souk-style greybox: a
  grid of cells driven by an editable `LAYOUT` pattern, with scattered buildings
  carving irregular alleys + small plazas around a central open plaza. Walkable =
  the OPEN cells (edge-connected → one navigation network, no dead ends). Kept the
  whole public API (`get_player_spawns` ×4 corners, `get_mark_locations` ×2,
  `get_teleport_pads`, `random_walkable_point`, "map" group, NavigationRegion2D),
  so the co-op bootstrap is unaffected. Clearance handled by shrinking buildings +
  pushing walls out (proven approach).
- **`scripts/portal.gd` (new):** one reusable "step here → appear there" Area2D
  that powers all three travel features (differ only by range/colour/cost):
  teleporter pads (cross-map, `teleporter_cost`), a trapdoor (medium hop,
  `trapdoor_cost`), and an underground passage (free). Bounce-back guarded via an
  arrivals-ignore list. Only "player"-group bodies travel; the crowd never does.
  Exposure cost rides the committed (permanent) door.
- The map spawns the portal pairs in `_ready()`. Works for both co-op players
  (shared World2D). **TODO (master_plan §8):** cast time, cooldown, the
  single-occupancy "something lurks" rule, and a use-tell are not built yet.

### Session: Local co-op split views
- **`scenes/main.tscn`:** now boots a Phase 4 local match through
  `scripts/local_coop_game.gd`.
- **Private views:** two side-by-side `SubViewport`s share the same world but use
  separate viewport-owned cameras and HUDs. This removes shared-camera
  omniscience for the test; true no-peek play still needs physical separation or
  a second-display/window pass later.
- **Two players:** `scripts/player.gd` now supports per-player Input Map action
  names. P1 uses WASD/Space/Shift or controller 0; P2 uses arrows/Enter/Ctrl or
  controller 1.
- **Independent contracts:** `scripts/contract_manager.gd` now supports
  per-player killable groups (`killable_for_1`, `killable_for_2`), one exposed
  mark per player for the quick test, then the other player becomes the valid
  target.
- **Round summary:** added `scripts/local_match_manager.gd` for two-player
  exposure sampling, kill counts, round end, and side-by-side scoring.
- **Exposure arrows:** `scripts/exposure_arrow.gd` now points each player toward
  the other player only when that target is over the threshold and off-screen.
- **Bugfix:** restored left-click as a P1 kill input for testing; the split-screen
  input pass had only kept Space/controller A for P1 kills.
- **Verification:** Godot 4.7 headless parse and a short main-scene run both
  completed without script/runtime errors.

## Phase 0 — Foundation (in progress)

### Session: Phase 0 implementation
- **Project layout:** Created `scripts/`, `components/`, `maps/`, and
  `assets/{sprites,audio,fonts}/` to match the build plan's folder structure.
- **Cleanup:** Removed the duplicate `scenes/game1.tscn`. Renamed the main scene
  `node_2d.tscn` → `scenes/main.tscn` (kept its UID so `run/main_scene` still
  resolves).
- **Player node (`scenes/main.tscn`):** Fixed three bugs from the starter scene:
  - `Polygon2D` now has a real 40×40 square (was empty/invisible).
  - `CollisionShape2D` reparented to be a direct child of `Player` (was wrongly
    nested under `Polygon2D`, so the body had no collider).
  - `RectangleShape2D` given a real 36×36 size (was zero-size).
  - Added a `Camera2D` child with position smoothing and a 1.5× zoom.
  - Motion Mode left as Floating (top-down, no gravity).
- **Input Map (`project.godot`):** Defined the abstract actions `move_up`,
  `move_down`, `move_left`, `move_right`, `action_primary`, `action_secondary`,
  `blend_walk` — each bound to BOTH keyboard and gamepad (Principle #2).
  WASD use physical keycodes so non-QWERTY layouts still work physically.
- **`scripts/player.gd`:** Walk/run movement via `Input.get_vector` +
  `move_and_slide()`. `walk_speed` / `run_speed` exported for tuning.
- **Display:** `stretch/aspect = keep`, windowed mode for dev.

### Pending your verification
- Open the project in Godot 4.7 and press Play. Confirm the test checkpoint
  (move with WASD + gamepad, blend key slows you, camera follows, no errors).
- After it passes, tag the commit `phase-0-complete`.

## Phase 1 — Exposure (in progress)

### Session: Exposure core + HUD meter (increment 1)
- **`components/exposure_component.gd` (new):** Reusable `Node` (class_name
  `ExposureComponent`) holding a 0–100 `exposure` value. `update()` raises it
  while running / moving erratically, lowers it while blend-walking or idle,
  clamps 0–100, and emits `exposure_changed`. All rates are `@export` tunables
  with units in their names. Reserved `exposed_alone_rise_per_second` (0 for now)
  for Phase 2 crowd-density wiring.
- **`scripts/hud.gd` (new):** `CanvasLayer` HUD. Listens to the player's
  ExposureComponent and updates a `ProgressBar`, tinting green→yellow→red.
  Component reference set via an `@export` NodePath (reusable for P4 split HUD).
- **`scripts/player.gd`:** Now computes `is_running` / `is_moving` and feeds its
  movement state to `ExposureComponent.update()` each physics frame. Renamed
  `_delta` → `delta` (now used). Exposure math stays OUT of the player (Principle #3).
- **`scenes/main.tscn`:** Added `ExposureComponent` under Player and a `HUD`
  CanvasLayer → `ExposureBar` (ProgressBar), wired the NodePath. Preserved the
  player resize done in-editor.

### Session: Movement control flip — walk is now default, hold to run
- **Design change:** Walking (blend-walk) is now the DEFAULT pace; the player
  holds a button to run. Reinforces "acting is exposing" — you're safe/blended
  by default and must actively choose the exposing action. The *mechanic* is
  unchanged (walking still lowers exposure); only the control mapping flipped.
- **`project.godot`:** Renamed input action `blend_walk` → `run` (same bindings:
  Shift + gamepad B). Name now matches what the button does (Principle #9).
- **`scripts/player.gd`:** Default speed = `walk_speed`; holding `run` = `run_speed`.
  `is_running = is_moving and is_run_held`. Updated the `@export` doc-comments.
- **Docs:** Updated `master_plan.md` §2, `UNSEEN_BUILD_PLAN.md` (mechanics list,
  Principle #2, Phase 0 task, readability example), and `CLAUDE.md` to the new
  scheme. Conceptual "blend-walking lowers exposure" references left as-is.

### Session: Exposure refactored into an extensible HUB
- **Why:** exposure feel/tuning matters less right now than making the framework
  open so future systems (kills, tools, crowd density, teleports) can affect
  exposure without touching the movement code.
- **`components/exposure_component.gd`:** now exposes three "doors", and is the
  single owner of the value (one private `_set_exposure` clamps + emits):
  - Door 1 `update(is_running, is_moving, direction, delta)` — movement (per-frame).
  - Door 2 `add_exposure(amount, reason)` — instant one-off spikes/drops (kills, penalties).
  - Door 3 `set_continuous_modifier(name, rate)` / `remove_continuous_modifier(name)`
    — ongoing per-second pushes from other systems (crowd density, alone, channeling),
    summed each frame.
  - Removed the `in_crowd` param + `exposed_alone_rise` export; crowd density will
    instead plug in via Door 3 in Phase 2. Added `debug_print_changes` to trace sources.
- **`scripts/player.gd`:** `update()` call dropped the `in_crowd` arg.
- **Build plan Phase 1:** rewritten task 1 to specify the hub/3-door design and
  marked the done items.

### Pending your verification (Phase 1 increment 1)
- Press Play. Standing still: bar slowly empties / stays low + green. Running
  (no blend key): bar climbs fast toward red. Holding blend + moving: bar falls.
  Zig-zagging while running climbs faster than a straight run. No errors in Output.
- Then we tune the rates and add the greybox test map + arrow-threshold scaffold.

## Phase 2 — The Crowd (in progress) ⚠ highest technical risk

### Session: Phase 2 increment 1 — greybox map + navigation + reusable Player
- **`scenes/player.tscn` (new):** Extracted the Player (CharacterBody2D + Polygon2D
  + CollisionShape2D + Camera2D + ExposureComponent) into its own reusable scene
  so maps can instance it and Phase 4 can spawn two. Preserved the in-editor resize.
- **`maps/test_map.tscn` (new):** Greybox "plaza" — dark floor, four grey
  perimeter walls (StaticBody2D + collision), and a `NavigationRegion2D`.
- **`scripts/test_map.gd` (new):** Builds a rectangular NavigationPolygon (the
  walkable "floor plan") at runtime from `nav_half_width`/`nav_half_height`
  exports. Reliable + readable; real maps will bake nav in-editor later.
- **`scenes/main.tscn` (rewired):** Now a composition root — instances the
  TestMap + the Player + the HUD (HUD still wired to the player's ExposureComponent
  via NodePath). Stays the run scene. Logic/level/UI now cleanly separated.

### Pending your verification (Phase 2 increment 1)
- Press Play. You should spawn in the centre of a grey walled plaza, walk around
  (walk default / hold run), bump into the four walls, camera follows, exposure
  bar still works. No errors in Output.
- Next increment: add ONE NPC that wanders the plaza via the navigation mesh.

### Session: Win/lose + scoring + end screen (Phase 3 loop complete)
- **The hunt now has stakes:** the hunter, while chasing, CATCHES you within
  `catch_distance` (70px) and kills you (`player.gd` gained `die()` + `died`).
- **`scripts/round_manager.gd` (new):** tracks elapsed time, samples player
  exposure every frame for a round average, and counts kills. Ends the round on
  WIN (contract complete), CAUGHT (player death), or TIME UP (`round_time_limit`,
  300s default). Computes a score: ghostliness (low avg exposure, biggest factor)
  + speed + clean kills + win/death bonus — all `@export` weights.
- **`scripts/end_screen.gd` + `scenes/end_screen.tscn` (new):** pause overlay
  showing the result + score breakdown and a "Play Again" button (reloads the
  round). process_mode = Always so it works while paused.
- **Signals added:** `contract_manager.contract_completed`, `kill_component.kill_landed`
  (emitted before the target dies so the final kill counts).
- **`scenes/main.tscn`:** added Round + EndScreen.

### Pending your verification (win/lose + score)
- WIN: complete the contract (2 marks → hunter) → end screen "CONTRACT COMPLETE"
  with a score breakdown; lower average exposure = higher score. Play Again reloads.
- LOSE: let the hunter lock on and catch you (stand still while exposed near it) →
  "YOU WERE CAUGHT" with a score. TIME UP triggers if the 300s limit is reached.
- NOTE: you run (220) faster than the hunter chases (160), so you can escape a
  lock by running — tune `chase_speed` / `catch_distance` if the hunt feels toothless.

### Session: Contract system + whiff cost + even crowd spawn
- **Kill button always costs exposure:** `kill_component` now always plays the
  strike and adds exposure on press — full `kill_exposure_spike` on a clean kill,
  `whiff_exposure_fraction` (10%) on a miss. No more free fishing for kills.
- **Contract system (`scripts/contract_manager.gd`, master_plan §7):**
  - Spawns NPC MARKS (using npc.tscn, identical look) standing at the map's
    gold-dot mark locations. Marks are killable; the rest of the crowd never is.
  - Kill all marks → the HUNTER becomes your killable TARGET (it is NOT killable
    before that). Kill it → "CONTRACT COMPLETE".
  - HUD `ContractLabel` shows progress (marks remaining → hunt target → complete).
  - `npc.gd`: added `can_wander` (marks stand still), a `died` signal, and `die()`.
  - `hunter_ai.gd`: no longer killable from the start (contract grants it); added `died`.
- **Even crowd spawn:** `test_map_01.random_walkable_point()` scatters spawns
  across all walkable cells (area-weighted); `crowd_manager` uses it. Fixes the
  start-of-round clustering (the old nav random-point query clumped before sync).
- **`scenes/main.tscn`:** added Contract node + HUD ContractLabel.

### Pending your verification (contract)
- Press Play. The crowd should be spread evenly across the map (not clumped).
- HUD shows "eliminate your marks: 2 remaining". Two NPCs stand at the gold dots
  (left & right lanes). Walk to one, kill it (click) → count drops. Kill both →
  label switches to "Hunt and kill your target"; the hunter is now killable.
  Kill the hunter → "CONTRACT COMPLETE". Civilians remain unkillable throughout.

### Session: Two-part exposure + working kill button
- **Exposure reworked again (master_plan §3 → v0.6):** now TWO parts. MOVEMENT
  exposure (running up / walking + idle down — recoverable) plus COMMITTED exposure
  (kills + tools — a permanent floor walking can never go below). Total = sum,
  clamped 0–100. So you can calm a sprint by walking, but never walk off a kill/
  tool. `exposure_component.gd` rewritten with the two pools; re-added
  `walk_fall_per_second` / `idle_fall_per_second`.
- **Kill button works (`components/kill_component.gd`):** `action_primary` (left
  click / Space / gamepad A) kills the nearest actor in the "killable" group within
  `kill_range` (120px). Plays a quick strike pulse and adds a PERMANENT
  `kill_exposure_spike` (30) to the killer (Door 2 → committed floor).
- **Kill rules (owner's design):** only "killable"-group actors can be killed.
  The hunter joins "killable"; civilians never do, so clicking near them does
  nothing — unmarked NPCs are unkillable. Contract marks will join "killable" later.
- **Hunter death (`hunter_ai.gd`):** added `die()` — fades + shrinks then frees;
  stops behaving; leaves the groups. One hunter for now, so restart to test again.
- **`scenes/player.tscn`:** added KillComponent. **`scenes/hunter.tscn`:** (exposure
  added last session).

### Pending your verification (two-part exposure + kill)
- Exposure: run → bar climbs; stop/walk → it falls back down. Then perform a kill
  → bar jumps and that portion will NOT walk off (the committed floor).
- Kill: walk up to the hunter (or let it chase you), press the kill button — it
  should do a strike pulse, the hunter fades out and dies, and your exposure spikes.
- Click near a civilian → nothing happens (unmarked NPCs are unkillable).
- NEXT: the contract (marks → assigned target) so kills have objectives.

### Session: Exposure is now one-way + exposure arrow (start of Phase 3)
- **DESIGN PIVOT — exposure only ever rises (master_plan §3 updated to v0.5):**
  nothing lowers it within a round (not walking, idle, or crowd). It's a finite
  budget you SPEND by acting; every loud action permanently commits you. Makes
  tool use a hard, lasting decision. `exposure_component.gd` rewritten: walking/
  idle now contribute nothing (removed the fall rates); crowd density is cover
  (sightlines/blend), not an exposure discount (§4 updated too).
- **Exposure arrow (`scripts/exposure_arrow.gd`, master_plan §3.1):** HUD arrow
  points toward an over-exposed actor and VANISHES the moment it's on your screen
  (you then find them in the crowd yourself). Tunable `arrow_threshold`,
  `arrow_color`, sizes. Tracks the hunter (group "hunter") for now.
- **Hunter can become exposed (`hunter_ai.gd` + `hunter.tscn`):** hunter now has
  its own ExposureComponent, joins group "hunter", and `wander_run_chance`
  (default 0.5) makes it sometimes RUN to a wander spot — running raises its
  exposure so the arrow lights up (lets us test the arrow). Chasing also exposes it.
- **`scenes/main.tscn`:** added the ExposureArrow to the HUD.

### Pending your verification (exposure one-way + arrow)
- Press Play. Your exposure bar should now only climb when you run and NEVER fall.
- The hunter wanders, sometimes running. When its exposure crosses the threshold
  AND it's off your screen, a red arrow on your HUD points toward it. Walk toward
  the arrow until the hunter comes on screen — the arrow should vanish.
- NEXT INCREMENT: the kill + contract (see build plan Phase 3 design notes).

### Session: Fixed NPCs getting stuck (navigation clearance)
- **Cause:** the walkable nav floor ran right up to the wall/building faces, so
  NPC bodies clipped corners (worst in the middle lane, buildings on both sides)
  and `move_and_slide` jammed them.
- **Fix (`scripts/test_map_01.gd`):** added `solid_clearance` (default 60px, must
  exceed an actor's ~36px half-width). Buildings are shrunk by it and outer walls
  pushed out by it, so there's always a gap between the navigation edge and solid
  collision. Navigation connectivity unchanged. Floor drawing simplified to one
  fill so no gutters show.

### Session: Reworked test_map_01 from a ring into 3 lanes
- **Center is now walkable streets, not one solid block.** Replaced the single
  central building with TWO buildings separated by alleys, creating three
  north–south lanes (left / middle / right) joined by the top + bottom connector
  streets. Multiple parallel routes to juke a hunter; buildings still break LOS;
  still loops with no dead ends.
- **`scripts/test_map_01.gd`:** Layout grid changed 3×3 → 5 columns
  (lane/building/lane/building/lane) × 3 rows; nav now built from the 13 walkable
  street cells (the 2 building cells excluded). New layout knobs: `connector_depth`,
  `side_lane_width`, `middle_lane_half_width`. Player/hunter corner spawns unchanged
  (still valid).

### Session: First playtest map — test_map_01 (greybox ring)
- **`scripts/test_map_01.gd` + `maps/test_map_01.tscn` (new):** First playtest
  greybox per MAP_DESIGN_SPEC.md. A RING: outer walls + a central building that
  blocks sightlines and forces a no-dead-end loop around it. Entire layout (walls,
  navigation, colour-coded floor) is generated from a few `@export` numbers.
  - Navigation built from a 3×3 grid minus the centre cell (8 connected walkable
    cells) — robust, edges align so the loop connects.
  - Risk geography drawn for readability (spec §5): warm = exposed connectors,
    blue = density zones (top "market" / bottom "plaza"), grey = walls/building,
    teal dots = teleport pads, gold dots = NPC marks.
  - Feature positions (player spawns ×4, marks ×2, teleport pads ×2, density
    zones ×2) computed from the layout and exposed via getters
    (`get_player_spawns()` etc.) so Phase 3 systems read them from the map, not
    hardcoded. Feature LOGIC (passages/trapdoor/teleport/marks) still arrives in
    its own phase — these are positions/visuals only for now (spec §7 stubbing).
- **`scenes/main.tscn`:** Swapped `test_map` → `test_map_01`; moved the player to
  a corner spawn (-1175,-810) and the hunter to the opposite corner (1175,810)
  (the old centre spawn is now inside the building). Crowd + hunter run in the new map.

### Session: Phase 2 increment 4 — the hunter bot (cat-and-mouse!)
- **`scripts/hunter_ai.gd` + `scenes/hunter.tscn` (new):** A bot that wanders like
  the crowd while scanning for the player. Builds `suspicion` (0–100) when it has
  line of sight, scaled by the player's exposure × proximity; locks and CHASES at
  `lock_threshold`, gives up below `unlock_threshold`. Line of sight = a raycast
  that only stops on walls (`world` layer) — the crowd never blocks sight.
  All detection values are `@export` (§5 expects heavy rewriting). `debug_show_state`
  tints it green→yellow→red so you can watch it hunt (off = looks like everyone).
- **`scripts/player.gd`:** Added `class_name Player` and joins the `player` group
  in `_ready()` so the hunter can find it decoupled.
- **`scenes/main.tscn`:** Dropped one Hunter at (-500, -300).

### Pending your verification (Phase 2 increment 4 — the core loop test)
- Press Play. The hunter (tinted) wanders. **Stand still / blend-walk in the
  crowd:** it should stay green and ignore you. **Run around in its view:** your
  exposure spikes, its tint goes yellow→red, and it locks on and chases. **Break
  line of sight** (duck behind a wall) or go calm/low-exposure: it loses you and
  goes green again. THIS is the Phase 2 "is it fun?" moment.

### Session: Player passes through the crowd (AC-style, no actor collision)
- **Design decision (recorded in `master_plan.md` §4):** players and NPCs no
  longer physically collide — only walls (`world`) block movement. Blending is
  the player's job (move like a civilian), not the NPCs' (be solid). Walking
  through crowds aids the disguise and removes snag/tell friction.
- **Change:** `collision_mask` set to `1` (world only) on both `player.tscn` and
  `npc.tscn`. Layers (player/npc) kept for future detection/hunter identification.

### Session: Phase 2 increment 3 — CrowdManager + collision layers
- **Collision layers named** (`project.godot` `[layer_names]`): 1=world, 2=player,
  3=npc — readable in the editor instead of bare numbers (Principle #9).
- **Layer wiring:** Player on `player`, collides with `world`+`npc` (mask 5).
  NPC on `npc`, collides with `world`+`player` (mask 3) but PASSES THROUGH other
  NPCs (no jamming/jitter; we'll add NavigationAgent2D avoidance for dense
  clustering later). Walls stay on default `world` layer.
- **`components/crowd_manager.gd` (new):** Spawns `npc_count` (default 25) NPCs at
  random valid navigation points after the nav mesh syncs; groups them under one
  `Crowd` node. Exposes `count_npcs_near(pos, radius)` for the upcoming density→
  exposure wiring.
- **`scenes/main.tscn`:** Replaced the single hand-placed NPC with a `Crowd`
  (CrowdManager) node.

### Pending your verification (Phase 2 increment 3)
- Press Play. ~25 identical figures wander the plaza, each on its own path,
  pausing and re-routing, never through walls. You can't walk through them; they
  don't walk through you. Try to lose yourself among them. No errors in Output.
- Performance check: watch the FPS (you can enable it) — should be a flat, high
  number. Next: wire crowd density into exposure (hiding in a cluster = safer).

### Session: Phase 2 increment 2 — shared visual + first wandering NPC
- **`scenes/character_visual.tscn` (new):** One shared "costume" (the Polygon2D
  look) INSTANCED by both player and NPC, enforcing Pillar #1 (sameness). Swap
  this one scene for a sprite later and player + whole crowd update together.
- **`scenes/player.tscn`:** Replaced its inline Polygon2D with an instance of
  `character_visual.tscn`. (Edit the look there now, not on the player directly.)
- **`scripts/npc.gd` + `scenes/npc.tscn` (new):** CharacterBody2D with a
  NavigationAgent2D. Wander loop: pick a random reachable point → walk there →
  pause a random time → repeat. `move_speed` = player blend-walk speed (the
  disguise linchpin, §4); pauses randomised so it doesn't look robotic.
- **`scenes/main.tscn`:** Dropped ONE NPC at (300, 200) to test wandering.

### Pending your verification (Phase 2 increment 2)
- Press Play. A second identical square wanders the plaza on its own: walks to a
  spot, pauses, walks elsewhere, never through walls. The player (centred, camera-
  followed) and the NPC are indistinguishable at rest. No errors in Output.
- Next: a CrowdManager that spawns 20–30 of these to fill the map.

### Session: Diagnosed "can't move" → added a reference grid floor
- **Not a bug:** debug print proved movement worked all along (position climbed
  steadily, no collisions). The flat single-colour floor + centred camera meant
  motion was invisible with no nearby landmark — it only LOOKED stuck.
- **`scripts/test_map.gd`:** Now draws the floor + a reference GRID in `_draw()`
  (tunable `grid_spacing`, `grid_color`, `floor_color`), so movement is visible.
- **`maps/test_map.tscn`:** Removed the flat `Floor` Polygon2D (script draws it now).
- **`scripts/player.gd`:** Removed the temporary movement debug print.

### Session: Enlarged plaza + self-syncing navigation
- **Plaza felt too small** (player bumped walls quickly). Enlarged `maps/test_map.tscn`
  from ±1200×±800 to ±1800×±1200 (≈2.25× the area).
- **`scripts/test_map.gd`:** Navigation no longer uses a hardcoded size — it now
  MEASURES the four walls and fills the walkable gap between them (minus a small
  `nav_margin`). Resize/move the walls in the editor and the nav floor auto-matches,
  so the two can never drift out of sync (Principle #7, one source of truth).
