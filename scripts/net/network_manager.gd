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

## The host's peer id. In Godot's high-level multiplayer the server is ALWAYS peer 1,
## so `rpc_id(HOST_PEER_ID, ...)` means "run this on the host". Named so the intent is
## obvious instead of a bare `1` scattered through the networking code.
const HOST_PEER_ID := 1

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
## Fired once a Steam lobby is created (host) or joined (client) and the peer is live.
signal steam_lobby_ready(lobby_id: int)
## Fired if creating or joining a Steam lobby fails (with a human-readable reason).
signal steam_lobby_failed(reason: String)

## Match setting chosen in the lobby (the host's choice, sent to everyone at start): use
## the compact arena — smaller map + fewer NPCs, lighter for the host to simulate/serve.
## Lives here (an autoload) so it survives the lobby → match scene change. Kept as the
## "is this a small map?" flag (drives the compact crowd count); the SCENE is now chosen by
## `selected_map` below, and the lobby sets both together.
## Defaults to true: the COMPACT arena is our main map now (see selected_map below), so an
## un-touched lobby still loads it with the lighter compact crowd. The lobby overrides both.
var small_arena: bool = true

## Which map the lobby picked (Phase 10). Index into the lobby's map list — the match reads
## it to load the right scene. FOUR_ZONE is the full main map; COMPACT, ROME and CITADEL are the
## small/medium maps (so they also set small_arena = true for the lighter crowd). Survives the
## scene change. CITADEL is the new AC-Rearmed-style main map (bigger + denser than COMPACT).
enum Map { FOUR_ZONE, COMPACT, ROME, CITADEL }
## Defaults to CITADEL — our main map now (matches small_arena = true above).
var selected_map: int = Map.CITADEL

## The two TOOLS this player picked in the lobby (ItemComponent.Tool ints: 0=smoke, 1=disguise,
## 2=morph, 3=decoy, 4=poison). Lives here so it survives the lobby → match scene change; the match
## sends it to the host, who stamps it into this player's spawn. Default: smoke + decoy.
var selected_tools: Array = [0, 3]

## The passive PERK this player picked in the lobby (0=None, 1=Ghost, 2=Blender, 3=Swift, 4=Survivor).
## Lives here so it survives the lobby → match scene change; the match sends it to the host, who applies
## its passive modifier to this player at spawn.
var selected_perk: int = 0

## The nickname this player typed in the lobby. Lives here (an autoload) so it survives the lobby →
## match scene change like selected_tools; the match sends it to the host, who shows it on the roster,
## the end scoreboard, and the death screen. Empty = the game falls back to "Player N".
var player_nickname: String = ""

# --- Steam (online play over the relay; only active when run in the GodotSteam editor) ---
## Valve's free test App ID (Spacewar), used until we have our own. Matches steam_appid.txt.
const STEAM_APP_ID := 480
## Steam lobby visibility: 1 = friends-only (only your Steam friends / people you invite
## can join — the safe choice while we share Valve's public test App ID 480). 2 = public.
const STEAM_LOBBY_TYPE := 1
## Steam success codes we check against: k_EResultOK and the lobby-enter "success" are both 1.
const STEAM_RESULT_OK := 1
## The Steam singleton, fetched by NAME so this script still parses in stock Godot.
var _steam: Object = null
var _steam_ready: bool = false
var _steam_status_text: String = "not initialised"
## True while the live transport is the Steam relay (vs ENet/LAN).
var _using_steam: bool = false
## The Steam lobby we created or joined (0 = none). Doubles as the copy-paste join code.
var _steam_lobby_id: int = 0


func _ready() -> void:
	# Connect to Godot's multiplayer events ONCE. They stay quiet until we actually
	# create a host or join, then start firing. We just forward them as our own
	# tidy signals so the rest of the game never touches the raw API.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_init_steam()


# Brings Steam online if we're running in the GodotSteam editor. Written defensively:
# everything is reached through the singleton by name and guarded with has_method(), so
# a missing/renamed function logs a clear message instead of breaking the game (LAN/ENet
# play keeps working regardless).
func _init_steam() -> void:
	if not Engine.has_singleton("Steam"):
		_steam_status_text = "not detected (open the project with the GodotSteam editor for online play)"
		print("[Steam] %s" % _steam_status_text)
		return

	_steam = Engine.get_singleton("Steam")

	# Init function name varies a little by GodotSteam version — call whichever exists.
	var init_returned: Variant = null
	if _steam.has_method("steamInitEx"):
		init_returned = _steam.steamInitEx()
	elif _steam.has_method("steamInit"):
		init_returned = _steam.steamInit()
	else:
		_steam_status_text = "GodotSteam present but no init function found (version mismatch?)"
		print("[Steam] %s" % _steam_status_text)
		return

	# The return type also varies: a Dictionary {status, verbal} or a bool.
	if init_returned is Dictionary:
		_steam_ready = int((init_returned as Dictionary).get("status", -1)) == 0
	elif init_returned is bool:
		_steam_ready = init_returned
	else:
		_steam_ready = true  # some versions return nothing on success

	if _steam_ready:
		var persona := "you"
		if _steam.has_method("getPersonaName"):
			persona = str(_steam.getPersonaName())
		_steam_status_text = "ready as %s" % persona
		_connect_steam_signals()
	else:
		_steam_status_text = "init failed — is the Steam client running and logged in? (%s)" % str(init_returned)
	print("[Steam] %s" % _steam_status_text)


func _process(delta: float) -> void:
	# Steam needs its callbacks pumped each frame (when not embedded). Guarded so it's a
	# no-op without Steam.
	if _steam != null and _steam.has_method("run_callbacks"):
		_steam.run_callbacks()
	_update_ping(delta)


# === ping / round-trip time (diagnostics for the in-match debug overlay) =====
var _ping_ms: float = 0.0
var _ping_accumulator: float = 0.0

func _update_ping(delta: float) -> void:
	# Only clients measure: bounce a timestamp off the host twice a second.
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return
	_ping_accumulator += delta
	if _ping_accumulator >= 0.5:
		_ping_accumulator = 0.0
		_ping_request.rpc_id(HOST_PEER_ID, Time.get_ticks_msec())


@rpc("any_peer", "call_remote", "unreliable")
func _ping_request(client_ticks: int) -> void:
	# Host side: bounce the client's timestamp straight back to them.
	_ping_reply.rpc_id(multiplayer.get_remote_sender_id(), client_ticks)


@rpc("any_peer", "call_remote", "unreliable")
func _ping_reply(client_ticks: int) -> void:
	# Client side: (now − sent) is the full round-trip time.
	_ping_ms = float(Time.get_ticks_msec() - client_ticks)


# Last measured round-trip time in milliseconds (0 on the host / before the first reply).
func ping_ms() -> float:
	return _ping_ms


# True if Steam initialised successfully (relay play is possible).
func is_steam_ready() -> bool:
	return _steam_ready


# Human-readable Steam state for the menu.
func steam_status() -> String:
	return _steam_status_text


# A sensible default nickname to prefill the lobby field with: the player's Steam persona name when
# Steam is up, otherwise "" (the lobby then shows a placeholder and the match falls back to "Player N").
func default_nickname() -> String:
	if _steam != null and _steam_ready and _steam.has_method("getPersonaName"):
		return str(_steam.getPersonaName())
	return ""


# True while we're connected through Steam (so the lobby shows the Steam code + invite).
func is_using_steam() -> bool:
	return _using_steam


# The lobby id as a copy-paste join code ("" when not in a Steam lobby).
func steam_lobby_code() -> String:
	return str(_steam_lobby_id) if _steam_lobby_id != 0 else ""


# Our own Steam id (0 if Steam isn't up). Used to tell "I created this lobby" apart from
# "I joined someone else's".
func _my_steam_id() -> int:
	if _steam != null and _steam.has_method("getSteamID"):
		return int(_steam.getSteamID())
	return 0


# === Steam transport (relay play; mirrors the ENet host/join below) =========

# Wire up the Steam lobby callbacks once, each guarded so a renamed signal in some
# GodotSteam version just logs instead of crashing.
func _connect_steam_signals() -> void:
	_safe_connect_steam("lobby_created", _on_steam_lobby_created)
	_safe_connect_steam("lobby_joined", _on_steam_lobby_joined)
	_safe_connect_steam("join_requested", _on_steam_join_requested)


func _safe_connect_steam(signal_name: String, callable: Callable) -> void:
	if _steam == null:
		return
	if not _steam.has_signal(signal_name):
		print("[Steam] note: signal '%s' not present in this build" % signal_name)
		return
	if not _steam.is_connected(signal_name, callable):
		_steam.connect(signal_name, callable)


# Builds a SteamMultiplayerPeer WITHOUT naming the class in code, so this script still
# parses in stock Godot (where that class doesn't exist). Returns null if unavailable.
func _make_steam_peer() -> Object:
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		return null
	return ClassDB.instantiate("SteamMultiplayerPeer")


# Become the host on Steam: create a friends-only lobby. The actual peer is built when
# Steam confirms the lobby (the lobby_created callback). Returns false if Steam isn't ready.
func host_steam() -> bool:
	if not _steam_ready:
		return false
	# createLobby is asynchronous → continues in _on_steam_lobby_created.
	_steam.createLobby(STEAM_LOBBY_TYPE, MAX_PLAYERS)
	return true


# Join a Steam lobby by its id (the copy-paste code). Async → continues in _on_steam_lobby_joined.
func join_steam(lobby_id: int) -> bool:
	if not _steam_ready or lobby_id == 0:
		return false
	_steam.joinLobby(lobby_id)
	return true


# Open the Steam overlay so the host can invite friends to the current lobby.
func invite_friends() -> void:
	if _using_steam and _steam != null and _steam_lobby_id != 0 \
			and _steam.has_method("activateGameOverlayInviteDialog"):
		_steam.activateGameOverlayInviteDialog(_steam_lobby_id)


func _on_steam_lobby_created(result: int, lobby_id: int) -> void:
	if result != STEAM_RESULT_OK:
		steam_lobby_failed.emit("Steam couldn't create a lobby (code %d)." % result)
		return
	_steam_lobby_id = lobby_id
	# Stamp our Steam id into the lobby so joiners can look up the host.
	if _steam.has_method("setLobbyData") and _steam.has_method("getSteamID"):
		_steam.setLobbyData(lobby_id, "host_steam_id", str(_steam.getSteamID()))
	var peer := _make_steam_peer()
	if peer == null:
		steam_lobby_failed.emit("This build has no SteamMultiplayerPeer (relay unavailable).")
		return
	peer.call("create_host", 0)
	multiplayer.multiplayer_peer = peer as MultiplayerPeer
	_using_steam = true
	print("[Steam] hosting lobby %d" % lobby_id)
	steam_lobby_ready.emit(lobby_id)


func _on_steam_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != STEAM_RESULT_OK:
		steam_lobby_failed.emit("Steam couldn't join that lobby (response %d)." % response)
		return
	var owner_id := 0
	if _steam.has_method("getLobbyOwner"):
		owner_id = int(_steam.getLobbyOwner(lobby_id))
	# Steam fires lobby_joined for the lobby's CREATOR too. We already built the host peer
	# in _on_steam_lobby_created, so ignore our own auto-join — otherwise we'd overwrite the
	# host peer with a client one and try to connect to ourselves.
	if owner_id == _my_steam_id() and _my_steam_id() != 0:
		return
	if owner_id == 0:
		steam_lobby_failed.emit("Couldn't find that lobby's host.")
		return
	_steam_lobby_id = lobby_id
	var peer := _make_steam_peer()
	if peer == null:
		steam_lobby_failed.emit("This build has no SteamMultiplayerPeer (relay unavailable).")
		return
	peer.call("create_client", owner_id, 0)
	multiplayer.multiplayer_peer = peer as MultiplayerPeer
	_using_steam = true
	print("[Steam] joined lobby %d (host %d)" % [lobby_id, owner_id])
	steam_lobby_ready.emit(lobby_id)


# A friend accepted our invite (or clicked "Join Game") while their game was open.
func _on_steam_join_requested(lobby_id: int, _friend_id: int) -> void:
	print("[Steam] join requested for lobby %d" % lobby_id)
	join_steam(lobby_id)


# === public API (the menu calls these) =====================================

# Become the host. Returns true on success.
func host_game(port: int = DEFAULT_PORT) -> bool:
	var enet := ENetMultiplayerPeer.new()
	# MAX_PLAYERS - 1 because the host itself takes one of the slots.
	var result := enet.create_server(port, MAX_PLAYERS - 1)
	if result != OK:
		push_error("NetworkManager: could not host on port %d (error %d)." % [port, result])
		return false
	multiplayer.multiplayer_peer = enet
	return true


# Connect to a host. For loopback testing the address is "127.0.0.1" (this PC).
func join_game(address: String = "127.0.0.1", port: int = DEFAULT_PORT) -> bool:
	var enet := ENetMultiplayerPeer.new()
	var result := enet.create_client(address, port)
	if result != OK:
		push_error("NetworkManager: could not start client to %s:%d (error %d)." % [address, port, result])
		return false
	multiplayer.multiplayer_peer = enet
	return true


# Tear the session down and go back to "not networked".
func leave() -> void:
	# If we were in a Steam lobby, leave it too so we don't linger as a ghost member.
	if _using_steam and _steam != null and _steam_lobby_id != 0 and _steam.has_method("leaveLobby"):
		_steam.leaveLobby(_steam_lobby_id)
	_steam_lobby_id = 0
	_using_steam = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null


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
