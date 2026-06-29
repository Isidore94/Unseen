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
const TOOL_NAMES := ["Smoke", "Disguise", "Morph", "Decoy", "Poison"]
## One-line "what does it do" for each tool, shown in the lobby so players can choose informed.
const TOOL_DESCRIPTIONS := [
	"Smoke — drop a cloud at your feet; anyone caught inside (a chasing hunter included) is stunned and can't kill for a few seconds.",
	"Disguise — aim at a civilian and look like them for 30s, breaking a pursuer's lock (you still see yourself normally).",
	"Morph — turn nearby civilians into copies of YOU for a few seconds, so a hunter can't tell which one is real.",
	"Decoy — spook the civilian you're aiming at into bolting, baiting a hunter into a wrong kill.",
	"Poison — a delayed, silent kill: your target drops a few seconds later with no crowd panic, so you walk away clean.",
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


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 14)
	panel.custom_minimum_size = Vector2(420.0, 0.0)
	center.add_child(panel)

	var title := Label.new()
	title.text = "LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	panel.add_child(title)

	_code_label = Label.new()
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_code_label.custom_minimum_size = Vector2(420.0, 0.0)
	panel.add_child(_code_label)

	_roster_label = Label.new()
	_roster_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_roster_label.add_theme_font_size_override("font_size", 22)
	panel.add_child(_roster_label)

	# NICKNAME: shown to everyone on the roster, scoreboard, and death screen — so unlike the assassin
	# pick (which is private), this name IS public. Prefilled with your Steam name when available, and
	# stored on NetworkManager so it survives the lobby → match scene change.
	var name_label := Label.new()
	name_label.text = "Your nickname"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(name_label)
	var name_field := LineEdit.new()
	name_field.max_length = 14  # keeps names from overflowing the HUD roster / scoreboard
	name_field.placeholder_text = "enter a nickname"
	# Use the name we already have (e.g. from a previous lobby visit), else the Steam persona name.
	name_field.text = NetworkManager.player_nickname if NetworkManager.player_nickname != "" else NetworkManager.default_nickname()
	NetworkManager.player_nickname = name_field.text.strip_edges()
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(name_field)
	name_field.text_changed.connect(func(t: String) -> void:
		NetworkManager.player_nickname = t.strip_edges())

	# EVERY player picks their assassin look. To stop two players wearing the SAME assassin, the host
	# shares which skins are TAKEN and we grey those out — but only the SET of body ids, never WHO took
	# them (anonymised). So opponents learn "that skin is in play" (the crowd already clones those looks
	# anyway), never which figure is you. WHICH assassin you ended on is still submitted privately at spawn.
	var skin_label := Label.new()
	skin_label.text = "Your assassin"
	skin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(skin_label)
	_skin_picker = OptionButton.new()
	_skin_base_labels.clear()
	for i in CosmeticRegistry.ASSASSIN_BODY_IDS.size():
		var id: StringName = CosmeticRegistry.ASSASSIN_BODY_IDS[i]
		var label := str(id).replace("body_", "").capitalize()
		_skin_base_labels.append(label)
		_skin_picker.add_item(label, i)
	_skin_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(_skin_picker)

	# NPC DISGUISE: if checked, you appear in-match as a regular COMMONER (your picked assassin is
	# still duplicated as crowd decoys, and so is your commoner look) — so opponents can't track you
	# by assassin OR commoner sprites. Movement/gameplay are unchanged; reveals still show your real
	# (commoner) portrait. Committed here at the lobby.
	var disguise_check := CheckBox.new()
	disguise_check.text = "NPC disguise (blend in as a commoner)"
	panel.add_child(disguise_check)

	# Defaults: a random assassin + a random commoner-disguise look, equipped now so a player who
	# never touches the controls still spawns correctly.
	_disguise_commoner = CosmeticRegistry.COMMONER_BODY_IDS[randi() % CosmeticRegistry.COMMONER_BODY_IDS.size()]
	_chosen_assassin = CosmeticRegistry.ASSASSIN_BODY_IDS[randi() % CosmeticRegistry.ASSASSIN_BODY_IDS.size()]
	_skin_picker.selected = CosmeticRegistry.ASSASSIN_BODY_IDS.find(_chosen_assassin)
	_apply_look_choice()
	_skin_picker.item_selected.connect(func(i: int) -> void:
		_on_pick_assassin(CosmeticRegistry.ASSASSIN_BODY_IDS[i]))
	# Claim our default assassin so the lobby starts deduped. If our random default collided with
	# someone already here, the host bumps us to a free skin (and tells us via _confirm_assassin).
	_send_pick(_chosen_assassin)
	disguise_check.toggled.connect(func(on: bool) -> void:
		_npc_disguise = on
		_apply_look_choice())

	# TOOLS: every player brings TWO tools, picked privately (like the assassin). The OptionButton
	# index IS the ItemComponent.Tool id (TOOL_NAMES is in enum order), stored on NetworkManager and
	# sent to the host at spawn (online_match._submit_tools).
	var tools_label := Label.new()
	tools_label.text = "Your two tools (private)"
	tools_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(tools_label)
	_tool1_picker = OptionButton.new()
	_tool2_picker = OptionButton.new()
	for i in TOOL_NAMES.size():
		_tool1_picker.add_item(TOOL_NAMES[i], i)
		_tool2_picker.add_item(TOOL_NAMES[i], i)
	_tool1_picker.selected = int(NetworkManager.selected_tools[0])
	_tool2_picker.selected = int(NetworkManager.selected_tools[1])
	_tool1_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tool2_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(_tool1_picker)
	panel.add_child(_tool2_picker)
	_tool1_picker.item_selected.connect(func(_i: int) -> void: _update_tools())
	_tool2_picker.item_selected.connect(func(_i: int) -> void: _update_tools())
	_update_tools()

	# A little legend so players know what every tool does before they pick.
	var tool_help := Label.new()
	tool_help.text = "\n".join(TOOL_DESCRIPTIONS)
	tool_help.add_theme_font_size_override("font_size", 12)
	tool_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tool_help.custom_minimum_size = Vector2(420.0, 0.0)
	tool_help.modulate = Color(1, 1, 1, 0.75)
	panel.add_child(tool_help)

	if NetworkManager.is_host():
		# On Steam, give the host a one-click overlay invite plus a copy-the-code button.
		if NetworkManager.is_using_steam():
			var invite_button := Button.new()
			invite_button.text = "Invite friends (Steam)"
			invite_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			invite_button.pressed.connect(func() -> void: NetworkManager.invite_friends())
			panel.add_child(invite_button)

			var copy_button := Button.new()
			copy_button.text = "Copy join code"
			copy_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			copy_button.pressed.connect(_on_copy_code_pressed.bind(copy_button))
			panel.add_child(copy_button)

		# Host picks the MAP (Phase 10). Item order MUST match NetworkManager.Map so the
		# selected index IS the map id we send. The two small maps are lighter to host.
		var map_label := Label.new()
		map_label.text = "Map"
		panel.add_child(map_label)
		_map_picker = OptionButton.new()
		_map_picker.add_item("Four Zones (full — rooftops & sewers)", NetworkManager.Map.FOUR_ZONE)
		_map_picker.add_item("Compact Arena (small)", NetworkManager.Map.COMPACT)
		_map_picker.add_item("Rome (small — tight streets, no verticality)", NetworkManager.Map.ROME)
		_map_picker.selected = NetworkManager.Map.COMPACT  # the compact arena is our main map
		_map_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_child(_map_picker)

		_start_button = Button.new()
		_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_start_button.pressed.connect(_on_start_pressed)
		panel.add_child(_start_button)
	else:
		_status_label = Label.new()
		_status_label.text = "Waiting for the host to start..."
		_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(_status_label)

	var leave_button := Button.new()
	leave_button.text = "Leave"
	leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave_button.pressed.connect(_return_to_menu)
	panel.add_child(leave_button)


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
			_start_button.disabled = not enough
			_start_button.text = "Start game" if enough else "Need %d players to start" % MIN_PLAYERS_TO_START
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


func _on_start_pressed() -> void:
	if _player_count() < MIN_PLAYERS_TO_START:
		return
	# Tell EVERY peer (including us) to load the match together, with the host's MAP choice.
	var map_id := _map_picker.selected if _map_picker != null else NetworkManager.Map.COMPACT
	_begin_match.rpc(map_id)


# Sent by the host to all peers: record the MAP choice and load the match scene together.
# The match's own ready handshake then takes over (nobody is spawned until every client's
# scene is up). small_arena is derived so the existing compact-crowd logic keeps working.
@rpc("authority", "call_local", "reliable")
func _begin_match(map_id: int) -> void:
	NetworkManager.selected_map = map_id
	NetworkManager.small_arena = map_id != NetworkManager.Map.FOUR_ZONE
	get_tree().change_scene_to_file(ONLINE_MATCH_SCENE)


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
