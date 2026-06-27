extends Node2D
class_name OnlineMatch

# OnlineMatch — UNSEEN, Phase 6.0 (see MULTIPLAYER_PLAN.md §5, §9).
#
# The online "run shell" — the networked replacement for the split-screen scene.
# It builds the world the SAME way on every machine (the map is plain static
# geometry, so each peer just builds its own copy) and lets the HOST spawn one
# character per connected player. Those characters are the only thing replicated.
#
# STATUS: 6.0 (players replicated) done; 6.1 in progress — a HOST-simulated crowd is
# now replicated to all clients too. Still to come in 6.1: server-validated kills and
# private per-player state (your mark, exposure, mini-map, highlight).

const MAP_SCENE := preload("res://maps/test_map_01.tscn")
const SMALL_MAP_SCENE := preload("res://maps/test_map_02.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const NPC_SCENE := preload("res://scenes/npc.tscn")
const MINI_MAP_SCRIPT := preload("res://scripts/mini_map.gd")
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
## Reloaded on a rematch (re-runs the whole start handshake with everyone still connected).
const ONLINE_MATCH_SCENE := "res://scenes/online_match.tscn"

## Crowd size for the COMPACT/Rome arenas (the lobby's small maps use this instead of npc_count).
## Tighter crowd (Phase 9 decision): a smaller, readable haystack. At clone_crowd_fraction = 0.25
## this is ~10 clones + ~30 filler. Raise it (or the fraction) if hiding feels too easy.
@export var compact_npc_count: int = 40

## How many sprite sheets exist (assets/sprites). Characters cycle through them so a
## small match still looks varied. Keep in sync with CharacterVisual's sheet list.
const NUM_SHEETS := 5

## Size of the AI crowd the host simulates (the people you hide among). Tightened in Phase 9 to a
## smaller, readable crowd; at clone_crowd_fraction = 0.25 that's ~15 clones + ~45 filler.
@export var npc_count: int = 60

## Fraction of the crowd that CROSSES the map (spawn at an edge, long paths). The rest
## are "homebodies" that mill around their spawn spot with short trips.
@export var traveler_fraction: float = 0.25

## How many NPC marks each player must kill before the human opponent becomes a valid
## target (buildplan §7.0, note 9). The host secretly designates this many crowd NPCs
## per peer and only opens the hunt phase once ALL of them are dead.
@export var marks_per_player: int = 2

## A designated mark is forced to stay LOCAL: it becomes a homebody that mills within
## this radius (px) of where it was tagged, so you can learn its patch (note 13).
@export var mark_wander_radius: float = 220.0

## The marks for one player are spread at least this far apart (px) — about two
## screen-widths — so you can't scoop both at once; it forces movement (note 13).
@export var mark_min_separation: float = 1400.0

## Per-viewer visibility (§7.2b): may a ROOFTOP player see OTHER rooftop players? Defaulted
## ON so rooftops aren't a blind solo zone (a buildplan still-open decision — flip to taste).
@export var rooftop_sees_rooftop: bool = true

# === per-viewer crowd APPEARANCE (§0.3 — the hidden-identity PILLAR) ====================
# Visibility (above) decides WHO you can see; this decides WHAT the crowd looks like to YOU.
# On THIS screen the crowd is rebuilt from copies of the OTHER players' looks (so each real
# opponent blends into a group of look-alikes) plus filler, with YOUR OWN look removed — you
# are never shown a copy of yourself, and your look is never a tell. Local-only and frozen
# once per match. It's keyed on the Loadout, so real cosmetics later flow through unchanged.
## CLONES + FILLER mix (the chosen combo: buildplan §0.3 + PHASE_8_MONETIZATION.md §2A). The crowd
## is mostly generic FILLER civilians with player-CLONES mixed in. This is the fraction of the crowd
## that is clones (copies of the OTHER players' looks, split evenly across opponents); the rest is
## filler. 0.25 = clones are ~a quarter of the crowd — a believable townsfolk crowd with each
## opponent hidden in a pocket of look-alikes. Raise it for a stronger blend / cosmetic showcase.
## Your own look is NEVER in the crowd. (Total crowd size is the host's npc_count / compact_npc_count.)
@export_range(0.0, 1.0, 0.05) var clone_crowd_fraction: float = 0.25
## Master switch for the per-viewer crowd reskin. Off = the crowd keeps the host's random
## looks (the pre-pillar behaviour) — handy for an A/B comparison while tuning.
@export var per_viewer_crowd_enabled: bool = true
## TEMPORARY — placeholder-art era only. With no real cosmetics yet, every account defaults to
## the SAME body, so the per-viewer crowd would be invisible (everyone identical). This forces
## each player onto a DISTINCT body sheet at spawn so you can SEE the system work: you become
## the only "you" on your screen while everyone else's crowd fills with copies of you. Turn
## OFF the moment players pick real, distinct cosmetics — their chosen look is then used as-is.
@export var placeholder_distinct_bodies: bool = true

# === scoring (buildplan §7.5 — winner = most points; mirrors LocalMatchManager) ========
# The match runs until ONE player is left alive (or time runs out); the WINNER is then
# whoever has the most points — NOT necessarily the survivor. These tunables mirror the
# offline LocalMatchManager so online and offline score the same way.
## Seconds before the match times out and is scored as-is (0 = no limit).
@export var round_time_limit: float = 300.0
## Points per % of "ghostliness" (100 − your average exposure). Low exposure is the fantasy.
@export var exposure_weight: float = 5.0
## Starting speed bonus; it bleeds away over the match, rewarding a fast clean game.
@export var speed_bonus_cap: float = 500.0
@export var speed_bleed_per_second: float = 2.0
## Points for each clean kill (your marks + the player you eliminate).
@export var kill_points: int = 100
## Awarded for COMPLETING your contract (killing your assigned target) — an achievement that
## scores points, not a circular "you won" flag (the winner is decided from the totals).
@export var contract_bonus: int = 500
## Subtracted from a player who is eliminated — being killed caps what you can still earn.
@export var death_penalty: int = 300

var _map: Node = null
var _players_parent: Node2D = null
var _player_spawner: MultiplayerSpawner = null
var _crowd_parent: Node2D = null
var _crowd_spawner: MultiplayerSpawner = null
var _status_label: Label = null

## Host-only bookkeeping: which character belongs to which peer, and the next spawn
## slot to use. Lives only on the host (the referee) — clients never see it.
var _players_by_peer: Dictionary = {}
var _next_spawn_index: int = 0

## Host-only: each peer's chosen cosmetic loadout payload (ids only), submitted by that
## client on join (§5). Used to fill the player's spawn_data so everyone renders them the
## same. Missing = the host builds a default look. Static during a match.
var _loadout_by_peer: Dictionary = {}

## Host-only: which crowd NPCs are each peer's secret marks (an Array of Npc, since a
## player now has `marks_per_player` of them — §7.0). The mapping never leaves the host;
## each peer is told only ITS OWN marks (MULTIPLAYER_PLAN.md §4).
var _mark_by_peer: Dictionary = {}
## Host-only: how many of each peer's marks are still alive. The hunt phase opens only
## when this reaches 0 (you must clear BOTH marks first — note 9).
var _marks_remaining_by_peer: Dictionary = {}

## Host-only contract state: each peer's phase ("marks" -> "target" -> "done").
var _phase_by_peer: Dictionary = {}
## The TARGET RING (host-only): hunter_peer -> the peer they are assigned to hunt. Fixed as a
## single cycle at match start so everyone has exactly one target and is exactly one other's
## prey (master_plan §7.2). If your target dies before you reach them, you re-link to the next
## living player in the ring (_next_living_target) so your arrow/reveal stay meaningful.
var _ring_target: Dictionary = {}  # hunter_peer -> target_peer
## True once the WHOLE match is decided (one player left, or time up). A single death no longer
## ends the match (buildplan §7.5) — it only eliminates that player.
var _match_over: bool = false

## Host-only scoring accumulators, one entry per peer (mirrors LocalMatchManager).
var _player_num: Dictionary = {}        # peer -> 1-based display number (spawn order)
var _exposure_sum: Dictionary = {}      # peer -> summed exposure samples
var _exposure_samples: Dictionary = {}  # peer -> sample count
var _kills_by_peer: Dictionary = {}     # peer -> clean kills landed
var _completed_by_peer: Dictionary = {} # peer -> killed their assigned target?
var _dead_by_peer: Dictionary = {}      # peer -> eliminated?
var _elapsed: float = 0.0               # match time, host clock (drives speed bonus + timeout)

## Host-only: peers that have pressed "Rematch" on the end screen. When everyone still
## connected has voted, the host reloads the match for all of them.
var _rematch_votes: Dictionary = {}

## Lobby → match readiness gate. The clients we expect (everyone who was in the lobby),
## which of them have reported their match scene ready, and whether we've begun. Nothing
## is spawned until EVERY expected client is ready, so no character is replicated to a
## client whose spawners don't exist yet (the lobby makes all peers transition at once).
var _expected_clients: Array = []
var _ready_clients: Dictionary = {}
var _match_begun: bool = false

## This machine's own private view. Host AND client each control one local player and
## each builds its own HUD + mini-map + mark highlight for that player only.
var _local_player: Player = null
var _player_hud_layer: CanvasLayer = null
var _mini_map: MiniMap = null
var _objective_label: Label = null
var _exposure_bar: ProgressBar = null
## Our marks, as the host named them (owner-only). We resolve each name to its local
## node once that NPC has replicated to us, highlight it, and point the mini-map at the
## nearest living one. The host tells us when each dies so we can drop it.
var _my_mark_names: Array = []
var _resolved_marks: Dictionary = {}  # mark_name -> Node2D (resolved locally)
## Online PvP: our opponent (the other player). Known from the start so the exposure
## arrow can react when they run; only KILLABLE once we've finished our own mark.
var _my_target_name: String = ""
var _my_target: Node2D = null
var _target_arrow: ExposureArrow = null
## True once our mark is dead — flips the arrow from exposure-gated to flashing.
var _hunt_phase: bool = false
## Client-side: re-asks the host to spawn us until our player appears (covers the rare
## case where our first request outran the host's scene during the lobby transition).
var _spawn_retry_timer: float = 0.0
## Per-viewer crowd reskin (§0.3) runs ONCE per match, after the whole crowd has replicated
## in. This latch makes sure it never re-runs — a stable disguise pool, because an NPC that
## changed clothes mid-match would be an obvious tell.
var _crowd_appearance_done: bool = false

# === Phase 7 online state (visibility / claim / items / reveals) =============
# Layer ints mirrored from LayerComponent.Layer (kept decoupled, like CharacterVisual).
const _LAYER_GROUND := 0
const _LAYER_ROOFTOP := 1
const _LAYER_SEWER := 2

## Slice B — the dark overlay shown over our OWN view while we're in the sewer (blind).
var _sewer_overlay: ColorRect = null

## Slice C — every access point on THIS machine, by its stable map index, so the host's
## replicated claim/cooldown can be applied to the right one.
var _access_points_by_index: Dictionary = {}

## Slice D — our own item kit readout, driven by host pushes (the host owns the charges).
var _item_label: Label = null
var _item_state: Dictionary = {"smoke": 0, "cloak": 0, "smoke_on": false, "cloak_on": false}

## Slice E — the faceplate row + any reveal that arrived before the HUD existed.
var _faceplates: FaceplateRow = null
var _pending_target_face: int = -1
var _pending_exposed_faces: Array = []
## Host-only: who has already earned a reveal, so each fires once.
var _target_reveal_awarded: bool = false
var _exposure_revealed: Dictionary = {}

## Network debug overlay (toggle with F3): FPS, ping, and how many predicted inputs are
## still un-confirmed. Off by default so it doesn't clutter normal play.
var _debug_layer: CanvasLayer = null
var _debug_label: Label = null
var _debug_visible: bool = false

## Phase 9 HOOK (PHASE_9_EXPERIMENTS.md). Re-announces every resolved kill at the MATCH level so
## experiments can listen in one place instead of re-wiring per player spawn. online_match emits
## this; it does not know or care who listens (the one-way dependency rule, §1.2).
signal host_kill_resolved(killer: Node, victim: Node, was_valid_target: bool)


func _ready() -> void:
	add_to_group("online_match")  # Phase 9 experiments find the match here (read-only accessors)
	_build_world()
	_build_hud()
	_build_debug_overlay()
	_wire_access_points()
	_spawn_experiments()

	# Portals are map-control teleporters. They must only fire on the HOST (the
	# referee); on clients the player bodies are just replicas, so a client-side
	# teleport would fight the host's position. Switch them off on clients.
	if not NetworkManager.is_host():
		for portal in get_tree().get_nodes_in_group("portal"):
			portal.set("monitoring", false)

	if NetworkManager.is_host():
		_start_as_host()
	else:
		_start_as_client()


func _build_world() -> void:
	# The host's lobby choice (compact vs full) reaches every peer via NetworkManager.
	var map_scene: PackedScene = SMALL_MAP_SCENE if NetworkManager.small_arena else MAP_SCENE
	_map = map_scene.instantiate()
	_map.name = "Map"
	add_child(_map)

	# All networked characters live under this node; the spawner replicates them.
	_players_parent = Node2D.new()
	_players_parent.name = "Players"
	add_child(_players_parent)

	# The MultiplayerSpawner copies host-spawned characters to every client. We give
	# it a custom spawn function so each peer builds the character from the same data
	# (position, look, who controls it) — identical on all screens.
	_player_spawner = MultiplayerSpawner.new()
	_player_spawner.name = "PlayerSpawner"
	add_child(_player_spawner)
	_player_spawner.spawn_path = _player_spawner.get_path_to(_players_parent)
	_player_spawner.spawn_function = Callable(self, "_create_networked_player")

	# The crowd lives under its own node with its own spawner. The host fills it; the
	# spawner copies each NPC to every client (where it's a display-only puppet).
	_crowd_parent = Node2D.new()
	_crowd_parent.name = "Crowd"
	add_child(_crowd_parent)
	_crowd_spawner = MultiplayerSpawner.new()
	_crowd_spawner.name = "CrowdSpawner"
	add_child(_crowd_spawner)
	_crowd_spawner.spawn_path = _crowd_spawner.get_path_to(_crowd_parent)
	_crowd_spawner.spawn_function = Callable(self, "_create_networked_npc")


# === host ===================================================================

func _start_as_host() -> void:
	# Everyone who was in the lobby is already connected. Wait for each of them to
	# report their match scene ready (via _request_spawn) before spawning anything.
	_expected_clients = multiplayer.get_peers()
	NetworkManager.player_left.connect(_on_player_left)
	_maybe_begin_match()  # handles the no-clients case (begins immediately)


# Begins the match once EVERY expected client's scene is ready: spawn all players,
# then the crowd, then assign each player a mark and tell each who their opponent is —
# all at once, after the handshake, so no spawn outruns a client's spawners.
func _maybe_begin_match() -> void:
	if _match_begun:
		return
	for client_peer in _expected_clients:
		if not _ready_clients.has(client_peer):
			return  # still waiting on someone
	_match_begun = true
	_spawn_player_for_peer(1)
	for client_peer in _expected_clients:
		_spawn_player_for_peer(client_peer)
	_spawn_crowd()
	_build_target_ring()
	for peer_id in _players_by_peer:
		_assign_mark_for_peer(peer_id)
	_notify_targets()


func _spawn_crowd() -> void:
	var map := _map as TestMap01
	# Fewer NPCs in the compact arena (lighter for the host to simulate + replicate).
	var crowd_size := compact_npc_count if NetworkManager.small_arena else npc_count
	for _i in crowd_size:
		# A minority cross the whole map (entering from an edge); most are homebodies
		# that spawn wherever and potter around there.
		var is_traveler := randf() < traveler_fraction
		var spawn_position := Vector2.ZERO
		if map != null:
			spawn_position = map.random_edge_walkable_point() if is_traveler else map.random_walkable_point()
		# The host picks this NPC's whole look ONCE here as a compact loadout payload
		# (ids only). The spawner replicates spawn_data verbatim to every client, so all
		# peers rebuild the identical NPC with near-zero ongoing bandwidth (§5).
		var loadout_payload := _random_npc_loadout_payload()
		var spawn_data := {
			"pos": spawn_position,
			# appearance kept as a fallback for older paths; loadout below is authoritative.
			"appearance": _body_index_from_payload(loadout_payload),
			"loadout": loadout_payload,
			"traveler": is_traveler,
			"wander_radius": randf_range(250.0, 500.0),
		}
		_crowd_spawner.spawn(spawn_data)


# Called BY a client (over the network) once that client's scene is built and ready
# to receive spawns. Spawning only after this handshake avoids a race where we'd
# replicate a character to a client that isn't listening yet.
@rpc("any_peer", "reliable")
func _request_spawn() -> void:
	if not multiplayer.is_server():
		return
	var requesting_peer := multiplayer.get_remote_sender_id()
	if _players_by_peer.has(requesting_peer):
		return  # already spawned (ignore a duplicate request)
	if _match_begun:
		# A late joiner after the match already started — bring them in directly.
		_spawn_player_for_peer(requesting_peer)
		_assign_mark_for_peer(requesting_peer)
		_insert_into_ring(requesting_peer)
		_notify_targets()
	else:
		# Still in the start handshake: mark this client ready, begin once all are.
		_ready_clients[requesting_peer] = true
		_maybe_begin_match()


# Host-only: build the TARGET RING — a random single cycle over all players, so each peer
# hunts exactly one other and is hunted by exactly one other (master_plan §7.2). One player =
# empty; two = the mutual pair; more = one big loop.
func _build_target_ring() -> void:
	if not multiplayer.is_server():
		return
	var peers: Array = _players_by_peer.keys()
	if peers.size() < 2:
		return
	peers.shuffle()
	for i in peers.size():
		var hunter: int = peers[i]
		var prey: int = peers[(i + 1) % peers.size()]
		_ring_target[hunter] = prey


# Host-only: privately tell each player the node name of their assigned target. Owner-only, so
# nobody else learns it. The exposure arrow tracks them (and flips to the hunt flash once you
# finish your marks). Calling _send_target_to again RETARGETS that player (used on reassignment).
func _notify_targets() -> void:
	if not multiplayer.is_server():
		return
	for peer_id in _ring_target:
		_send_target_to(peer_id)


func _send_target_to(peer_id: int) -> void:
	var target_peer: int = int(_ring_target.get(peer_id, 0))
	if target_peer == 0 or not _players_by_peer.has(target_peer):
		return
	var target := _players_by_peer[target_peer] as Node
	if target == null or not is_instance_valid(target):
		return
	_receive_target.rpc_id(peer_id, String(target.name))


# Owner-only: our assigned target's node name. The first arrives at match start; a later one
# (after our target was killed) RETARGETS us — drop the old resolved target + arrow so the
# per-frame view rebuilds them for the new target.
@rpc("authority", "call_local", "reliable")
func _receive_target(target_name: String) -> void:
	if target_name == _my_target_name:
		return
	_my_target_name = target_name
	_my_target = null
	if _target_arrow != null and is_instance_valid(_target_arrow):
		_target_arrow.queue_free()
	_target_arrow = null


func _spawn_player_for_peer(peer_id: int) -> void:
	# This peer's chosen look. If they submitted a loadout on join we use it; otherwise we
	# build a sensible default (a body from their spawn order + the DEFAULT items). Either
	# way the spawner replicates it to everyone, so all peers render this player identically.
	var loadout_payload := _loadout_for_peer(peer_id)
	# Placeholder-era test aid (§0.3): with no real cosmetics every account defaults to the same
	# body, so the per-viewer crowd would be invisible. Force a DISTINCT body per player so you
	# can SEE it working. Drop this flag once players pick real, distinct cosmetics.
	if placeholder_distinct_bodies:
		loadout_payload = _with_body_index(loadout_payload, _next_spawn_index % NUM_SHEETS)
	var spawn_data := {
		"peer": peer_id,
		"pos": _spawn_position_for_index(_next_spawn_index),
		"appearance": _body_index_from_payload(loadout_payload),
		"loadout": loadout_payload,
	}
	var character := _player_spawner.spawn(spawn_data)
	_players_by_peer[peer_id] = character
	_next_spawn_index += 1

	# Start this peer's score row (host-only). _player_num is 1-based spawn order, for the
	# scoreboard ("Player 1/2/3/4").
	_player_num[peer_id] = _next_spawn_index
	_exposure_sum[peer_id] = 0.0
	_exposure_samples[peer_id] = 0
	_kills_by_peer[peer_id] = 0
	_completed_by_peer[peer_id] = false
	_dead_by_peer[peer_id] = false

	# Host relays THIS player's exposure to its owner only (private — §4). The signal
	# fires only when the value changes, so this isn't a constant stream.
	var exposure := character.get_node_or_null("ExposureComponent")
	if exposure != null:
		exposure.exposure_changed.connect(_on_player_exposure_changed.bind(peer_id))

	# Host watches for this player being killed (eliminates them; ends the match if last).
	character.died.connect(_on_player_killed.bind(peer_id))

	# Count this player's clean kills for scoring. request_kill emits kill_landed on the HOST
	# (where it resolves), so this fires even though the client's KillComponent is frozen here.
	var kill := character.get_node_or_null("KillComponent") as KillComponent
	if kill != null:
		kill.kill_landed.connect(_on_peer_kill_landed.bind(peer_id))
		# Phase 9: re-announce this player's kills (clean AND whiff) at the match level.
		kill.kill_resolved.connect(_relay_kill_resolved)

	# Host owns this player's item kit: relay cloak to the opponent's arrow and push the
	# charges readout to the owner whenever it changes (Slice D).
	var item := character.get_node_or_null("ItemComponent") as ItemComponent
	if item != null:
		item.item_activated.connect(_on_item_activated.bind(peer_id))
		item.item_expired.connect(_on_item_expired.bind(peer_id))
		_push_item_state_to(peer_id)

	_update_status()


# Host-side: a player's exposure changed → push it to that player (their own bar) AND
# to their opponent (so the opponent's exposure arrow can react when this player runs).
func _on_player_exposure_changed(value: float, peer_id: int) -> void:
	_receive_exposure.rpc_id(peer_id, value)
	# Feed this player's exposure to whoever is HUNTING them, so that hunter's exposure arrow
	# reacts when their prey runs loud.
	var hunter_peer := _hunter_of_target(peer_id)
	if hunter_peer != 0:
		_receive_opponent_exposure.rpc_id(hunter_peer, value)
	# BLUE reveal (§7.4): hitting 100% exposure reveals your look to EVERY other living player
	# (you've become a beacon), once.
	if value >= 100.0 and not bool(_exposure_revealed.get(peer_id, false)):
		_exposure_revealed[peer_id] = true
		var character := _players_by_peer.get(peer_id) as Player
		if character != null:
			for other_peer in _players_by_peer:
				if other_peer != peer_id and not bool(_dead_by_peer.get(other_peer, false)):
					_receive_exposure_reveal.rpc_id(other_peer, int(character.appearance_index))


# Owner-only: our opponent's exposure, fed to our local copy of them so the exposure
# arrow can decide whether to point (it shows when they run past the threshold).
@rpc("authority", "call_local", "unreliable")
func _receive_opponent_exposure(value: float) -> void:
	if _my_target != null and is_instance_valid(_my_target):
		var exposure := _my_target.get_node_or_null("ExposureComponent") as ExposureComponent
		if exposure != null:
			exposure.exposure = value


# Owner-only: update OUR exposure bar with the host's authoritative value.
@rpc("authority", "call_local", "unreliable")
func _receive_exposure(value: float) -> void:
	if _exposure_bar != null:
		_exposure_bar.value = value


func _on_player_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# If the match was still waiting on this peer to start, stop waiting for them.
	_expected_clients.erase(peer_id)
	_ready_clients.erase(peer_id)
	if _players_by_peer.has(peer_id):
		var character: Node = _players_by_peer[peer_id]
		if is_instance_valid(character):
			character.queue_free()  # the spawner replicates the removal to clients
		_players_by_peer.erase(peer_id)
	# A mid-match departure counts as an elimination: re-link anyone hunting them and end the
	# match if only one player is left.
	if _match_begun and not _match_over:
		_dead_by_peer[peer_id] = true
		_relink_hunters_of(peer_id)
		if _alive_count() <= 1:
			_end_match("last_standing")
	_maybe_begin_match()  # in case we were waiting on the peer who just left (pre-start only)
	_update_status()


# === client =================================================================

func _start_as_client() -> void:
	NetworkManager.connection_failed.connect(_return_to_menu)
	NetworkManager.server_closed.connect(_return_to_menu)
	# Tell the host we're ready for our character — but only once actually connected.
	if _is_connected():
		_announce_ready_to_host()
	else:
		NetworkManager.connection_succeeded.connect(_announce_ready_to_host)


func _is_connected() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _announce_ready_to_host() -> void:
	# Tell the host our chosen look FIRST (a reliable RPC, so it arrives before the spawn
	# request that follows), then ask to be spawned. Sending it once here is the whole
	# join-time loadout sync (§5) — it's static for the match, so nothing repeats per-frame.
	_submit_loadout.rpc_id(1, _local_loadout_payload())
	# "Host, my scene is up — please spawn my character." Runs the host's _request_spawn.
	_request_spawn.rpc_id(1)
	_update_status()


# === shared =================================================================

# Runs on EVERY peer to build a character from the host's spawn data, so it looks
# and sits identically everywhere. Each machine then decides locally (in the player
# script) whether this character is the one it controls.
func _create_networked_player(spawn_data: Dictionary) -> Node:
	var character := PLAYER_SCENE.instantiate() as Player
	character.network_controlled = true
	character.controlling_peer_id = int(spawn_data["peer"])
	character.appearance_index = int(spawn_data["appearance"])
	# Full host-replicated look (ids only). player._setup_network_role applies it via
	# apply_loadout; falls back to appearance_index when absent.
	character.loadout_payload = spawn_data.get("loadout", {})
	character.player_id = int(spawn_data["peer"])
	character.position = spawn_data["pos"]
	# The host decides the look, so stop the visual from picking its own at random.
	var visual := character.get_node_or_null("CharacterVisual")
	if visual != null:
		visual.set("randomize_on_ready", false)
	return character


# Runs on EVERY peer to build a crowd NPC from the host's spawn data, so each NPC
# looks and starts identically everywhere. The host then runs its AI; clients freeze it.
func _create_networked_npc(spawn_data: Dictionary) -> Node:
	var npc := NPC_SCENE.instantiate() as Npc
	npc.network_controlled = true
	npc.appearance_index = int(spawn_data["appearance"])
	# Full host-chosen look (ids only). npc._setup_network_role applies it via apply_loadout;
	# it falls back to appearance_index if this is somehow absent.
	npc.loadout_payload = spawn_data.get("loadout", {})
	npc.position = spawn_data["pos"]
	npc.is_traveler = bool(spawn_data["traveler"])
	npc.home_position = spawn_data["pos"]  # homebodies mill around where they spawned
	npc.wander_radius = float(spawn_data["wander_radius"])
	var visual := npc.get_node_or_null("CharacterVisual")
	if visual != null:
		visual.set("randomize_on_ready", false)
	return npc


# === cosmetic loadouts (network replication, §5) ===========================

# Client → host: "here is the look I have equipped." Sent once on join (see
# _announce_ready_to_host). The host stores it and stamps it into this peer's spawn_data
# so every machine renders them identically. Ids only — near-zero bandwidth, never per-frame.
@rpc("any_peer", "reliable")
func _submit_loadout(payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_loadout_by_peer[sender] = payload
	# ON-CHANGE seam: if this peer already has a live character (a mid-match wardrobe
	# change), we'd re-broadcast + re-apply here. Loadouts are static during a match today
	# (§5), so we only stash it for the (re)spawn. Hook left intentionally for later.


# The loadout payload for the human at THIS machine, read from the account inventory if
# present (built later in CosmeticInventory). Empty when there's no inventory yet — the
# host then falls back to a default look.
func _local_loadout_payload() -> Dictionary:
	var inv := get_node_or_null("/root/CosmeticInventory")
	if inv != null and inv.has_method("equipped_payload"):
		return inv.call("equipped_payload")
	return {}


# Host-only: the payload to spawn `peer_id` with — their submitted loadout if we have it,
# our own inventory for the host's own player, else a sensible default.
func _loadout_for_peer(peer_id: int) -> Dictionary:
	if _loadout_by_peer.has(peer_id):
		return _loadout_by_peer[peer_id]
	if peer_id == multiplayer.get_unique_id():
		var mine := _local_loadout_payload()
		if not mine.is_empty():
			return mine
	return _default_loadout_payload(_next_spawn_index % NUM_SHEETS)


# A baseline loadout: the given body sheet + the DEFAULT (free) items for the other slots.
func _default_loadout_payload(body_index: int) -> Dictionary:
	var loadout := Loadout.new()
	loadout.set_item(CosmeticItem.Slot.BODY, CosmeticRegistry.body_id_for_index(body_index))
	loadout.set_item(CosmeticItem.Slot.OUTFIT, &"outfit_none")
	loadout.set_item(CosmeticItem.Slot.HEAD, &"hat_none")
	loadout.set_item(CosmeticItem.Slot.WEAPON, &"weapon_none")
	return loadout.to_payload()


# A random crowd look drawn from the global pool (the §4 config hook lives in the registry).
func _random_npc_loadout_payload() -> Dictionary:
	return Loadout.randomized(CosmeticRegistry.npc_pool_by_slot()).to_payload()


# Return a copy of `payload` with its BODY slot forced to the given sheet index, leaving the
# rest of the look untouched. Used only by the placeholder_distinct_bodies test aid.
func _with_body_index(payload: Dictionary, body_index: int) -> Dictionary:
	var loadout := Loadout.from_payload(payload)
	loadout.set_item(CosmeticItem.Slot.BODY, CosmeticRegistry.body_id_for_index(body_index))
	return loadout.to_payload()


# Pull the body sheet index back out of a loadout payload, for the legacy `appearance`
# field we still ship alongside the loadout for back-compat.
func _body_index_from_payload(payload: Dictionary) -> int:
	var body_id := Loadout.from_payload(payload).get_item(CosmeticItem.Slot.BODY)
	if body_id == &"":
		return 0
	return CosmeticRegistry.index_for_body_id(body_id)


func _spawn_position_for_index(index: int) -> Vector2:
	var map := _map as TestMap01
	if map != null:
		var spawns := map.get_player_spawns()
		if index >= 0 and index < spawns.size():
			return spawns[index]
	# Fallback if the map has no spawn points: stagger them so they don't overlap.
	return Vector2(-400.0 + index * 200.0, 0.0)


func _return_to_menu() -> void:
	# Pause survives a scene change, so always clear it on the way out (e.g. after the
	# end screen, or if the host drops while we're paused) or the menu would be frozen.
	get_tree().paused = false
	NetworkManager.leave()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# === marks (host picks; only the owner is told) =============================

# Host-only: secretly pick a random wandering crowd member as this peer's mark, mark
# it as killable by that peer, and privately tell ONLY that peer which one it is.
func _assign_mark_for_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or _mark_by_peer.has(peer_id):
		return
	var candidates: Array = []
	for child in _crowd_parent.get_children():
		var npc := child as Npc
		if npc != null and not npc.is_dead() and not npc.is_in_group("mark"):
			candidates.append(npc)
	if candidates.is_empty():
		return
	var chosen: Array = _pick_spaced_marks(candidates, marks_per_player)
	var mark_names: Array = []
	for mark in chosen:
		mark.add_to_group("killable_for_%d" % peer_id)  # the host-validated kill check uses this
		mark.add_to_group("mark")
		# Force the mark to stay LOCAL (note 13): a homebody milling around where it was
		# tagged. The NPC's wander logic reads these live, so changing them now is enough.
		mark.is_traveler = false
		mark.home_position = mark.global_position
		mark.wander_radius = mark_wander_radius
		# Tell the owner privately when this mark dies (the host emits "died" on the kill).
		mark.died.connect(_on_mark_killed.bind(peer_id, String(mark.name)))
		mark_names.append(String(mark.name))
	_mark_by_peer[peer_id] = chosen
	_marks_remaining_by_peer[peer_id] = chosen.size()
	# Send the marks' node names ONLY to their owner. Names match across peers, so the
	# owner can find the same NPCs in its own copy of the crowd.
	_receive_marks.rpc_id(peer_id, mark_names)


# Host-only: pick `count` crowd NPCs to be one player's marks, spread at least
# `mark_min_separation` apart so they can't be scooped together (note 13). Greedy: shuffle,
# take the first, then add any NPC far enough from all picks. If the separation is too
# strict to fill the quota (a tight map), top up with whatever's left so we still hand out
# `count` marks.
func _pick_spaced_marks(candidates: Array, count: int) -> Array:
	var pool: Array = candidates.duplicate()
	pool.shuffle()
	var chosen: Array = []
	for npc in pool:
		if chosen.size() >= count:
			break
		var far_enough := true
		for picked in chosen:
			if picked.global_position.distance_to(npc.global_position) < mark_min_separation:
				far_enough = false
				break
		if far_enough:
			chosen.append(npc)
	if chosen.size() < count:
		for npc in pool:
			if chosen.size() >= count:
				break
			if not chosen.has(npc):
				chosen.append(npc)
	return chosen


# Host-side: one of a peer's marks was killed. Tell the owner so they can drop that
# mark's highlight, then count it off; only once ALL marks are down do we open the hunt
# phase (note 9 — you must clear both marks first).
func _on_mark_killed(peer_id: int, mark_name: String) -> void:
	_notify_mark_down.rpc_id(peer_id, mark_name)
	var remaining: int = int(_marks_remaining_by_peer.get(peer_id, 0)) - 1
	_marks_remaining_by_peer[peer_id] = remaining
	if remaining <= 0:
		_begin_target_phase(peer_id)


# Host-only: the peer has finished their mark, so now they hunt the human opponent.
# We make the opponent killable BY this peer and privately tell this peer who it is.
func _begin_target_phase(peer_id: int) -> void:
	if not multiplayer.is_server() or _phase_by_peer.get(peer_id, "marks") == "target":
		return
	var target_peer := int(_ring_target.get(peer_id, 0))
	if target_peer == 0 or not _players_by_peer.has(target_peer):
		return  # nobody to hunt yet
	_phase_by_peer[peer_id] = "target"
	var target := _players_by_peer[target_peer] as Player
	target.add_to_group("killable_for_%d" % peer_id)  # the kill check now lets us kill them
	_enter_hunt_phase.rpc_id(peer_id)
	# RED reveal (§7.4): the FIRST player to finish their marks learns their target's look.
	if not _target_reveal_awarded:
		_target_reveal_awarded = true
		_receive_target_reveal.rpc_id(peer_id, int(target.appearance_index))


# Returns any other living player's peer id (the opponent). 2-player for now.
func _other_peer(peer_id: int) -> int:
	for other in _players_by_peer:
		if other != peer_id:
			return other
	return 0


# Owner-only: our mark is down — start hunting our opponent. The exposure arrow that's
# been tracking them switches to its stronger FLASHING style.
@rpc("authority", "call_local", "reliable")
func _enter_hunt_phase() -> void:
	_hunt_phase = true
	_clear_mark_highlights()
	_my_mark_names.clear()
	_resolved_marks.clear()
	if _objective_label != null:
		_objective_label.text = "Marks down — HUNT YOUR OPPONENT."
	if _target_arrow != null:
		_target_arrow.set_flashing(true)


# === elimination, scoring & match end (buildplan §7.5) ======================

# Host-side: this player was killed. A death no longer ends the match — it ELIMINATES that
# player (their body is already frozen by Player.die). We attribute the kill, re-link anyone
# who was hunting the dead player onto a live target, and end the match only when ONE is left.
func _on_player_killed(loser_peer: int) -> void:
	if not multiplayer.is_server() or _match_over:
		return
	if bool(_dead_by_peer.get(loser_peer, false)):
		return  # already eliminated
	_dead_by_peer[loser_peer] = true

	# Attribute the kill. request_kill stamps last_attacker_peer on the victim. If the killer
	# was this player's assigned hunter, it COMPLETES their contract (the +contract_bonus).
	var loser := _players_by_peer.get(loser_peer) as Player
	var killer_peer: int = int(loser.get("last_attacker_peer")) if loser != null else -1
	if killer_peer > 0 and int(_ring_target.get(killer_peer, 0)) == loser_peer:
		_completed_by_peer[killer_peer] = true
		_phase_by_peer[killer_peer] = "done"

	# Freeze the corpse on EVERY machine. The host already ran die() on its own copy via the
	# kill; this mirrors it so the dead player's own client stops predicting movement (no
	# spectator rubber-banding) and everyone's arrows treat them as dead.
	if loser != null:
		_freeze_player.rpc(String(loser.name))

	_relink_hunters_of(loser_peer)
	_update_status()
	if _alive_count() <= 1:
		_end_match("last_standing")


# Everyone: freeze a killed player's body locally (idempotent — Player.die guards re-death).
@rpc("authority", "call_local", "reliable")
func _freeze_player(player_name: String) -> void:
	if _players_parent == null:
		return
	var node := _players_parent.get_node_or_null(player_name) as Player
	if node != null and not node.is_dead():
		node.die()


# Re-link anyone whose assigned target is `gone_peer` (just died or left) onto a live opponent,
# so their arrow/reveal keep pointing somewhere real and a contract is still reachable.
func _relink_hunters_of(gone_peer: int) -> void:
	for hunter in _ring_target.keys():
		if int(_ring_target[hunter]) == gone_peer and not bool(_dead_by_peer.get(hunter, false)):
			var new_target := _next_living_target(hunter)
			if new_target != 0 and _players_by_peer.has(new_target):
				_ring_target[hunter] = new_target
				(_players_by_peer[new_target] as Node).add_to_group("killable_for_%d" % hunter)
				if _phase_by_peer.get(hunter, "marks") == "target":
					_send_target_to(hunter)  # retargets their hunt arrow


# Any living player other than `hunter` (used to re-link a hunter whose target just died).
func _next_living_target(hunter: int) -> int:
	for p in _players_by_peer:
		if p != hunter and not bool(_dead_by_peer.get(p, false)):
			return p
	return 0


func _alive_count() -> int:
	var n := 0
	for p in _players_by_peer:
		if not bool(_dead_by_peer.get(p, false)):
			n += 1
	return n


# The peer currently hunting `prey_peer` (0 if none). Used to route exposure → the right arrow.
func _hunter_of_target(prey_peer: int) -> int:
	for hunter in _ring_target:
		if int(_ring_target[hunter]) == prey_peer:
			return hunter
	return 0


# Host-side: tally a clean kill for scoring (fired by the killer's KillComponent on the host).
func _on_peer_kill_landed(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_kills_by_peer[peer_id] = int(_kills_by_peer.get(peer_id, 0)) + 1


# Splice a late joiner into the ring so it stays one connected loop: pick a living player L,
# take L's current target T, then set L -> new_peer -> T.
func _insert_into_ring(new_peer: int) -> void:
	var existing: Array = []
	for p in _ring_target:
		if p != new_peer and not bool(_dead_by_peer.get(p, false)):
			existing.append(p)
	if existing.is_empty():
		var other := _other_peer(new_peer)
		if other != 0:
			_ring_target[new_peer] = other
			_ring_target[other] = new_peer
		return
	existing.shuffle()
	var link: int = existing[0]
	var their_target: int = int(_ring_target.get(link, 0))
	_ring_target[link] = new_peer
	_ring_target[new_peer] = their_target if their_target != 0 else link


# Host-only: per-frame scoring tick — advance the clock, sample every LIVING player's exposure
# (for the round average), and end on the time limit. Stops once the match is decided.
func _host_score_tick(delta: float) -> void:
	if not _match_begun or _match_over:
		return
	_elapsed += delta
	for peer_id in _players_by_peer:
		if bool(_dead_by_peer.get(peer_id, false)):
			continue
		var character := _players_by_peer[peer_id] as Player
		if character == null or not is_instance_valid(character) or character.exposure_component == null:
			continue
		_exposure_sum[peer_id] = float(_exposure_sum.get(peer_id, 0.0)) + character.exposure_component.exposure
		_exposure_samples[peer_id] = int(_exposure_samples.get(peer_id, 0)) + 1
	if round_time_limit > 0.0 and _elapsed >= round_time_limit:
		_end_match("timeout")


# Host-only: score everyone, sort highest-first (ties → lowest average exposure), and broadcast
# the scoreboard so every machine shows the same result and winner.
func _end_match(reason: String) -> void:
	if _match_over:
		return
	_match_over = true
	var rows: Array = []
	for peer_id in _players_by_peer:
		var row := _score_for_peer(peer_id)
		row["peer"] = peer_id
		row["num"] = int(_player_num.get(peer_id, 0))
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["total"]) != int(b["total"]):
			return int(a["total"]) > int(b["total"])
		return float(a["avg_exposure"]) < float(b["avg_exposure"]))
	var winner_peer: int = int(rows[0]["peer"]) if not rows.is_empty() else 0
	_declare_match_over.rpc(rows, winner_peer, reason)


# Host-only: one player's score breakdown (mirrors LocalMatchManager._score_for_player).
func _score_for_peer(peer_id: int) -> Dictionary:
	var samples: int = maxi(1, int(_exposure_samples.get(peer_id, 0)))
	var avg_exposure: float = float(_exposure_sum.get(peer_id, 0.0)) / float(samples)
	var exposure_score: int = int(round((100.0 - avg_exposure) * exposure_weight))
	var speed_score: int = int(maxf(0.0, speed_bonus_cap - _elapsed * speed_bleed_per_second))
	var kill_score: int = int(_kills_by_peer.get(peer_id, 0)) * kill_points
	var outcome_bonus: int = 0
	if bool(_completed_by_peer.get(peer_id, false)):
		outcome_bonus += contract_bonus
	if bool(_dead_by_peer.get(peer_id, false)):
		outcome_bonus -= death_penalty
	var total: int = maxi(0, exposure_score + speed_score + kill_score + outcome_bonus)
	return {
		"avg_exposure": avg_exposure,
		"kills": int(_kills_by_peer.get(peer_id, 0)),
		"completed": bool(_completed_by_peer.get(peer_id, false)),
		"dead": bool(_dead_by_peer.get(peer_id, false)),
		"total": total,
	}


# Everyone: freeze the match and show the scoreboard (winner highlighted, "YOU" tagged).
@rpc("authority", "call_local", "reliable")
func _declare_match_over(rows: Array, winner_peer: int, reason: String) -> void:
	get_tree().paused = true
	_show_scoreboard(rows, winner_peer, reason)


# Fire the local winner's equipped WIN_ANIM on their own rig through the one animation
# entry point (§6). Finds our character by the peer id that controls it. Stub pop today.
func _play_local_win_animation() -> void:
	var my_id := multiplayer.get_unique_id()
	for node in get_tree().get_nodes_in_group("player"):
		if int(node.get("controlling_peer_id")) == my_id:
			var visual := node.get_node_or_null("CharacterVisual")
			if visual != null and visual.has_method("play_cosmetic_animation"):
				visual.call("play_cosmetic_animation", CosmeticItem.Slot.WIN_ANIM)
			return


# The local account's profile identity label ("Badge · Title"), or "" if none / no
# inventory. Display hook for §7 — guarded so play still works without the inventory autoload.
func _local_profile_label() -> String:
	var inv := get_node_or_null("/root/CosmeticInventory")
	if inv != null and inv.has_method("profile"):
		var profile = inv.call("profile")
		if profile != null:
			return profile.label()
	return ""


func _show_scoreboard(rows: Array, winner_peer: int, reason: String) -> void:
	var my_id := multiplayer.get_unique_id()
	var overlay := CanvasLayer.new()
	overlay.name = "EndOverlay"
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS  # keep the buttons live while paused
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 10)
	overlay.add_child(box)

	var headline := Label.new()
	var we_won := winner_peer == my_id
	if we_won:
		_play_local_win_animation()  # fire the winner's WIN_ANIM cosmetic on the results screen (§6)
	headline.text = "YOU WIN" if we_won else ("PLAYER %d WINS" % _num_of(rows, winner_peer))
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.add_theme_font_size_override("font_size", 52)
	box.add_child(headline)

	var sub := Label.new()
	sub.text = "Last assassin standing — most points wins" if reason == "last_standing" else "Time up — most points wins"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	# IDENTITY DISPLAY HOOK (§7): surface THIS account's profile (badge · title) on the
	# results screen — one of the places account identity shows (scoreboard / results /
	# name tag). Placeholder text today; real banner/badge art reads the same ids later.
	var identity := _local_profile_label()
	if identity != "":
		var identity_label := Label.new()
		identity_label.text = identity
		identity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		identity_label.modulate = Color(0.8, 0.85, 1.0)
		box.add_child(identity_label)

	# One line per player, already sorted highest-first.
	for row in rows:
		var line := Label.new()
		var you_tag: String = "   (YOU)" if int(row["peer"]) == my_id else ""
		var status: String = ""
		if bool(row["dead"]):
			status = "   [eliminated]"
		elif bool(row["completed"]):
			status = "   [contract ✓]"
		line.text = "P%d — %d pts   ·   kills %d   ·   avg exp %d%%%s%s" % [
			int(row["num"]), int(row["total"]), int(row["kills"]),
			int(round(float(row["avg_exposure"]))), status, you_tag]
		if int(row["peer"]) == winner_peer:
			line.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))  # gold winner
		line.add_theme_font_size_override("font_size", 20)
		box.add_child(line)

	var rematch_button := Button.new()
	rematch_button.text = "Rematch"
	rematch_button.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_child(rematch_button)
	rematch_button.pressed.connect(func() -> void:
		rematch_button.disabled = true
		rematch_button.text = "Waiting for players…"
		_request_rematch.rpc_id(1))

	var menu_button := Button.new()
	menu_button.text = "Back to menu"
	menu_button.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_child(menu_button)
	menu_button.pressed.connect(func() -> void:
		get_tree().paused = false
		_return_to_menu())


# The 1-based player number for a peer, read from the scoreboard rows.
func _num_of(rows: Array, peer_id: int) -> int:
	for row in rows:
		if int(row["peer"]) == peer_id:
			return int(row["num"])
	return 0


# Host-only: collect rematch votes. Once everyone still connected has voted, reload the match
# for all of them — re-running the start handshake gives a fresh ring, marks, and scores.
@rpc("any_peer", "call_local", "reliable")
func _request_rematch() -> void:
	if not multiplayer.is_server():
		return
	var voter := multiplayer.get_remote_sender_id()
	if voter == 0:
		voter = multiplayer.get_unique_id()
	_rematch_votes[voter] = true
	var needed := multiplayer.get_peers().size() + 1  # all clients + the host
	if _rematch_votes.size() >= needed:
		_do_rematch.rpc()


# Everyone: clear the pause and reload the match scene together for a fresh round.
@rpc("authority", "call_local", "reliable")
func _do_rematch() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(ONLINE_MATCH_SCENE)


# Owner-only: the host tells US which crowd NPCs are our marks. We just remember the
# names; the per-frame view resolves each once that NPC has replicated to us.
@rpc("authority", "call_local", "reliable")
func _receive_marks(mark_names: Array) -> void:
	_my_mark_names = mark_names.duplicate()


# Owner-only: the host tells US one of our marks just died (clients don't see the crowd's
# death state reliably). Drop its highlight and re-point the mini-map at what's left.
@rpc("authority", "call_local", "reliable")
func _notify_mark_down(mark_name: String) -> void:
	var mark: Node2D = _resolved_marks.get(mark_name)
	if mark != null and is_instance_valid(mark):
		var visual := mark.get_node_or_null("CharacterVisual")
		if visual != null and visual.has_method("set_highlight"):
			visual.call("set_highlight", false)
	_my_mark_names.erase(mark_name)
	_resolved_marks.erase(mark_name)
	_refresh_mark_tracking()


# === this machine's private view (host AND client each have one) ============

func _process(delta: float) -> void:
	if NetworkManager.is_host():
		_host_score_tick(delta)  # advance the clock + sample exposure for scoring
	_retry_spawn_if_needed(delta)
	_update_local_view()
	_maybe_assign_crowd_appearances()
	_update_visibility()
	_update_debug_overlay()


# Builds the (hidden) network debug overlay. Toggle it in-match with F3.
func _build_debug_overlay() -> void:
	_debug_layer = CanvasLayer.new()
	_debug_layer.name = "DebugOverlay"
	_debug_layer.visible = false
	add_child(_debug_layer)
	_debug_label = Label.new()
	_debug_label.position = Vector2(24.0, 320.0)
	_debug_label.add_theme_font_size_override("font_size", 16)
	_debug_label.modulate = Color(0.6, 1.0, 0.6)
	_debug_layer.add_child(_debug_label)


func _update_debug_overlay() -> void:
	if not _debug_visible or _debug_label == null:
		return
	var fps := Engine.get_frames_per_second()
	var ping := int(round(NetworkManager.ping_ms()))
	var pending := _local_player.get_pending_input_count() if _local_player != null else 0
	var role := "HOST" if NetworkManager.is_host() else "CLIENT"
	_debug_label.text = "[F3] NET DEBUG\n%s\nFPS: %d\nping: %d ms\npredicted (pending): %d" % [
		role, fps, ping, pending
	]


# Client-only safety net: if our own player hasn't appeared yet, keep asking the host
# every second. _request_spawn is idempotent (the host ignores duplicates), so this is
# harmless and guarantees we're brought in even if the first ask raced the transition.
func _retry_spawn_if_needed(delta: float) -> void:
	if NetworkManager.is_host() or _local_player != null:
		return
	_spawn_retry_timer += delta
	if _spawn_retry_timer >= 1.0:
		_spawn_retry_timer = 0.0
		if _is_connected():
			_request_spawn.rpc_id(1)


# Lazily wires up our own HUD and resolves our mark. Doing it per-frame (instead of
# at one exact moment) sidesteps every network timing race: as soon as our player
# and our mark exist locally, we hook them up — no sooner, no special handshake.
func _update_local_view() -> void:
	if _local_player == null:
		_local_player = _find_local_player()
		if _local_player != null:
			_build_player_hud()

	# Resolve any of our marks that have now replicated to us, highlight each (only THIS
	# screen does, so there's no leak online), and keep the mini-map pointed at one.
	if _crowd_parent != null and not _my_mark_names.is_empty():
		var resolved_any := false
		for mark_name in _my_mark_names:
			if _resolved_marks.has(mark_name):
				continue
			var mark := _crowd_parent.get_node_or_null(mark_name) as Node2D
			if mark != null:
				_resolved_marks[mark_name] = mark
				_highlight_mark(mark)
				resolved_any = true
		if resolved_any:
			_refresh_mark_tracking()

	# Resolve our opponent (known from the start) and raise the exposure arrow that
	# points their way when they run. There are no mini-map pings for players — the
	# arrow is the only hint, and only when they're exposed and off-screen.
	if _my_target == null and _my_target_name != "" and _players_parent != null and _player_hud_layer != null:
		var opponent := _players_parent.get_node_or_null(_my_target_name) as Node2D
		if opponent != null:
			_my_target = opponent
			_build_target_arrow(opponent)


func _find_local_player() -> Player:
	if _players_parent == null:
		return null
	var my_id := multiplayer.get_unique_id()
	for child in _players_parent.get_children():
		var player := child as Player
		if player != null and player.controlling_peer_id == my_id:
			return player
	return null


func _build_player_hud() -> void:
	_player_hud_layer = CanvasLayer.new()
	_player_hud_layer.name = "PlayerHUD"
	add_child(_player_hud_layer)

	# Your OWN exposure bar (private — the host sends only your value to you).
	var exposure_caption := Label.new()
	exposure_caption.position = Vector2(24.0, 78.0)
	exposure_caption.add_theme_font_size_override("font_size", 14)
	exposure_caption.text = "EXPOSURE"
	_player_hud_layer.add_child(exposure_caption)

	_exposure_bar = ProgressBar.new()
	_exposure_bar.name = "ExposureBar"
	_exposure_bar.min_value = 0.0
	_exposure_bar.max_value = 100.0
	_exposure_bar.show_percentage = false
	_exposure_bar.position = Vector2(24.0, 100.0)
	_exposure_bar.custom_minimum_size = Vector2(300.0, 22.0)
	_exposure_bar.size = Vector2(300.0, 22.0)
	_player_hud_layer.add_child(_exposure_bar)

	_objective_label = Label.new()
	_objective_label.position = Vector2(24.0, 132.0)
	_objective_label.add_theme_font_size_override("font_size", 18)
	_objective_label.text = "Locating your mark..."
	_player_hud_layer.add_child(_objective_label)

	_mini_map = MINI_MAP_SCRIPT.new() as MiniMap
	_mini_map.name = "MiniMap"
	_player_hud_layer.add_child(_mini_map)
	_mini_map.setup(_map as TestMap01, _local_player, null)
	# Top-right corner of this player's screen.
	var screen_width := get_viewport().get_visible_rect().size.x
	_mini_map.position = Vector2(screen_width - _mini_map.map_size_px.x - 24.0, 24.0)

	_build_layer_feedback()   # sewer overlay + arrow uptime (Slice B)
	_build_item_hud()         # smoke/cloak charges readout (Slice D)
	_build_faceplate_row()    # red/blue identity reveals (Slice E)


func _highlight_mark(mark: Node) -> void:
	var visual := mark.get_node_or_null("CharacterVisual")
	if visual != null and visual.has_method("set_highlight"):
		visual.call("set_highlight", true)


# Point the mini-map at the first still-living mark and update the "x / y done" caption.
# Called when a mark resolves locally or when the host tells us one died.
func _refresh_mark_tracking() -> void:
	var living: Array = []
	for mark_name in _my_mark_names:
		var mark: Node2D = _resolved_marks.get(mark_name)
		if mark != null and is_instance_valid(mark):
			living.append(mark)
	if _mini_map != null:
		_mini_map.track_objective(living[0] if not living.is_empty() else null)
	if _objective_label != null and not _hunt_phase:
		if _my_mark_names.is_empty():
			_objective_label.text = "Locating your marks..."
		else:
			_objective_label.text = "Kill your marks (gold dots) — %d left." % living.size()


# Drop the highlight on every mark we still hold a reference to (used when the hunt
# phase opens, so no stale ring lingers on a corpse).
func _clear_mark_highlights() -> void:
	for mark_name in _resolved_marks:
		var mark: Node2D = _resolved_marks[mark_name]
		if mark != null and is_instance_valid(mark):
			var visual := mark.get_node_or_null("CharacterVisual")
			if visual != null and visual.has_method("set_highlight"):
				visual.call("set_highlight", false)


# An arrow that points toward our opponent when they're off-screen. It starts in
# exposure-gated mode (only shows when they run past the threshold) and flips to a
# periodic flash once we've finished our mark. It uses the active camera (ours).
func _build_target_arrow(opponent: Node2D) -> void:
	if _player_hud_layer == null:
		return
	_target_arrow = ExposureArrow.new()
	_target_arrow.name = "TargetArrow"
	_player_hud_layer.add_child(_target_arrow)
	_target_arrow.track_target(opponent)
	if _hunt_phase:
		_target_arrow.set_flashing(true)
	# If we're already in the sewer when the arrow is created, give it 100% uptime now.
	var layer_comp := _local_player.get_node_or_null("LayerComponent") as LayerComponent
	if layer_comp != null and layer_comp.current_layer == _LAYER_SEWER:
		_target_arrow.set_sewer_mode(true)


# === Slice B — per-viewer visibility (the hidden view, §7.2b / §0.3) =========
# Each machine hides the characters its OWN player shouldn't see, from the host-replicated
# layer (+ smoke) carried on every character. Local-only — never touches the host's sim.
func _update_visibility() -> void:
	if _local_player == null or not is_instance_valid(_local_player):
		return
	var my_layer := _layer_of_character(_local_player)
	for parent in [_players_parent, _crowd_parent]:
		if parent == null:
			continue
		for child in parent.get_children():
			var character := child as Node2D
			if character == null:
				continue
			if character == _local_player:
				character.visible = true  # you always see yourself
			else:
				character.visible = _can_local_player_see(my_layer, character)


func _layer_of_character(character: Node) -> int:
	var layer_comp := character.get_node_or_null("LayerComponent") as LayerComponent
	if layer_comp != null:
		return layer_comp.current_layer
	return _LAYER_GROUND  # the crowd has no LayerComponent → always on the ground


func _can_local_player_see(my_layer: int, other: Node2D) -> bool:
	# A smoked player is invisible to everyone else, whatever the layer (§7.6).
	if other is Player and bool(other.get("_net_smoked")):
		return false
	var other_layer := _layer_of_character(other)
	match my_layer:
		_LAYER_SEWER:
			return false  # blind underground: you see no one (the overlay covers the world)
		_LAYER_ROOFTOP:
			if other_layer == _LAYER_GROUND:
				return true  # the vantage: watch the ground below
			if other_layer == _LAYER_ROOFTOP:
				return rooftop_sees_rooftop
			return false  # can't see down into the sewer
		_:  # GROUND
			return other_layer == _LAYER_GROUND


# === §0.3 — per-viewer crowd APPEARANCE (the hidden-identity pillar) ==========
# Visibility (above) decides WHO you see; this decides WHAT they look like. On THIS screen the
# crowd is rebuilt from copies of the OTHER players' looks (+ filler), with YOUR own look taken
# out, so you're never shown a copy of yourself and each real opponent hides inside a group of
# look-alikes. Local-only (it never touches the host's sim or replication) and run ONCE, frozen
# — a stable disguise pool. Keyed on the Loadout, so real cosmetics later flow through unchanged.

# Run the reskin once, as soon as it's safe: our own player exists AND the whole crowd has
# replicated in (NPCs arrive over several frames on a client). Latched so it never repeats.
func _maybe_assign_crowd_appearances() -> void:
	if _crowd_appearance_done or not per_viewer_crowd_enabled:
		return
	if _local_player == null or _crowd_parent == null:
		return
	# Every peer can compute the crowd size itself (it knows the same lobby choice), so a client
	# can tell when its crowd is fully here without any extra network message.
	var expected_crowd := compact_npc_count if NetworkManager.small_arena else npc_count
	if _crowd_parent.get_child_count() < expected_crowd:
		return  # still arriving — wait for the last NPC so the dupe/filler counts come out right
	_crowd_appearance_done = true
	_assign_crowd_appearances()


# Rebuild every crowd NPC's look on THIS machine from the per-viewer pool (§0.3).
func _assign_crowd_appearances() -> void:
	# Our own look — the one thing that must NEVER appear out in our crowd.
	var my_key := _look_key(_loadout_of_player(_local_player))

	# The looks we DUPLICATE into the crowd: every OTHER player's loadout (never our own).
	var other_looks: Array = []  # Array[Loadout]
	for child in _players_parent.get_children():
		var other := child as Player
		if other != null and other != _local_player:
			other_looks.append(_loadout_of_player(other))

	# The crowd NPCs on THIS machine (marks included — they're ordinary crowd folk to look at).
	var npcs: Array = []
	for child in _crowd_parent.get_children():
		if child is Npc:
			npcs.append(child)
	if npcs.is_empty():
		return
	var crowd_size := npcs.size()

	# CLONES + FILLER. Most of the crowd is generic filler civilians; a tunable fraction
	# (clone_crowd_fraction) are CLONES of the OTHER players, split evenly across opponents so each
	# is hidden in a pocket of look-alikes (§2A). Your own look never appears. With no opponents yet
	# the crowd is all filler.
	var looks: Array = []  # Array[Loadout]
	var clone_total := 0
	if not other_looks.is_empty():
		clone_total = int(round(crowd_size * clampf(clone_crowd_fraction, 0.0, 1.0)))
	for i in clone_total:
		looks.append(other_looks[i % other_looks.size()])  # round-robin = balanced groups
	# Fill the rest with filler base looks, re-rolling any that would match OUR look.
	var pool := CosmeticRegistry.npc_pool_by_slot()
	var guard := 0  # stop a pathological pool (e.g. a single body) from looping forever
	while looks.size() < crowd_size:
		var filler := Loadout.randomized(pool)
		guard += 1
		if _look_key(filler) != my_key or guard > crowd_size * 8:
			looks.append(filler)
	# Scatter the clones through the crowd instead of clumping one player's look together.
	looks.shuffle()

	for i in npcs.size():
		var visual := (npcs[i] as Node).get_node_or_null("CharacterVisual")
		if visual != null and visual.has_method("apply_loadout"):
			visual.call("apply_loadout", (looks[i] as Loadout).duplicate_loadout())


# A character's VISIBLE identity, used to keep our own look out of the crowd. Today only the
# BODY layer is painted (outfit/head/weapon are art-less placeholders), so the body sheet IS
# the visible identity. THIS is the seam: when overlay art lands, fold the other slot ids in
# here and the "never see myself" rule sharpens automatically — every caller routes through it.
func _look_key(loadout: Loadout) -> StringName:
	return loadout.get_item(CosmeticItem.Slot.BODY) if loadout != null else &""


# Read a spawned character's equipped look back out as a Loadout — its host-assigned payload,
# or the legacy body index as a fallback. Used to source the per-viewer crowd from the players.
func _loadout_of_player(character: Node) -> Loadout:
	if character == null:
		return Loadout.new()
	var payload: Dictionary = character.get("loadout_payload")
	if payload != null and not payload.is_empty():
		return Loadout.from_payload(payload)
	var loadout := Loadout.new()
	loadout.set_item(CosmeticItem.Slot.BODY, CosmeticRegistry.body_id_for_index(int(character.get("appearance_index"))))
	return loadout


# Build the sewer screen overlay and wire it (+ the arrow's 100% uptime) to OUR layer.
func _build_layer_feedback() -> void:
	if _player_hud_layer == null or _local_player == null:
		return
	_sewer_overlay = ColorRect.new()
	_sewer_overlay.name = "SewerOverlay"
	_sewer_overlay.color = Color(0.02, 0.03, 0.04, 0.82)
	_sewer_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sewer_overlay.visible = false
	_sewer_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_hud_layer.add_child(_sewer_overlay)
	_player_hud_layer.move_child(_sewer_overlay, 0)  # behind the rest of the HUD (dim the WORLD only)
	var layer_comp := _local_player.get_node_or_null("LayerComponent") as LayerComponent
	if layer_comp != null:
		layer_comp.layer_changed.connect(_on_local_layer_changed)
		_on_local_layer_changed(layer_comp.current_layer)


func _on_local_layer_changed(new_layer: int) -> void:
	var in_sewer := new_layer == _LAYER_SEWER
	if _sewer_overlay != null:
		_sewer_overlay.visible = in_sewer
	if _target_arrow != null:
		_target_arrow.set_sewer_mode(in_sewer)


# === Slice C — access-point claim + cooldown replication (§7.3) ==============
# Index every access point on THIS machine. On the host, listen for claims/lockouts and
# broadcast them so every client's marker shows the same "claimed / on cooldown" state.
func _wire_access_points() -> void:
	for node in get_tree().get_nodes_in_group("access_point"):
		var point := node as AccessPoint
		if point == null:
			continue
		_access_points_by_index[point.access_index] = point
		if NetworkManager.is_host():
			point.claim_changed.connect(func(owner_id: int) -> void:
				_apply_access_claim.rpc(point.access_index, owner_id))
			point.cooldown_started.connect(func() -> void:
				_apply_access_cooldown.rpc(point.access_index))


# Clients only (the host already applied it directly): reflect a claim / a lockout start.
@rpc("authority", "reliable")
func _apply_access_claim(index: int, owner_id: int) -> void:
	var point := _access_points_by_index.get(index) as AccessPoint
	if point != null:
		point.apply_claim_replicated(owner_id)


@rpc("authority", "reliable")
func _apply_access_cooldown(index: int) -> void:
	var point := _access_points_by_index.get(index) as AccessPoint
	if point != null:
		point.apply_cooldown_replicated()


# === Slice D — item kit HUD + cloak routing (§7.6) ==========================
func _build_item_hud() -> void:
	_item_label = Label.new()
	_item_label.name = "ItemLabel"
	_item_label.position = Vector2(24.0, 168.0)
	_item_label.add_theme_font_size_override("font_size", 16)
	_player_hud_layer.add_child(_item_label)
	_refresh_item_label()


func _refresh_item_label() -> void:
	if _item_label == null:
		return
	var smoke_on: String = " (ON)" if bool(_item_state["smoke_on"]) else ""
	var cloak_on: String = " (ON)" if bool(_item_state["cloak_on"]) else ""
	_item_label.text = "SMOKE x%d%s   CLOAK x%d%s" % [
		int(_item_state["smoke"]), smoke_on, int(_item_state["cloak"]), cloak_on]


# HOST: a player's item turned on. Update the owner's readout; for CLOAK, suppress the hunt
# arrow held by whoever is HUNTING this player (their exposure arrow still fires).
func _on_item_activated(which: int, _duration: float, peer_id: int) -> void:
	_push_item_state_to(peer_id)
	if which == ItemComponent.Item.CLOAK:
		var hunter := _hunter_of_target(peer_id)
		if hunter != 0:
			_set_opponent_arrow_suppressed.rpc_id(hunter, true)


func _on_item_expired(which: int, peer_id: int) -> void:
	_push_item_state_to(peer_id)
	if which == ItemComponent.Item.CLOAK:
		var hunter := _hunter_of_target(peer_id)
		if hunter != 0:
			_set_opponent_arrow_suppressed.rpc_id(hunter, false)


# HOST: send a player their authoritative item charges + active state (owner-only).
func _push_item_state_to(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var character := _players_by_peer.get(peer_id) as Node
	if character == null:
		return
	var item := character.get_node_or_null("ItemComponent") as ItemComponent
	if item == null:
		return
	_receive_item_state.rpc_id(peer_id,
		item.charges_left(ItemComponent.Item.SMOKE),
		item.charges_left(ItemComponent.Item.CLOAK),
		item.smoke_active(), item.cloak_active())


# Owner-only: update our item readout with the host's authoritative numbers.
@rpc("authority", "call_local", "reliable")
func _receive_item_state(smoke_left: int, cloak_left: int, smoke_on: bool, cloak_on: bool) -> void:
	_item_state = {"smoke": smoke_left, "cloak": cloak_left, "smoke_on": smoke_on, "cloak_on": cloak_on}
	_refresh_item_label()


# Owner-only: the player we hunt raised a cloak — hide our hunt arrow on them.
@rpc("authority", "call_local", "reliable")
func _set_opponent_arrow_suppressed(on: bool) -> void:
	if _target_arrow != null:
		_target_arrow.set_suppressed(on)


# === Slice E — identity reveals + faceplates (§7.4) =========================
func _build_faceplate_row() -> void:
	_faceplates = FaceplateRow.new()
	_faceplates.name = "FaceplateRow"
	var screen_width := get_viewport().get_visible_rect().size.x
	_faceplates.position = Vector2(screen_width * 0.5 - 130.0, 16.0)
	_faceplates.custom_minimum_size = Vector2(260.0, 60.0)
	_player_hud_layer.add_child(_faceplates)
	# Apply any reveal that arrived before this HUD existed.
	if _pending_target_face >= 0:
		_faceplates.set_target_face(_pending_target_face)
	for index in _pending_exposed_faces:
		_faceplates.add_exposed_face(index)


# Owner-only: we finished our marks first — here's our target's look (red plate).
@rpc("authority", "call_local", "reliable")
func _receive_target_reveal(appearance_index: int) -> void:
	if _faceplates != null:
		_faceplates.set_target_face(appearance_index)
	else:
		_pending_target_face = appearance_index


# Owner-only: an opponent hit 100% exposure — here's their look (blue plate).
@rpc("authority", "call_local", "reliable")
func _receive_exposure_reveal(appearance_index: int) -> void:
	if _faceplates != null:
		_faceplates.add_exposed_face(appearance_index)
	elif not _pending_exposed_faces.has(appearance_index):
		_pending_exposed_faces.append(appearance_index)


# === minimal on-screen status (6.0 debugging aid) ===========================

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	_status_label = Label.new()
	_status_label.position = Vector2(24.0, 20.0)
	_status_label.add_theme_font_size_override("font_size", 18)
	layer.add_child(_status_label)
	_update_status()


func _update_status() -> void:
	if _status_label == null:
		return
	var role := "HOST" if NetworkManager.is_host() else "CLIENT"
	var connected := _players_by_peer.size() if NetworkManager.is_host() else (1 if _is_connected() else 0)
	_status_label.text = "%s  (peer %d)   players: %d\nWASD move · Shift run · Esc menu" % [
		role, NetworkManager.local_peer_id(), connected,
	]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Quick escape back to the menu while prototyping.
		if event.keycode == KEY_ESCAPE:
			_return_to_menu()
		# F3 toggles the network debug overlay (FPS / ping / pending inputs).
		elif event.keycode == KEY_F3:
			_debug_visible = not _debug_visible
			if _debug_layer != null:
				_debug_layer.visible = _debug_visible


# ===========================================================================
# PHASE 9 EXPERIMENT SUPPORT (PHASE_9_EXPERIMENTS.md) — host-side hooks + read-only accessors.
# online_match emits one kill signal and offers a few getters. It names NO experiment, so any
# experiment can be deleted with zero impact here (the delete test, §1.4).
# ===========================================================================

# Re-emit a player's resolved kill at the match level (wired from each KillComponent on spawn).
func _relay_kill_resolved(killer: Node, victim: Node, was_valid: bool) -> void:
	host_kill_resolved.emit(killer, victim, was_valid)


# Spin up whatever experiment scripts live in scripts/experiments/. This loop loads whatever .gd
# files are present and names none of them, so deleting an experiment file is a clean removal.
# Every peer runs this and names each node after its file, so an experiment's owner-only cue RPCs
# resolve to the matching node on every machine. Each experiment is inert unless its flag is on.
func _spawn_experiments() -> void:
	var dir := DirAccess.open("res://scripts/experiments")
	if dir == null:
		return  # folder absent (all experiments removed) — base game runs untouched
	var holder := Node.new()
	holder.name = "Experiments"
	add_child(holder)
	for file_name in dir.get_files():
		if not file_name.ends_with(".gd"):
			continue
		var script: Script = load("res://scripts/experiments/" + file_name)
		if script == null:
			continue
		var node := Node.new()
		node.name = file_name.get_basename()
		node.set_script(script)
		holder.add_child(node)


# How far through the round we are, 0..1 (host clock; 0 if there's no time limit). Used by 9B.
func round_fraction() -> float:
	if round_time_limit <= 0.0:
		return 0.0
	return clampf(_elapsed / round_time_limit, 0.0, 1.0)


# The local machine's HUD layer, where a client renders any cue the host sends it (9C/9D/9F).
func local_hud_layer() -> CanvasLayer:
	return _player_hud_layer


# The player controlled at THIS machine (for a client to position a direction/intensity cue).
func local_player_body() -> Node2D:
	return _local_player


# Host-only: every hunter→target edge in the ring whose BOTH ends are still alive, with whether
# each end has finished its marks (is in the hunt phase). 9D/9F read this to find pairs to cue.
func host_hunt_edges() -> Array:
	var edges: Array = []
	if not multiplayer.is_server():
		return edges
	for hunter_peer in _ring_target:
		var target_peer: int = int(_ring_target[hunter_peer])
		var hunter := _players_by_peer.get(hunter_peer) as Node2D
		var target := _players_by_peer.get(target_peer) as Node2D
		if hunter == null or target == null or not is_instance_valid(hunter) or not is_instance_valid(target):
			continue
		if bool(_dead_by_peer.get(hunter_peer, false)) or bool(_dead_by_peer.get(target_peer, false)):
			continue
		edges.append({
			"hunter": hunter, "target": target,
			"hunter_peer": hunter_peer, "target_peer": target_peer,
			"hunter_ready": _is_hunt_ready(hunter_peer),
			"target_ready": _is_hunt_ready(target_peer),
		})
	return edges


# Host-only: has this peer cleared all its NPC marks (so the human-hunt phase is open for them)?
func _is_hunt_ready(peer: int) -> bool:
	return int(_marks_remaining_by_peer.get(peer, marks_per_player)) <= 0
