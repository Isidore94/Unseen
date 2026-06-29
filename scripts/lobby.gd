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

	# EVERY player privately picks their assassin look. This is LOCAL — it never broadcasts to the
	# lobby, so opponents never learn your sprite (the hidden-identity pillar starts at character
	# select). It's stored on your CosmeticInventory and submitted to the host at spawn.
	var skin_label := Label.new()
	skin_label.text = "Your assassin (private)"
	skin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(skin_label)
	var skin_picker := OptionButton.new()
	for i in CosmeticRegistry.ASSASSIN_BODY_IDS.size():
		var id: StringName = CosmeticRegistry.ASSASSIN_BODY_IDS[i]
		skin_picker.add_item(str(id).replace("body_", "").capitalize(), i)
	skin_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(skin_picker)

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
	skin_picker.selected = CosmeticRegistry.ASSASSIN_BODY_IDS.find(_chosen_assassin)
	_apply_look_choice()
	skin_picker.item_selected.connect(func(i: int) -> void:
		_chosen_assassin = CosmeticRegistry.ASSASSIN_BODY_IDS[i]
		_apply_look_choice())
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
