extends Node2D
class_name OnlineMatch

# OnlineMatch — UNSEEN, Phase 6.0 (see MULTIPLAYER_PLAN.md §5, §9).
#
# The online "run shell" — the networked replacement for the split-screen scene.
# It builds the world the SAME way on every machine (the map is plain static
# geometry, so each peer just builds its own copy) and lets the HOST spawn one
# character per connected player. Those characters are the only thing replicated.
#
# 6.0 SCOPE: just players walking around in sync. No crowd, no kills yet — those
# come in 6.1. This milestone exists to prove the networking loop end-to-end.

const MAP_SCENE := preload("res://maps/test_map_01.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

## How many sprite sheets exist (assets/sprites). Characters cycle through them so a
## small match still looks varied. Keep in sync with CharacterVisual's sheet list.
const NUM_SHEETS := 5

var _map: Node = null
var _players_parent: Node2D = null
var _player_spawner: MultiplayerSpawner = null
var _status_label: Label = null

## Host-only bookkeeping: which character belongs to which peer, and the next spawn
## slot to use. Lives only on the host (the referee) — clients never see it.
var _players_by_peer: Dictionary = {}
var _next_spawn_index: int = 0


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


# === host ===================================================================

func _start_as_host() -> void:
	# Spawn the host's own character (the host is peer 1 and also a player).
	_spawn_player_for_peer(1)
	# When a client's scene is ready, it asks us (via _request_spawn) to spawn it.
	NetworkManager.player_left.connect(_on_player_left)


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


func _spawn_player_for_peer(peer_id: int) -> void:
	var spawn_data := {
		"peer": peer_id,
		"pos": _spawn_position_for_index(_next_spawn_index),
		"appearance": _next_spawn_index % NUM_SHEETS,
	}
	var character := _player_spawner.spawn(spawn_data)
	_players_by_peer[peer_id] = character
	_next_spawn_index += 1
	_update_status()


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


func _spawn_position_for_index(index: int) -> Vector2:
	var map := _map as TestMap01
	if map != null:
		var spawns := map.get_player_spawns()
		if index >= 0 and index < spawns.size():
			return spawns[index]
	# Fallback if the map has no spawn points: stagger them so they don't overlap.
	return Vector2(-400.0 + index * 200.0, 0.0)


func _return_to_menu() -> void:
	NetworkManager.leave()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


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
