extends Node
class_name RoundManager

# Round manager — UNSEEN, Phase 3 (master_plan §10). Runs the round: tracks how
# you played, decides when it ends, scores it, and shows the end screen.
#
# THE ROUND ENDS WHEN:
#   - you complete your contract  -> WIN
#   - the hunter catches you       -> caught (loss)
#   - the time limit runs out      -> time up
#
# SCORE rewards playing like a ghost: LOW AVERAGE EXPOSURE matters most, plus
# speed and clean kills. You still get a score if you die — performance, not just
# survival, is what's rated (master_plan §6.1).

## Seconds before the round times out (0 = no limit). Generous for testing.
@export var round_time_limit: float = 300.0

# Score tuning (all @export so the balance is easy to feel out).
@export var exposure_weight: float = 5.0    # points per % of "ghostliness" (100 - avg)
@export var speed_bonus_cap: float = 500.0  # starting speed bonus, bleeds with time
@export var speed_bleed_per_second: float = 2.0
@export var kill_points: int = 100
@export var win_bonus: int = 500
@export var death_penalty: int = 300

var _player: Player = null
var _end_screen: EndScreen = null

var _elapsed: float = 0.0
var _exposure_sum: float = 0.0
var _exposure_samples: int = 0
var _kills: int = 0
var _round_over: bool = false


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	await get_tree().physics_frame
	_end_screen = get_tree().get_first_node_in_group("end_screen") as EndScreen

	_player = get_tree().get_first_node_in_group("player") as Player
	if _player != null:
		_player.died.connect(_on_player_died)
		var kill_component := _player.get_node_or_null("KillComponent") as KillComponent
		if kill_component != null:
			kill_component.kill_landed.connect(_on_kill_landed)

	var contract := get_tree().get_first_node_in_group("contract") as ContractManager
	if contract != null:
		contract.contract_completed.connect(_on_contract_completed)


func _process(delta: float) -> void:
	if _round_over:
		return
	_elapsed += delta
	# Sample the player's exposure every frame to build a round average.
	if _player != null and is_instance_valid(_player):
		_exposure_sum += _player.exposure_component.exposure
		_exposure_samples += 1
	if round_time_limit > 0.0 and _elapsed >= round_time_limit:
		_end_round("timeout")


func _on_kill_landed() -> void:
	_kills += 1

func _on_contract_completed() -> void:
	_end_round("win")

func _on_player_died() -> void:
	_end_round("dead")


func _end_round(outcome: String) -> void:
	if _round_over:
		return
	_round_over = true

	var average_exposure: float = _exposure_sum / maxf(1.0, float(_exposure_samples))
	var exposure_score: int = int(round((100.0 - average_exposure) * exposure_weight))
	var speed_score: int = int(maxf(0.0, speed_bonus_cap - _elapsed * speed_bleed_per_second))
	var kill_score: int = _kills * kill_points

	var outcome_bonus: int = 0
	var result_text: String = ""
	match outcome:
		"win":
			outcome_bonus = win_bonus
			result_text = "CONTRACT COMPLETE"
		"dead":
			outcome_bonus = -death_penalty
			result_text = "YOU WERE CAUGHT"
		"timeout":
			result_text = "TIME UP"

	var total: int = maxi(0, exposure_score + speed_score + kill_score + outcome_bonus)

	var breakdown: String = "Average exposure: %d%%   (+%d)\nTime: %ds   (+%d)\nKills: %d   (+%d)\nOutcome bonus: %+d\n————————\nSCORE: %d" % [
		int(round(average_exposure)), exposure_score,
		int(_elapsed), speed_score,
		_kills, kill_score,
		outcome_bonus,
		total,
	]

	if _end_screen != null:
		_end_screen.show_result(result_text, breakdown)
