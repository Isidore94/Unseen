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
## Online play hands the objective node(s) in directly (the host privately tells each client which
## crowd members are its marks). `_objective_node` is the single ping target (PvP); `_objective_nodes`
## holds ALL live PvE marks so the player can see every target at once and path between them.
var _objective_node: Node2D = null
var _objective_nodes: Array = []
## Online: when true, the objective is shown as periodic pings (PvP opponent), not a
## live dot (PvE mark). Offline keeps using the contract's phase instead.
var _ping_mode: bool = false

var _ping_timer: float = 0.0
var _ping_visible: bool = false
var _last_opponent_pos: Vector2 = Vector2.ZERO

## Cached MINIATURE of the map: one {rect (mini-map space), color} per grid cell, built once
## in setup() from TestMap01.minimap_paint() — real roof colours, district-tinted streets,
## water/bridges/alleys. Per-frame drawing just replays these rects (cheap), so the mini-map
## finally looks like the map instead of faint boxes on a dark panel.
var _static_cells: Array = []
var _has_fountain: bool = false
var _fountain_center_mini: Vector2 = Vector2.ZERO
var _fountain_radius_mini: float = 0.0
var _fountain_water: Color = Color(0.20, 0.45, 0.65)
var _fountain_stone: Color = Color(0.40, 0.42, 0.45)
var _border_water: Color = Color(0.17, 0.43, 0.47)
var _sewer_points_mini: Array = []


func setup(map: TestMap01, player: Node2D, contract: ContractManager) -> void:
	_map = map
	_player = player
	_contract = contract
	custom_minimum_size = map_size_px
	size = map_size_px
	_build_static_paint()


# Build the miniature once: convert every painted cell from world space to mini-map space
# and remember the landmarks. Falls back silently on maps without minimap_paint().
func _build_static_paint() -> void:
	_static_cells.clear()
	_sewer_points_mini.clear()
	_has_fountain = false
	if _map == null or not _map.has_method("minimap_paint"):
		return
	var paint: Dictionary = _map.minimap_paint()
	for cell in paint.get("cells", []):
		var world_rect: Rect2 = cell["rect"]
		var top_left := _world_to_map(world_rect.position)
		var bottom_right := _world_to_map(world_rect.end)
		_static_cells.append({"rect": Rect2(top_left, bottom_right - top_left), "color": cell["color"]})
	_has_fountain = bool(paint.get("has_fountain", false))
	if _has_fountain:
		_fountain_center_mini = _world_to_map(paint["fountain_center"])
		_fountain_radius_mini = float(paint["fountain_radius"]) * map_size_px.x / (2.0 * _map.play_half_width)
		_fountain_water = paint.get("fountain_water", _fountain_water)
		_fountain_stone = paint.get("fountain_stone", _fountain_stone)
	_border_water = paint.get("water_margin", _border_water)
	if _map.has_method("get_sewer_entrances"):
		for entrance in _map.get_sewer_entrances():
			_sewer_points_mini.append(_world_to_map(entrance))


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
	_objective_nodes = [node] if node != null else []
	_ping_mode = false


# Online, PvE: track ALL your live marks at once (a dot each), so you can path between both.
func track_objectives(nodes: Array) -> void:
	_objective_nodes = nodes.duplicate()
	_objective_node = nodes[0] if not nodes.is_empty() else null
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
	if _static_cells.is_empty():
		# Fallback (a map without minimap_paint): the old dark panel + faint buildings.
		draw_rect(Rect2(Vector2.ZERO, map_size_px), Color(0.04, 0.04, 0.06, 0.72), true)
		if _map != null and _map.has_method("get_building_rects"):
			for rect in _map.get_building_rects():
				var top_left := _world_to_map(rect.position)
				var bottom_right := _world_to_map(rect.end)
				draw_rect(Rect2(top_left, bottom_right - top_left), Color(1, 1, 1, 0.10), true)
	else:
		# TRUE MINIATURE: the map's own water border, then every cell in its real colour
		# (roofs, district-tinted streets, canal, bridges, alleys), then the fountain.
		draw_rect(Rect2(Vector2.ZERO, map_size_px), _border_water, true)
		for cell in _static_cells:
			draw_rect(cell["rect"], cell["color"], true)
		if _has_fountain:
			draw_circle(_fountain_center_mini, _fountain_radius_mini * 1.35, _fountain_stone)
			draw_circle(_fountain_center_mini, _fountain_radius_mini, _fountain_water)
		# Sewer entrances: small green squares (matches their world grate colour).
		for point in _sewer_points_mini:
			draw_rect(Rect2(point - Vector2(2, 2), Vector2(4, 4)), Color(0.25, 0.7, 0.35), true)
	draw_rect(Rect2(Vector2.ZERO, map_size_px), Color(0, 0, 0, 0.45), false, 2.0)
	if _map == null:
		return

	# Teleporters / passages — colour-coded. Each pair shares a colour, and a thin line
	# links its two ends, so you can read at a glance where each one comes out.
	if _map.has_method("get_portal_links"):
		for link in _map.get_portal_links():
			var end_a := _world_to_map(link["a"])
			var end_b := _world_to_map(link["b"])
			var link_color: Color = link["color"]
			draw_line(end_a, end_b, Color(link_color.r, link_color.g, link_color.b, 0.5), 1.5)
			_draw_dot(end_a, 3.0, link_color)
			_draw_dot(end_b, 3.0, link_color)

	# You.
	if _player != null and is_instance_valid(_player):
		_draw_dot(_world_to_map(_player.global_position), 4.5, self_color)

	# Objective dot.
	if _contract != null and is_instance_valid(_contract):
		# Offline: phase-driven (live mark, then PvP ping) via the contract.
		var phase: String = _contract.get_phase()
		if phase == "marks":
			var mark := _objective()
			if mark != null and is_instance_valid(mark):
				_draw_dot(_world_to_map(mark.global_position), 4.5, mark_color)
		elif _ping_visible:
			_draw_dot(_world_to_map(_last_opponent_pos), 5.5, opponent_ping_color)
	else:
		# Online: mode is set explicitly by the match (live mark, or pinged opponent).
		if _ping_mode:
			if _ping_visible:
				_draw_dot(_world_to_map(_last_opponent_pos), 5.5, opponent_ping_color)
		else:
			# A dot for EVERY live mark, so both targets show and you can path between them.
			for node in _objective_nodes:
				if node != null and is_instance_valid(node):
					_draw_dot(_world_to_map((node as Node2D).global_position), 4.5, mark_color)


# A marker dot with a dark outline ring, so it stays readable on the light sand ground
# (plain coloured circles vanished against the miniature's bright streets).
func _draw_dot(pos: Vector2, radius: float, color: Color) -> void:
	draw_circle(pos, radius + 1.6, Color(0, 0, 0, 0.8))
	draw_circle(pos, radius, color)
