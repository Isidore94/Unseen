# MULTIPLAYER_PLAN.md — UNSEEN online (Phase 6)

> The detailed build plan for **online multiplayer** (the **Phase 6** transport/netcode layer,
> now built — kept as reference). The historical principles/sequencing it cites lived in the old
> `UNSEEN_BUILD_PLAN.md` (now retired); today the active plan is `buildplan.md` and the coding
> rules live in `CLAUDE.md`. Read `master_plan.md` §6 (kill) and §3 (exposure) for the rules we
> must enforce server-side. Mechanics are unchanged here — this is purely *how the game runs
> across machines*.

**Scope of this plan:** 2–4 players, listen-server (one player hosts), Godot's built-in
high-level multiplayer for the game logic, Steam relay for connectivity. **First milestone
is 2 players.** No dedicated servers, no matchmaking yet (friend-invite lobbies first).

---

## 0. Plain-language primer (read once, then the jargon below makes sense)

You're a beginner, so here are the words this doc uses, in plain terms:

- **Peer** — one running copy of the game (one machine). Each peer gets a number (an *id*).
- **Server / host** — the one peer that is the *referee*. In our model the host is also a
  player (a "**listen server**": they play AND referee on the same machine). The server's
  peer id is always **1**.
- **Client** — every non-host peer. Clients ask the server to do things; they don't decide
  anything important themselves.
- **Authority** — "who owns the truth about this thing." If the server has authority over a
  character, only the server may move it; everyone else just *displays* the server's version.
- **RPC (Remote Procedure Call)** — calling a function *on another machine*. e.g. a client
  calls `request_commit()` "on the server" to ask for a kill. Marked in code with `@rpc`.
- **Replication** — automatically copying a node's state (like position) from the authority
  to everyone else, every network tick. Godot gives us two helper nodes for this:
  - **`MultiplayerSpawner`** — when the server adds a scene (a character) to the world, this
    makes the same scene appear on every client.
  - **`MultiplayerSynchronizer`** — keeps chosen properties (e.g. `position`) of a node in
    sync from its authority to everyone else.
- **Snapshot + interpolation** — the server sends positions a few times a second
  ("snapshots"). Clients **interpolate** (smoothly slide) between the last two snapshots so
  movement looks smooth even though updates are chunky. Clients render ~100 ms "in the past"
  on purpose so they always have two snapshots to slide between.
- **Steam relay (SDR — Steam Datagram Relay)** — instead of players connecting directly
  (which needs port-forwarding and exposes your home IP), traffic hops through Valve's global
  relay network. It solves NAT (no router setup), hides IPs (anti-DDoS), and authenticates
  players by Steam account. We get this almost for free via GodotSteam.

---

## 1. THE defining constraint — hidden identity (do NOT skip this)

Our whole game is: **you cannot tell which characters are humans and which are AI NPCs.**
That single fact makes our netcode *different from every Godot multiplayer tutorial*, and
getting it wrong silently destroys the game. So this is rule zero:

> **A client must never receive any data that reveals which character is a human player
> (other than its own).**

The standard Godot tutorial model is **client-authoritative players**: each client owns its
own character, predicts its movement, and broadcasts its position to everyone. **We cannot
use that model.** Here's why it breaks us:

- A `MultiplayerSynchronizer` whose authority is "client 3" literally announces *"this
  character is controlled by peer 3."* Any modified client can read that and **highlight every
  human in the crowd** — an instant, unbeatable wallhack. The disguise is the game; this kills it.

So we invert it: **the server owns and simulates EVERY character — players and NPCs alike —
and replicates them all identically.** Clients send *input*, not positions. To a client, the
crowd is 30-odd identical characters moving around; nothing in the network data says which is
a person. The server alone holds the secret map of "peer ↔ character" and "player ↔ mark."

Everything in §2–§4 follows from this one rule.

---

## 2. Chosen architecture

**Model: server-authoritative listen-server, input-only clients.**

- One player **hosts** (peer 1). They are referee *and* a player.
- The host machine simulates **all gameplay**: every character's movement (players + NPCs),
  the crowd AI, kill validation, exposure, contracts/marks, scores, match flow.
- Each **client** does only two jobs:
  1. **Send its input** to the server (move direction, run held, "commit kill" presses).
  2. **Display** the world the server replicates (its own character + an indistinguishable
     crowd), smoothed with interpolation.
- **Authority of EVERY character = the server (peer 1).** Uniform authority is what prevents
  the identity leak: there is no per-character "owned by peer X" to read.

**Why this and not client-prediction-first:** correctness before feel. Input-only clients are
simple and leak-proof. The cost is input latency on your own character (you press → server
moves you → you see it, one round-trip later). On the loopback dev setup that's ~0 ms; over
real Steam relay it's noticeable, so we add **local prediction for your own avatar only** as a
*feel pass* in 6.2 (predicting only your own character leaks nothing — you already know it's
yours). We do **not** build prediction in the first cut.

**Crowd sync strategy (build plan §Phase 6 task 5):** start with **(a) server-simulated NPCs,
positions replicated to clients** (snapshot + interpolation). It's the safest for anti-cheat
and the simplest to reason about. If bandwidth with ~30 NPCs becomes a problem, optimize to
**waypoint replication** (server sends each NPC's current path target + speed occasionally;
clients run the same navmesh locally to move it smoothly between updates) — far less
bandwidth, still server-authoritative. We do **not** use per-client deterministic simulation
(desync risk + reverse-engineering risk). Decision recorded; revisit only if measured.

---

## 3. Connectivity stack

Two layers, kept **separable** so we can build and test the hard part (game logic) without
Steam in the way:

### 3.1 Game-logic layer — Godot high-level multiplayer (always)
- `multiplayer.multiplayer_peer = <peer>` ; server is id 1 ; `multiplayer.is_server()`.
- `MultiplayerSpawner` to spawn characters from the server to all clients.
- `MultiplayerSynchronizer` (authority = server) to replicate character transforms uniformly.
- `@rpc` functions for input, kill requests, and private per-player messages.
- `multiplayer.get_remote_sender_id()` so the server knows *which client* an RPC came from.

### 3.2 Transport layer — swappable, behind one interface
The high-level layer doesn't care *how* bytes travel. We expose a single `NetworkManager`
that can create either kind of peer:

- **`ENetMultiplayerPeer` (development / loopback)** — built into Godot, no addons, no Steam.
  `create_server(port, max_clients)` / `create_client("127.0.0.1", port)`. We build and test
  **all of 6.0 and 6.1 on this**, running two copies on one machine. Huge for momentum: real
  netcode progress with zero Steam setup.
- **`SteamMultiplayerPeer` (real play)** — a GDExtension that runs Godot's high-level MP over
  **Steam Networking Sockets**, which route through the **Steam relay (SDR)**. Swapped in at
  6.2. Connection is by the host's **Steam ID**, not an IP.

> Keeping ENet and Steam behind `NetworkManager` means flipping transports is a one-line
> change in one file — the entire game above it is identical.

### 3.3 Steam pieces (only needed from 6.2)
- **GodotSteam** (Steamworks wrapper for Godot 4.x): Steam init, friends, **lobbies**, relay.
- **SteamMultiplayerPeer** addon: the MultiplayerPeer over Steam sockets (the bridge between
  GodotSteam and Godot's high-level MP).
- **App ID**: use **480** (Valve's "Spacewar" test app) for development. A real App ID comes
  with the Steam Direct fee at Phase 7. A `steam_appid.txt` containing `480` sits in the
  project root during dev. **The Steam client must be running** for any Steam path to work.

### 3.4 Steam lobby flow (friend-invite, first version)
1. **Host** calls `Steam.createLobby(FRIENDS_ONLY, max_members)`. On the `lobby_created`
   callback: store `lobby_id`, write the host's Steam ID into lobby metadata, create a
   `SteamMultiplayerPeer` as host, set it as `multiplayer.multiplayer_peer`.
2. **Invite** via the Steam overlay invite, or by sharing the lobby id.
3. **Joiner** calls `Steam.joinLobby(lobby_id)`. On `lobby_joined`: read the host's Steam ID
   from lobby metadata, create a `SteamMultiplayerPeer` connected to that Steam ID, set it as
   `multiplayer.multiplayer_peer`.
4. From here Godot's normal `peer_connected` / `peer_disconnected` signals fire and the game
   logic layer (§3.1) takes over — **identical to the ENet path**.

---

## 4. What replicates, to whom, and how — "everything in place"

This table is the contract. If it's built exactly like this, identity stays hidden and nothing
is client-trusted. **Owner-only** rows are private to one player and are the reason the game
has secrets at all.

| State | Authority | Sent to | Mechanism | Why it's done this way |
|---|---|---|---|---|
| Character transform (ALL players + NPCs) | Server (1) | All clients | `MultiplayerSynchronizer`, authority=1, + client interpolation | Uniform authority → no "owned by peer X" leak; one source of truth |
| Character facing / walk anim | — (derived) | — | each client derives it from the interpolated velocity (CharacterVisual already does this) | Zero bandwidth; reuses existing visual logic |
| Character appearance (sprite-sheet index) | Server | All clients | Synchronizer property, set once at spawn | Crowd looks uniform. (Per-viewer cosmetics later = targeted RPC, see §7) |
| **Local player input** (move vec, run, presses) | The client | **Server only** | `rpc_id(1, receive_input, …)`; server reads `get_remote_sender_id()` | Keeps the input→identity mapping **server-side only**. Never a per-entity synchronizer |
| **Kill commit request** | Client → Server | Server validates | `rpc_id(1, request_commit, target_entity_id)` (reliable) | Never trust the client; server re-checks range, cone, valid-target, cooldown |
| Kill result / death | Server | All clients | `@rpc` broadcast on the entity id | Everyone sees the same world; the *killer's* identity is not revealed |
| **Exposure value** | Server | **Owner client only** | `rpc_id(owner_peer, update_exposure, …)` | Your exposure is private intel; broadcasting it leaks and aids cheating |
| **Your mark** (which entity to kill) | Server | **Owner client only** | `rpc_id(owner_peer, assign_mark, entity_id)` | Only you learn your mark → drives your private mini-map dot + highlight |
| Mini-map mark position | Server | Owner client only | targeted RPC each tick (or owner-only) | Private objective tracking (master_plan §7.1) |
| PvP opponent ping | Server | The earning client only | `rpc_id(client, ping_opponent, pos)` every few s | The §7.1 reward for finishing your mark first — delayed intel, private |
| Contract phase / score / match start+end | Server | broadcast (or owner) | `@rpc` | Authoritative match flow; no client self-reports a win |

**Entity ids:** every character is a node under the spawner with a unique name = its *entity
id*. The server keeps two **private** maps that never leave the host:
`peer_id → controlled_entity` and `peer_id → mark_entity`. At spawn the server tells **each
client only its OWN** entity id and (later) its OWN mark entity id. Knowing your own identity
is not a leak; knowing others' is.

---

## 5. Node & scene architecture (the new pieces)

Small, single-responsibility scripts, same as the rest of the project (build plan §1.3):

- **`scripts/net/network_manager.gd` (autoload singleton `NetworkManager`)**
  *One job: connectivity.* Picks the transport (ENet vs Steam), hosts `host_game()` /
  `join_game()`, owns the `MultiplayerPeer`, re-emits `peer_connected` / `peer_disconnected` /
  `connection_failed` as clean signals the rest of the game listens to. Nothing game-specific.
- **`scripts/net/steam_lobby.gd`**
  *One job: Steam lobbies.* createLobby / joinLobby / invite / read host id. Only touched on
  the Steam path; the ENet path never loads it. Keeps Steam isolated.
- **`scenes/online_match.gd` + `.tscn` (the new run shell, replaces split-screen on the host)**
  Server side: builds the map, spawns the crowd, spawns one player per connected peer (via
  `MultiplayerSpawner`), assigns server authority + the private identity/mark maps, runs the
  contracts and match manager. Every side: sets up the **single local viewport** — one camera
  following *this machine's* player, one full-screen HUD + mini-map. (No SubViewports online.)
- **`scenes/main_menu.gd` + `.tscn` (new default run scene)**
  Host / Join (friend invite) / and a "Local AI test" button that launches the OLD
  split-screen scene for offline testing. This is the new `main.tscn` target.
- **Input flow:** each client samples input each physics frame into a tiny struct
  `{ move: Vector2, run: bool }` and `rpc_id(1, receive_input, struct)` at the network tick;
  "commit kill" is sent separately as a reliable `request_commit(entity_id)` RPC. The server
  applies inputs to the matching characters inside its own `_physics_process`.

---

## 6. Migration — what changes in the code we already have

Most of the game is reused untouched, because we built server-authoritative-ready since
Phase 0 (build plan §1.6). Concretely:

**Reused unchanged**
- `components/exposure_component.gd` (already pure: computes from inputs, no Input/no reach-in).
- `scripts/character_visual.gd` (facing/anim derive from velocity → works on replicated bodies).
- `scripts/mini_map.gd` rendering, `scripts/portal.gd`, `scripts/camera_follow.gd`,
  `scripts/test_map_01.gd` (the map is built by the server; clients get it/rebuild it).

**Reused with a thin server-authority wrapper**
- `components/kill_component.gd` → the *commit press* becomes `request_commit` RPC to the
  server; the server runs the existing `_best_suspect_in_front` / validation and broadcasts the
  result. (The aim/lock logic is unchanged; only *who decides* moves to the server.)
- `scripts/contract_manager.gd` → runs **server-only**; sends each player its mark via
  owner-only RPC instead of touching the node directly.
- `scripts/npc.gd` / `components/crowd_manager.gd` → simulated **on the server only**; clients
  receive replicated bodies (their `_physics_process` AI is disabled on clients).
- `scripts/player.gd` → input is read locally and **sent**, not applied directly; the server
  applies it. Local prediction added later (6.2).

**Moved out of the default run path, but KEPT in the project (as you asked)**
- `scripts/local_coop_game.gd` + its scene = the split-screen shell. It stays in the repo and
  stays runnable from Main Menu → "Local AI test," but it is **no longer** what `main.tscn`
  launches. Nothing is deleted. (Reason: online play is needed to truly playtest social
  stealth — on one screen you can just see each other.)
- The per-player duplicated input actions (`p1_*`, `p2_*`) aren't needed online (each machine
  has one local player using the base `move_*` / `action_primary` / `run` actions). We keep the
  Input Map entries; online simply uses the base actions.

---

## 7. The mark-highlight & cosmetics payoff (why online *fixes* earlier problems)

Two things we flagged as "leaks in split-screen" become **clean and correct** online, for free:

- **Mark highlight** — online, the server tells *only you* which entity is your mark, and only
  *your* machine draws the highlight. The opponent's machine never receives that fact. The
  shared-world leak simply doesn't exist when each player renders their own view.
- **Per-viewer cosmetics** (your future plan: 4 player looks, crowd built from copies, each
  player never sees their own look) — this is just an **owner-aware appearance message**: the
  server sends each client a per-character appearance map tailored to that viewer (excluding
  their own look). It's the same per-recipient RPC pattern as the mark assignment. Marked as a
  post-6.3 feature; the `set_appearance()` seam from CharacterVisual is already where it plugs in.

---

## 8. Tunable constants (all `@export`/config, no magic numbers — build plan §1.7)

| Name | Suggested start | Controls |
|---|---|---|
| `max_players` | 4 | Lobby cap (first milestone runs at 2) |
| `network_tick_hz` | 30 | How often inputs/snapshots are sent |
| `physics_tick_hz` | 60 | Server simulation rate (Godot default) |
| `interpolation_delay_ms` | 100 | How far "in the past" clients render remote bodies |
| `snapshot_rate_hz` | 20–30 | Transform replication frequency |
| `kill_request_channel` | reliable | Kill commits must never be dropped |
| `input_channel` | unreliable | Movement input — newest matters, drops are fine |

---

## 9. Sub-phases (each has a hard done-gate + how to test it)

**6.0 — Loopback spike (ENet, 2 players, NO Steam).**
Build `NetworkManager` (ENet), `main_menu` host/join, `online_match` shell. Server simulates
both players' movement from input RPCs; transforms replicate; basic interpolation on the remote
player. *No crowd, no kills yet.*
**Done =** two game windows on one machine; both characters walk and you see each other move
smoothly and in sync. **Test:** run the project twice (two editor instances / two exports), one
hosts, one joins `127.0.0.1`.

**6.1 — Server-authoritative game systems over the network (ENet loopback, 2 players + bots).**
Port crowd (server-simulated), contract/marks (server, owner-only assign), kills (`request_commit`
→ server validate → broadcast), exposure (owner-only), mini-map + mark highlight (now per-client).
**Done =** a full match plays correctly end-to-end across two networked instances: find mark →
kill → hunt opponent → win/lose, with no client able to see the other's mark/exposure.
**Test:** two instances, play a whole round; verify on the *joiner* that the host's mark/exposure
are NOT visible.

**6.2 — Steam relay transport (2 real machines).**
Add GodotSteam + SteamMultiplayerPeer; build `steam_lobby.gd`; friend-invite lobby; swap transport
behind `NetworkManager`. Add **local prediction** for your own avatar (feel pass) now that real
latency exists.
**Done =** two different machines + two Steam accounts finish a match over the internet via the
relay (no port-forwarding). **Test:** you + one friend (or a second PC/account).

**6.3 — Scale to 4 + lobby UX.**
Lobby screen (player list, ready-up, host starts), spawn 3–4 players, interpolation/feel tuning at
realistic ping (simulate 80–150 ms), reconnect/disconnect handling.
**Done =** four machines finish a stable match with no desync or crash (build plan §Phase 6 test
checkpoint).

---

## 10. Prerequisites & what YOU need to set up

Reassurance first: **6.0 and 6.1 need none of the Steam stuff** — just Godot and running the
project twice. You can get the entire game working over the network before touching Steam.

When we reach **6.2**, you'll need:
- The **Steam client installed and running** on each test machine.
- **GodotSteam** (the Godot 4.x GDExtension build matching Godot 4.7) dropped into `addons/`.
- The **SteamMultiplayerPeer** GDExtension in `addons/`.
- A `steam_appid.txt` with `480` in the project root (dev/test App ID).
- **Two Steam accounts on two machines** to test a real relay match (a second account / second PC,
  or a willing friend).
- Eventually (Phase 7): the **$100 Steam Direct** fee → your own real App ID.

I'll give exact, click-by-click setup steps when we get to 6.2 — not before, so it doesn't
distract from the netcode.

---

## 11. Risks & fallbacks (named now so they don't surprise us)

- **GodotSteam/Godot version mismatch** — pin the GodotSteam build to Godot 4.7. Fallback: stay on
  ENet + manual IP for testing until versions line up.
- **Crowd bandwidth at ~30 NPCs** — if snapshots are heavy, switch to **waypoint replication**
  (§2). Fallback: lower NPC count or `snapshot_rate_hz` while tuning.
- **Own-avatar input lag over relay** — addressed by local prediction in 6.2. Fallback: cap match
  to lower-ping lobbies; consider a small fixed input buffer.
- **Desync revealing players** — the uniform server-authority model (§1) is specifically chosen to
  prevent this; never add a per-client authority shortcut "just to make movement smoother."
- **Godot high-level MP hits a wall at our scale** — build plan's documented fallback is **Photon**.
  Only if measured, not assumed.

---

## 12. Decisions already made (so we don't re-litigate)

1. **Listen-server** (a player hosts), not dedicated — near-zero cost, fine for 2–4.
2. **Server simulates everything, clients send input only** — required by the hidden-identity rule.
3. **Uniform server authority on every character** — no per-player authority, ever (anti-leak).
4. **ENet loopback first, Steam relay second** — game logic proven before connectivity complexity.
5. **Snapshot+interpolation crowd**, waypoint optimization only if measured.
6. **Split-screen kept but removed from the default run path**, reachable as an offline AI test.

Open question to confirm with you when we start 6.2: friend-invite lobbies only at first (yes),
or also a "join by code" path early? (Recommend: invites only first.)
