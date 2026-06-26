extends Control
class_name MainMenu

# MainMenu — UNSEEN, Phase 6.0. The new default scene the game launches into.
#
# Three choices:
#   HOST          — become the referee and wait for a friend to join.
#   JOIN          — connect to a host (an IP for now; a Steam friend later, 6.2).
#   LOCAL AI TEST — launch the OLD split-screen scene (kept for offline testing).
#
# The UI is built in code (same style as the rest of the project) so the .tscn stays
# trivial. Connectivity is delegated entirely to the NetworkManager autoload.

const ONLINE_MATCH_SCENE := "res://scenes/online_match.tscn"
const LOCAL_COOP_SCENE := "res://scenes/main.tscn"  # the kept split-screen test harness

var _address_field: LineEdit = null
var _status_label: Label = null
var _buttons: Array[Button] = []


func _ready() -> void:
	# Make sure we start from a clean, non-networked state (e.g. after leaving a match).
	NetworkManager.leave()
	_build_ui()


func _build_ui() -> void:
	# A CenterContainer fills the whole screen and keeps the menu centred no matter
	# the window size (the previous fixed offset pushed it off the bottom-right edge).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 14)
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.custom_minimum_size = Vector2(320.0, 0.0)
	center.add_child(panel)

	var title := Label.new()
	title.text = "UNSEEN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	panel.add_child(title)

	var host_button := _add_button(panel, "Host game")
	host_button.pressed.connect(_on_host_pressed)

	# Join row: an address box + a Join button side by side.
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	panel.add_child(join_row)
	_address_field = LineEdit.new()
	_address_field.text = "127.0.0.1"
	_address_field.custom_minimum_size = Vector2(200.0, 0.0)
	join_row.add_child(_address_field)
	var join_button := Button.new()
	join_button.text = "Join game"
	join_row.add_child(join_button)
	join_button.pressed.connect(_on_join_pressed)
	_buttons.append(join_button)

	var local_button := _add_button(panel, "Local AI test (split screen)")
	local_button.pressed.connect(_on_local_test_pressed)

	_status_label = Label.new()
	_status_label.text = "Run the game twice: one HOST, one JOIN 127.0.0.1."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(320.0, 0.0)
	panel.add_child(_status_label)

	_build_version_label()


# Shows the build version in the bottom-left corner. It reads the ONE source of
# truth (project.godot → application/config/version), so bumping the version in one
# place updates everywhere it's shown.
func _build_version_label() -> void:
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var version_label := Label.new()
	version_label.text = "v%s" % version
	version_label.modulate = Color(1, 1, 1, 0.5)
	# Anchor to the bottom-left of the full-screen menu, then nudge in from the edge.
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
	_buttons.append(button)
	return button


func _on_host_pressed() -> void:
	if NetworkManager.host_game():
		get_tree().change_scene_to_file(ONLINE_MATCH_SCENE)
	else:
		_status_label.text = "Could not host (is the port already in use?)."


func _on_join_pressed() -> void:
	var address := _address_field.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	if NetworkManager.join_game(address):
		# Load the match scene now (optimistically) so our spawner is ready before the
		# host starts replicating characters to us. If the connection fails, the match
		# scene sends us straight back here.
		get_tree().change_scene_to_file(ONLINE_MATCH_SCENE)
	else:
		_status_label.text = "Could not start a connection to %s." % address


func _on_local_test_pressed() -> void:
	get_tree().change_scene_to_file(LOCAL_COOP_SCENE)
