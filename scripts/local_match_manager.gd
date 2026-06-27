extends Node
class_name LocalMatchManager

# Two-player local match scoring and round end.

## Seconds before the round times out (0 = no limit).
@export var round_time_limit: float = 300.0

@export var exposure_weight: float = 5.0
@export var speed_bonus_cap: float = 500.0
@export var speed_bleed_per_second: float = 2.0
@export var kill_points: int = 100
## Awarded for COMPLETING your contract (an achievement that scores points) — NOT a flat
## "you won" bonus. The winner is whoever has the most points (buildplan §7.5), so the
## win can't be a circular input to itself.
@export var contract_bonus: int = 500
## Subtracted from a player who is eliminated — being killed caps what you can still earn.
@export var death_penalty: int = 300

@export var player_one_path: NodePath
@export var player_two_path: NodePath
@export var contract_one_path: NodePath
@export var contract_two_path: NodePath
@export var end_screen_path: NodePath

var _players: Dictionary = {}
var _contracts: Dictionary = {}
var _exposure_sum: Dictionary = {}
var _exposure_samples: Dictionary = {}
var _kills: Dictionary = {}
var _completed: Dictionary = {}  # did this player finish their contract?
var _end_screen: EndScreen = null
var _elapsed: float = 0.0
var _round_over: bool = false


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	await get_tree().physics_frame

	_end_screen = get_node_or_null(end_screen_path) as EndScreen
	_register_player(1, get_node_or_null(player_one_path) as Player)
	_register_player(2, get_node_or_null(player_two_path) as Player)
	_register_contract(1, get_node_or_null(contract_one_path) as ContractManager)
	_register_contract(2, get_node_or_null(contract_two_path) as ContractManager)


func _process(delta: float) -> void:
	if _round_over:
		return

	_elapsed += delta
	for player_id in _players.keys():
		var player := _players[player_id] as Player
		if player != null and is_instance_valid(player):
			_exposure_sum[player_id] += player.exposure_component.exposure
			_exposure_samples[player_id] += 1

	if round_time_limit > 0.0 and _elapsed >= round_time_limit:
		_end_round("timeout", 0)


func _register_player(player_id: int, player: Player) -> void:
	_players[player_id] = player
	_exposure_sum[player_id] = 0.0
	_exposure_samples[player_id] = 0
	_kills[player_id] = 0
	_completed[player_id] = false

	if player == null:
		push_warning("LocalMatchManager: Player %d not found." % player_id)
		return

	player.died.connect(Callable(self, "_on_player_died").bind(player_id))
	var kill_component := player.get_node_or_null("KillComponent") as KillComponent
	if kill_component != null:
		kill_component.kill_landed.connect(Callable(self, "_on_kill_landed").bind(player_id))


func _register_contract(player_id: int, contract: ContractManager) -> void:
	_contracts[player_id] = contract
	if contract == null:
		push_warning("LocalMatchManager: Contract %d not found." % player_id)
		return
	contract.contract_completed.connect(Callable(self, "_on_contract_completed").bind(player_id))


func _on_kill_landed(player_id: int) -> void:
	_kills[player_id] += 1


func _on_contract_completed(player_id: int) -> void:
	_completed[player_id] = true
	_end_round("contract", player_id)


func _on_player_died(_dead_player_id: int) -> void:
	# A death only ENDS the round (buildplan §7.5) — it does NOT decide the winner; the
	# scores do. The dead player just carries the death penalty into the tally.
	_end_round("player_down", 0)


func _end_round(reason: String, _trigger_id: int) -> void:
	if _round_over:
		return
	_round_over = true

	var p1_score := _score_for_player(1)
	var p2_score := _score_for_player(2)
	# Winner is whoever has the most points, full stop; ties break to lowest average
	# exposure (ghostliness is the core fantasy). 0 = an exact draw.
	var winner_id := _winner_by_points(p1_score, p2_score)

	var result_text := _result_text(reason, winner_id)
	var breakdown := _score_breakdown(1, p1_score) + "\n\n" + _score_breakdown(2, p2_score)

	if _end_screen != null:
		_end_screen.show_result(result_text, breakdown)


# Most points wins; tie on points → lowest average exposure; still tied → an exact draw (0).
func _winner_by_points(p1_score: Dictionary, p2_score: Dictionary) -> int:
	if int(p1_score["total"]) > int(p2_score["total"]):
		return 1
	if int(p2_score["total"]) > int(p1_score["total"]):
		return 2
	var e1 := _average_exposure(1)
	var e2 := _average_exposure(2)
	if e1 < e2:
		return 1
	if e2 < e1:
		return 2
	return 0


func _score_for_player(player_id: int) -> Dictionary:
	var average_exposure := _average_exposure(player_id)
	var exposure_score: int = int(round((100.0 - average_exposure) * exposure_weight))
	var speed_score: int = int(maxf(0.0, speed_bonus_cap - _elapsed * speed_bleed_per_second))
	var kill_score: int = int(_kills[player_id]) * kill_points
	var outcome_bonus: int = 0

	# Finishing your contract scores points; being eliminated costs you. These are NOT
	# "you won" flags — the winner is decided from the totals afterwards.
	if bool(_completed[player_id]):
		outcome_bonus += contract_bonus
	if _is_player_dead(player_id):
		outcome_bonus -= death_penalty

	var total: int = maxi(0, exposure_score + speed_score + kill_score + outcome_bonus)
	return {
		"average_exposure": average_exposure,
		"exposure_score": exposure_score,
		"speed_score": speed_score,
		"kill_score": kill_score,
		"outcome_bonus": outcome_bonus,
		"total": total,
	}


func _average_exposure(player_id: int) -> float:
	var samples: int = maxi(1, int(_exposure_samples[player_id]))
	return float(_exposure_sum[player_id]) / float(samples)


func _is_player_dead(player_id: int) -> bool:
	var player := _players.get(player_id) as Player
	return player != null and player.is_dead()


func _result_text(reason: String, winner_id: int) -> String:
	if winner_id == 0:
		return "DRAW"
	var headline := "P%d WINS" % winner_id
	match reason:
		"contract":
			return "%s — contract complete" % headline
		"timeout":
			return "TIME UP — %s" % headline
		_:
			return headline


func _score_breakdown(player_id: int, score: Dictionary) -> String:
	return "P%d SCORE: %d\nAverage exposure: %d%%   (+%d)\nTime: %ds   (+%d)\nKills: %d   (+%d)\nOutcome bonus: %+d" % [
		player_id,
		score["total"],
		int(round(score["average_exposure"])),
		score["exposure_score"],
		int(_elapsed),
		score["speed_score"],
		int(_kills[player_id]),
		score["kill_score"],
		score["outcome_bonus"],
	]
