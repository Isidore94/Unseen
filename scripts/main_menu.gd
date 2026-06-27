extends Control
class_name MainMenu

# MainMenu — UNSEEN, Phase 6.2. The default scene the game launches into.
#
# Two ways to play online:
#   HOST ONLINE (Steam) / JOIN BY CODE — internet play over the Steam relay (no IP, no
#       port-forwarding). Only shown when Steam is available (the GodotSteam editor /
#       an exported build with Steam running).
#   HOST (LAN) / JOIN IP               — direct ENet on your network, for quick local
#       testing (this is also what works without Steam).
#   SINGLE-PLAYER                      — the offline test harness (1 human vs a bot hunter).
#
# The UI is built in code (same style as the rest of the project). All connectivity is
# delegated to the NetworkManager autoload, so this screen never touches the raw network.

const LOBBY_SCENE := "res://scenes/lobby.tscn"
const SINGLE_PLAYER_SCENE := "res://scenes/main.tscn"  # offline single-player test harness

var _ip_field: LineEdit = null
var _code_field: LineEdit = null
var _status_label: Label = null


func _ready() -> void:
	# Make sure we start from a clean, non-networked state (e.g. after leaving a match).
	NetworkManager.leave()
	# A Steam lobby finishes asynchronously — wait for these before changing scene.
	NetworkManager.steam_lobby_ready.connect(_on_steam_lobby_ready)
	NetworkManager.steam_lobby_failed.connect(_on_steam_lobby_failed)
	_build_ui()


func _build_ui() -> void:
	# A CenterContainer fills the whole screen and keeps the menu centred at any size.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 12)
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.custom_minimum_size = Vector2(340.0, 0.0)
	center.add_child(panel)

	var title := Label.new()
	title.text = "UNSEEN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	panel.add_child(title)

	# --- Steam (internet) play, only when Steam is up ---
	if NetworkManager.is_steam_ready():
		var host_online := _add_button(panel, "Host online (invite friends)")
		host_online.pressed.connect(_on_host_steam_pressed)

		var code_row := HBoxContainer.new()
		code_row.add_theme_constant_override("separation", 8)
		panel.add_child(code_row)
		_code_field = LineEdit.new()
		_code_field.placeholder_text = "paste join code"
		_code_field.custom_minimum_size = Vector2(200.0, 0.0)
		code_row.add_child(_code_field)
		var join_code_button := Button.new()
		join_code_button.text = "Join by code"
		join_code_button.pressed.connect(_on_join_steam_pressed)
		code_row.add_child(join_code_button)

		panel.add_child(_make_section_label("— or test on your network —"))

	# --- LAN / direct ENet play (always available; the only option without Steam) ---
	var host_lan := _add_button(panel, "Host (LAN)")
	host_lan.pressed.connect(_on_host_pressed)

	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	panel.add_child(ip_row)
	_ip_field = LineEdit.new()
	_ip_field.text = "127.0.0.1"
	_ip_field.custom_minimum_size = Vector2(200.0, 0.0)
	ip_row.add_child(_ip_field)
	var join_ip_button := Button.new()
	join_ip_button.text = "Join IP"
	join_ip_button.pressed.connect(_on_join_pressed)
	ip_row.add_child(join_ip_button)

	var local_button := _add_button(panel, "Single-player (offline)")
	local_button.pressed.connect(_on_local_test_pressed)

	_status_label = Label.new()
	_status_label.text = "Host online and invite a friend, or test locally."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(340.0, 0.0)
	panel.add_child(_status_label)

	var steam_label := Label.new()
	steam_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	steam_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	steam_label.custom_minimum_size = Vector2(360.0, 0.0)
	steam_label.modulate = Color(0.6, 0.85, 1.0)
	steam_label.text = "Steam: %s" % NetworkManager.steam_status()
	panel.add_child(steam_label)

	_build_version_label()


func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = Color(1, 1, 1, 0.5)
	return label


# Shows the build version in the bottom-left corner. It reads the ONE source of truth
# (project.godot → application/config/version), so bumping it in one place updates here.
func _build_version_label() -> void:
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var version_label := Label.new()
	version_label.text = "v%s" % version
	version_label.modulate = Color(1, 1, 1, 0.5)
	version_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	version_label.offset_left = 16.0
	version_label.offset_top = -36.0
	version_label.offset_right = 220.0
	version_label.offset_bottom = -12.0
	add_child(version_label)


func _add_button(parent: Node, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(button)
	return button


# === Steam (internet) handlers ==============================================

func _on_host_steam_pressed() -> void:
	if NetworkManager.host_steam():
		_status_label.text = "Creating Steam lobby…"
	else:
		_status_label.text = "Steam isn't ready (is the Steam client running?)."


func _on_join_steam_pressed() -> void:
	var code := _code_field.text.strip_edges()
	var lobby_id := code.to_int()
	if lobby_id == 0:
		_status_label.text = "Paste a valid join code first."
		return
	if NetworkManager.join_steam(lobby_id):
		_status_label.text = "Joining lobby…"
	else:
		_status_label.text = "Steam isn't ready to join."


func _on_steam_lobby_ready(_lobby_id: int) -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_steam_lobby_failed(reason: String) -> void:
	_status_label.text = reason


# === LAN / direct ENet handlers =============================================

func _on_host_pressed() -> void:
	if NetworkManager.host_game():
		get_tree().change_scene_to_file(LOBBY_SCENE)
	else:
		_status_label.text = "Could not host (is the port already in use?)."


func _on_join_pressed() -> void:
	var address := _ip_field.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	if NetworkManager.join_game(address):
		get_tree().change_scene_to_file(LOBBY_SCENE)
	else:
		_status_label.text = "Could not start a connection to %s." % address


func _on_local_test_pressed() -> void:
	get_tree().change_scene_to_file(SINGLE_PLAYER_SCENE)
