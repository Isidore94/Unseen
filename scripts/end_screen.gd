extends CanvasLayer
class_name EndScreen

# End screen — UNSEEN, Phase 3. The round-over overlay: shows the result and the
# score breakdown, pauses the game, and offers "Play Again" (reloads the round).
# Its process_mode is Always (set in the scene) so the button still works while
# the rest of the game is paused.

@onready var _result_label: Label = $Center/Box/ResultLabel
@onready var _breakdown_label: Label = $Center/Box/BreakdownLabel
@onready var _play_again_button: Button = $Center/Box/PlayAgainButton


func _ready() -> void:
	add_to_group("end_screen")
	visible = false
	# "Rematch" = a fresh round with the same players/settings (buildplan §7.5). For local
	# co-op that's a clean reload of this scene.
	_play_again_button.text = "Rematch"
	_play_again_button.pressed.connect(_on_play_again)


# Called by the RoundManager when the round ends.
func show_result(result_text: String, breakdown_text: String) -> void:
	_result_label.text = result_text
	_breakdown_label.text = breakdown_text
	visible = true
	get_tree().paused = true


func _on_play_again() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
