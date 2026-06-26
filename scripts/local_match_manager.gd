extends Node
class_name LocalMatchManager

# Two-player local match scoring and round end.

## Seconds before the round times out (0 = no limit).
@export var round_time_limit: float = 300.0

@export var exposure_weight: float = 5.0
@export var speed_bonus_cap: float = 500.0
@export var speed_bleed_per_second: float = 2.0
@export var kill_points: int = 100
@export var win_bonus: int = 500
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
	_end_round("contract", player_id)


func _on_player_died(dead_player_id: int) -> void:
	_end_round("player_down", _opponent_id(dead_player_id))


func _end_round(reason: String, winner_id: int) -> void:
	if _round_over:
		return
	_round_over = true

	var p1_score := _score_for_player(1, winner_id)
	var p2_score := _score_for_player(2, winner_id)

	if reason == "timeout":
		if p1_score["total"] > p2_score["total"]:
			winner_id = 1
		elif p2_score["total"] > p1_score["total"]:
			winner_id = 2

	var result_text := _result_text(reason, winner_id)
	var breakdown := _score_breakdown(1, p1_score) + "\n\n" + _score_breakdown(2, p2_score)

	if _end_screen != null:
		_end_screen.show_result(result_text, breakdown)


func _score_for_player(player_id: int, winner_id: int) -> Dictionary:
	var average_exposure := _average_exposure(player_id)
	var exposure_score: int = int(round((100.0 - average_exposure) * exposure_weight))
	var speed_score: int = int(maxf(0.0, speed_bonus_cap - _elapsed * speed_bleed_per_second))
	var kill_score: int = int(_kills[player_id]) * kill_points
	var outcome_bonus: int = 0

	if player_id == winner_id:
		outcome_bonus = win_bonus
	elif _is_player_dead(player_id):
		outcome_bonus = -death_penalty

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
		return "TIME UP - DRAW"
	match reason:
		"contract":
			return "P%d CONTRACT COMPLETE" % winner_id
		"timeout":
			return "TIME UP - P%d LEADS" % winner_id
		_:
			return "P%d WINS" % winner_id


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


func _opponent_id(player_id: int) -> int:
	return 2 if player_id == 1 else 1
