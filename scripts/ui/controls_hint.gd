extends PanelContainer
class_name ControlsHint

# ControlsHint — UNSEEN. A small always-on legend of the core keys, shown top-left of the HUD
# so a brand-new player can learn the NON-obvious controls (climb a stair, use an item, claim a
# point) without a manual. It is pure reference text — no gameplay logic — so one responsibility
# (Principle #3) and it drops into any HUD with one line.
#
# It reads the keys from the Input Map by ACTION NAME (never hardcoded keycodes — Principle #2),
# so if you rebind an action in Project Settings, this legend updates itself to match.

## Each row is [label shown to the player, Input Map action name]. Order = top-to-bottom.
const ROWS: Array = [
	["Move", "move_up"],          # WASD cluster — we show one and label it "Move"
	["Run (hold)", "run"],
	["Attack / kill", "action_primary"],
	["Use stair / sewer", "interact"],
	["Drop off roof", "drop_down"],
	["Claim point", "action_secondary"],
	["Smoke", "item_primary"],
	["Cloak", "item_secondary"],
	["Emote", "emote"],
]


func _ready() -> void:
	# A faint dark box so the text reads over any map colour.
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	box.set_corner_radius_all(6)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", box)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.text = _build_text()
	add_child(label)


# Build the legend text, asking the Input Map for the real key bound to each action so the
# hint can never drift out of sync with the actual controls.
func _build_text() -> String:
	var lines: Array = ["CONTROLS"]
	for row in ROWS:
		var label: String = row[0]
		var action: String = row[1]
		# "Move" is the WASD cluster — show the cluster, not just the one sampled action.
		var keys: String = "WASD" if action == "move_up" else _key_for(action)
		lines.append("%s  —  %s" % [keys, label])
	return "\n".join(lines)


# The human-readable key name currently bound to an action (first keyboard binding found).
func _key_for(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			# as_text_physical_keycode() gives "R", "Shift", "Space", etc. for the bound key.
			var text: String = (event as InputEventKey).as_text_physical_keycode()
			if text != "":
				return text
	return "?"
