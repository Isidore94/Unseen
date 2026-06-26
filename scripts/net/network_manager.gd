extends Node

# NetworkManager — UNSEEN, Phase 6.0 (see MULTIPLAYER_PLAN.md §3, §5).
#
# ONE JOB: connectivity. It creates the connection (who is host, who is client) and
# re-emits Godot's raw multiplayer events as clean, named signals the game listens to.
# Nothing game-specific lives here — no players, no rules — so the transport can be
# swapped later (ENet now → Steam relay in 6.2) without touching the game.
#
# It is an AUTOLOAD (a "singleton"): one copy exists for the whole app, reachable
# everywhere as `NetworkManager`, and it survives scene changes (menu → match).
#
# PLAIN TERMS:
#   - "host" = the one machine that referees (its peer id is always 1).
#   - "client" = everyone else; they connect TO the host.
#   - We use ENet (Godot's built-in networking) over localhost for now, so you can
#     test by running the game twice on one PC — no Steam, no internet required.

## Port the host listens on / clients connect to. Any free high number is fine.
const DEFAULT_PORT := 24565

## Hard cap on players this build allows (first milestone runs with 2).
const MAX_PLAYERS := 4

## Fired (on the host) when a client joins, and (on clients) when another peer joins.
signal player_joined(peer_id: int)
## Fired when a peer leaves / disconnects.
signal player_left(peer_id: int)
## Fired on a CLIENT once it has successfully connected to the host.
signal connection_succeeded
## Fired on a CLIENT if the connection attempt fails.
signal connection_failed
## Fired on a CLIENT if the host goes away mid-session.
signal server_closed

var _active_peer: MultiplayerPeer = null


func _ready() -> void:
	# Connect to Godot's multiplayer events ONCE. They stay quiet until we actually
	# create a host or join, then start firing. We just forward them as our own
	# tidy signals so the rest of the game never touches the raw API.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# === public API (the menu calls these) =====================================

# Become the host. Returns true on success.
func host_game(port: int = DEFAULT_PORT) -> bool:
	var enet := ENetMultiplayerPeer.new()
	# MAX_PLAYERS - 1 because the host itself takes one of the slots.
	var result := enet.create_server(port, MAX_PLAYERS - 1)
	if result != OK:
		push_error("NetworkManager: could not host on port %d (error %d)." % [port, result])
		return false
	_active_peer = enet
	multiplayer.multiplayer_peer = enet
	return true


# Connect to a host. For loopback testing the address is "127.0.0.1" (this PC).
func join_game(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> bool:
	var enet := ENetMultiplayerPeer.new()
	var result := enet.create_client(address, port)
	if result != OK:
		push_error("NetworkManager: could not start client to %s:%d (error %d)." % [address, port, result])
		return false
	_active_peer = enet
	multiplayer.multiplayer_peer = enet
	return true


# Tear the session down and go back to "not networked".
func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	_active_peer = null


# True on the host machine (the referee). False on clients.
func is_host() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


# This machine's own peer id (host is always 1).
func local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


# === raw event handlers → clean signals ====================================

func _on_peer_connected(peer_id: int) -> void:
	player_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	player_left.emit(peer_id)


func _on_connected_to_server() -> void:
	connection_succeeded.emit()


func _on_connection_failed() -> void:
	connection_failed.emit()
	leave()


func _on_server_disconnected() -> void:
	server_closed.emit()
	leave()
