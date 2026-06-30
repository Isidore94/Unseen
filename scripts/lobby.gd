extends Control
class_name Lobby

# Lobby — UNSEEN, Phase 6.2. A waiting room between the menu and the match.
#
# Everyone who hosts or joins lands here first. The host sees a START button that
# stays DISABLED until at least MIN_PLAYERS_TO_START players are present, so a match
# never begins with only one person. When the host starts, every peer is told to load
# the match together (so they all transition at the same time).
#
# Connectivity is whatever NetworkManager is using (ENet/LAN now; Steam relay next),
# so this screen doesn't change when we add Steam.

const ONLINE_MATCH_SCENE := "res://scenes/online_match.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

## Don't let the host start until this many players are in the lobby.
const MIN_PLAYERS_TO_START := 2

var _code_label: Label = null
var _roster_label: Label = null
var _status_label: Label = null
var _start_button: Button = null
## Host-only: which connected client peers have ticked "Ready up" (peer int -> true). The host is
## implicitly ready (they press Start), so this only tracks the OTHER players. Start stays disabled
## until every entry is ready.
var _ready_peers: Dictionary = {}
var _map_picker: OptionButton = null
var _tool1_picker: OptionButton = null
var _tool2_picker: OptionButton = null
var _skin_picker: OptionButton = null
## Base labels for the assassin picker, so we can append/remove "(taken)" without losing the name.
var _skin_base_labels: Array = []
## Assassin body ids OTHER players have claimed (the host sends this — anonymised, never WHO). Greyed out.
var _taken_assassins: Array = []
## Host-only: which body id each peer has claimed (body_id String -> peer int). Never broadcast as a map.
var _assassin_claims: Dictionary = {}
## Tool names in ItemComponent.Tool order, so an OptionButton's selected index IS the tool id.
const TOOL_NAMES := ["Smoke", "Disguise", "Morph", "Decoy", "Poison", "Firecracker"]
## One-line "what does it do" for each tool, shown in the lobby so players can choose informed.
const TOOL_DESCRIPTIONS := [
	"Smoke — drop a cloud at your feet; anyone caught inside (a chasing hunter included) is stunned and can't kill for a few seconds.",
	"Disguise — aim at a civilian and look like them for 30s, breaking a pursuer's lock (you still see yourself normally).",
	"Morph — turn nearby civilians into copies of YOU for a few seconds, so a hunter can't tell which one is real.",
	"Decoy — spook the civilian you're aiming at into bolting, baiting a hunter into a wrong kill.",
	"Poison — a delayed, silent kill: your target drops a few seconds later with no crowd panic, so you walk away clean.",
	"Firecracker — throw a flashbang: every player caught in the burst is briefly stunned (can't move or kill). A panic button to break a chase or interrupt a hunter closing in.",
]
## Passive PERKS, in OnlineMatch's perk-id order (the picker index IS the perk id). One per match.
const PERK_NAMES := ["None", "Ghost", "Blender", "Swift", "Survivor"]
const PERK_DESCRIPTIONS := [
	"None — no passive perk.",
	"Ghost — your exposure cools off faster, so you recover from running sooner.",
	"Blender — your exposure rises slower when you run, so you stand out less.",
	"Swift — your tool cooldowns are shorter.",
	"Survivor — you stay safe (kill-immune) longer after each respawn.",
]
## Local, PRIVATE character choices (never broadcast to the lobby — hidden identity).
var _chosen_assassin: StringName = &""
var _npc_disguise: bool = false
## The commoner look the player shows IF they pick NPC disguise (chosen once, this lobby).
var _disguise_commoner: StringName = &""


func _ready() -> void:
	# The roster changes as people come and go; refresh the screen when it does.
	NetworkManager.player_joined.connect(_on_roster_changed)
	NetworkManager.player_left.connect(_on_roster_changed)
	# Host also frees a leaver's claimed assassin so that skin opens back up for others.
	NetworkManager.player_left.connect(_on_lobby_peer_left)
	# If our connection drops or the host closes, bail back to the menu.
	NetworkManager.connection_failed.connect(_return_to_menu)
	NetworkManager.server_closed.connect(_return_to_menu)
	_build_ui()
	_refresh()


func _on_roster_changed(_peer_id: int) -> void:
	_refresh()
	if multiplayer.is_server():
		_broadcast_lobby_status()  # keep clients' "(x/y ready)" line current as people come and go


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Layout: a centred HEADER, a TWO-COLUMN body, then a FOOTER. Two columns so the whole form fits
	# on a 1080p screen (it used to run off the bottom as a single tall column). The screen is wide, so
	# we spend that width instead of height.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	center.add_child(outer)

	var title := Label.new()
	title.text = "LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	outer.add_child(title)

	_code_label = Label.new()
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_code_label.custom_minimum_size = Vector2(820.0, 0.0)
	outer.add_child(_code_label)

	_roster_label = Label.new()
	_roster_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_roster_label.add_theme_font_size_override("font_size", 20)
	outer.add_child(_roster_label)

	# The two side-by-side columns. LEFT = your identity + tools; RIGHT = perk + map/start (or ready-up).
	var col_w := 400.0
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(col_w, 0.0)
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(col_w, 0.0)
	columns.add_child(right)

	# === LEFT COLUMN — your identity + your two tools ===
	# NICKNAME: public (shown on roster / scoreboard / death screen), unlike the private assassin pick.
	left.add_child(_section_label("Your nickname"))
	var name_field := LineEdit.new()
	name_field.max_length = 14  # keeps names from overflowing the HUD roster / scoreboard
	name_field.placeholder_text = "enter a nickname"
	name_field.text = NetworkManager.player_nickname if NetworkManager.player_nickname != "" else NetworkManager.default_nickname()
	NetworkManager.player_nickname = name_field.text.strip_edges()
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(name_field)
	name_field.text_changed.connect(func(t: String) -> void:
		NetworkManager.player_nickname = t.strip_edges())

	# ASSASSIN: anonymised dedupe — taken skins grey out (never showing WHO took them).
	left.add_child(_section_label("Your assassin"))
	_skin_picker = OptionButton.new()
	_skin_base_labels.clear()
	for i in CosmeticRegistry.ASSASSIN_BODY_IDS.size():
		var id: StringName = CosmeticRegistry.ASSASSIN_BODY_IDS[i]
		var label := str(id).replace("body_", "").capitalize()
		_skin_base_labels.append(label)
		_skin_picker.add_item(label, i)
	_skin_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_skin_picker)

	var disguise_check := CheckBox.new()
	disguise_check.text = "NPC disguise (blend in as a commoner)"
	left.add_child(disguise_check)

	# Defaults: a random assassin + a random commoner-disguise look, equipped now so a player who
	# never touches the controls still spawns correctly.
	_disguise_commoner = CosmeticRegistry.COMMONER_BODY_IDS[randi() % CosmeticRegistry.COMMONER_BODY_IDS.size()]
	_chosen_assassin = CosmeticRegistry.ASSASSIN_BODY_IDS[randi() % CosmeticRegistry.ASSASSIN_BODY_IDS.size()]
	_skin_picker.selected = CosmeticRegistry.ASSASSIN_BODY_IDS.find(_chosen_assassin)
	_apply_look_choice()
	_skin_picker.item_selected.connect(func(i: int) -> void:
		_on_pick_assassin(CosmeticRegistry.ASSASSIN_BODY_IDS[i]))
	_send_pick(_chosen_assassin)  # claim our default so the lobby starts deduped (host bumps collisions)
	disguise_check.toggled.connect(func(on: bool) -> void:
		_npc_disguise = on
		_apply_look_choice())

	# TOOLS: two private picks; the OptionButton index IS the ItemComponent.Tool id.
	left.add_child(_section_label("Your two tools (private)"))
	_tool1_picker = OptionButton.new()
	_tool2_picker = OptionButton.new()
	for i in TOOL_NAMES.size():
		_tool1_picker.add_item(TOOL_NAMES[i], i)
		_tool2_picker.add_item(TOOL_NAMES[i], i)
	_tool1_picker.selected = int(NetworkManager.selected_tools[0])
	_tool2_picker.selected = int(NetworkManager.selected_tools[1])
	_tool1_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tool2_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(_tool1_picker)
	left.add_child(_tool2_picker)
	_tool1_picker.item_selected.connect(func(_i: int) -> void: _update_tools())
	_tool2_picker.item_selected.connect(func(_i: int) -> void: _update_tools())
	_update_tools()
	left.add_child(_help_label("\n".join(TOOL_DESCRIPTIONS), col_w))

	# === RIGHT COLUMN — passive perk + host map/start (or client ready-up) ===
	right.add_child(_section_label("Your perk (passive)"))
	var perk_picker := OptionButton.new()
	for i in PERK_NAMES.size():
		perk_picker.add_item(PERK_NAMES[i], i)
	perk_picker.selected = int(NetworkManager.selected_perk)
	perk_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(perk_picker)
	perk_picker.item_selected.connect(func(i: int) -> void: NetworkManager.selected_perk = i)
	right.add_child(_help_label("\n".join(PERK_DESCRIPTIONS), col_w))

	if NetworkManager.is_host():
		# On Steam, give the host a one-click overlay invite plus a copy-the-code button.
		if NetworkManager.is_using_steam():
			var invite_button := Button.new()
			invite_button.text = "Invite friends (Steam)"
			invite_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			invite_button.pressed.connect(func() -> void: NetworkManager.invite_friends())
			right.add_child(invite_button)

			var copy_button := Button.new()
			copy_button.text = "Copy join code"
			copy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			copy_button.pressed.connect(_on_copy_code_pressed.bind(copy_button))
			right.add_child(copy_button)

		# Host picks the MAP. Each item carries its Map ID (read back via get_selected_id at start), so the
		# picker can list any SUBSET of maps in any order. For now only Compact + Citadel — Four Zones and
		# Rome are hidden until they're reworked (the Map enum + their scenes still exist for later).
		right.add_child(_section_label("Map"))
		_map_picker = OptionButton.new()
		_map_picker.add_item("Compact Arena (small)", NetworkManager.Map.COMPACT)
		_map_picker.add_item("Citadel (AC-style — bigger, dense, tight alleys)", NetworkManager.Map.CITADEL)
		_select_map_id(NetworkManager.Map.CITADEL)  # default to the Citadel
		_map_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.add_child(_map_picker)

		_start_button = Button.new()
		_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_start_button.pressed.connect(_on_start_pressed)
		right.add_child(_start_button)
	else:
		# READY-UP: each non-host player tells the host when they're set (the host can't start until all are).
		var ready_check := CheckButton.new()
		ready_check.text = "Ready up"
		ready_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ready_check.toggled.connect(func(on: bool) -> void: _set_ready_local(on))
		right.add_child(ready_check)
		_status_label = Label.new()
		_status_label.text = "Tick 'Ready up' when you're set — the host starts once everyone is ready."
		_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_status_label.custom_minimum_size = Vector2(col_w, 0.0)
		right.add_child(_status_label)

	# === FOOTER — a centred Leave button under both columns ===
	var leave_button := Button.new()
	leave_button.text = "Leave"
	leave_button.custom_minimum_size = Vector2(220.0, 0.0)
	leave_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave_button.pressed.connect(_return_to_menu)
	outer.add_child(leave_button)


# A centred section caption used throughout the lobby form.
func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# A small, dimmed, word-wrapped help block (the tool / perk descriptions) at a fixed column width.
func _help_label(text: String, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0.0)
	l.modulate = Color(1, 1, 1, 0.75)
	return l


# Apply the player's private look choice locally. It rides to the match in the loadout the client
# submits to the host at spawn (online_match._submit_loadout / equipped_payload).
#   - No disguise: visible BODY = your assassin; no decoy.
#   - NPC disguise: visible BODY = a commoner; your assassin is sent as a DECOY to also be cloned
#     into the crowd, so opponents can't track you by sprite type. Reveals show the commoner.
func _apply_look_choice() -> void:
	var inv := get_node_or_null("/root/CosmeticInventory")
	if inv == null:
		return
	if _npc_disguise:
		inv.call("equip", CosmeticItem.Slot.BODY, _disguise_commoner)
		inv.set("decoy_body_id", _chosen_assassin)
	else:
		inv.call("equip", CosmeticItem.Slot.BODY, _chosen_assassin)
		inv.set("decoy_body_id", &"")


# Store the two picked tools on NetworkManager (survives the scene change to the match).
func _update_tools() -> void:
	NetworkManager.selected_tools = [_tool1_picker.selected, _tool2_picker.selected]


func _refresh() -> void:
	var count := _player_count()
	_roster_label.text = "Players: %d / %d" % [count, NetworkManager.MAX_PLAYERS]

	if NetworkManager.is_host():
		if NetworkManager.is_using_steam():
			_code_label.text = "Steam join code:\n%s\n(or use Invite friends)" % NetworkManager.steam_lobby_code()
		else:
			_code_label.text = "LAN join code: %s\n(same-network play; use Host online for internet)" % _host_code()
		if _start_button != null:
			var enough := count >= MIN_PLAYERS_TO_START
			var all_ready := _all_clients_ready()
			_start_button.disabled = not (enough and all_ready)
			if not enough:
				_start_button.text = "Need %d players to start" % MIN_PLAYERS_TO_START
			elif not all_ready:
				_start_button.text = "Waiting for all to ready up (%d/%d)" % [_ready_count(), _client_count()]
			else:
				_start_button.text = "Start game"
	else:
		_code_label.text = "Connected — waiting in the lobby."


# Total players = the peers we can see + ourselves.
func _player_count() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_peers().size() + 1


# The host's address for friends on the same network to paste into "Join". Internet
# play (a code that works anywhere) arrives with the Steam relay.
func _host_code() -> String:
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127."):
			return address
	return "127.0.0.1"


func _on_copy_code_pressed(button: Button) -> void:
	var code := NetworkManager.steam_lobby_code()
	if code != "":
		DisplayServer.clipboard_set(code)
		button.text = "Copied!"


# Select the picker row whose Map ID matches `id` (so defaults don't depend on row order).
func _select_map_id(id: int) -> void:
	if _map_picker == null:
		return
	for i in _map_picker.item_count:
		if _map_picker.get_item_id(i) == id:
			_map_picker.selected = i
			return


func _on_start_pressed() -> void:
	if _player_count() < MIN_PLAYERS_TO_START or not _all_clients_ready():
		return
	# Tell EVERY peer (including us) to load the match together, with the host's MAP choice. Use the
	# item's ID (not its row index), so the picker can show any subset of maps in any order.
	var map_id := _map_picker.get_selected_id() if _map_picker != null else NetworkManager.Map.CITADEL
	_begin_match.rpc(map_id)


# Sent by the host to all peers: record the MAP choice and load the match scene together.
# The match's own ready handshake then takes over (nobody is spawned until every client's
# scene is up). small_arena is derived so the existing compact-crowd logic keeps working.
@rpc("authority", "call_local", "reliable")
func _begin_match(map_id: int) -> void:
	NetworkManager.selected_map = map_id
	NetworkManager.small_arena = map_id != NetworkManager.Map.FOUR_ZONE
	get_tree().change_scene_to_file(ONLINE_MATCH_SCENE)


# === ready-up =============================================================
# Each non-host player ticks "Ready up"; the host can only start once EVERY connected client is ready
# (the host themselves is implicitly ready — they press Start). Clients see a live "(x/y ready)" count.

# A client toggled their ready box → tell the host. (The host has no box; it starts the game instead.)
func _set_ready_local(on: bool) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return
	_set_ready.rpc_id(NetworkManager.HOST_PEER_ID, on)


# Client → host: record this client's ready state, re-evaluate the Start button, and echo the count
# back to everyone so each lobby shows the same "(x/y ready)".
@rpc("any_peer", "reliable")
func _set_ready(is_ready: bool) -> void:
	if not multiplayer.is_server():
		return
	_ready_peers[multiplayer.get_remote_sender_id()] = is_ready
	_refresh()
	_broadcast_lobby_status()


# Host: are ALL connected clients ready? (get_peers() on the host is everyone EXCEPT the host.)
func _all_clients_ready() -> bool:
	if not multiplayer.is_server():
		return false
	for p in multiplayer.get_peers():
		if not bool(_ready_peers.get(p, false)):
			return false
	return true


func _ready_count() -> int:
	var n := 0
	for p in multiplayer.get_peers():
		if bool(_ready_peers.get(p, false)):
			n += 1
	return n


func _client_count() -> int:
	return multiplayer.get_peers().size() if multiplayer.multiplayer_peer != null else 0


# Host → clients: the current "(x/y ready)" so each waiting player sees the same lobby status.
func _broadcast_lobby_status() -> void:
	if not multiplayer.is_server():
		return
	var ready := _ready_count()
	var total := _client_count()
	for p in multiplayer.get_peers():
		_receive_lobby_status.rpc_id(p, ready, total)


@rpc("authority", "reliable")
func _receive_lobby_status(ready: int, total: int) -> void:
	if _status_label != null:
		_status_label.text = "Waiting for the host to start — %d/%d players ready." % [ready, total]


func _return_to_menu() -> void:
	NetworkManager.leave()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# === assassin dedupe (anonymised "taken" list) =============================
# Two players must never wear the SAME assassin. The host is the authority on who has which skin; it
# only ever tells clients the SET of taken body ids (minus their own), never the owner — so picks stay
# private in identity while still being unique. With 4 skins and up to 4 players, a full 4p lobby ends
# with every skin claimed, so there's nothing left to switch to (your "no changing in 4p").

# We chose an assassin in the picker — apply it locally and claim it on the host.
func _on_pick_assassin(id: StringName) -> void:
	_chosen_assassin = id
	_apply_look_choice()
	_send_pick(id)


# Send our pick to the authority: the host runs the claim directly; a client asks over the wire.
func _send_pick(id: StringName) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_host_handle_pick(multiplayer.get_unique_id(), String(id))
	else:
		_request_assassin.rpc_id(NetworkManager.HOST_PEER_ID, String(id))


# Apply a host-confirmed pick locally WITHOUT re-sending it. Setting OptionButton.selected in code
# doesn't emit item_selected, so this can't loop back into another claim.
func _set_local_pick(id: StringName) -> void:
	_chosen_assassin = id
	var idx := CosmeticRegistry.ASSASSIN_BODY_IDS.find(id)
	if idx >= 0 and _skin_picker != null:
		_skin_picker.selected = idx
	_apply_look_choice()


# Grey out (disable) every assassin another player has claimed, so a duplicate can't be selected.
func _refresh_skin_availability() -> void:
	if _skin_picker == null:
		return
	for i in CosmeticRegistry.ASSASSIN_BODY_IDS.size():
		var id := String(CosmeticRegistry.ASSASSIN_BODY_IDS[i])
		var taken: bool = id in _taken_assassins
		_skin_picker.set_item_disabled(i, taken)
		var base: String = str(_skin_base_labels[i]) if i < _skin_base_labels.size() else id
		_skin_picker.set_item_text(i, base + ("  (taken)" if taken else ""))


# --- host-only claim bookkeeping ---

# The authority records a peer's claim (freeing their old one), bumping them to a free skin if the
# one they asked for is already someone else's, then confirms it back and re-syncs everyone.
func _host_handle_pick(peer: int, requested: String) -> void:
	if not multiplayer.is_server():
		return
	for id in _assassin_claims.keys():
		if int(_assassin_claims[id]) == peer:
			_assassin_claims.erase(id)  # free this peer's previous claim so re-picking your own works
	var chosen := requested
	if _assassin_claims.has(chosen):
		chosen = _first_free_assassin()  # the requested skin is another player's — bump to a free one
	if chosen == "":
		chosen = requested  # more players than skins (shouldn't happen at 4/4) — allow the dup as a fallback
	_assassin_claims[chosen] = peer
	if peer == multiplayer.get_unique_id():
		_set_local_pick(StringName(chosen))  # the host is a player too
	else:
		_confirm_assassin.rpc_id(peer, chosen)
	_sync_taken()


func _first_free_assassin() -> String:
	for id in CosmeticRegistry.ASSASSIN_BODY_IDS:
		if not _assassin_claims.has(String(id)):
			return String(id)
	return ""


# Host: send each peer the set of skins taken by OTHERS (so their own stays selectable). Just ids.
func _sync_taken() -> void:
	if not multiplayer.is_server():
		return
	var peers := multiplayer.get_peers().duplicate()
	peers.append(multiplayer.get_unique_id())
	for p in peers:
		var others: Array = []
		for id in _assassin_claims:
			if int(_assassin_claims[id]) != int(p):
				others.append(id)
		if int(p) == multiplayer.get_unique_id():
			_taken_assassins = others
			_refresh_skin_availability()
		else:
			_receive_taken.rpc_id(int(p), others)


# Host: a peer left the lobby — free their claim so that skin opens back up.
func _on_lobby_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_ready_peers.erase(peer_id)  # a leaver can't hold up the ready gate
	var freed := false
	for id in _assassin_claims.keys():
		if int(_assassin_claims[id]) == peer_id:
			_assassin_claims.erase(id)
			freed = true
	if freed:
		_sync_taken()


# Client → host: "I'd like this assassin." The host validates + bumps if needed.
@rpc("any_peer", "reliable")
func _request_assassin(id: String) -> void:
	if not multiplayer.is_server():
		return
	_host_handle_pick(multiplayer.get_remote_sender_id(), id)


# Host → one client: your confirmed skin (equals your request unless it collided and we bumped you).
@rpc("authority", "reliable")
func _confirm_assassin(id: String) -> void:
	_set_local_pick(StringName(id))


# Host → one client: the set of skins taken by OTHER players. Grey these out in the picker.
@rpc("authority", "reliable")
func _receive_taken(taken_ids: Array) -> void:
	_taken_assassins = taken_ids
	_refresh_skin_availability()
