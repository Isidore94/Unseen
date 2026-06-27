extends Node2D
class_name TestMap01

# test_map_01 — UNSEEN, playtest greybox (MAP_DESIGN_SPEC.md).
#
# A TIGHT-ALLEY souk layout: a grid of cells, each a BUILDING, OPEN street, or the
# central FOUNTAIN. Chunky building blocks fill the quadrants; one-cell-wide alleys
# and four cardinal streets bore through them into a WIDE open fountain plaza in the
# dead centre. The open cells stay edge-connected so you can always route around
# (no dead ends — verified by flood fill before this layout was committed).
#
# WHY GRID CELLS: the walkable area is the set of OPEN cells. Adjacent open cells
# share exact edges, so the navigation system stitches them into one connected
# network (the approach we know works). Variety comes from the LAYOUT pattern.
#
# MAP-CONTROL FEATURES (master_plan §8) are spawned as Portal pairs:
#   - teleporter pads  (cross-map, exposure cost)
#   - a trapdoor       (medium hop, small exposure tell)
#   - an underground passage (free — pure map knowledge)

# The layout grid. '#' = building, '.' = open street/plaza, 'F' = the central
# fountain (solid — you walk AROUND it). Edit this to reshape the map.
#
# The shape: a SOLID building ring hugs the outer wall (no wasted open border — you
# meet buildings right away from the edge), an inner ring road runs just inside it,
# and a tight one-cell alley grid carves chunky 2-wide building blocks. Only the
# dead centre opens up — a WIDE fountain plaza/avenue. That contrast is the point.
const LAYOUT := [
	"###############",
	"#.............#",
	"#.##.##.##.##.#",
	"#.##.##.##.##.#",
	"#.##.......##.#",
	"#......F......#",
	"#.##.......##.#",
	"#.##.##.##.##.#",
	"#.##.##.##.##.#",
	"#.............#",
	"###############",
]

## Optional smaller/alternate layout. When non-empty, this is used INSTEAD of LAYOUT, so
## a second map scene (e.g. a compact arena) can reuse this whole script just by setting
## a different grid + smaller play_half_* in the Inspector. Empty = use LAYOUT above.
@export var layout_override: Array[String] = []

# ===== size / tuning =====
## Half-extents of the playable area. Enlarged so a bigger crowd spreads out instead
## of clumping (the nav, walls, spawns and portals all scale from these two numbers).
@export var play_half_width: float = 2400.0
@export var play_half_height: float = 1750.0
@export var wall_thickness: float = 40.0
## Gap kept between the walkable navigation floor and solid walls/buildings, so
## actors never clip corners. MUST exceed an actor half-width (~36) with margin to
## spare — at 60 a body sitting on the nav edge still has ~24px of air before the
## wall, so avoidance jostling can't shove it through a corner.
@export var solid_clearance: float = 60.0
@export var grid_spacing: float = 200.0

# exposure costs for the map-control features (§8)
@export var teleporter_cost: float = 20.0
@export var trapdoor_cost: float = 8.0

## Radius of the central fountain's solid collision (you route around it), in pixels.
## Kept comfortably smaller than a plaza cell so actors never get pinched against it.
@export var fountain_radius: float = 120.0

# ===== colours =====
@export var exposed_color: Color = Color(0.27, 0.20, 0.15)
@export var density_color: Color = Color(0.15, 0.20, 0.30)
@export var building_color: Color = Color(0.33, 0.31, 0.28)
@export var wall_color: Color = Color(0.42, 0.40, 0.36)
@export var grid_color: Color = Color(1, 1, 1, 0.04)
## Fountain look: a stone basin ring with water inside.
@export var fountain_stone_color: Color = Color(0.40, 0.42, 0.45)
@export var fountain_water_color: Color = Color(0.20, 0.45, 0.65)

@onready var navigation_region: NavigationRegion2D = $NavigationRegion2D

var _player_spawns: Array[Vector2] = []
var _mark_locations: Array[Vector2] = []
var _teleport_pads: Array[Vector2] = []
var _density_zones: Array[Rect2] = []
## Each portal pair: {"a": Vector2, "b": Vector2, "color": Color}. The mini-map reads
## this to show where each teleporter goes (matching colour = the two linked ends).
var _portal_links: Array = []


func _ready() -> void:
	add_to_group("map")
	_define_features()
	_build_walls()
	_build_fountain()
	_build_navigation()
	_spawn_portals()
	queue_redraw()


# === public API (kept stable for the co-op bootstrap & systems) ============
func get_player_spawns() -> Array[Vector2]:
	return _player_spawns

func get_mark_locations() -> Array[Vector2]:
	return _mark_locations

func get_teleport_pads() -> Array[Vector2]:
	return _teleport_pads

# Portal pairs (positions + colour) — used by the mini-map to show the teleporters.
func get_portal_links() -> Array:
	return _portal_links

# Building rectangles (in world coords) — used by the mini-map to sketch the layout.
func get_building_rects() -> Array:
	return _building_rects()


# Random point spread evenly across the open cells (area-weighted), inset so it's
# never inside a wall. Used to scatter the crowd at spawn.
func random_walkable_point() -> Vector2:
	var cells := _open_cells()
	var total_area: float = 0.0
	for cell in cells:
		total_area += cell.size.x * cell.size.y
	var pick: float = randf() * total_area
	for cell in cells:
		var area: float = cell.size.x * cell.size.y
		if pick < area:
			var inner: Rect2 = cell.grow(-solid_clearance)
			if inner.size.x <= 0.0 or inner.size.y <= 0.0:
				return cell.get_center()
			return inner.position + Vector2(randf() * inner.size.x, randf() * inner.size.y)
		pick -= area
	return cells[0].get_center() if not cells.is_empty() else Vector2.ZERO


# A random walkable point WITHIN `radius` of `center` — for "homebody" NPCs that mill
# around a small area instead of crossing the whole map.
func random_walkable_point_near(center: Vector2, radius: float) -> Vector2:
	for _attempt in 12:
		var angle: float = randf() * TAU
		var distance: float = sqrt(randf()) * radius  # sqrt = even spread across the disk
		var candidate: Vector2 = center + Vector2(cos(angle), sin(angle)) * distance
		if _is_point_walkable(candidate):
			return candidate
	return center  # give up and stay put


# A random walkable point in one of the EDGE cells — where map-crossing NPCs enter from.
func random_edge_walkable_point() -> Vector2:
	var edge_cells: Array = []
	for row in _rows():
		for col in _cols():
			var on_edge: bool = row == 0 or row == _rows() - 1 or col == 0 or col == _cols() - 1
			if on_edge and not _is_solid(col, row):
				edge_cells.append(_cell_rect(col, row))
	if edge_cells.is_empty():
		return random_walkable_point()
	var cell: Rect2 = edge_cells[randi() % edge_cells.size()]
	var inner: Rect2 = cell.grow(-solid_clearance)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return cell.get_center()
	return inner.position + Vector2(randf() * inner.size.x, randf() * inner.size.y)


# True if a world point lies inside an OPEN cell (inset by the clearance), i.e. a spot
# an actor can actually stand without clipping a wall.
func _is_point_walkable(point: Vector2) -> bool:
	var cell_w: float = (2.0 * play_half_width) / float(_cols())
	var cell_h: float = (2.0 * play_half_height) / float(_rows())
	var col: int = int((point.x + play_half_width) / cell_w)
	var row: int = int((point.y + play_half_height) / cell_h)
	if col < 0 or col >= _cols() or row < 0 or row >= _rows():
		return false
	if _is_solid(col, row):
		return false
	return _cell_rect(col, row).grow(-solid_clearance).has_point(point)


# === grid maths ============================================================
# The active grid: the override if one was set in the Inspector, else the default LAYOUT.
func _layout() -> Array:
	return layout_override if not layout_override.is_empty() else LAYOUT

func _cols() -> int:
	return (_layout()[0] as String).length()

func _rows() -> int:
	return _layout().size()

func _cell_rect(col: int, row: int) -> Rect2:
	var cell_w: float = (2.0 * play_half_width) / float(_cols())
	var cell_h: float = (2.0 * play_half_height) / float(_rows())
	var x0: float = -play_half_width + col * cell_w
	var y0: float = -play_half_height + row * cell_h
	return Rect2(Vector2(x0, y0), Vector2(cell_w, cell_h))

func _cell_center(col: int, row: int) -> Vector2:
	return _cell_rect(col, row).get_center()

func _is_building(col: int, row: int) -> bool:
	return (_layout()[row] as String)[col] == "#"

func _is_fountain(col: int, row: int) -> bool:
	return (_layout()[row] as String)[col] == "F"

# Anything an actor cannot walk through: a building OR the fountain. Used for
# navigation + walkability so nobody ever paths into the fountain basin.
func _is_solid(col: int, row: int) -> bool:
	return _is_building(col, row) or _is_fountain(col, row)

func _has_fountain() -> bool:
	for row in _rows():
		for col in _cols():
			if _is_fountain(col, row):
				return true
	return false

func _fountain_center() -> Vector2:
	for row in _rows():
		for col in _cols():
			if _is_fountain(col, row):
				return _cell_center(col, row)
	return Vector2.ZERO

func _open_cells() -> Array:
	var cells: Array = []
	for row in _rows():
		for col in _cols():
			if not _is_solid(col, row):
				cells.append(_cell_rect(col, row))
	return cells

# Buildings shrunk by the clearance so the nav floor keeps a gap from them.
func _building_rects() -> Array:
	var rects: Array = []
	for row in _rows():
		for col in _cols():
			if _is_building(col, row):
				rects.append(_cell_rect(col, row).grow(-solid_clearance))
	return rects

func _outer_wall_rects() -> Array:
	var ox := play_half_width + solid_clearance
	var oy := play_half_height + solid_clearance
	var t := wall_thickness
	return [
		Rect2(Vector2(-ox - t, -oy - t), Vector2(2 * ox + 2 * t, t)),
		Rect2(Vector2(-ox - t, oy), Vector2(2 * ox + 2 * t, t)),
		Rect2(Vector2(-ox - t, -oy - t), Vector2(t, 2 * oy + 2 * t)),
		Rect2(Vector2(ox, -oy - t), Vector2(t, 2 * oy + 2 * t)),
	]


func _define_features() -> void:
	# Spawns: the four near-corner alley junctions (one cell in, since the corner cells
	# are now part of the solid building ring), far apart.
	_player_spawns = [
		_cell_center(1, 1),
		_cell_center(_cols() - 2, 1),
		_cell_center(1, _rows() - 2),
		_cell_center(_cols() - 2, _rows() - 2),
	]
	# Marks: two open cells on the central N/S avenue, near the top and bottom inner
	# ring roads (the contract picks one per player).
	_mark_locations = [
		_cell_center(_cols() / 2, 1),
		_cell_center(_cols() / 2, _rows() - 2),
	]
	# Teleport pads: opposite mid-sides on the inner ring road (the cross-map jump).
	_teleport_pads = [
		_cell_center(1, _rows() / 2),
		_cell_center(_cols() - 2, _rows() / 2),
	]
	# Density "market" zone: the wide central plaza around the fountain (visual cover).
	_density_zones = [
		_cell_rect(4, 4).merge(_cell_rect(_cols() - 5, 6)),
	]


# === navigation (from the open cells) ======================================
func _build_navigation() -> void:
	var nav_polygon := NavigationPolygon.new()
	var vertices := PackedVector2Array()
	var polygons: Array = []
	for cell in _open_cells():
		var base := vertices.size()
		vertices.append(cell.position)
		vertices.append(Vector2(cell.end.x, cell.position.y))
		vertices.append(cell.end)
		vertices.append(Vector2(cell.position.x, cell.end.y))
		polygons.append(PackedInt32Array([base, base + 1, base + 2, base + 3]))
	nav_polygon.vertices = vertices
	for polygon in polygons:
		nav_polygon.add_polygon(polygon)
	navigation_region.navigation_polygon = nav_polygon


func _build_walls() -> void:
	for rect in _outer_wall_rects():
		_add_static_box(rect.get_center(), rect.size)
	for rect in _building_rects():
		_add_static_box(rect.get_center(), rect.size)


# The central fountain is a round solid you walk around. Its whole grid cell is
# already excluded from navigation, so this collision circle only ever sits inside
# that empty cell — actors route around the cell and never pinch against the basin.
func _build_fountain() -> void:
	if not _has_fountain():
		return
	var body := StaticBody2D.new()
	body.position = _fountain_center()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = fountain_radius
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _add_static_box(center: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


# === map-control features (Portal pairs, §8) ===============================
func _spawn_portals() -> void:
	# Teleporter pads — cross-map, exposure cost (teal). Opposite mid-sides.
	_spawn_portal_pair(_teleport_pads[0], _teleport_pads[1], Color(0.2, 0.8, 0.85, 0.85), teleporter_cost, 58.0)
	# Trapdoor — a medium diagonal hop with a small exposure tell (orange).
	_spawn_portal_pair(_cell_center(4, 2), _cell_center(_cols() - 5, _rows() - 3), Color(0.95, 0.55, 0.2, 0.85), trapdoor_cost, 46.0)
	# Underground passage — free, a cross-map diagonal under the building blocks (grey).
	# NOTE: this is the plain passage; the single-occupancy outer-alley connectors
	# (with "someone's in there" messaging) replace/extend it in the next increment.
	_spawn_portal_pair(_cell_center(1, 2), _cell_center(_cols() - 2, _rows() - 3), Color(0.55, 0.55, 0.62, 0.9), 0.0, 52.0)


func _spawn_portal_pair(a: Vector2, b: Vector2, color: Color, cost: float, radius: float) -> void:
	# Skip a pair whose endpoint would land in a wall/building — keeps ANY layout safe
	# (the compact map has no cell where the big map's trapdoor used to sit, for example).
	if not _is_point_walkable(a) or not _is_point_walkable(b):
		return
	var portal_a := _make_portal(a, color, cost, radius)
	var portal_b := _make_portal(b, color, cost, radius)
	portal_a.link = portal_b
	portal_b.link = portal_a
	# Remember the pair so the mini-map can draw it (matching colour links the two ends).
	_portal_links.append({"a": a, "b": b, "color": color})


func _make_portal(pos: Vector2, color: Color, cost: float, radius: float) -> Portal:
	var portal := Portal.new()
	portal.position = pos
	portal.portal_color = color
	portal.exposure_cost = cost
	portal.portal_radius = radius
	add_child(portal)
	return portal


# === drawing ===============================================================
func _draw() -> void:
	var ox := play_half_width + solid_clearance
	var oy := play_half_height + solid_clearance
	draw_rect(Rect2(Vector2(-ox, -oy), Vector2(2 * ox, 2 * oy)), exposed_color, true)
	for zone in _density_zones:
		draw_rect(zone, density_color, true)
	_draw_grid()
	for rect in _building_rects():
		draw_rect(rect, building_color, true)
	for rect in _outer_wall_rects():
		draw_rect(rect, wall_color, true)
	_draw_fountain()


# Draws the central fountain on TOP of the plaza floor: a stone basin ring, water
# inside, a soft rim highlight, and a little central spout. Greybox, but it reads
# as a landmark so players can orient by the middle of the map.
func _draw_fountain() -> void:
	if not _has_fountain():
		return
	var c := _fountain_center()
	draw_circle(c, fountain_radius, fountain_stone_color)
	draw_circle(c, fountain_radius * 0.72, fountain_water_color)
	draw_arc(c, fountain_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 4.0)
	draw_circle(c, fountain_radius * 0.18, fountain_stone_color)


func _draw_grid() -> void:
	var ox := play_half_width
	var oy := play_half_height
	var x := ceilf(-ox / grid_spacing) * grid_spacing
	while x <= ox:
		draw_line(Vector2(x, -oy), Vector2(x, oy), grid_color, 2.0)
		x += grid_spacing
	var y := ceilf(-oy / grid_spacing) * grid_spacing
	while y <= oy:
		draw_line(Vector2(-ox, y), Vector2(ox, y), grid_color, 2.0)
		y += grid_spacing
