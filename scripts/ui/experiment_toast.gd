extends VBoxContainer
class_name ExperimentToast

# A small HUD helper for the Phase 9 experiments (PHASE_9_EXPERIMENTS.md): it shows which
# experiments are ACTIVE (so the player knows what's on) and pops a transient MESSAGE when one
# fires (so the player understands what just happened). Experiments call it by group:
#   get_tree().get_first_node_in_group("experiment_toast").show_message("...")
# It's pure feedback — no gameplay. If no experiment is on, the active line reads "none".

var _message_label: Label = null
var _fade_timer: float = 0.0
const MESSAGE_HOLD := 2.6
const MESSAGE_FADE := 0.9


func _ready() -> void:
	add_to_group("experiment_toast")
	var active := Label.new()
	active.add_theme_font_size_override("font_size", 13)
	active.modulate = Color(0.75, 0.88, 1.0, 0.9)
	active.text = _active_text()
	add_child(active)

	_message_label = Label.new()
	_message_label.add_theme_font_size_override("font_size", 20)
	_message_label.modulate = Color(1.0, 0.88, 0.45, 0.0)  # starts hidden, fades in on a message
	add_child(_message_label)


# A one-line summary of which experiment flags are on, read from the ExperimentFlags autoload.
func _active_text() -> String:
	var ef := get_node_or_null("/root/ExperimentFlags")
	if ef == null:
		return ""
	var on: Array[String] = []
	if ef.get("whiff_recovery_enabled"): on.append("Whiff-recovery")
	if ef.get("crowd_thinning_enabled"): on.append("Crowd-thinning")
	if ef.get("earned_read_enabled"): on.append("Earned-read [Q]")
	if ef.get("mutual_proximity_enabled"): on.append("Mutual-proximity")
	if ef.get("crowd_reaction_enabled"): on.append("Crowd-reaction")
	if ef.get("behavioral_flag_enabled"): on.append("Behavioral-flag")
	return "EXPERIMENTS: " + (", ".join(on) if not on.is_empty() else "none")


# Pop a transient message (called by experiments when something notable happens).
func show_message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.modulate.a = 1.0
	_fade_timer = MESSAGE_HOLD


func _process(delta: float) -> void:
	if _fade_timer > 0.0:
		_fade_timer -= delta
		if _fade_timer < MESSAGE_FADE and _message_label != null:
			_message_label.modulate.a = clampf(_fade_timer / MESSAGE_FADE, 0.0, 1.0)
