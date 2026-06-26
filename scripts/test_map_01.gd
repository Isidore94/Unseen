extends Node2D
class_name TestMap01

# test_map_01 — UNSEEN, playtest greybox (MAP_DESIGN_SPEC.md).
#
# A more VARIED souk-style layout: a grid of cells, each either a BUILDING or
# OPEN. Scattered buildings carve an irregular network of alleys and small plazas
# around a central open plaza — a "chunk" of a dense market town. The open cells
# stay edge-connected so you can always route around (no dead ends).
#
# WHY GRID CELLS: the walkable area is the set of OPEN cells. Adjacent open cells
# share exact edges, so the navigation system stitches them into one connected
# network (the approach we know works). Variety comes from the LAYOUT pattern.
#
# MAP-CONTROL FEATURES (master_plan §8) are spawned as Portal pairs:
#   - teleporter pads  (cross-map, exposure cost)
#   - a trapdoor       (medium hop, small exposure tell)
#   - an underground passage (free — pure map knowledge)

# The layout. '#' = building, '.' = open street/plaza. Edit this to reshape the map.
const LAYOUT := [
	"..#.#..",
	"#....#.",
	"..#.#..",
	".#.....",
	"..#.#..",
]

# ===== size / tuning =====
@export var play_half_width: float = 1500.0
@export var play_half_height: float = 1100.0
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

# ===== colours =====
@export var exposed_color: Color = Color(0.27, 0.20, 0.15)
@export var density_color: Color = Color(0.15, 0.20, 0.30)
@export var building_color: Color = Color(0.33, 0.31, 0.28)
@export var wall_color: Color = Color(0.42, 0.40, 0.36)
@export var grid_color: Color = Color(1, 1, 1, 0.04)

@onready var navigation_region: NavigationRegion2D = $NavigationRegion2D

var _player_spawns: Array[Vector2] = []
var _mark_locations: Array[Vector2] = []
var _teleport_pads: Array[Vector2] = []
var _density_zones: Array[Rect2] = []


func _ready() -> void:
	add_to_group("map")
	_define_features()
	_build_walls()
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


# === grid maths ============================================================
func _cols() -> int:
	return (LAYOUT[0] as String).length()

func _rows() -> int:
	return LAYOUT.size()

func _cell_rect(col: int, row: int) -> Rect2:
	var cell_w: float = (2.0 * play_half_width) / float(_cols())
	var cell_h: float = (2.0 * play_half_height) / float(_rows())
	var x0: float = -play_half_width + col * cell_w
	var y0: float = -play_half_height + row * cell_h
	return Rect2(Vector2(x0, y0), Vector2(cell_w, cell_h))

func _cell_center(col: int, row: int) -> Vector2:
	return _cell_rect(col, row).get_center()

func _is_building(col: int, row: int) -> bool:
	return (LAYOUT[row] as String)[col] == "#"

func _open_cells() -> Array:
	var cells: Array = []
	for row in _rows():
		for col in _cols():
			if not _is_building(col, row):
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
	# Spawns: the four corner cells (all open in the layout), far apart.
	_player_spawns = [
		_cell_center(0, 0),
		_cell_center(_cols() - 1, 0),
		_cell_center(0, _rows() - 1),
		_cell_center(_cols() - 1, _rows() - 1),
	]
	# Marks: two central open cells (the contract picks one per player).
	_mark_locations = [
		_cell_center(3, 1),
		_cell_center(3, 3),
	]
	# Teleport pads: opposite mid-sides (the cross-map jump).
	_teleport_pads = [
		_cell_center(0, 2),
		_cell_center(_cols() - 1, 2),
	]
	# Density "market" zones (visual cover regions).
	_density_zones = [
		_cell_rect(3, 1).merge(_cell_rect(3, 3)),
		_cell_rect(_cols() - 1, 3).merge(_cell_rect(_cols() - 1, 4)),
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
	# Teleporter pads — cross-map, exposure cost (teal).
	_spawn_portal_pair(_teleport_pads[0], _teleport_pads[1], Color(0.2, 0.8, 0.85, 0.85), teleporter_cost, 58.0)
	# Trapdoor — a medium diagonal hop with a small exposure tell (orange).
	_spawn_portal_pair(_cell_center(1, 1), _cell_center(5, 3), Color(0.95, 0.55, 0.2, 0.85), trapdoor_cost, 46.0)
	# Underground passage — free, traverses the centre vertically (grey).
	_spawn_portal_pair(_cell_center(3, 0), _cell_center(3, 4), Color(0.55, 0.55, 0.62, 0.9), 0.0, 52.0)


func _spawn_portal_pair(a: Vector2, b: Vector2, color: Color, cost: float, radius: float) -> void:
	var portal_a := _make_portal(a, color, cost, radius)
	var portal_b := _make_portal(b, color, cost, radius)
	portal_a.link = portal_b
	portal_b.link = portal_a


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
