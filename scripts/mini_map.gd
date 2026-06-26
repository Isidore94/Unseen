extends Control
class_name MiniMap

# Mini-map — UNSEEN, Phase 4. A small per-player HUD map so you can FIND your
# objective (master_plan §7.1). Lives in each player's own viewport HUD, so it's
# private — the other player never sees it.
#
#   PvE (marks):  a live dot shows roughly where your mark is (it wanders, so it
#                 moves). You still have to ID it in the crowd and aim & commit.
#   PvP (target): once your mark is done, the opponent's spot is revealed only as
#                 a periodic PING every few seconds — intel with delay, not a live
#                 tracker (the §7.1 reward for finishing first).

@export var map_size_px: Vector2 = Vector2(230, 170)
@export var ping_interval: float = 4.0
@export var ping_duration: float = 1.3
@export var self_color: Color = Color(0.35, 0.75, 1.0)
@export var mark_color: Color = Color(0.95, 0.82, 0.2)
@export var opponent_ping_color: Color = Color(1.0, 0.35, 0.3)

var _map: TestMap01 = null
var _player: Node2D = null
var _contract: ContractManager = null
## Online play hands the objective node in directly (the host privately tells each
## client which crowd member is its mark), instead of asking an offline contract.
var _objective_node: Node2D = null
## Online: when true, the objective is shown as periodic pings (PvP opponent), not a
## live dot (PvE mark). Offline keeps using the contract's phase instead.
var _ping_mode: bool = false

var _ping_timer: float = 0.0
var _ping_visible: bool = false
var _last_opponent_pos: Vector2 = Vector2.ZERO


func setup(map: TestMap01, player: Node2D, contract: ContractManager) -> void:
	_map = map
	_player = player
	_contract = contract
	custom_minimum_size = map_size_px
	size = map_size_px


func _process(delta: float) -> void:
	# PvP tracking ping: briefly reveal the opponent's current spot every few secs.
	_ping_timer += delta
	if _ping_timer >= ping_interval:
		_ping_timer = 0.0
		_ping_visible = true
		var objective := _objective()
		if objective != null:
			_last_opponent_pos = objective.global_position
	elif _ping_visible and _ping_timer >= ping_duration:
		_ping_visible = false
	queue_redraw()


# Online, PvE: track a node with a LIVE dot (your wandering mark).
func track_objective(node: Node2D) -> void:
	_objective_node = node
	_ping_mode = false


# Online, PvP: track a node with delayed PINGS only (your opponent, once you've
# earned tracking by finishing your mark — master_plan §7.1).
func track_objective_pinged(node: Node2D) -> void:
	_objective_node = node
	_ping_mode = true


func _objective() -> Node2D:
	if _objective_node != null and is_instance_valid(_objective_node):
		return _objective_node
	if _contract != null and is_instance_valid(_contract):
		return _contract.get_objective()
	return null


func _world_to_map(world: Vector2) -> Vector2:
	var half := Vector2(_map.play_half_width, _map.play_half_height)
	var normalised := (world + half) / (half * 2.0)
	return normalised * map_size_px


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, map_size_px), Color(0.04, 0.04, 0.06, 0.72), true)
	draw_rect(Rect2(Vector2.ZERO, map_size_px), Color(1, 1, 1, 0.22), false, 2.0)
	if _map == null:
		return

	# Buildings (faint) so the layout is recognisable.
	if _map.has_method("get_building_rects"):
		for rect in _map.get_building_rects():
			var top_left := _world_to_map(rect.position)
			var bottom_right := _world_to_map(rect.end)
			draw_rect(Rect2(top_left, bottom_right - top_left), Color(1, 1, 1, 0.10), true)

	# You.
	if _player != null and is_instance_valid(_player):
		draw_circle(_world_to_map(_player.global_position), 4.5, self_color)

	# Objective dot.
	if _contract != null and is_instance_valid(_contract):
		# Offline: phase-driven (live mark, then PvP ping) via the contract.
		var phase: String = _contract.get_phase()
		if phase == "marks":
			var mark := _objective()
			if mark != null and is_instance_valid(mark):
				draw_circle(_world_to_map(mark.global_position), 4.5, mark_color)
		elif _ping_visible:
			draw_circle(_world_to_map(_last_opponent_pos), 5.5, opponent_ping_color)
	else:
		# Online: mode is set explicitly by the match (live mark, or pinged opponent).
		var objective := _objective()
		if objective != null and is_instance_valid(objective):
			if _ping_mode:
				if _ping_visible:
					draw_circle(_world_to_map(_last_opponent_pos), 5.5, opponent_ping_color)
			else:
				draw_circle(_world_to_map(objective.global_position), 4.5, mark_color)
