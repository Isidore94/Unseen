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
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const NPC_SCENE := preload("res://scenes/npc.tscn")
const MINI_MAP_SCRIPT := preload("res://scripts/mini_map.gd")
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

## How many sprite sheets exist (assets/sprites). Characters cycle through them so a
## small match still looks varied. Keep in sync with CharacterVisual's sheet list.
const NUM_SHEETS := 5

## Size of the AI crowd the host simulates (the people you hide among).
@export var npc_count: int = 180

## Fraction of the crowd that CROSSES the map (spawn at an edge, long paths). The rest
## are "homebodies" that mill around their spawn spot with short trips.
@export var traveler_fraction: float = 0.25

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

## Host-only: which crowd NPC is each peer's secret mark. The mapping never leaves
## the host; each peer is told only ITS OWN mark (MULTIPLAYER_PLAN.md §4).
var _mark_by_peer: Dictionary = {}

## Host-only contract state: each peer's phase ("marks" -> "target" -> "done") and,
## once in the target phase, which peer they are hunting.
var _phase_by_peer: Dictionary = {}
var _hunter_target: Dictionary = {}  # hunter_peer -> target_peer
var _round_over: bool = false

## This machine's own private view. Host AND client each control one local player and
## each builds its own HUD + mini-map + mark highlight for that player only.
var _local_player: Player = null
var _player_hud_layer: CanvasLayer = null
var _mini_map: MiniMap = null
var _objective_label: Label = null
var _exposure_bar: ProgressBar = null
var _my_mark_name: String = ""
var _my_mark: Node2D = null
## Online PvP: our opponent (the other player). Known from the start so the exposure
## arrow can react when they run; only KILLABLE once we've finished our own mark.
var _my_target_name: String = ""
var _my_target: Node2D = null
var _target_arrow: ExposureArrow = null
## True once our mark is dead — flips the arrow from exposure-gated to flashing.
var _hunt_phase: bool = false


func _ready() -> void:
	_build_world()
	_build_hud()

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
	_map = MAP_SCENE.instantiate()
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
	# Spawn the host's own character (the host is peer 1 and also a player).
	_spawn_player_for_peer(1)
	# Populate the crowd the players hide among (host-simulated, replicated out).
	_spawn_crowd()
	# Now the crowd exists, give the host its own secret mark.
	_assign_mark_for_peer(1)
	# When a client's scene is ready, it asks us (via _request_spawn) to spawn it.
	NetworkManager.player_left.connect(_on_player_left)


func _spawn_crowd() -> void:
	var map := _map as TestMap01
	for _i in npc_count:
		# A minority cross the whole map (entering from an edge); most are homebodies
		# that spawn wherever and potter around there.
		var is_traveler := randf() < traveler_fraction
		var spawn_position := Vector2.ZERO
		if map != null:
			spawn_position = map.random_edge_walkable_point() if is_traveler else map.random_walkable_point()
		var spawn_data := {
			"pos": spawn_position,
			"appearance": randi() % NUM_SHEETS,
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
	_spawn_player_for_peer(requesting_peer)
	_assign_mark_for_peer(requesting_peer)
	# Both players now exist — tell each who their opponent is (for the exposure arrow).
	_notify_opponents()


# Host-only: privately tell each player which node is their opponent (2-player: the
# other one). Owner-only, so nobody else learns it. Used by the exposure arrow.
func _notify_opponents() -> void:
	if not multiplayer.is_server():
		return
	for peer_id in _players_by_peer:
		var opponent_peer := _other_peer(peer_id)
		if opponent_peer != 0:
			var opponent := _players_by_peer[opponent_peer] as Node
			_receive_opponent.rpc_id(peer_id, String(opponent.name))


# Owner-only: remember our opponent's node name; the per-frame view resolves it.
@rpc("authority", "call_local", "reliable")
func _receive_opponent(opponent_name: String) -> void:
	if _my_target_name == "":
		_my_target_name = opponent_name


func _spawn_player_for_peer(peer_id: int) -> void:
	var spawn_data := {
		"peer": peer_id,
		"pos": _spawn_position_for_index(_next_spawn_index),
		"appearance": _next_spawn_index % NUM_SHEETS,
	}
	var character := _player_spawner.spawn(spawn_data)
	_players_by_peer[peer_id] = character
	_next_spawn_index += 1

	# Host relays THIS player's exposure to its owner only (private — §4). The signal
	# fires only when the value changes, so this isn't a constant stream.
	var exposure := character.get_node_or_null("ExposureComponent")
	if exposure != null:
		exposure.exposure_changed.connect(_on_player_exposure_changed.bind(peer_id))

	# Host watches for this player being killed (their death ends the round).
	character.died.connect(_on_player_killed.bind(peer_id))

	_update_status()


# Host-side: a player's exposure changed → push it to that player (their own bar) AND
# to their opponent (so the opponent's exposure arrow can react when this player runs).
func _on_player_exposure_changed(value: float, peer_id: int) -> void:
	_receive_exposure.rpc_id(peer_id, value)
	var opponent_peer := _other_peer(peer_id)
	if opponent_peer != 0:
		_receive_opponent_exposure.rpc_id(opponent_peer, value)


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
	if _players_by_peer.has(peer_id):
		var character: Node = _players_by_peer[peer_id]
		if is_instance_valid(character):
			character.queue_free()  # the spawner replicates the removal to clients
		_players_by_peer.erase(peer_id)
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
	npc.position = spawn_data["pos"]
	npc.is_traveler = bool(spawn_data["traveler"])
	npc.home_position = spawn_data["pos"]  # homebodies mill around where they spawned
	npc.wander_radius = float(spawn_data["wander_radius"])
	var visual := npc.get_node_or_null("CharacterVisual")
	if visual != null:
		visual.set("randomize_on_ready", false)
	return npc


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
	var mark: Npc = candidates[randi() % candidates.size()]
	mark.add_to_group("killable_for_%d" % peer_id)  # the host-validated kill check uses this
	mark.add_to_group("mark")
	_mark_by_peer[peer_id] = mark
	# Tell the owner privately when their mark dies (the host emits "died" on the kill).
	mark.died.connect(_on_mark_killed.bind(peer_id))
	# Send the mark's node name ONLY to its owner. The name matches across peers, so
	# the owner can find the same NPC in its own copy of the crowd.
	_receive_mark.rpc_id(peer_id, String(mark.name))


# Host-side: a peer's mark was killed → move that peer into the PvP "hunt" phase.
func _on_mark_killed(peer_id: int) -> void:
	_begin_target_phase(peer_id)


# Host-only: the peer has finished their mark, so now they hunt the human opponent.
# We make the opponent killable BY this peer and privately tell this peer who it is.
func _begin_target_phase(peer_id: int) -> void:
	if not multiplayer.is_server() or _phase_by_peer.get(peer_id, "marks") == "target":
		return
	var opponent_peer := _other_peer(peer_id)
	if opponent_peer == 0:
		return  # nobody to hunt yet
	_phase_by_peer[peer_id] = "target"
	_hunter_target[peer_id] = opponent_peer
	var opponent := _players_by_peer[opponent_peer] as Player
	opponent.add_to_group("killable_for_%d" % peer_id)  # the kill check now lets us kill them
	_enter_hunt_phase.rpc_id(peer_id)


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
	_my_mark = null
	_my_mark_name = ""
	if _objective_label != null:
		_objective_label.text = "Mark down — HUNT YOUR OPPONENT."
	if _target_arrow != null:
		_target_arrow.set_flashing(true)


# === win / lose =============================================================

# Host-side: a player was killed → the round is over; whoever was hunting them wins.
func _on_player_killed(loser_peer: int) -> void:
	if not multiplayer.is_server() or _round_over:
		return
	_round_over = true
	var winner_peer := _hunter_of(loser_peer)
	_declare_round_over.rpc(winner_peer)


func _hunter_of(loser_peer: int) -> int:
	for hunter_peer in _hunter_target:
		if _hunter_target[hunter_peer] == loser_peer:
			return hunter_peer
	return _other_peer(loser_peer)  # fallback: the other player


# Everyone: show the result for THIS machine and freeze the match.
@rpc("authority", "call_local", "reliable")
func _declare_round_over(winner_peer: int) -> void:
	var we_won := winner_peer == multiplayer.get_unique_id()
	_show_end_overlay(we_won)
	get_tree().paused = true


func _show_end_overlay(we_won: bool) -> void:
	var overlay := CanvasLayer.new()
	overlay.name = "EndOverlay"
	# Keep working while the tree is paused, so the button still responds.
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.add_theme_constant_override("separation", 16)
	overlay.add_child(box)

	var result := Label.new()
	result.text = "YOU WIN" if we_won else "YOU LOSE"
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", 56)
	box.add_child(result)

	var menu_button := Button.new()
	menu_button.text = "Back to menu"
	menu_button.process_mode = Node.PROCESS_MODE_ALWAYS
	box.add_child(menu_button)
	menu_button.pressed.connect(func() -> void:
		get_tree().paused = false
		_return_to_menu()
	)


# Owner-only: the host tells US which crowd NPC is our mark. We just remember the
# name; the per-frame view resolves it once that NPC has replicated to us.
@rpc("authority", "call_local", "reliable")
func _receive_mark(mark_name: String) -> void:
	_my_mark_name = mark_name


# === this machine's private view (host AND client each have one) ============

func _process(_delta: float) -> void:
	_update_local_view()


# Lazily wires up our own HUD and resolves our mark. Doing it per-frame (instead of
# at one exact moment) sidesteps every network timing race: as soon as our player
# and our mark exist locally, we hook them up — no sooner, no special handshake.
func _update_local_view() -> void:
	if _local_player == null:
		_local_player = _find_local_player()
		if _local_player != null:
			_build_player_hud()

	if _my_mark == null and _my_mark_name != "" and _crowd_parent != null:
		var mark := _crowd_parent.get_node_or_null(_my_mark_name) as Node2D
		if mark != null:
			_my_mark = mark
			_highlight_mark(mark)  # only THIS screen highlights it — no leak online
			if _mini_map != null:
				_mini_map.track_objective(mark)
			if _objective_label != null:
				_objective_label.text = "Find and eliminate your mark (gold dot)."

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


func _highlight_mark(mark: Node) -> void:
	var visual := mark.get_node_or_null("CharacterVisual")
	if visual != null and visual.has_method("set_highlight"):
		visual.call("set_highlight", true)


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
	# Quick escape back to the menu while prototyping.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_return_to_menu()
