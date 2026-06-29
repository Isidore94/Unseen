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
const ROME_SCENE := preload("res://maps/rome.tscn")  # Phase 10 — street-only small map
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const NPC_SCENE := preload("res://scenes/npc.tscn")
const MINI_MAP_SCRIPT := preload("res://scripts/mini_map.gd")
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
## Reloaded on a rematch (re-runs the whole start handshake with everyone still connected).
const ONLINE_MATCH_SCENE := "res://scenes/online_match.tscn"

## Crowd size for the COMPACT/Rome arenas (the lobby's small maps use this instead of npc_count).
## Tighter crowd (Phase 9 decision): a smaller, readable haystack. At clone_crowd_fraction = 0.25
## this is ~10 clones + ~30 filler. Raise it (or the fraction) if hiding feels too easy.
@export var compact_npc_count: int = 55

## How many sprite sheets exist (assets/sprites). Keep in sync with CharacterVisual's sheet list.
const NUM_SHEETS := 15
## Body index of the first ASSASSIN skin in CharacterVisual.SHEET_TEXTURES / CosmeticRegistry. The
## 4 premium assassin looks sit at 11–14; showcase config puts each player on a distinct one.
const ASSASSIN_BODY_BASE := 11
const ASSASSIN_BODY_COUNT := 4
## Per-player roster colours (top-right scoreboard), by spawn order.
const ROSTER_COLORS := [Color(0.3, 0.7, 1.0), Color(0.4, 0.85, 0.4), Color(0.95, 0.6, 0.25), Color(0.7, 0.5, 0.95)]

## Size of the AI crowd the host simulates (the people you hide among). Tightened in Phase 9 to a
## smaller, readable crowd; at clone_crowd_fraction = 0.25 that's ~15 clones + ~45 filler.
@export var npc_count: int = 78

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
## OFF now that players pick their assassin in the lobby — their chosen look is used as-is
## (the lobby always equips one, so each player still spawns as a distinct assassin).
@export var placeholder_distinct_bodies: bool = false

# === scoring (buildplan §7.5 — winner = most points; mirrors LocalMatchManager) ========
# The match runs until ONE player is left alive (or time runs out); the WINNER is then
# whoever has the most points — NOT necessarily the survivor. These tunables mirror the
# offline LocalMatchManager so online and offline score the same way.
## Seconds before the match times out and is scored as-is (0 = no limit).
@export var round_time_limit: float = 300.0
## Start-of-round countdown (seconds). Players are frozen and kills blocked until it ends — this is
## the window for the per-viewer crowd reskin + replication to settle before play begins.
@export var round_start_countdown: float = 3.0
## Points per % of "ghostliness" (100 − your average exposure). Low exposure is the fantasy.
@export var exposure_weight: float = 5.0
## Starting speed bonus; it bleeds away over the match, rewarding a fast clean game.
@export var speed_bonus_cap: float = 500.0
@export var speed_bleed_per_second: float = 2.0
## Points for each clean kill (your marks + the player you eliminate).
@export var kill_points: int = 100
## Points for killing a PLAYER (the PvP payoff) — MASSIVE vs an NPC mark, so taking out a human
## dominates the scoreboard. Counted separately from NPC-mark kills.
@export var player_kill_points: int = 1000
## Awarded for COMPLETING your contract (killing your assigned target) — an achievement that
## scores points, not a circular "you won" flag (the winner is decided from the totals).
@export var contract_bonus: int = 500
## Subtracted from a player who is eliminated — being killed caps what you can still earn.
@export var death_penalty: int = 300

# === KILL-QUALITY BONUSES (AC Rearmed-style) — extra points + an on-screen label per stylish kill ===
## Killer's exposure at/under this when they kill their target = INCOGNITO (the unseen-kill bonus).
@export var incognito_exposure_max: float = 25.0
## ...at/under this (but over incognito) = the smaller DISCREET bonus.
@export var discreet_exposure_max: float = 60.0
@export var incognito_bonus: int = 300
@export var discreet_bonus: int = 150
## Bonus for a silent POISON kill on your target.
@export var poison_bonus: int = 150
## Bonus for killing the player who most recently killed YOU (REVENGE).
@export var revenge_bonus: int = 200
var _style_bonus_by_peer: Dictionary = {}  ## peer -> accumulated kill-quality bonus points
var _last_killed_by: Dictionary = {}       ## peer -> the peer who most recently killed them (for revenge)

# === RESPAWN MODE (RESPAWN_MODE_PLAN.md) — only active when GameModeFlags.respawn_mode_enabled =====
## Seconds a killed player stays down (corpse) before respawning at a fresh life.
@export var respawn_delay_seconds: float = 2.5
## Post-respawn grace: seconds the fresh life is immune to kills (anti spawn-farm); breaks if they kill.
@export var respawn_grace_seconds: float = 2.0
## Spawn picker: how many walkable points to sample as respawn candidates per death.
@export var spawn_candidate_samples: int = 24
## Spawn picker: candidates within this radius (px) of ANY live player are excluded (their contact/visual zone).
@export var spawn_contact_exclusion_px: float = 360.0
## Spawn picker: candidates within this radius (px) of your KILLER are excluded (anti-farm).
@export var spawn_anti_farm_px: float = 900.0
## Spawn picker: weight on local crowd density (favour respawning already blended into a crowd).
@export var spawn_density_weight: float = 1.0
## Spawn picker: radius (px) the crowd-density count is measured over at each candidate point.
@export var spawn_density_radius_px: float = 360.0
## Spawn picker: weight on closeness to your new target (start with a hunt, not a long commute).
@export var spawn_target_proximity_weight: float = 0.0008
## Spawn picker: pick at random among the top-N scoring candidates so spawns aren't campable.
@export var spawn_topk: int = 4

const NO_POS := Vector2(INF, INF)
var _seat_order: Array = []        ## fixed peer order set at match start; target = next LIVING peer in it
var _respawn_due: Dictionary = {}  ## peer -> seconds left until respawn
var _grace_due: Dictionary = {}    ## peer -> seconds left of post-respawn grace

# === PvE LADDER (RESPAWN_MODE_PLAN.md §6) — only when GameModeFlags.pve_ladder_enabled ============
## Optional NPC marks offered per life. Killing one grants an upgrade point you spend (your choice)
## on arrow PRECISION or unlocking your 2nd TOOL — capped per axis; all of it resets on death.
@export var pve_marks_per_life: int = 3
const LADDER_PRECISION_CAP := 2   ## arrow tiers above base (0 -> 1 -> 2)
const LADDER_TOOL_CAP := 1        ## tool unlocks above base (unlock slot 1)
var _ladder_tier_by_peer: Dictionary = {}    ## peer -> arrow precision tier (0..LADDER_PRECISION_CAP)
var _ladder_tools_by_peer: Dictionary = {}   ## peer -> tool steps spent (0..LADDER_TOOL_CAP)
var _ladder_pending_by_peer: Dictionary = {} ## peer -> unspent upgrade points
var _ladder_marks_by_peer: Dictionary = {}   ## peer -> Array[Npc] marks assigned this life
# Owner-side (this machine's local player):
var _my_arrow_tier: int = 0
var _my_ladder_pending: int = 0

# === HUNTER-DANGER CUES (AC Rearmed-style pursuer warning) =========================================
## Distance (px) under which your assigned hunter triggers the NEAR cue (level 1: glow + slow heartbeat).
@export var danger_near_px: float = 900.0
## Distance (px) under which your hunter triggers the VERY-NEAR cue (level 2: brighter + fast heartbeat).
@export var danger_close_px: float = 460.0
## How often (seconds) the host re-evaluates everyone's danger level.
@export var danger_eval_interval: float = 0.25
var _danger_overlay: DangerOverlay = null
var _danger_accum: float = 0.0
var _danger_level_by_peer: Dictionary = {}  ## last level sent to each peer (only re-sent on change)

# === FIRECRACKER tool (AC Rearmed flashbang) ======================================================
## Radius (px) of the firecracker's instant stun burst.
@export var firecracker_radius: float = 320.0
## How long (seconds) players caught in the burst are stunned (can't move or kill).
@export var firecracker_stun_seconds: float = 1.6

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
var _kills_by_peer: Dictionary = {}     # peer -> clean kills landed (NPC marks + players)
var _player_kills_by_peer: Dictionary = {}  # peer -> PLAYER kills (subset of above; scored huge)
var _completed_by_peer: Dictionary = {} # peer -> killed their assigned target?
var _dead_by_peer: Dictionary = {}      # peer -> eliminated?
var _elapsed: float = 0.0               # match time (host clock; clients tick locally for the timer)
var _roster_accum: float = 0.0          # throttle for the host's ~1Hz roster broadcast

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
## Round-start countdown state. `_round_active` flips true (host) when the countdown ends and the
## freeze lifts. `_round_countdown` is the host's authoritative timer; `_countdown_display`/`_go_left`
## drive the local "3/2/1/GO!" overlay on every peer.
var _round_active: bool = false
var _round_countdown: float = 0.0
var _countdown_display: float = 0.0
var _go_left: float = 0.0

## This machine's own private view. Host AND client each control one local player and
## each builds its own HUD + mini-map + mark highlight for that player only.
var _local_player: Player = null
var _player_hud_layer: CanvasLayer = null
var _mini_map: MiniMap = null
var _objective_label: Label = null
var _exposure_bar: ProgressBar = null
var _mhud: MatchHud = null   ## the premium themed HUD (panels); _player_hud_layer keeps the cues/overlays
## A CanvasLayer ABOVE the HUD panels, just for the exposure/hunt arrow, so the arrow is never
## hidden behind a corner panel (the sewer-dim overlay must stay BELOW the panels, so the arrow
## can't share _player_hud_layer with it).
var _arrow_layer: CanvasLayer = null

## --- spectate (after THIS machine's player is eliminated) ---
## True once our local player has died: their GUI is hidden and we drive a free camera instead.
var _spectating: bool = false
## The free-roam camera the eliminated player flies with WASD / the left stick.
var _spectate_camera: Camera2D = null
## The "ELIMINATED" banner layer, kept so we can hide it when the end scoreboard takes over.
var _death_overlay: CanvasLayer = null
## How fast (px/sec) the free-spectate camera pans. @export so it's tunable (Principle #6).
@export var spectate_camera_speed: float = 900.0

## --- crowd panic on a kill (CORE, host-authoritative) ---
## NPCs within this distance (px) of a kill scatter away from it.
@export var crowd_panic_radius_px: float = 560.0
## How long (seconds) panicked NPCs flee before returning to normal wandering.
@export var crowd_panic_seconds: float = 6.0
## Flee speed as a multiple of an NPC's walk speed (so the scatter clearly out-paces the crowd).
@export var crowd_panic_speed_scale: float = 2.2
## Our marks, as the host named them (owner-only). We resolve each name to its local
## node once that NPC has replicated to us, highlight it, and point the mini-map at the
## nearest living one. The host tells us when each dies so we can drop it.
var _my_mark_names: Array = []
var _resolved_marks: Dictionary = {}  # mark_name -> Node2D (resolved locally)
## The colour of OUR mark rings — set to our roster colour once the roster arrives, so each
## player's target circles match their own scoreboard dot. It is applied LOCALLY only; the ring's
## on/off state and colour are NEVER replicated, so no other peer can see (or even know there is)
## a ring around our marks. (Marks are unique per player and told only to their owner, too.)
var _my_ring_color: Color = Color(1.0, 0.84, 0.25)
## Online PvP: our opponent (the other player). Known from the start so the exposure
## arrow can react when they run; only KILLABLE once we've finished our own mark.
var _my_target_name: String = ""
## True once another player has started hunting US (their marks are done). Drives the red "YOU ARE
## BEING HUNTED" HUD state. Stored so it applies even if it arrives before our HUD is built.
var _is_hunted: bool = false
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

## Our own item kit readout, driven by host pushes (the host owns the charges). `slots` is a
## 2-element array, each [tool, charges, cooldown_left, active_left] for our two equipped tools.
var _item_label: Label = null
var _item_state: Dictionary = {"slots": [[0, 0, 0.0, 0.0], [0, 0, 0.0, 0.0]]}
## Host-side: each peer's two chosen tools (from the lobby), and how long each player is stunned.
var _tools_by_peer: Dictionary = {}
## Host-side: each peer's public nickname (from the lobby). Used to build ONE identity (name + number
## + colour) that BOTH the live roster and the end scoreboard read, so they can never disagree.
var _nickname_by_peer: Dictionary = {}
var _stun_left_by_peer: Dictionary = {}
## Local (per-machine): which OTHER players we're currently showing disguised (so we only swap the
## body on transition), and the active MORPH overrides we'll revert ([{visual, restore_index, left}]).
var _disguise_shown: Dictionary = {}
var _morph_active: Array = []
## Our own body index (for restoring the HUD portrait after a disguise/morph "?" period).
var _my_appearance_index: int = 0

## Slice E — the faceplate row + any reveal that arrived before the HUD existed.
var _faceplates: FaceplateRow = null
var _pending_target_face: int = -1
var _pending_exposed_faces: Array = []
## Host-only: who has already earned a reveal, so each fires once.
var _target_reveal_awarded: bool = false
## Who received the one-time TARGET reveal, and about whom — so that red plate can be refreshed if
## its subject later disguises / un-disguises (0 = none yet).
var _target_reveal_to: int = 0
var _target_reveal_subject: int = 0
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
	CosmeticRegistry.roll_filler_bodies()  # this match's 3–5 commoner crowd looks
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
	# The host's lobby map choice reaches every peer via NetworkManager (Phase 10). The crowd
	# size still keys off small_arena below (COMPACT and ROME are both small).
	var map_scene: PackedScene = MAP_SCENE
	match NetworkManager.selected_map:
		NetworkManager.Map.COMPACT:
			map_scene = SMALL_MAP_SCENE
		NetworkManager.Map.ROME:
			map_scene = ROME_SCENE
		_:
			map_scene = MAP_SCENE
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
	# Spawn in a SHUFFLED order so player numbers (= spawn order) are reassigned each match — a
	# rematch gives everyone a fresh number, which also rotates who-hunts-whom (the ring follows
	# number order below). Host is just another peer in the shuffle.
	var spawn_order: Array = [NetworkManager.HOST_PEER_ID]
	spawn_order.append_array(_expected_clients)
	spawn_order.shuffle()
	for peer in spawn_order:
		_spawn_player_for_peer(peer)
	_spawn_crowd()
	if _respawn_mode():
		# RESPAWN MODE: PvP from the first life. Marks are OPTIONAL ladder content (off in this
		# increment), so we skip the mandatory mark gate and put everyone straight into the hunt.
		_seat_order = spawn_order.duplicate()
		_recompute_ring_from_seats()
		_respawn_rewire_all()
		if _ladder_on():
			for peer_id in _players_by_peer:
				_ladder_reset_life(peer_id)  # hand out the first life's optional marks + lock the 2nd tool
	else:
		_build_target_ring()
		for peer_id in _players_by_peer:
			_assign_mark_for_peer(peer_id)
		_notify_targets()
	# Hold everyone for the start-of-round countdown (players spawned frozen above) — gives the
	# per-viewer reskin + replication time to settle — then the host lifts the freeze for all.
	if round_start_countdown > 0.0:
		_round_countdown = round_start_countdown
		_start_round_countdown.rpc(round_start_countdown)
	else:
		_round_active = true


# Everyone: kick off the local "3/2/1/GO!" display. The actual unfreeze is host-authoritative
# (the host clears each player's _net_frozen when _round_countdown ends); this is just the overlay.
@rpc("authority", "call_local", "reliable")
func _start_round_countdown(duration: float) -> void:
	_countdown_display = duration


# Per frame: the HOST counts the freeze down and lifts it for everyone at zero; every peer drives
# its own "3/2/1/GO!" overlay from the (synced-start) display timer.
func _tick_round_countdown(delta: float) -> void:
	# HOST: authoritative freeze timer → unfreeze all players when it ends.
	if NetworkManager.is_host() and not _round_active and _round_countdown > 0.0:
		_round_countdown = maxf(0.0, _round_countdown - delta)
		if _round_countdown == 0.0:
			_round_active = true
			for character in _players_by_peer.values():
				if character != null and is_instance_valid(character):
					character.set("_net_frozen", false)
	# EVERY peer: the on-screen overlay (local timer; all peers started it ~together via the RPC).
	if _countdown_display > 0.0:
		_countdown_display = maxf(0.0, _countdown_display - delta)
		if _mhud != null:
			_mhud.set_countdown(str(int(ceil(_countdown_display))) if _countdown_display > 0.0 else "GO!")
		if _countdown_display == 0.0:
			_go_left = 0.8  # hold "GO!" briefly, then clear
	elif _go_left > 0.0:
		_go_left = maxf(0.0, _go_left - delta)
		if _go_left == 0.0 and _mhud != null:
			_mhud.set_countdown("")


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


# Host-only: build the TARGET RING in PLAYER-NUMBER order — Player 1 hunts 2, 2 hunts 3, … and the
# last wraps back to 1. So each peer hunts exactly one other and is hunted by exactly one other
# (master_plan §7.2). The numbers themselves were shuffled at spawn, so the ring is randomised each
# match without needing a second shuffle here. `_players_by_peer` keys are in spawn (= number) order.
func _build_target_ring() -> void:
	if not multiplayer.is_server():
		return
	var peers: Array = _players_by_peer.keys()
	if peers.size() < 2:
		return
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
		# Showcase: put each player on a distinct premium ASSASSIN skin (11–14) so the per-viewer
		# crowd fills with assassin look-alikes around them, hidden in the Roman commoner crowd.
		loadout_payload = _with_body_index(loadout_payload, ASSASSIN_BODY_BASE + (_next_spawn_index % ASSASSIN_BODY_COUNT))
	var spawn_data := {
		"peer": peer_id,
		"pos": _spawn_position_for_index(_next_spawn_index),
		"appearance": _body_index_from_payload(loadout_payload),
		"loadout": loadout_payload,
		"tools": _tools_for_peer(peer_id),  # the two tools this player picked in the lobby
	}
	var character := _player_spawner.spawn(spawn_data)
	_players_by_peer[peer_id] = character
	# Spawn frozen until the start-of-round countdown ends (a late joiner after the round is active
	# spawns unfrozen). Replicated, so the freeze holds on every screen.
	character.set("_net_frozen", not _round_active)
	_next_spawn_index += 1

	# Start this peer's score row (host-only). _player_num is 1-based spawn order, for the
	# scoreboard ("Player 1/2/3/4").
	_player_num[peer_id] = _next_spawn_index
	_exposure_sum[peer_id] = 0.0
	_exposure_samples[peer_id] = 0
	_kills_by_peer[peer_id] = 0
	_player_kills_by_peer[peer_id] = 0
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

	# Host owns this player's tool kit: apply each tool's world effect when used + push the
	# charges/cooldown readout to the owner whenever it changes.
	var item := character.get_node_or_null("ItemComponent") as ItemComponent
	if item != null:
		item.tool_activated.connect(_on_tool_activated.bind(peer_id))
		item.tool_expired.connect(_on_tool_expired.bind(peer_id))
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
					_receive_exposure_reveal.rpc_id(other_peer, peer_id, _revealed_look(character))


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
	if _mhud != null:
		_mhud.set_exposure(value / 100.0)


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
	_submit_loadout.rpc_id(NetworkManager.HOST_PEER_ID, _local_loadout_payload())
	# Tell the host the two TOOLS we picked in the lobby (so it stamps them into our spawn).
	_submit_tools.rpc_id(NetworkManager.HOST_PEER_ID, _local_tools())
	# Tell the host our public nickname (shown on the roster / scoreboard / death screen).
	_submit_nickname.rpc_id(NetworkManager.HOST_PEER_ID, _local_nickname())
	# "Host, my scene is up — please spawn my character." Runs the host's _request_spawn.
	_request_spawn.rpc_id(NetworkManager.HOST_PEER_ID)
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
	# Equip the two tools this player picked (same on every machine, so slot→tool agrees).
	var item := character.get_node_or_null("ItemComponent") as ItemComponent
	if item != null and spawn_data.has("tools"):
		item.apply_equipped(spawn_data["tools"])
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
	# SECURITY TODO(monetization) — server-authoritative ownership. We currently TRUST this
	# payload: the host renders whatever cosmetic ids the client sends, and ownership is only
	# checked client-side in CosmeticInventory. That is FINE today (nothing is paid, the host
	# is just a peer), but it is NOT a security boundary. Before any cosmetic costs money, the
	# host (or a backend it trusts) MUST validate every id in `payload` against THIS account's
	# server-held inventory and replace any unowned id with its slot default — otherwise day one
	# of the shop ships a free-cosmetics exploit. See CODE_AUDIT_PHASES_7-11.md §1.
	_loadout_by_peer[sender] = payload
	# ON-CHANGE seam: if this peer already has a live character (a mid-match wardrobe
	# change), we'd re-broadcast + re-apply here. Loadouts are static during a match today
	# (§5), so we only stash it for the (re)spawn. Hook left intentionally for later.


# === tool loadout (the two tools picked in the lobby) =======================
# Client → host: "here are the two tools I picked." Stored, then stamped into our spawn data.
@rpc("any_peer", "reliable")
func _submit_tools(tools: Array) -> void:
	if not multiplayer.is_server():
		return
	_tools_by_peer[multiplayer.get_remote_sender_id()] = tools

# The two tools chosen at THIS machine (from NetworkManager, set by the lobby; sensible default).
func _local_tools() -> Array:
	return NetworkManager.selected_tools.duplicate()


# === player identity (nickname + number + colour), shared by BOTH leaderboards ==============

# Client → host: "here is my public nickname." Stored, then read by _display_name_for everywhere.
@rpc("any_peer", "reliable")
func _submit_nickname(nickname: String) -> void:
	if not multiplayer.is_server():
		return
	_nickname_by_peer[multiplayer.get_remote_sender_id()] = nickname.strip_edges().left(14)

# The nickname typed at THIS machine (from NetworkManager, set by the lobby).
func _local_nickname() -> String:
	return str(NetworkManager.player_nickname).strip_edges()

# Host-only: a peer's nickname — their submitted one, our own for the host's own player, or "".
func _nickname_for_peer(peer_id: int) -> String:
	var nm := ""
	if _nickname_by_peer.has(peer_id):
		nm = str(_nickname_by_peer[peer_id])
	elif peer_id == multiplayer.get_unique_id():
		nm = _local_nickname()
	return nm.strip_edges()

# Host-only: the name to SHOW for a peer — their nickname, or "Player N" when they didn't set one.
# This is the single source of truth both the roster and the scoreboard use, so names always match.
func _display_name_for(peer_id: int) -> String:
	var nm := _nickname_for_peer(peer_id)
	if nm != "":
		return nm
	return "Player %d" % int(_player_num.get(peer_id, 0))

# Host-only: a peer's colour, keyed by their stable player NUMBER (not row order) so it never changes
# when the boards re-sort by score, and so the roster, the scoreboard, and the player's ring all agree.
func _color_for_num(num: int) -> Color:
	return ROSTER_COLORS[maxi(0, num - 1) % ROSTER_COLORS.size()]

# Host-only: find a peer's display name inside an already-built rows array (used by the scoreboard).
func _name_of(rows: Array, peer_id: int) -> String:
	for row in rows:
		if int(row["peer"]) == peer_id:
			return str(row.get("name", "Player %d" % int(row.get("num", 0))))
	return "Player"

# Host-only: the two tools to spawn `peer_id` with — their submitted pick, our own for the host, or
# a safe default. Always returns exactly two tool ints.
func _tools_for_peer(peer_id: int) -> Array:
	var tools: Array = []
	if _tools_by_peer.has(peer_id):
		tools = _tools_by_peer[peer_id]
	elif peer_id == multiplayer.get_unique_id():
		tools = _local_tools()
	if tools.size() < 2:
		tools = [ItemComponent.Tool.SMOKE, ItemComponent.Tool.DECOY]
	return [int(tools[0]), int(tools[1])]


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
	_receive_hunted.rpc_id(target_peer, true)  # warn the prey: a hunter is now after you
	# RED reveal (§7.4): the FIRST player to finish their marks learns their target's look.
	if not _target_reveal_awarded:
		_target_reveal_awarded = true
		_target_reveal_to = peer_id
		_target_reveal_subject = target_peer
		_receive_target_reveal.rpc_id(peer_id, _revealed_look(target))


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
	if _mhud != null:
		_mhud.set_objective("Marks down — HUNT YOUR OPPONENT.")
	if _target_arrow != null:
		_target_arrow.set_flashing(true)


# Owner-only: another player is now hunting US. Flag it + turn the HUD's top-left box red.
@rpc("authority", "call_local", "reliable")
func _receive_hunted(on: bool) -> void:
	_is_hunted = on
	if _mhud != null:
		_mhud.set_hunted(on)
		if on:
			_mhud.add_log("A hunter is on your trail — you are being hunted.")


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

	# Drop the dead player from the EXPOSED reveal row on every screen — they're out, so their blue
	# plate shouldn't keep hanging around (the roster already dims + ✗-tags them via _build_roster_rows).
	_exposure_revealed[loser_peer] = false
	_remove_exposed_reveal.rpc(loser_peer)

	# Attribute the kill. request_kill stamps last_attacker_peer on the victim. If the killer
	# was this player's assigned hunter, it COMPLETES their contract (the +contract_bonus).
	var loser := _players_by_peer.get(loser_peer) as Player
	var killer_peer: int = int(loser.get("last_attacker_peer")) if loser != null else -1
	if killer_peer > 0:
		# A PLAYER kill — worth massive points (covers melee AND poison, both stamp last_attacker_peer).
		_player_kills_by_peer[killer_peer] = int(_player_kills_by_peer.get(killer_peer, 0)) + 1
	if killer_peer > 0 and int(_ring_target.get(killer_peer, 0)) == loser_peer:
		_completed_by_peer[killer_peer] = true
		if not _respawn_mode():
			_phase_by_peer[killer_peer] = "done"  # classic: contract finished. Respawn: keep hunting.
	_award_kill_bonuses(killer_peer, loser_peer, loser)  # AC-style stealth/poison/revenge bonuses + label

	# Freeze the corpse on EVERY machine. The host already ran die() on its own copy via the
	# kill; this mirrors it so the dead player's own client stops predicting movement (no
	# spectator rubber-banding) and everyone's arrows treat them as dead.
	if loser != null:
		_freeze_player.rpc(String(loser.name))

	if _respawn_mode():
		# RESPAWN MODE: no spectate, no last-standing end. Re-form the chain over the living and
		# schedule this player's return. The round ends only on the clock (_host_score_tick).
		_recompute_ring_from_seats()
		_respawn_rewire_all()
		_respawn_due[loser_peer] = respawn_delay_seconds
		_notify_owner.rpc_id(loser_peer, "You were killed — respawning…")
		_update_status()
		return

	# Tell the eliminated player WHO got them + HOW, so their machine shows the death screen and
	# drops them into free-spectate. Sent only to the loser (their identity stays private to others).
	var killer_name: String = _display_name_for(killer_peer) if killer_peer > 0 else ""
	var method: String = str(loser.get("last_attacker_method")) if loser != null else ""
	if loser_peer == multiplayer.get_unique_id():
		_enter_spectate(killer_name, method)  # the host themselves died
	else:
		_receive_eliminated.rpc_id(loser_peer, killer_name, method)

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


# The eliminated player's OWN machine (sent only to them by _on_player_killed): show the death
# screen and hand them the free-spectate camera. call_remote so the host doesn't double-run it —
# the host calls _enter_spectate directly when the host's own player dies.
@rpc("authority", "call_remote", "reliable")
func _receive_eliminated(killer_name: String, method: String) -> void:
	_enter_spectate(killer_name, method)


# This machine's player is out: drop the in-match GUI, show the death screen, and start the free
# camera where they fell. Runs once (guarded) on the eliminated player's machine only.
func _enter_spectate(killer_name: String, method: String) -> void:
	if _spectating:
		return
	_spectating = true
	_show_death_overlay(killer_name, method)
	# Take the player out of their in-match GUI — they're spectating now, not playing.
	if _mhud != null:
		_mhud.visible = false
	if _player_hud_layer != null:
		_player_hud_layer.visible = false
	if _arrow_layer != null:
		_arrow_layer.visible = false
	# A free camera, starting on the spot where we were killed, that we fly with WASD / the stick.
	_spectate_camera = Camera2D.new()
	_spectate_camera.name = "SpectateCamera"
	_spectate_camera.zoom = Vector2(1.1, 1.1)
	if _local_player != null and is_instance_valid(_local_player):
		_spectate_camera.global_position = _local_player.global_position
	add_child(_spectate_camera)
	_spectate_camera.make_current()


# Per-frame (while spectating): pan the free camera with the movement actions. Uses the same
# move_* actions as walking — the dead body ignores them (its physics is off), so they only fly
# the camera. Clamped to the map so you can't drift off into the void.
func _update_spectate_camera(delta: float) -> void:
	if _spectate_camera == null or not is_instance_valid(_spectate_camera):
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO:
		_spectate_camera.global_position += dir * spectate_camera_speed * delta
	if _mini_map != null and _mini_map.map_size_px.x > 0.0:
		_spectate_camera.global_position.x = clampf(_spectate_camera.global_position.x, 0.0, _mini_map.map_size_px.x)
		_spectate_camera.global_position.y = clampf(_spectate_camera.global_position.y, 0.0, _mini_map.map_size_px.y)


# The "ELIMINATED — by X" banner, pinned to the top so it never covers the spectate view.
func _show_death_overlay(killer_name: String, method: String) -> void:
	var layer := CanvasLayer.new()
	layer.name = "DeathOverlay"
	layer.layer = 6  # above the HUD (which sits at layer 5)
	add_child(layer)
	_death_overlay = layer

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 40.0
	box.offset_bottom = 220.0  # explicit height so the stacked labels lay out (a 0-height container won't)
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)

	var headline := Label.new()
	headline.text = "ELIMINATED"
	headline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.add_theme_font_size_override("font_size", 64)
	headline.add_theme_color_override("font_color", Color(0.92, 0.24, 0.20))
	box.add_child(headline)

	var detail := Label.new()
	detail.text = _death_cause_text(killer_name, method)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 24)
	box.add_child(detail)

	var hint := Label.new()
	hint.text = "Spectating — move to fly the camera"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(1, 1, 1, 0.7)
	box.add_child(hint)


# How the death screen reads, based on the method KillComponent stamped.
func _death_cause_text(killer_name: String, method: String) -> String:
	if killer_name == "":
		return "You were eliminated."
	if method == "poison":
		return "Poisoned by %s" % killer_name
	return "Assassinated by %s" % killer_name


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
					# Tell them why their target changed (no identity leaked — just "you have a new one").
					_notify_owner.rpc_id(hunter, "Your target was eliminated — a new target is assigned.")
					# If this hunter earned the one-time TARGET reveal, move the red plate to the NEW target
					# so it never keeps showing a dead player (mirrors _refresh_reveals_for's send).
					if hunter == _target_reveal_to:
						_target_reveal_subject = new_target
						_receive_target_reveal.rpc_id(_target_reveal_to, _revealed_look(_players_by_peer[new_target]))


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
	# RESPAWN grace breaks the moment you act offensively — no shielded spawn pushes.
	if _grace_due.has(peer_id):
		_grace_due.erase(peer_id)
		_clear_grace(peer_id)


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


# ================================================================================================
# RESPAWN MODE (RESPAWN_MODE_PLAN.md). All host-authoritative; gated by GameModeFlags. With the flag
# OFF none of this runs and the classic elimination loop above is unchanged.
# ================================================================================================

# True only on the HOST whose flag governs the match. Safe to call from host-only code paths.
func _respawn_mode() -> bool:
	return GameModeFlags.respawn_mode_enabled


# Host per-frame: count pending respawns + grace windows down; fire each when it reaches zero.
func _tick_respawns(delta: float) -> void:
	if _match_over or not _respawn_mode():
		return
	for peer in _respawn_due.keys():
		_respawn_due[peer] = float(_respawn_due[peer]) - delta
		if float(_respawn_due[peer]) <= 0.0:
			_respawn_due.erase(peer)
			_respawn_player(peer)
	for peer in _grace_due.keys():
		_grace_due[peer] = float(_grace_due[peer]) - delta
		if float(_grace_due[peer]) <= 0.0:
			_grace_due.erase(peer)
			_clear_grace(peer)


# Host: bring a downed player back at a fresh life — pick a spot, revive everywhere, re-wire the chain.
func _respawn_player(peer: int) -> void:
	var node := _players_by_peer.get(peer) as Player
	if node == null or not is_instance_valid(node):
		return
	# Pick the spot while `peer` is still flagged dead, so the exclusion checks skip their own corpse.
	var pos := _pick_spawn(peer)
	_revive_player.rpc(String(node.name), pos)  # every machine un-dies + repositions the body
	_dead_by_peer[peer] = false
	node.set("grace_active", true)
	_grace_due[peer] = respawn_grace_seconds
	_recompute_ring_from_seats()
	_respawn_rewire_all()
	_ladder_reset_life(peer)  # fresh life: wipe earned upgrades, re-lock the 2nd tool, new marks (no-op if ladder off)
	_notify_owner.rpc_id(peer, "Respawned — fresh life. Briefly safe.")
	_update_status()


# Every machine: reverse a player's death (un-fade, re-enable physics/actions, wipe per-life state)
# and snap the body to the spawn point.
@rpc("authority", "call_local", "reliable")
func _revive_player(player_name: String, pos: Vector2) -> void:
	if _players_parent == null:
		return
	var node := _players_parent.get_node_or_null(player_name) as Player
	if node != null:
		node.revive(pos)


func _clear_grace(peer: int) -> void:
	var node := _players_by_peer.get(peer) as Player
	if node != null and is_instance_valid(node):
		node.set("grace_active", false)


# The stable contract chain: target = the next LIVING player in the fixed seat order. Always one valid
# cycle over the living — no self-target (>=2 alive), no targetless player (>=2 alive), and no mutual
# pair (>=3 alive). At exactly 2 alive the pair is mutual (the only valid 2-player chain; accepted).
func _recompute_ring_from_seats() -> void:
	_ring_target.clear()
	var n := _seat_order.size()
	for i in n:
		var hunter: int = int(_seat_order[i])
		if bool(_dead_by_peer.get(hunter, false)) or not _players_by_peer.has(hunter):
			continue
		for step in range(1, n):
			var cand: int = int(_seat_order[(i + step) % n])
			if cand != hunter and not bool(_dead_by_peer.get(cand, false)) and _players_by_peer.has(cand):
				_ring_target[hunter] = cand
				break


# Push the current ring to clients: every living hunter is in 'target' phase, knows its prey, can kill
# it, and the prey is told it's hunted. Idempotent — safe to call on every membership change.
func _respawn_rewire_all() -> void:
	for hunter in _ring_target:
		var prey := int(_ring_target[hunter])
		if prey == 0 or not _players_by_peer.has(prey) or bool(_dead_by_peer.get(prey, false)):
			continue
		(_players_by_peer[prey] as Node).add_to_group("killable_for_%d" % hunter)
		if _phase_by_peer.get(hunter, "marks") != "target":
			_phase_by_peer[hunter] = "target"
			_enter_hunt_phase.rpc_id(hunter)
		_send_target_to(hunter)
		_receive_hunted.rpc_id(prey, true)


# Host: choose a SAFE-BUT-RELEVANT respawn point. Density-weighted when enabled; authored fallback else.
func _pick_spawn(peer: int) -> Vector2:
	var map := _map as TestMap01
	if not GameModeFlags.density_spawn_enabled or map == null or not map.has_method("random_walkable_point"):
		return _spawn_position_for_index(maxi(0, int(_player_num.get(peer, 1)) - 1))
	var killer_pos := _killer_position(peer)
	var target_peer := int(_ring_target.get(peer, 0))
	var target_node := _players_by_peer.get(target_peer) as Node2D
	var scored: Array = []
	for _i in spawn_candidate_samples:
		var p: Vector2 = map.random_walkable_point()
		# HARD EXCLUDE: too near any live player (their contact/visual zone) or near your killer (anti-farm).
		if _too_close_to_live_player(p):
			continue
		if killer_pos != NO_POS and p.distance_to(killer_pos) < spawn_anti_farm_px:
			continue
		# SCORE: strongly favour crowd density (respawn already blended); favour closeness to your target.
		var score := float(_crowd_density_at(p, spawn_density_radius_px)) * spawn_density_weight
		if target_node != null and is_instance_valid(target_node):
			score += spawn_target_proximity_weight * (4000.0 - minf(4000.0, p.distance_to(target_node.global_position)))
		scored.append({"pos": p, "score": score})
	if scored.is_empty():
		# Everywhere excluded (tight map / full lobby): fall back to an authored spawn (never a kill zone).
		return _spawn_position_for_index(maxi(0, int(_player_num.get(peer, 1)) - 1))
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	# MILD randomization among the top-K so spawns aren't deterministic/campable.
	var top := mini(spawn_topk, scored.size())
	return scored[randi() % top]["pos"]


func _too_close_to_live_player(p: Vector2) -> bool:
	for q in _players_by_peer:
		if bool(_dead_by_peer.get(q, false)):
			continue
		var node := _players_by_peer[q] as Node2D
		if node != null and is_instance_valid(node) and p.distance_to(node.global_position) < spawn_contact_exclusion_px:
			return true
	return false


# Live crowd density at a point (host-side; the online crowd are Npc children of _crowd_parent).
func _crowd_density_at(point: Vector2, radius: float) -> int:
	if _crowd_parent == null:
		return 0
	var count := 0
	var r2 := radius * radius
	for child in _crowd_parent.get_children():
		var npc := child as Npc
		if npc != null and not npc.is_dead() and npc.global_position.distance_squared_to(point) <= r2:
			count += 1
	return count


# Where the peer's last killer is now (NO_POS if unknown) — used to exclude spawns near them (anti-farm).
func _killer_position(peer: int) -> Vector2:
	var node := _players_by_peer.get(peer) as Player
	if node == null:
		return NO_POS
	var killer_peer := int(node.get("last_attacker_peer"))
	var killer := _players_by_peer.get(killer_peer) as Node2D
	if killer != null and is_instance_valid(killer):
		return killer.global_position
	return NO_POS


# ================================================================================================
# PvE LADDER (RESPAWN_MODE_PLAN.md §6). Optional per-life NPC marks: kill one to earn an upgrade
# point, then CHOOSE to sharpen your arrow (precision) or unlock your 2nd tool — capped per axis,
# wiped on death. All host-authoritative; gated by GameModeFlags.pve_ladder_enabled.
# ================================================================================================

func _ladder_on() -> bool:
	return GameModeFlags.respawn_mode_enabled and GameModeFlags.pve_ladder_enabled


# Host: start a fresh life's ladder for `peer` — clear earned upgrades, re-lock the 2nd tool, hand out
# a new set of optional marks, and push the reset state to the owner.
func _ladder_reset_life(peer: int) -> void:
	if not _ladder_on():
		return
	_release_ladder_marks(peer)
	_ladder_tier_by_peer[peer] = 0
	_ladder_tools_by_peer[peer] = 0
	_ladder_pending_by_peer[peer] = 0
	var node := _players_by_peer.get(peer) as Player
	if node != null and is_instance_valid(node):
		var item := node.get_node_or_null("ItemComponent") as ItemComponent
		if item != null:
			item.set_base_life_lock()  # base life: only slot 0 usable
	_assign_ladder_marks(peer)
	_push_ladder_state(peer)


# Host: free this peer's still-living marks so those NPCs blend back in / can be reused next life.
func _release_ladder_marks(peer: int) -> void:
	var marks: Array = _ladder_marks_by_peer.get(peer, [])
	for m in marks:
		if m != null and is_instance_valid(m):
			m.remove_from_group("mark")
			m.remove_from_group("killable_for_%d" % peer)
	_ladder_marks_by_peer[peer] = []


# Host: give `peer` up to pve_marks_per_life OPTIONAL crowd marks for this life, highlighted to the
# owner. We connect each NPC's death ONCE (guarded by the "ladder_wired" group) and route the grant
# to whoever currently owns it — so re-using an NPC across lives can't double-connect or mis-credit.
func _assign_ladder_marks(peer: int) -> void:
	if _crowd_parent == null:
		return
	var candidates: Array = []
	for child in _crowd_parent.get_children():
		var npc := child as Npc
		if npc != null and not npc.is_dead() and not npc.is_in_group("mark"):
			candidates.append(npc)
	candidates.shuffle()
	var chosen: Array = []
	var names: Array = []
	for npc in candidates:
		if chosen.size() >= pve_marks_per_life:
			break
		npc.add_to_group("mark")
		npc.add_to_group("killable_for_%d" % peer)
		if not npc.is_in_group("ladder_wired"):
			npc.add_to_group("ladder_wired")
			npc.died.connect(_on_ladder_mark_died.bind(npc))
		chosen.append(npc)
		names.append(String(npc.name))
	_ladder_marks_by_peer[peer] = chosen
	if not names.is_empty():
		_receive_marks.rpc_id(peer, names)  # reuse the existing owner-only mark highlight


# Host: an NPC that was someone's optional mark died — credit its CURRENT owner with an upgrade point.
func _on_ladder_mark_died(npc: Node) -> void:
	if not _ladder_on():
		return
	for peer in _ladder_marks_by_peer:
		var marks: Array = _ladder_marks_by_peer[peer]
		if marks.has(npc):
			marks.erase(npc)  # consumed — can't double-count
			_ladder_marks_by_peer[peer] = marks
			_ladder_pending_by_peer[peer] = int(_ladder_pending_by_peer.get(peer, 0)) + 1
			_notify_mark_down.rpc_id(int(peer), String(npc.name))  # drop its highlight on the owner
			_push_ladder_state(int(peer))
			return


# Host → owner: current ladder state — the arrow tier to apply + how many points are unspent.
func _push_ladder_state(peer: int) -> void:
	_receive_ladder_state.rpc_id(peer, int(_ladder_tier_by_peer.get(peer, 0)), int(_ladder_pending_by_peer.get(peer, 0)))


@rpc("authority", "call_local", "reliable")
func _receive_ladder_state(tier: int, pending: int) -> void:
	_my_arrow_tier = tier
	_my_ladder_pending = pending
	if _target_arrow != null and is_instance_valid(_target_arrow):
		_target_arrow.set_precision_tier(tier)
	if _mhud != null and pending > 0:
		_mhud.add_log("Upgrade ready (%d) — [F] sharpen arrow · [G] unlock 2nd tool." % pending)


# Owner-side per-frame: spend a pending upgrade point with the two axis keys (no-op without one).
func _read_ladder_input() -> void:
	if not _ladder_on() or _spectating or _my_ladder_pending <= 0:
		return
	if _local_player == null or not is_instance_valid(_local_player) or _local_player.is_dead():
		return
	if Input.is_action_just_pressed("upgrade_precision"):
		_request_ladder_spend.rpc_id(NetworkManager.HOST_PEER_ID, 0)
	elif Input.is_action_just_pressed("upgrade_tool"):
		_request_ladder_spend.rpc_id(NetworkManager.HOST_PEER_ID, 1)


# Owner → host: spend a pending point on an axis (0 = precision, 1 = tool). Host validates + caps.
# call_local so the host's OWN key-press runs (rpc_id to self); the is_server guard no-ops on clients.
@rpc("any_peer", "call_local", "reliable")
func _request_ladder_spend(axis: int) -> void:
	if not multiplayer.is_server() or not _ladder_on():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer := sender if sender != 0 else multiplayer.get_unique_id()
	_apply_ladder_spend(peer, axis)


func _apply_ladder_spend(peer: int, axis: int) -> void:
	if int(_ladder_pending_by_peer.get(peer, 0)) <= 0:
		return
	var spent := false
	if axis == 0:
		var tier := int(_ladder_tier_by_peer.get(peer, 0))
		if tier < LADDER_PRECISION_CAP:
			_ladder_tier_by_peer[peer] = tier + 1
			spent = true
	elif axis == 1:
		if int(_ladder_tools_by_peer.get(peer, 0)) < LADDER_TOOL_CAP:
			_ladder_tools_by_peer[peer] = 1
			var node := _players_by_peer.get(peer) as Player
			if node != null and is_instance_valid(node):
				var item := node.get_node_or_null("ItemComponent") as ItemComponent
				if item != null:
					item.unlock_slot(1)
			spent = true
			_notify_owner.rpc_id(peer, "Second tool unlocked.")
	if spent:
		_ladder_pending_by_peer[peer] = int(_ladder_pending_by_peer[peer]) - 1
		_push_ladder_state(peer)


# ================================================================================================
# HUNTER-DANGER CUES (AC Rearmed-style pursuer warning). Host decides each player's danger level from
# how close their assigned hunter is, and tells ONLY that player — never which figure the hunter is.
# ================================================================================================

# Host per-frame (throttled): grade everyone's danger by distance to their hunter; send on change.
func _tick_danger(delta: float) -> void:
	if _match_over or not _round_active:
		return
	_danger_accum += delta
	if _danger_accum < danger_eval_interval:
		return
	_danger_accum = 0.0
	for prey in _players_by_peer:
		var level := 0
		if not bool(_dead_by_peer.get(prey, false)):
			var hunter := _hunter_of_target(prey)
			if hunter != 0 and not bool(_dead_by_peer.get(hunter, false)):
				var prey_node := _players_by_peer[prey] as Node2D
				var hunter_node := _players_by_peer.get(hunter) as Node2D
				if prey_node != null and is_instance_valid(prey_node) and hunter_node != null and is_instance_valid(hunter_node):
					var d := prey_node.global_position.distance_to(hunter_node.global_position)
					if d <= danger_close_px:
						level = 2
					elif d <= danger_near_px:
						level = 1
		if int(_danger_level_by_peer.get(prey, -1)) != level:
			_danger_level_by_peer[prey] = level
			_receive_danger.rpc_id(int(prey), level)


# Owner-only: render the danger level the host computed for us (0 safe / 1 near / 2 very near).
@rpc("authority", "call_local", "reliable")
func _receive_danger(level: int) -> void:
	if _danger_overlay != null and is_instance_valid(_danger_overlay):
		_danger_overlay.set_level(level)


# ================================================================================================
# KILL-QUALITY BONUSES (AC Rearmed-style). Host-side: when a player kills their target, grade the
# kill (unseen / discreet / poison / revenge), bank the bonus, and pop a label on the killer's screen.
# ================================================================================================

# Host: grade `killer_peer`'s kill of `loser_peer` and award stealth/poison/revenge bonuses.
func _award_kill_bonuses(killer_peer: int, loser_peer: int, loser: Node) -> void:
	_last_killed_by[loser_peer] = killer_peer  # so the loser can later score REVENGE on this killer
	if killer_peer <= 0:
		return
	var labels: Array = []
	var bonus := 0
	# Stealth tier from the KILLER's current exposure — a clean, unseen kill is worth the most.
	var killer := _players_by_peer.get(killer_peer) as Player
	var killer_exposure := 100.0
	if killer != null and is_instance_valid(killer) and killer.exposure_component != null:
		killer_exposure = killer.exposure_component.exposure
	if killer_exposure <= incognito_exposure_max:
		bonus += incognito_bonus
		labels.append("INCOGNITO")
	elif killer_exposure <= discreet_exposure_max:
		bonus += discreet_bonus
		labels.append("DISCREET")
	# Silent poison finish.
	if loser != null and String(loser.get("last_attacker_method")) == "poison":
		bonus += poison_bonus
		labels.append("POISON")
	# Revenge: the player we just killed had most recently killed US.
	if int(_last_killed_by.get(killer_peer, 0)) == loser_peer:
		bonus += revenge_bonus
		labels.append("REVENGE")
		_last_killed_by.erase(killer_peer)  # consumed — no repeat-revenge on the same grudge
	if bonus > 0:
		_style_bonus_by_peer[killer_peer] = int(_style_bonus_by_peer.get(killer_peer, 0)) + bonus
		_receive_kill_bonus.rpc_id(killer_peer, " · ".join(labels), bonus)


# Owner-only: a stylish kill — log it and pop a fading centered label for juice.
@rpc("authority", "call_local", "reliable")
func _receive_kill_bonus(label: String, points: int) -> void:
	var text := ("%s  +%d" % [label, points]) if label != "" else ("+%d" % points)
	if _mhud != null:
		_mhud.add_log(text)
	_flash_bonus_label(text)


func _flash_bonus_label(text: String) -> void:
	if _player_hud_layer == null:
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.25))
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl.offset_top = 150.0
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_hud_layer.add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "offset_top", 110.0, 1.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.0).set_delay(0.6)
	tw.tween_callback(lbl.queue_free)


# ================================================================================================
# FIRECRACKER tool — an instant flashbang burst that briefly stuns nearby players (AC Rearmed).
# ================================================================================================

# Host: stun every OTHER living player within firecracker_radius of the user; flash for everyone.
func _deploy_firecracker(user: Player, peer_id: int) -> void:
	if user == null or not is_instance_valid(user):
		return
	var origin := user.global_position
	for other in _players_by_peer:
		if int(other) == peer_id or bool(_dead_by_peer.get(other, false)):
			continue
		var node := _players_by_peer[other] as Player
		if node == null or not is_instance_valid(node):
			continue
		if node.global_position.distance_to(origin) <= firecracker_radius:
			# Reuse the smoke-stun bookkeeping (decremented + applied in _update_smoke_stuns).
			_stun_left_by_peer[other] = maxf(float(_stun_left_by_peer.get(other, 0.0)), firecracker_stun_seconds)
	_spawn_firecracker_flash.rpc(origin)


# Everyone: a brief expanding white-yellow flash at the burst location (cosmetic).
@rpc("authority", "call_local", "reliable")
func _spawn_firecracker_flash(pos: Vector2) -> void:
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	var n := 24
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a), sin(a)) * firecracker_radius)
	poly.polygon = pts
	poly.color = Color(1.0, 0.98, 0.85, 0.45)
	poly.global_position = pos
	poly.z_index = 60
	var parent: Node = _map if _map != null else self
	parent.add_child(poly)
	var tw := create_tween()
	tw.tween_property(poly, "scale", Vector2(1.3, 1.3), 0.35)
	tw.parallel().tween_property(poly, "modulate:a", 0.0, 0.35)
	tw.tween_callback(poly.queue_free)


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
		var num: int = int(_player_num.get(peer_id, 0))
		row["peer"] = peer_id
		row["num"] = num
		row["name"] = _display_name_for(peer_id)  # same identity the live roster used
		row["color"] = _color_for_num(num)
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
	# Split kills: PLAYER kills score massively; the rest (NPC marks) score the normal amount.
	var player_kills: int = int(_player_kills_by_peer.get(peer_id, 0))
	var npc_kills: int = maxi(0, int(_kills_by_peer.get(peer_id, 0)) - player_kills)
	var kill_score: int = npc_kills * kill_points + player_kills * player_kill_points
	var outcome_bonus: int = 0
	if bool(_completed_by_peer.get(peer_id, false)):
		outcome_bonus += contract_bonus
	if bool(_dead_by_peer.get(peer_id, false)):
		outcome_bonus -= death_penalty
	var style_bonus: int = int(_style_bonus_by_peer.get(peer_id, 0))  # AC-style kill-quality bonuses
	var total: int = maxi(0, exposure_score + speed_score + kill_score + outcome_bonus + style_bonus)
	return {
		"avg_exposure": avg_exposure,
		"kills": int(_kills_by_peer.get(peer_id, 0)),
		"player_kills": player_kills,
		"completed": bool(_completed_by_peer.get(peer_id, false)),
		"dead": bool(_dead_by_peer.get(peer_id, false)),
		"total": total,
	}


# Everyone: freeze the match and show the scoreboard (winner highlighted, "YOU" tagged).
@rpc("authority", "call_local", "reliable")
func _declare_match_over(rows: Array, winner_peer: int, reason: String) -> void:
	get_tree().paused = true
	if _death_overlay != null and is_instance_valid(_death_overlay):
		_death_overlay.visible = false  # let the final scoreboard show cleanly over the spectate view
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
	headline.text = "YOU WIN" if we_won else ("%s WINS" % _name_of(rows, winner_peer))
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
		line.text = "%d. %s — %d pts   ·   kills %d   ·   avg exp %d%%%s%s" % [
			int(row["num"]), str(row.get("name", "Player")), int(row["total"]), int(row["kills"]),
			int(round(float(row["avg_exposure"]))), status, you_tag]
		if int(row["peer"]) == winner_peer:
			line.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))  # gold winner
		else:
			line.add_theme_color_override("font_color", row.get("color", Color(0.9, 0.87, 0.8)))  # roster colour
		line.add_theme_font_size_override("font_size", 20)
		box.add_child(line)

	var rematch_button := Button.new()
	rematch_button.text = "Rematch (re-pick in lobby)"
	rematch_button.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_child(rematch_button)
	rematch_button.pressed.connect(func() -> void:
		rematch_button.disabled = true
		rematch_button.text = "Waiting for players…"
		_request_rematch.rpc_id(NetworkManager.HOST_PEER_ID))

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


# Everyone: clear the pause and return to the LOBBY together, so each player can re-pick their
# assassin + NPC-disguise (and the host the map) before confirming a fresh round (their request).
@rpc("authority", "call_local", "reliable")
func _do_rematch() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


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
	if _spectating:
		_update_spectate_camera(delta)  # the eliminated player flies the free camera
	if NetworkManager.is_host():
		_host_score_tick(delta)  # advance the clock + sample exposure for scoring
		_update_smoke_stuns(delta)  # stun anyone standing in a smoke cloud
		_tick_respawns(delta)  # RESPAWN MODE: count down pending respawns + grace windows
		_tick_danger(delta)  # AC-style "hunter closing in" cue (host decides the level; identity-safe)
	_tick_round_countdown(delta)  # start-of-round freeze + "3/2/1/GO!" overlay
	_retry_spawn_if_needed(delta)
	_update_local_view()
	_maybe_assign_crowd_appearances()
	_update_visibility()
	_tick_morphs(delta)  # revert finished morphs (every machine; morph is applied locally)
	_update_identity_portrait()  # "?" portrait while OUR disguise/morph is active
	_tick_item_countdown(delta)
	_read_ladder_input()  # PvE ladder: spend earned upgrade points with the two axis keys (owner-side)
	# Round clock: the host advances _elapsed in _host_score_tick; clients tick it locally (everyone
	# started together via the lobby, so it stays roughly in sync without extra messages).
	if not NetworkManager.is_host():
		_elapsed += delta
	if _mhud != null:
		_mhud.set_timer("Round 1", _format_time(maxf(0.0, round_time_limit - _elapsed)))
	# Host broadcasts a rough roster (names + live scores) ~once a second.
	if NetworkManager.is_host():
		_roster_accum += delta
		if _roster_accum >= 1.0:
			_roster_accum = 0.0
			_receive_roster.rpc(_build_roster_rows())
	_update_debug_overlay()


func _format_time(seconds: float) -> String:
	var s := int(ceil(seconds))
	return "%d:%02d" % [s / 60, s % 60]


# Host-only: a rough scoreboard — each player's name (by spawn order), colour, and total score.
func _build_roster_rows() -> Array:
	var rows: Array = []
	for peer in _players_by_peer.keys():
		var num: int = int(_player_num.get(peer, 0))
		rows.append({
			"name": _display_name_for(peer),         # nickname, or "Player N" — same as the scoreboard
			"num": num,                              # stable display number (colour + ranking key)
			"color": _color_for_num(num),            # keyed by number, so it survives the re-sort below
			"score": int(_score_for_peer(peer).get("total", 0)),
			"dead": bool(_dead_by_peer.get(peer, false)),
			"peer": peer,  # so each client can find ITS OWN row and label the top-left box
		})
	# Rank highest-first (ties → lower player number) so the LIVE board reads the same way the end
	# scoreboard does. Each client still finds its own row by `peer`, and colours are by number, so
	# re-sorting every tick never reshuffles anyone's colour.
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		return int(a["num"]) < int(b["num"]))
	return rows


# Everyone: render the host's roster snapshot in the HUD scoreboard.
@rpc("authority", "call_local", "reliable")
func _receive_roster(rows: Array) -> void:
	if _mhud == null:
		return
	_mhud.set_roster(rows)
	# Show MY player number in the top-left box (matches the scoreboard), with "YOU" underneath.
	var my_id := multiplayer.get_unique_id()
	for row in rows:
		if int(row.get("peer", 0)) == my_id:
			_mhud.set_player_name(String(row.get("name", "YOU")), "YOU")
			# Our mark rings use our own roster colour (matches our scoreboard dot), applied locally.
			var col: Color = row.get("color", _my_ring_color)
			if col != _my_ring_color:
				_my_ring_color = col
				_recolor_my_rings()
				_mhud.set_legend_target_color(col)  # legend chip matches your ring colour
			break


# Count our own active item timers down locally so the "(ON Ns)" readout ticks every frame.
# The host still owns the real effect (it pushes the authoritative seconds on start/end); this
# only keeps the displayed number moving between those pushes.
func _tick_item_countdown(delta: float) -> void:
	if _mhud == null:
		return
	var changed := false
	for s in _item_state.get("slots", []):
		if float(s[2]) > 0.0:  # cooldown
			s[2] = maxf(0.0, float(s[2]) - delta)
			changed = true
		if float(s[3]) > 0.0:  # active effect
			s[3] = maxf(0.0, float(s[3]) - delta)
			changed = true
	if changed:
		_refresh_item_label()


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
			_request_spawn.rpc_id(NetworkManager.HOST_PEER_ID)


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
	# The cue/overlay layer (experiments, hunt arrow, sewer darken, faceplate reveals attach here).
	_player_hud_layer = CanvasLayer.new()
	_player_hud_layer.name = "PlayerHUD"
	add_child(_player_hud_layer)

	# The premium themed HUD (panels, roster, abilities, minimap slot). It joins the
	# "experiment_toast" group, so experiment events route into its log (no middle-screen text).
	_mhud = MatchHud.new()
	_mhud.name = "MatchHud"
	add_child(_mhud)
	var my_idx := int(_local_player.get("appearance_index")) if _local_player != null else 0
	_my_appearance_index = my_idx
	_mhud.set_player("YOU", "", my_idx)
	_mhud.set_objective("Locating your marks…")
	_mhud.add_log("Match started.")

	# A layer ABOVE the HUD just for the arrow, so panels never cover it (layer 5 > the default 1).
	_arrow_layer = CanvasLayer.new()
	_arrow_layer.name = "ArrowLayer"
	_arrow_layer.layer = 5
	add_child(_arrow_layer)

	# The hunter-danger vignette + heartbeat, on its own layer just under the arrow. The HOST drives
	# its level (identity-safe — only how close your hunter is, never which figure).
	var danger_layer := CanvasLayer.new()
	danger_layer.name = "DangerLayer"
	danger_layer.layer = 4
	add_child(danger_layer)
	_danger_overlay = DangerOverlay.new()
	_danger_overlay.name = "DangerOverlay"
	danger_layer.add_child(_danger_overlay)

	# Mini-map into the HUD's minimap slot, scaled to fit.
	_mini_map = MINI_MAP_SCRIPT.new() as MiniMap
	_mini_map.name = "MiniMap"
	if _mhud.minimap_slot != null:
		_mhud.minimap_slot.add_child(_mini_map)
	else:
		_player_hud_layer.add_child(_mini_map)
	_mini_map.position = Vector2.ZERO
	_mini_map.setup(_map as TestMap01, _local_player, null)
	if _mhud.minimap_slot != null and _mini_map.map_size_px.x > 0.0:
		var fit := minf(_mhud.minimap_slot.size.x / _mini_map.map_size_px.x, _mhud.minimap_slot.size.y / _mini_map.map_size_px.y)
		_mini_map.scale = Vector2(fit, fit)

	_build_layer_feedback()   # sewer overlay + arrow uptime (Slice B)
	_build_item_hud()         # smoke/cloak readout → MatchHud ability slots (Slice D)
	_build_faceplate_row()    # red/blue identity reveals (Slice E)
	if _is_hunted:
		_mhud.set_hunted(true)  # already being hunted before our HUD existed


func _highlight_mark(mark: Node) -> void:
	var visual := mark.get_node_or_null("CharacterVisual")
	if visual != null and visual.has_method("set_highlight"):
		visual.set("highlight_color", _my_ring_color)  # OUR colour, drawn only on OUR screen
		visual.call("set_highlight", true)


# Re-tint our existing mark rings to our colour (called once the roster tells us our colour).
func _recolor_my_rings() -> void:
	for mark_name in _resolved_marks:
		var mark: Node2D = _resolved_marks[mark_name]
		if mark != null and is_instance_valid(mark):
			var visual := mark.get_node_or_null("CharacterVisual")
			if visual != null:
				visual.set("highlight_color", _my_ring_color)


# Point the mini-map at the first still-living mark and update the "x / y done" caption.
# Called when a mark resolves locally or when the host tells us one died.
func _refresh_mark_tracking() -> void:
	var living: Array = []
	for mark_name in _my_mark_names:
		var mark: Node2D = _resolved_marks.get(mark_name)
		if mark != null and is_instance_valid(mark):
			living.append(mark)
	if _mini_map != null:
		_mini_map.track_objectives(living)  # show ALL your live marks so you can path between them
	if _mhud != null and not _hunt_phase:
		if _my_mark_names.is_empty():
			_mhud.set_objective("Locating your marks…")
		else:
			_mhud.set_objective("Kill your marks (your circles) — %d left." % living.size())


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
	# Sits on the dedicated top layer so HUD panels never cover the bearing.
	var arrow_parent: Node = _arrow_layer if _arrow_layer != null else _player_hud_layer
	arrow_parent.add_child(_target_arrow)
	_target_arrow.track_target(opponent)
	_target_arrow.set_precision_tier(_my_arrow_tier)  # keep our PvE-earned precision across retargets
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
				_apply_self_smoke_cue(character)  # ...but show YOU that you're hidden
			else:
				character.visible = _can_local_player_see(my_layer, character)
				_apply_disguise_view(character)  # show OTHER players' disguise (commoner) look


# Per-viewer DISGUISE: if this OTHER player is disguised, show them as their commoner body; when the
# disguise ends, restore their real look. Only changes on transition (tracked in _disguise_shown).
func _apply_disguise_view(character: Node2D) -> void:
	if not (character is Player):
		return
	var visual := character.get_node_or_null("CharacterVisual")
	if visual == null or not visual.has_method("set_appearance"):
		return
	var disguise_body := int(character.get("_net_disguise_body"))
	var shown := bool(_disguise_shown.get(character, false))
	if disguise_body >= 0 and not shown:
		visual.call("set_appearance", disguise_body)
		_disguise_shown[character] = true
	elif disguise_body < 0 and shown:
		# Restore their real look (the host-assigned loadout).
		if visual.has_method("apply_loadout"):
			visual.call("apply_loadout", _loadout_of_player(character))
		_disguise_shown[character] = false


# Self-only feedback: while YOUR smoke is up you stay fully visible to yourself (others can't
# see you), so fade your own rig to a clear-but-playable opacity so you KNOW you're hidden.
# Reads the same replicated `_net_smoked` flag the hiding uses, so it can never disagree with it.
func _apply_self_smoke_cue(character: Node2D) -> void:
	var visual := character.get_node_or_null("CharacterVisual")
	if visual == null or not visual.has_method("set_smoked"):
		return
	visual.call("set_smoked", bool(character.get("_net_smoked")), 0.45)


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

	# The looks we DUPLICATE into the crowd: every OTHER player's visible loadout (never our own),
	# PLUS any NPC-disguise decoy (their hidden assassin) so BOTH their commoner and their assassin
	# appear as crowd look-alikes — opponents can't track them by sprite type.
	var other_looks: Array = []  # Array[Loadout]
	for child in _players_parent.get_children():
		var other := child as Player
		if other != null and other != _local_player:
			other_looks.append(_loadout_of_player(other))
			var payload: Dictionary = other.get("loadout_payload")
			var decoy: StringName = payload.get("decoy_body", &"") if payload != null else &""
			if decoy != &"":
				var decoy_look := Loadout.new()
				decoy_look.set_item(CosmeticItem.Slot.BODY, decoy)
				other_looks.append(decoy_look)

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
	# Fill the rest with a 50/50 commoner/assassin crowd mix, re-rolling any that match OUR look.
	var guard := 0  # stop a pathological pool (e.g. a single body) from looping forever
	while looks.size() < crowd_size:
		var filler := Loadout.new()
		filler.set_item(CosmeticItem.Slot.BODY, CosmeticRegistry.random_crowd_body())
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
# The "what does this character look like" key used to camouflage the per-viewer crowd: two
# loadouts with the same key are visually interchangeable, so we never put YOUR key in YOUR crowd.
# PILLAR TODO (§0.3): today only BODY renders (outfit/head/weapon art are placeholders), so the
# body id IS the whole silhouette and a body-only key is correct. The MOMENT overlay art ships,
# fold OUTFIT/HEAD/WEAPON (and palette) into this key too — otherwise a paid outfit/hat on a human
# is not duplicated into a crowd look-alike group and becomes a tell. See CODE_AUDIT_PHASES_7-11.md §2.
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


# === tool kit HUD + effects =================================================
func _build_item_hud() -> void:
	_refresh_item_label()


# Drive the two MatchHud ability slots from our authoritative tool state: the tool's name + icon,
# its charges, and a live countdown (cooldown, or "ON Ns" while a durational effect runs).
func _refresh_item_label() -> void:
	if _mhud == null:
		return
	var slots: Array = _item_state.get("slots", [])
	for slot in mini(slots.size(), 2):
		var s: Array = slots[slot]
		var tool := int(s[0])
		var charges := int(s[1])
		var cooldown := float(s[2])
		var active := float(s[3])
		var key := "slot%d" % slot
		_mhud.set_ability_tool(key, ItemComponent.tool_name(tool), ItemComponent.tool_icon(tool))
		var sub := "x%d" % charges
		if active > 0.0:
			sub = "ON %ds" % int(ceil(active))
		elif cooldown > 0.0:
			sub = "%ds" % int(ceil(cooldown))
		var usable := (charges > 0 and cooldown <= 0.0 and active <= 0.0) or active > 0.0
		_mhud.set_ability(key, sub, usable)
	_mhud.set_ability("emote", "[V]", true)


# While OUR identity is hidden (disguise active — read straight off our replicated flag — or a morph
# is running), the top-left portrait shows a "?". Driven every frame from authoritative state so it
# can't get out of sync with the effect. Called from _process.
func _update_identity_portrait() -> void:
	if _mhud == null or _local_player == null:
		return
	var hidden := int(_local_player.get("_net_disguise_body")) >= 0
	if not hidden:
		for s in _item_state.get("slots", []):
			if float(s[3]) > 0.0 and int(s[0]) == ItemComponent.Tool.MORPH:
				hidden = true
				break
	if hidden:
		_mhud.set_portrait_unknown()
	else:
		_mhud.set_portrait(_my_appearance_index)


# HOST: a tool was used by `peer_id`. Apply its world effect (server-authoritative), then refresh
# that player's readout. (Disguise/morph/decoy/poison are wired in the next slices.)
func _on_tool_activated(tool: int, slot: int, peer_id: int) -> void:
	var character := _players_by_peer.get(peer_id) as Player
	if character != null and is_instance_valid(character):
		var ok := true
		match tool:
			ItemComponent.Tool.SMOKE:
				_deploy_smoke(character, peer_id)
			ItemComponent.Tool.DECOY:
				ok = _deploy_decoy(character)
			ItemComponent.Tool.DISGUISE:
				ok = _apply_disguise(character, peer_id)
			ItemComponent.Tool.MORPH:
				_apply_morph_host(character, peer_id)
			ItemComponent.Tool.POISON:
				ok = _apply_poison(character, peer_id)
			ItemComponent.Tool.FIRECRACKER:
				_deploy_firecracker(character, peer_id)
			_:
				_announce_panic_unimplemented(tool)  # placeholder until its slice lands
		# A target-needing tool (disguise/decoy/poison) fired with nothing in the ring — refund + tell.
		if not ok:
			var item := character.get_node_or_null("ItemComponent") as ItemComponent
			if item != null:
				item.refund(slot)
			_notify_owner.rpc_id(peer_id, "Aim at someone in your ring first.")
	_push_item_state_to(peer_id)


# Owner-only feedback line (so tools that worked/failed give the user a clear, immediate cue).
@rpc("authority", "call_local", "reliable")
func _notify_owner(text: String) -> void:
	if _mhud != null:
		_mhud.add_log(text)


# Everyone: remove an eliminated player's EXPOSED reveal plate so it doesn't linger after they're out.
@rpc("authority", "call_local", "reliable")
func _remove_exposed_reveal(reveal_id: int) -> void:
	if _mhud != null:
		_mhud.remove_exposed_reveal(reveal_id)


func _on_tool_expired(tool: int, _slot: int, peer_id: int) -> void:
	if tool == ItemComponent.Tool.DISGUISE:
		_clear_disguise(peer_id)
	_push_item_state_to(peer_id)


# Temporary: log "not yet wired" for tools whose effect ships in a later slice, so a player who
# equips one isn't left wondering why nothing happened (the charge/cooldown still tick).
func _announce_panic_unimplemented(tool: int) -> void:
	if _mhud != null:
		_mhud.add_log("%s isn't wired up yet." % ItemComponent.tool_name(tool).capitalize())


# HOST: deploy a smoke cloud at the player's feet (spawned on every machine so all SEE it). The
# host's per-frame stun loop then catches anyone (but the deployer) standing inside it.
func _deploy_smoke(character: Player, peer_id: int) -> void:
	var item := character.get_node_or_null("ItemComponent") as ItemComponent
	if item == null:
		return
	_spawn_smoke_cloud.rpc(character.global_position, item.smoke_cloud_radius, item.smoke_cloud_seconds, item.smoke_stun_seconds, peer_id)


# Everyone: spawn the smoke cloud visual + marker in the world. The host's copy also drives stuns
# (via the "smoke_cloud" group); clients' copies are visual-only.
@rpc("authority", "call_local", "reliable")
func _spawn_smoke_cloud(world_pos: Vector2, radius: float, life: float, stun_seconds: float, deployer_peer: int) -> void:
	var cloud := SmokeCloud.new()
	cloud.set("stun_seconds", stun_seconds)
	var parent: Node = _map if _map != null else self
	parent.add_child(cloud)
	cloud.setup(world_pos, radius, life, deployer_peer)
	# A small deploy pop on the deployer's body, for feedback.
	var deployer := _players_by_peer.get(deployer_peer) as Node
	if deployer == null and _players_parent != null:
		for p in _players_parent.get_children():
			if int(p.get("controlling_peer_id")) == deployer_peer:
				deployer = p
				break
	if deployer != null:
		var v := deployer.get_node_or_null("CharacterVisual")
		if v != null and v.has_method("play_strike"):
			v.call("play_strike")


# HOST: DECOY — spook the NPC in the player's interaction ring (the one they're facing) into bolting
# away (it looks like a fleeing human, baiting a hunter into a wrong kill). The host owns NPC motion,
# so the flee replicates to every client as ordinary movement.
func _deploy_decoy(character: Player) -> bool:
	var item := character.get_node_or_null("ItemComponent") as ItemComponent
	var flee: float = item.decoy_flee_seconds if item != null else 4.0
	var target := _tool_target_for(character)  # the NPC the client targeted (or our best guess)
	if target == null or not target.has_method("flee_run"):
		return false
	# 2.0× walk = 180 px/s, comfortably below the player's 220 run so you can still chase it down.
	target.call("flee_run", target.velocity, flee, 2.0)  # bolt in its current direction
	return true


# The NPC a tool should act on: prefer the EXACT one the controlling client sent (validated to be a
# real crowd NPC near the player), so decoy/disguise hit what the player saw highlighted; fall back
# to the host's own facing query (used for the host's own player, which sends no target). Consumed.
func _tool_target_for(character: Player) -> Node2D:
	var node := _consume_pending_target(character, false)  # NPC only
	return node if node != null else character.interaction_target(false)


# Like _tool_target_for but also allows a PLAYER (poison can kill your human target too).
func _poison_target_for(character: Player) -> Node2D:
	var node := _consume_pending_target(character, true)
	return node if node != null else character.interaction_target(true)


# Read + clear the client-sent target, validating it's a real character near the player. `allow_player`
# lets a player target through (poison); otherwise only crowd NPCs (decoy/disguise). Null if invalid.
func _consume_pending_target(character: Player, allow_player: bool) -> Node2D:
	var path: NodePath = character.get("_pending_tool_target")
	character.set("_pending_tool_target", NodePath(""))  # consume — don't leak to the next tool
	if path == NodePath(""):
		return null
	var node := get_node_or_null(path) as Node2D
	if node == null or not is_instance_valid(node) or node == character:
		return null
	var ok_kind := node.is_in_group("npc") or (allow_player and node.is_in_group("player"))
	if not ok_kind:
		return null
	if node.global_position.distance_to(character.global_position) > character.interaction_radius * 1.6:
		return null
	return node


# HOST: POISON — a delayed, quiet kill on the target in your ring (NPC mark or your human target).
func _apply_poison(character: Player, peer_id: int) -> bool:
	var kill := character.get_node_or_null("KillComponent") as KillComponent
	if kill == null:
		return false
	var item := character.get_node_or_null("ItemComponent") as ItemComponent
	var delay: float = item.poison_delay_seconds if item != null else 4.0
	var target := _poison_target_for(character)
	if target == null:
		return false
	if not kill.host_poison(target, delay):
		return false
	_notify_owner.rpc_id(peer_id, "Target poisoned — they drop in %ds." % int(delay))
	return true


# HOST: DISGUISE — this player looks like a random COMMONER to everyone else for the duration
# (a replicated body index every other machine swaps in; the owner keeps their real look). Also
# suppress the hunt arrow their hunter holds on them — the disguise breaks the visual lock.
func _apply_disguise(character: Player, peer_id: int) -> bool:
	# Must be aimed at an NPC in the ring — you disguise AS that civilian (take their look).
	var target := _tool_target_for(character)
	if target == null:
		return false
	character.set("_net_disguise_body", _appearance_of_node(target))
	var hunter := _hunter_of_target(peer_id)
	if hunter != 0:
		_set_opponent_arrow_suppressed.rpc_id(hunter, true)
	var item := character.get_node_or_null("ItemComponent") as ItemComponent
	var secs: int = int(item.disguise_seconds) if item != null else 30
	_notify_owner.rpc_id(peer_id, "Disguised as a civilian (%ds)." % secs)
	_refresh_reveals_for(peer_id)  # if we were already revealed, our plate flips to "?" now
	return true


# The look to put on a reveal plate for `character`: their real body index, or −1 ("?") if they're
# DISGUISED right now — disguise hides your identity even from an exposure/target reveal.
func _revealed_look(character: Node) -> int:
	if character != null and int(character.get("_net_disguise_body")) >= 0:
		return -1
	return int(character.get("appearance_index"))


# The body index a character is currently wearing (falls back to a random commoner).
func _appearance_of_node(node: Node) -> int:
	var v := node.get_node_or_null("CharacterVisual")
	if v != null and v.has_method("get_appearance"):
		return int(v.call("get_appearance"))
	return _random_commoner_index()


func _clear_disguise(peer_id: int) -> void:
	var character := _players_by_peer.get(peer_id) as Player
	if character != null and is_instance_valid(character):
		character.set("_net_disguise_body", -1)
	var hunter := _hunter_of_target(peer_id)
	if hunter != 0:
		_set_opponent_arrow_suppressed.rpc_id(hunter, false)
	_refresh_reveals_for(peer_id)  # disguise over → any reveal plate of us flips back to our real sprite


# Re-send the current reveal look for `peer_id` so its plate matches its disguise state right now:
# "?" while disguised, real sprite once the disguise ends. Covers the EXPOSED plate (everyone who
# can see it) and the TARGET plate (the one hunter who earned it).
func _refresh_reveals_for(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var character := _players_by_peer.get(peer_id) as Player
	if character == null or not is_instance_valid(character):
		return
	var look := _revealed_look(character)
	if bool(_exposure_revealed.get(peer_id, false)):
		for other_peer in _players_by_peer:
			if other_peer != peer_id and not bool(_dead_by_peer.get(other_peer, false)):
				_receive_exposure_reveal.rpc_id(other_peer, peer_id, look)
	if _target_reveal_subject == peer_id and _target_reveal_to != 0:
		_receive_target_reveal.rpc_id(_target_reveal_to, look)


func _random_commoner_index() -> int:
	var ids: Array = CosmeticRegistry.COMMONER_BODY_IDS
	if ids.is_empty():
		return 1
	return int(CosmeticRegistry.index_for_body_id(ids[randi() % ids.size()]))


# HOST: MORPH — tell EVERY machine to reskin the nearest NPCs around this player to that player's
# look for a while (so a hunter can't tell which is the real one). Each machine applies it locally
# to its own crowd (the look is per-viewer), so it rides on top of the per-viewer crowd cleanly.
func _apply_morph_host(character: Player, _peer_id: int) -> void:
	var item := character.get_node_or_null("ItemComponent") as ItemComponent
	if item == null:
		return
	# Identify the morphing body by NODE NAME (consistent across peers), not its controlling_peer_id —
	# so clients never need the owner id to apply a morph (Stage 8: don't depend on the identity field).
	_apply_morph.rpc(String(character.name), item.morph_npc_count, item.morph_radius, item.morph_seconds)


# Everyone: copy player `peer`'s CURRENT look onto the `count` nearest crowd NPCs within `radius`,
# remembering each NPC's previous look so _process can revert it after `duration`.
@rpc("authority", "call_local", "reliable")
func _apply_morph(player_name: String, count: int, radius: float, duration: float) -> void:
	if _players_parent == null:
		return
	var player := _players_parent.get_node_or_null(player_name) as Node2D
	if player == null:
		return
	var src := player.get_node_or_null("CharacterVisual")
	if src == null or not src.has_method("get_appearance"):
		return
	var look_index := int(src.call("get_appearance"))
	for npc in _nearest_npcs_local(player.global_position, count, radius):
		var visual: Node = (npc as Node).get_node_or_null("CharacterVisual")
		if visual == null or not visual.has_method("set_appearance"):
			continue
		_morph_active.append({"visual": visual, "restore": int(visual.call("get_appearance")), "left": duration})
		visual.call("set_appearance", look_index)


# Find a player node on THIS machine by the peer that controls it (clients don't have _players_by_peer).
func _player_by_peer_local(peer: int) -> Node2D:
	if _players_parent == null:
		return null
	for child in _players_parent.get_children():
		if int(child.get("controlling_peer_id")) == peer:
			return child as Node2D
	return null


# The `count` closest living crowd NPCs within `radius` of `pos` (host or client; local crowd).
func _nearest_npcs_local(pos: Vector2, count: int, radius: float) -> Array:
	var scored: Array = []
	if _crowd_parent != null:
		for child in _crowd_parent.get_children():
			var npc := child as Npc
			if npc == null or npc.is_dead():
				continue
			var dist := npc.global_position.distance_to(pos)
			if dist <= radius:
				scored.append({"npc": npc, "dist": dist})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])
	var out: Array = []
	for i in mini(count, scored.size()):
		out.append(scored[i]["npc"])
	return out


# Per frame (every machine): count down active morphs and revert each NPC when its time is up.
func _tick_morphs(delta: float) -> void:
	for i in range(_morph_active.size() - 1, -1, -1):
		var entry: Dictionary = _morph_active[i]
		entry["left"] = float(entry["left"]) - delta
		var visual = entry["visual"]
		if visual == null or not is_instance_valid(visual):
			_morph_active.remove_at(i)
			continue
		if float(entry["left"]) <= 0.0:
			visual.call("set_appearance", int(entry["restore"]))
			_morph_active.remove_at(i)


# HOST-only, per frame: stun any (non-owner) player standing in a smoke cloud, for the cloud's
# stun_seconds; tick the stun down and lift it (unfreeze + re-enable kills) when it ends.
func _update_smoke_stuns(delta: float) -> void:
	var clouds := get_tree().get_nodes_in_group("smoke_cloud")
	for peer in _players_by_peer:
		var character := _players_by_peer[peer] as Player
		if character == null or not is_instance_valid(character) or bool(_dead_by_peer.get(peer, false)):
			continue
		# Refresh the stun if currently inside a cloud someone ELSE deployed.
		for cloud in clouds:
			var sc := cloud as SmokeCloud
			if sc == null or sc.owner_peer == peer:
				continue
			if sc.contains(character.global_position):
				# Cap the stun by the cloud's REMAINING life so it can never outlast the animation.
				var capped := minf(float(sc.get("stun_seconds")), sc.remaining())
				_stun_left_by_peer[peer] = maxf(float(_stun_left_by_peer.get(peer, 0.0)), capped)
		var left := float(_stun_left_by_peer.get(peer, 0.0))
		if left > 0.0:
			left = maxf(0.0, left - delta)
			_stun_left_by_peer[peer] = left
		_set_player_stunned(character, left > 0.0)


# Freeze/unfreeze a player and block/allow their kills (host-authoritative, replicated).
func _set_player_stunned(character: Player, on: bool) -> void:
	if bool(character.get("_net_stunned")) == on:
		return
	character.set("_net_stunned", on)
	var kill := character.get_node_or_null("KillComponent")
	if kill != null:
		kill.set("attacks_disabled", on)


# HOST: send a player their authoritative tool state (owner-only): per slot [tool, charges,
# cooldown_left, active_left]. The client ticks the timers between pushes (in _tick_item_countdown).
func _push_item_state_to(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var character := _players_by_peer.get(peer_id) as Node
	if character == null:
		return
	var item := character.get_node_or_null("ItemComponent") as ItemComponent
	if item == null:
		return
	var slots: Array = []
	for slot in 2:
		slots.append([item.tool_in_slot(slot), item.charges_left_slot(slot), item.cooldown_left_slot(slot), item.active_left_slot(slot)])
	_receive_item_state.rpc_id(peer_id, slots)


# Owner-only: store the host's authoritative tool numbers + refresh the readout.
@rpc("authority", "call_local", "reliable")
func _receive_item_state(slots: Array) -> void:
	_item_state = {"slots": slots}
	_refresh_item_label()


# Owner-only: the player we hunt raised a cloak — hide our hunt arrow on them.
@rpc("authority", "call_local", "reliable")
func _set_opponent_arrow_suppressed(on: bool) -> void:
	if _target_arrow != null:
		_target_arrow.set_suppressed(on)


# === Slice E — identity reveals + faceplates (§7.4) =========================
func _build_faceplate_row() -> void:
	# Reveals now render as MatchHud portrait plates. Apply any that arrived before the HUD existed.
	if _mhud == null:
		return
	if _pending_target_face >= 0:
		_mhud.set_target_reveal(_pending_target_face)
	for pair in _pending_exposed_faces:
		_mhud.add_exposed_reveal(int(pair[0]), int(pair[1]))


# Owner-only: we finished our marks first — here's our target's look (red plate).
@rpc("authority", "call_local", "reliable")
func _receive_target_reveal(appearance_index: int) -> void:
	if _mhud != null:
		_mhud.set_target_reveal(appearance_index)
		_mhud.add_log("Marks down — your target is revealed.")
	else:
		_pending_target_face = appearance_index


# Owner-only: an opponent hit 100% exposure — here's their look (blue plate), keyed by reveal_id
# (their peer) so the SAME player's plate updates if they later disguise / un-disguise.
@rpc("authority", "call_local", "reliable")
func _receive_exposure_reveal(reveal_id: int, appearance_index: int) -> void:
	if _mhud != null:
		_mhud.add_exposed_reveal(reveal_id, appearance_index)
	else:
		_pending_exposed_faces.append([reveal_id, appearance_index])


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
	# Abstract Input Map actions only — never raw keycodes (Principle #2), so these work on a
	# controller too. `ui_cancel` is Godot's built-in Escape/B-button action; `toggle_net_debug`
	# is our own action (F3 by default) defined in project.godot's Input Map.
	if event.is_action_pressed("ui_cancel"):
		_return_to_menu()  # leave the match back to the menu
	elif event.is_action_pressed("toggle_net_debug"):
		# Toggle the network debug overlay (FPS / ping / pending inputs).
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
	# CORE crowd panic: scatter nearby NPCs on EVERY resolved kill. Owned here (not the optional
	# crowd_reaction experiment) so it's reliable online and in exported builds — the experiment's
	# file-scan loader doesn't run in exports, which is why the crowd never reacted in MP. Poison never
	# emits kill_resolved, so a poisoning stays silent (no scatter) exactly as designed.
	_scatter_crowd_on_kill(victim)


# Host-only: make living NPCs near a kill flee outward for a few seconds. The host owns NPC motion,
# so the flee replicates to every client as ordinary movement (same path the decoy tool uses).
func _scatter_crowd_on_kill(victim: Node) -> void:
	if not multiplayer.is_server() or victim == null or not is_instance_valid(victim):
		return
	var kill_pos: Vector2 = (victim as Node2D).global_position
	for node in get_tree().get_nodes_in_group("npc"):
		var npc := node as Npc
		if npc == null or not is_instance_valid(npc) or npc.is_dead() or not npc.has_method("react_to_kill"):
			continue
		var distance: float = npc.global_position.distance_to(kill_pos)
		if distance > crowd_panic_radius_px:
			continue
		# Closer NPCs bolt faster (a tighter, more obviously-startled knot right at the kill).
		var closeness: float = 1.0 - clampf(distance / crowd_panic_radius_px, 0.0, 1.0)
		var scale: float = lerpf(crowd_panic_speed_scale * 0.6, crowd_panic_speed_scale, closeness)
		npc.react_to_kill(kill_pos, true, crowd_panic_seconds, scale)


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
