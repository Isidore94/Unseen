extends Node2D
class_name TestMap01

# test_map_01 — UNSEEN, the FOUR-ZONE main map (buildplan.md §7.1).
#
# A tight city arena split into four corner ZONES around a central fountain plaza:
#
#       NW  (street + rooftop)   |   NE  (sewer)
#       --------------------- HUB ---------------------
#       SW  (sewer)              |   SE  (street + rooftop)
#
# The two STREET zones (NW + SE, paired on a diagonal) are long parallel buildings
# with tight one-cell N–S streets and a single mid-alley — long sightlines, the
# place rooftops will live (§7.2). The two SEWER zones (NE + SW) are more open with
# scattered blocks — the place sewer entrances will live. A 1-cell HUB cross of
# streets joins all four to the central fountain. Tight streets are the point
# (note 5a): we want long lanes, not open plazas.
#
# WHY GRID CELLS: the walkable area is the set of OPEN cells. Adjacent open cells
# share exact edges, so the navigation system stitches them into one connected
# network. A cell's ZONE is derived from its position (which quarter of the grid it
# falls in), so the floor colour and where access points spawn come for free from
# the layout — no need to hand-annotate every character.
#
# CONNECTIVITY: every open cell is reachable from the centre — this was flood-fill
# verified before commit (scratchpad/gen_layout.py), and `_verify_connectivity()`
# re-checks it at runtime and prints a warning if a future edit walls something off.
#
# MAP-CONTROL FEATURES (master_plan §8) are spawned as Portal pairs:
#   - teleporter pads        (top ↔ bottom cross-map jump, exposure cost — note 2/10)
#   - a trapdoor             (medium hop, small exposure tell)
#   - an underground passage (free, links the two sewer corners — pure map knowledge)

# The layout grid. '#' = building, '.' = open street/plaza, 'F' = the central fountain (solid),
# 'W' = canal water (solid — you can't walk on it), 'B' = bridge (walkable, crosses the canal).
# Generated + connectivity-verified offline;
# edit it and the runtime check will warn you if you accidentally seal a pocket off.
const LAYOUT := [
	"#########################",
	"#.......................#",
	"#.##.##.##.#............#",
	"#.##.##.##.#..##....##..#",
	"#.##.##.##.#..##....##..#",
	"#...................##..#",
	"#.##.##.##.#..###.......#",
	"#.##.##.##.#..###.......#",
	"#.##.##.##..............#",
	"#...........F...........#",
	"#.............#.##.##.#.#",
	"#..##....##..##.##.##.#.#",
	"#..##....##..##.##.##.#.#",
	"#........##.............#",
	"#..###.......##.##.##.#.#",
	"#..###.......##.##.##.#.#",
	"#............##.##.##.#.#",
	"#.......................#",
	"#########################",
]

## Optional smaller/alternate layout. When non-empty, this is used INSTEAD of LAYOUT, so
## a second map scene can reuse this whole script just by setting a different grid +
## smaller play_half_* in the Inspector. Empty = use LAYOUT above.
@export var layout_override: Array[String] = []

# ===== zones =====
## The four corner zones plus the central hub. Used to colour the floor and to decide
## where rooftop stairs (street zones) and sewer entrances (sewer zones) spawn.
enum Zone { NW, NE, SW, SE, HUB }

# ===== size / tuning =====
## Half-extents of the playable area. The nav, walls, spawns and portals all scale
## from these two numbers. Tighter streets come from the denser GRID, not a smaller
## arena, so the crowd still has room to spread.
@export var play_half_width: float = 2400.0
@export var play_half_height: float = 1750.0
@export var wall_thickness: float = 40.0
## Gap kept between the walkable navigation floor and solid walls/buildings, so actors
## never clip corners. MUST exceed an actor half-width (~36) with margin to spare.
@export var solid_clearance: float = 56.0
@export var grid_spacing: float = 200.0

# exposure costs for the map-control features (§8)
@export var teleporter_cost: float = 20.0
@export var trapdoor_cost: float = 8.0
## Shared global cooldown (s) on the teleporter pair so it can't be chained (§7.3).
@export var teleporter_cooldown: float = 15.0
## Pad radius (px) for the teleporter + trapdoor — both the visual AND the trigger/collision. Kept
## SMALL (75% below the old 58/46) so the pads are a spot you step on, not a blob that walls a lane.
@export var teleporter_radius: float = 14.5
@export var trapdoor_radius: float = 11.5

## Radius of the central fountain's solid collision (you route around it), in pixels.
@export var fountain_radius: float = 120.0

# ===== access points (sewer entrances; §7.2 wires the layer mechanics) =====
## ROOFTOPS ARE REMOVED. The rooftop layer "didn't really do anything" in playtest, so we no
## longer spawn rooftop stairs (flip this on only if rooftops are ever re-designed). The rooftop
## LayerComponent code stays dormant — with no stairs to climb, no one ever reaches that layer.
@export var enable_rooftops: bool = false
## How many rooftop stairs to mark in EACH street zone (NW, SE) — only used if enable_rooftops.
@export var rooftop_stairs_per_street_zone: int = 2
## SEWERS ARE CORNER POCKETS now: a small huddle of entrances in two opposite corners, so the
## sewer is a place to DUCK FOR COVER and pop up a short hop away — never a tunnel across the map.
## How many sewer entrances cluster in EACH corner pocket.
@export var sewer_entrances_per_pocket: int = 3
## When false, this map spawns NO map-control portals (teleporters / trapdoor / underground
## passage). Street-only maps like Rome set this false — just tight lanes, no shortcuts (§8).
@export var enable_portals: bool = true
## Finer control: when false, the cross-map TELEPORTER pads are skipped but the trapdoor still
## spawns (if enable_portals is on). Citadel sets this false — no magic top↔bottom jump, but the
## short trapdoor hop stays. Only matters when enable_portals is true.
@export var enable_teleporters: bool = true
## OVERHANG concealment (master_plan §8 cover; the "shadow" cover we had on the Citadel): when true,
## every building casts a walkable ROOF OVERHANG over the adjacent street toward the map centre. That
## overhang (a RoofOverlay zone) is drawn OPAQUE above players, so it HIDES whoever's under it on OTHER
## screens, and turns translucent only on your OWN screen while you personally stand under it. Purely
## visual (no exposure effect); the street underneath stays walkable. Off by default — maps opt in.
@export var enable_overhangs: bool = false
## Buildings within this many cells of the map BORDER cast NO overhang — less cover at the edges, more
## toward the busy centre. Set 0 to give EVERY building an overhang (the original all-buildings web).
@export var overhang_border_margin: int = 3
var _roof_overlay: RoofOverlay = null  ## overhead concealment overlay (built once, on this machine)

# ===== colours =====
## Out-of-bounds border behind everything.
@export var exposed_color: Color = Color(0.16, 0.14, 0.12)
## Crowd-cover plaza tint (drawn under the central density zone).
@export var density_color: Color = Color(0.15, 0.20, 0.30)
@export var building_color: Color = Color(0.20, 0.18, 0.16)
@export var wall_color: Color = Color(0.42, 0.40, 0.36)
@export var grid_color: Color = Color(1, 1, 1, 0.03)
# Per-zone FLOOR colours — muted so characters stay readable on top (Pillar #6), but
# distinct enough that each corner reads at a glance (the four-colour quarters).
@export var zone_nw_color: Color = Color(0.30, 0.255, 0.195)   # NW street — warm sand
@export var zone_se_color: Color = Color(0.205, 0.235, 0.30)   # SE street — cool slate
@export var zone_ne_color: Color = Color(0.215, 0.265, 0.205)  # NE sewer — moss
@export var zone_sw_color: Color = Color(0.295, 0.225, 0.185)  # SW sewer — rust
@export var zone_hub_color: Color = Color(0.32, 0.31, 0.265)   # central avenues — stone
## Fountain look: a stone basin ring with water inside.
@export var fountain_stone_color: Color = Color(0.40, 0.42, 0.45)
@export var fountain_water_color: Color = Color(0.20, 0.45, 0.65)

@onready var navigation_region: NavigationRegion2D = $NavigationRegion2D

var _player_spawns: Array[Vector2] = []
var _mark_locations: Array[Vector2] = []
var _teleport_pads: Array[Vector2] = []
var _density_zones: Array[Rect2] = []
## Access-point world positions (§7.2 will mount the real layer mechanics here).
var _rooftop_stairs: Array[Vector2] = []
var _sewer_entrances: Array[Vector2] = []
## Each portal pair: {"a": Vector2, "b": Vector2, "color": Color}. The mini-map reads
## this to show where each teleporter goes (matching colour = the two linked ends).
var _portal_links: Array = []


func _ready() -> void:
	add_to_group("map")
	if stylized_render:
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # smooth the stretched noise ground
	_define_features()
	_build_walls()
	_build_fountain()
	_build_navigation()
	if enable_portals:
		_spawn_portals()
	_spawn_access_points()
	_verify_connectivity()
	queue_redraw()


# === public API (kept stable for the co-op bootstrap & systems) ============
func get_player_spawns() -> Array[Vector2]:
	return _player_spawns

func get_mark_locations() -> Array[Vector2]:
	return _mark_locations

func get_teleport_pads() -> Array[Vector2]:
	return _teleport_pads

# Rooftop stair / sewer entrance world positions — §7.2 reads these to build layers.
func get_rooftop_stairs() -> Array[Vector2]:
	return _rooftop_stairs

func get_sewer_entrances() -> Array[Vector2]:
	return _sewer_entrances

# Portal pairs (positions + colour) — used by the mini-map to show the teleporters.
func get_portal_links() -> Array:
	return _portal_links

# Building rectangles (in world coords) — used by the mini-map to sketch the layout.
func get_building_rects() -> Array:
	return _building_rects()

# Which zone a world point falls in (for future zone-aware systems, e.g. §7.2/§7.3).
func get_zone_at(world_point: Vector2) -> Zone:
	var coords := _point_to_cell(world_point)
	return _cell_zone(coords.x, coords.y)


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
# "Edge" means the perimeter RING (row/col 1 from each side): the true border rows are all
# wall in every layout, so the old row-0 test never matched and this always fell back.
func random_edge_walkable_point() -> Vector2:
	var edge_cells: Array = []
	for row in _rows():
		for col in _cols():
			var on_edge: bool = row <= 1 or row >= _rows() - 2 or col <= 1 or col >= _cols() - 2
			if on_edge and not _is_solid(col, row):
				edge_cells.append(_cell_rect(col, row))
	if edge_cells.is_empty():
		return random_walkable_point()
	var cell: Rect2 = edge_cells[randi() % edge_cells.size()]
	var inner: Rect2 = cell.grow(-solid_clearance)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return cell.get_center()
	return inner.position + Vector2(randf() * inner.size.x, randf() * inner.size.y)


# A PRESET-style EVEN scatter: `count` walkable spawn points spread across the WHOLE map. We lay a
# target grid (sized ~count, matching the play area's aspect) and snap each target to the nearest
# UNUSED open cell, so the crowd fills the map corner-to-corner instead of clumping where random picks
# happen to land. A small per-point jitter keeps it from reading as a rigid lattice. Coverage is
# deterministic (every cell is used before any repeats), so it's effectively a preset spread.
func even_spawn_points(count: int) -> Array:
	var points: Array = []
	if count <= 0:
		return points
	var cells := _open_cells()  # Array[Rect2] of walkable cells
	if cells.is_empty():
		return points
	# A target grid sized ~count, matching the play area's aspect, so points cover X and Y evenly.
	var aspect: float = play_half_width / maxf(1.0, play_half_height)
	var gy: int = maxi(1, int(round(sqrt(float(count) / aspect))))
	var gx: int = maxi(1, int(ceil(float(count) / float(gy))))
	var used: Dictionary = {}  # cell index -> true, so each cell hosts one NPC until cells run out
	for iy in gy:
		for ix in gx:
			if points.size() >= count:
				break
			var tx: float = lerpf(-play_half_width, play_half_width, (float(ix) + 0.5) / float(gx))
			var ty: float = lerpf(-play_half_height, play_half_height, (float(iy) + 0.5) / float(gy))
			var idx: int = _nearest_open_cell_index(Vector2(tx, ty), cells, used)
			used[idx] = true
			var cell: Rect2 = cells[idx]
			var inner: Rect2 = cell.grow(-solid_clearance)
			if inner.size.x > 0.0 and inner.size.y > 0.0:
				points.append(inner.position + Vector2(randf() * inner.size.x, randf() * inner.size.y))
			else:
				points.append(cell.get_center())
	return points


# === errand destinations (the "walking with intent" crowd) =================
# Instead of wandering to random points, crowd NPCs walk ERRANDS between POINTS OF INTEREST.
# The map is split into a 3x3 grid of NINE errand districts (finer than the four gameplay
# zones — quadrants proved too coarse: a quadrant looked "full" while all its NPCs hugged
# the centre side, and the corners drained empty). Each district keeps its own POI list and
# its own live population; most errands are LOCAL (inside the district), and the crossings
# are weighted toward UNDER-populated + NEARBY districts — so empty corners actively pull
# walkers in, while long hauls through the central plaza stay rare.
#
# POIs are "doorway" points — spots at the EDGE of a street cell, against a building —
# plus landmarks (fountain plaza, bridges, roofed alleys, sewer entrances). So a lingering
# NPC stands where a person would stand (a doorway, an awning, the fountain rim), never in
# the middle of the road.

## How many errand POIs to keep per 3x3 district (spread via farthest-first selection).
## Keep this generous: with too few shared magnets, several NPCs pile onto the same spot.
@export var errand_pois_per_region: int = 12
## Random scatter (px) added around every errand destination, so ten NPCs "at the fountain"
## stand in a loose cluster instead of stacking on one exact point. Must comfortably exceed
## an NPC's avoidance radius (40) or arrivals at a shared spot deadlock into jostling.
@export var errand_arrival_jitter_px: float = 70.0
## How often (seconds, at most) the per-district NPC population is recounted for the
## under-population weighting. Counting is cheap but happens on every errand pick, so a
## short cache keeps a 100-NPC crowd from re-counting itself dozens of times a second.
@export var errand_population_cache_seconds: float = 0.5
## Weight multiplier for crossing to a FAR district (2+ steps away on the 3x3 grid, e.g.
## corner to opposite corner) versus an adjacent one. Far crossings are the legs that cut
## through the central plaza — keep them rare and the middle stops being a commuter river.
@export_range(0.0, 1.0, 0.05) var errand_far_crossing_weight: float = 0.4
## A LOCAL errand tries to land at least this far away (px), so it reads as a purposeful
## trip down the street — not the old shuffle-in-place.
@export var errand_local_min_distance_px: float = 200.0
## When a district holds MORE than this multiple of the average district population, NPCs
## there always CROSS away instead of staying local — people disperse from a packed square.
## This is the safety valve that stops any one spot (the fountain plaza) becoming a sink.
@export var errand_overcrowd_ratio: float = 1.35

var _errand_pois_by_region: Dictionary = {}  ## district int (0-8) -> Array[Vector2], built lazily once
var _region_population_cache: Dictionary = {}
var _region_population_cached_at: float = -1000.0


# Which 3x3 errand district a world point falls in: 0..8, row-major (0 = NW corner,
# 4 = centre, 8 = SE corner). Independent of the gameplay Zone quadrants on purpose.
func _errand_region_of(point: Vector2) -> int:
	var col3 := clampi(int((point.x + play_half_width) / (2.0 * play_half_width / 3.0)), 0, 2)
	var row3 := clampi(int((point.y + play_half_height) / (2.0 * play_half_height / 3.0)), 0, 2)
	return row3 * 3 + col3


# How many steps apart two districts sit on the 3x3 grid (Chebyshev distance: adjacent
# and diagonal-adjacent are both 1; corner to opposite corner is 2).
func _errand_region_distance(a: int, b: int) -> int:
	return maxi(absi(a % 3 - b % 3), absi(a / 3 - b / 3))


# A purposeful destination for a crowd NPC standing at `from_pos`. With `prefer_local`
# true, a LOCAL errand in the current district (the NPC does a few of those per visit —
# its "neighbourhood business" — which is what keeps districts populated instead of the
# whole crowd being permanently mid-commute); otherwise a CROSSING weighted toward
# under-populated + nearby districts. The NPC controls that cadence (npc.gd,
# local_legs_between_crossings). Called each time an errand leg ends (host/offline only).
func errand_destination(from_pos: Vector2, prefer_local: bool = false) -> Vector2:
	_build_errand_pois()
	var current_region := _errand_region_of(from_pos)
	var populations := _region_populations()
	# OVERCROWD exodus: if this district is packed well past the average, always leave —
	# people disperse from a crammed square. Without this, popular spots became sinks.
	var total_population := 0
	for value in populations.values():
		total_population += int(value)
	var average_population := float(total_population) / 9.0
	var overcrowded: bool = average_population > 0.0 \
		and float(populations.get(current_region, 0)) > errand_overcrowd_ratio * average_population
	if prefer_local and not overcrowded:
		var local: Array = _errand_pois_by_region.get(current_region, [])
		if not local.is_empty():
			# Try for a spot a proper walk away, so it reads as a trip, not a shuffle.
			for _attempt in 4:
				var poi: Vector2 = local[randi() % local.size()]
				if poi.distance_to(from_pos) >= errand_local_min_distance_px:
					return _jittered_poi(poi)
			return _jittered_poi(local[randi() % local.size()])
	# CROSSING: weight each other district by 1/(1+population) — empty districts pull
	# hardest, so drained corners refill — damped for FAR districts (long hauls through
	# the middle stay the exception).
	var regions: Array = []
	var weights: Array = []
	var total_weight := 0.0
	for region in _errand_pois_by_region:
		if region == current_region or (_errand_pois_by_region[region] as Array).is_empty():
			continue
		var weight: float = 1.0 / (1.0 + float(populations.get(region, 0)))
		if _errand_region_distance(current_region, int(region)) >= 2:
			weight *= errand_far_crossing_weight
		regions.append(region)
		weights.append(weight)
		total_weight += weight
	if regions.is_empty():
		return random_walkable_point()
	var pick := randf() * total_weight
	var chosen: int = regions[0]
	for i in regions.size():
		if pick < float(weights[i]):
			chosen = regions[i]
			break
		pick -= float(weights[i])
	var pois: Array = _errand_pois_by_region[chosen]
	return _jittered_poi(pois[randi() % pois.size()])


# The POI plus a random scatter, so simultaneous visitors to one spot spread into a loose
# cluster (see errand_arrival_jitter_px). If the scattered point lands in a wall we keep the
# raw POI — the navigation system clamps any target onto the walkable mesh regardless.
func _jittered_poi(poi: Vector2) -> Vector2:
	var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * errand_arrival_jitter_px
	var candidate := poi + offset
	return candidate if _is_point_walkable(candidate) else poi


# Build the per-district POI lists once: doorway points on every street cell that touches a
# building, plus landmark points (fountain ring, bridges, alleys, sewer pockets), then keep
# a spread-out subset per district so errands cover each district evenly.
func _build_errand_pois() -> void:
	if not _errand_pois_by_region.is_empty():
		return
	var candidates_by_region: Dictionary = {}
	for row in _rows():
		for col in _cols():
			if _is_solid(col, row):
				continue
			var poi := _doorway_point(col, row)
			if poi == Vector2.INF:
				# No adjacent building (an open plaza cell) — alleys/bridges still count as POIs.
				if not (_is_alley(col, row) or _is_bridge(col, row)):
					continue
				poi = _cell_center(col, row)
			var region := _errand_region_of(poi)
			if not candidates_by_region.has(region):
				candidates_by_region[region] = [] as Array[Vector2]
			(candidates_by_region[region] as Array[Vector2]).append(poi)
	# Landmarks: a ring of points around the fountain plaza (people gravitate to the centre).
	if _has_fountain():
		var centre := _fountain_center()
		for i in 8:
			var angle := TAU * float(i) / 8.0
			var point := centre + Vector2(cos(angle), sin(angle)) * (fountain_radius + 110.0)
			if _is_point_walkable(point):
				var region2 := _errand_region_of(point)
				if not candidates_by_region.has(region2):
					candidates_by_region[region2] = [] as Array[Vector2]
				(candidates_by_region[region2] as Array[Vector2]).append(point)
	# Sewer pockets give the corners a destination too.
	for entrance in _sewer_entrances:
		var region3 := _errand_region_of(entrance)
		if not candidates_by_region.has(region3):
			candidates_by_region[region3] = [] as Array[Vector2]
		(candidates_by_region[region3] as Array[Vector2]).append(entrance)
	# Keep a spread-out subset per district so POIs don't clump on one street.
	for region in candidates_by_region:
		var typed: Array[Vector2] = []
		typed.assign(candidates_by_region[region])
		_errand_pois_by_region[region] = _pick_spread_points(typed, errand_pois_per_region)


# The "stand in the doorway" point of a street cell: its centre nudged toward one adjacent
# building, as far as the walkable inset allows. Returns Vector2.INF if no building touches
# this cell (a mid-plaza cell — not a natural place to stand around).
func _doorway_point(col: int, row: int) -> Vector2:
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var toward_building := Vector2i.ZERO
	var options: Array[Vector2i] = []
	for offset in directions:
		if _building_at(col + offset.x, row + offset.y):
			options.append(offset)
	if options.is_empty():
		return Vector2.INF
	toward_building = options[(col * 31 + row * 17) % options.size()]  # stable pick per cell
	var cell := _cell_rect(col, row)
	var max_nudge_x := maxf(0.0, cell.size.x * 0.5 - solid_clearance - 6.0)
	var max_nudge_y := maxf(0.0, cell.size.y * 0.5 - solid_clearance - 6.0)
	return cell.get_center() + Vector2(toward_building.x * max_nudge_x, toward_building.y * max_nudge_y)


# NPCs per 3x3 district, cached briefly (see errand_population_cache_seconds). Uses the
# live "npc" group so dead/despawned NPCs fall out automatically.
func _region_populations() -> Dictionary:
	var now := float(Time.get_ticks_msec()) / 1000.0
	if now - _region_population_cached_at < errand_population_cache_seconds:
		return _region_population_cache
	_region_population_cached_at = now
	_region_population_cache = {}
	for node in get_tree().get_nodes_in_group("npc"):
		var body := node as Node2D
		if body == null:
			continue
		var region := _errand_region_of(body.global_position)
		_region_population_cache[region] = int(_region_population_cache.get(region, 0)) + 1
	return _region_population_cache


# Index of the open cell whose centre is nearest `target`, preferring cells not yet in `used` (so the
# even grid lands one NPC per cell); falls back to the nearest of ALL cells once every cell is used.
func _nearest_open_cell_index(target: Vector2, cells: Array, used: Dictionary) -> int:
	var best: int = -1
	var best_d: float = INF
	var best_any: int = 0
	var best_any_d: float = INF
	for i in cells.size():
		var d: float = ((cells[i] as Rect2).get_center() - target).length_squared()
		if d < best_any_d:
			best_any_d = d
			best_any = i
		if not used.has(i) and d < best_d:
			best_d = d
			best = i
	return best if best != -1 else best_any


# True if a world point lies inside an OPEN cell (inset by the clearance), i.e. a spot
# an actor can actually stand without clipping a wall.
func _is_point_walkable(point: Vector2) -> bool:
	var coords := _point_to_cell(point)
	var col: int = coords.x
	var row: int = coords.y
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

# World point -> the (col,row) of the grid cell it lands in (as a Vector2i).
func _point_to_cell(point: Vector2) -> Vector2i:
	var cell_w: float = (2.0 * play_half_width) / float(_cols())
	var cell_h: float = (2.0 * play_half_height) / float(_rows())
	var col: int = int((point.x + play_half_width) / cell_w)
	var row: int = int((point.y + play_half_height) / cell_h)
	return Vector2i(col, row)

func _is_building(col: int, row: int) -> bool:
	return (_layout()[row] as String)[col] == "#"

# Bounds-safe building test: anything off the grid counts as NOT a building (open), so neighbour
# checks at the map edge don't index out of range.
func _building_at(col: int, row: int) -> bool:
	if col < 0 or col >= _cols() or row < 0 or row >= _rows():
		return false
	return _is_building(col, row)

func _is_fountain(col: int, row: int) -> bool:
	return (_layout()[row] as String)[col] == "F"

# Canal WATER — solid, drawn as water, you can't walk on it (cross via the bridges).
func _is_water(col: int, row: int) -> bool:
	return (_layout()[row] as String)[col] == "W"

# A BRIDGE cell — walkable (NOT solid), drawn as planks where it crosses the canal.
func _is_bridge(col: int, row: int) -> bool:
	return (_layout()[row] as String)[col] == "B"

# An ALLEY cell — a WALKABLE secret cut-through a building (marked 'a' in the layout) that is still
# ROOFED, so it acts as a concealment zone. Layouts without any 'a' simply have no alleys (returns false).
func _is_alley(col: int, row: int) -> bool:
	return (_layout()[row] as String)[col] == "a"

# Anything an actor cannot walk through: a building, the fountain, OR canal water.
func _is_solid(col: int, row: int) -> bool:
	return _is_building(col, row) or _is_fountain(col, row) or _is_water(col, row)

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


# === zones =================================================================
# A cell's zone is derived purely from where it sits in the grid: the central row /
# column (and the 3x3 plaza around the fountain) are the HUB; the four quarters around
# them are NW/NE/SW/SE. Diagonal pairing: NW+SE = street, NE+SW = sewer.
func _center_col() -> int:
	return _cols() / 2

func _center_row() -> int:
	return _rows() / 2

func _cell_zone(col: int, row: int) -> Zone:
	var cc := _center_col()
	var cr := _center_row()
	if col == cc or row == cr:
		return Zone.HUB
	if absi(col - cc) <= 1 and absi(row - cr) <= 1:
		return Zone.HUB
	if col < cc and row < cr:
		return Zone.NW
	if col > cc and row < cr:
		return Zone.NE
	if col < cc and row > cr:
		return Zone.SW
	return Zone.SE

func _zone_floor_color(zone: Zone) -> Color:
	match zone:
		Zone.NW: return zone_nw_color
		Zone.NE: return zone_ne_color
		Zone.SW: return zone_sw_color
		Zone.SE: return zone_se_color
		_: return zone_hub_color

# True for the 1-cell ring road hugging the outer wall. We keep features (marks,
# access points) OFF the ring — it's just a connector, and its corners are spawns.
func _is_perimeter_ring(col: int, row: int) -> bool:
	return col == 1 or col == _cols() - 2 or row == 1 or row == _rows() - 2

# Open-cell CENTRES belonging to one zone (excluding the perimeter ring) — the
# candidate spots for that zone's marks and access points.
func _open_centers_in_zone(zone: Zone) -> Array[Vector2]:
	var centers: Array[Vector2] = []
	for row in _rows():
		for col in _cols():
			if _is_solid(col, row) or _is_perimeter_ring(col, row):
				continue
			if _cell_zone(col, row) == zone:
				centers.append(_cell_center(col, row))
	return centers


# === feature placement =====================================================
func _define_features() -> void:
	# Spawns: the four near-corner ring junctions — maximally far apart so no two
	# players ever start adjacent (note 12, the spawn-spacing intent). Each corner is
	# SNAPPED to the nearest open cell, so a layout that builds over a corner (e.g. the
	# Citadel's filled south row) can never spawn a player inside a wall.
	_player_spawns = []
	for corner: Vector2i in [Vector2i(1, 1), Vector2i(_cols() - 2, 1), Vector2i(1, _rows() - 2), Vector2i(_cols() - 2, _rows() - 2)]:
		_player_spawns.append(_nearest_open_cell_center(corner))

	# Marks: four well-separated spots, one per quarter, chosen farthest-first so any
	# two picked for a contract are at least a couple of screens apart (note 13).
	var quarter_points: Array[Vector2] = []
	for zone in [Zone.NW, Zone.NE, Zone.SW, Zone.SE]:
		var centers := _open_centers_in_zone(zone)
		if not centers.is_empty():
			quarter_points.append_array(_pick_spread_points(centers, 1))
	_mark_locations = quarter_points

	# Teleport pads: TOP centre ↔ BOTTOM centre — the vertical cross-map jump (note 2).
	_teleport_pads = [
		_cell_center(_center_col(), 1),
		_cell_center(_center_col(), _rows() - 2),
	]

	# Rooftop stairs: only if rooftops are explicitly re-enabled (removed by default — see the
	# enable_rooftops note). Spread within each STREET zone so they're not bunched together.
	_rooftop_stairs = []
	if enable_rooftops:
		for zone in [Zone.NW, Zone.SE]:
			_rooftop_stairs.append_array(_pick_spread_points(_open_centers_in_zone(zone), rooftop_stairs_per_street_zone))
	# Sewer entrances: CLUSTERED into two corner POCKETS (NE + SW corners). Clustering — not
	# spreading — is the point: the entrances huddle in a corner, so the sewer lets you reposition
	# a short hop within that corner, not traverse the whole map underground.
	_sewer_entrances = []
	_sewer_entrances.append_array(_corner_pocket_points(Zone.NE, sewer_entrances_per_pocket))
	_sewer_entrances.append_array(_corner_pocket_points(Zone.SW, sewer_entrances_per_pocket))

	# Density "market" zone: the central fountain plaza (visual + exposure cover).
	var cc := _center_col()
	var cr := _center_row()
	_density_zones = [
		_cell_rect(cc - 1, cr - 1).merge(_cell_rect(cc + 1, cr + 1)),
	]


# Farthest-first selection: pick `count` points that are spread as far apart as
# possible from a list of candidates. Start at the first candidate, then repeatedly
# add whichever remaining point is farthest from everything already chosen. Used so
# marks / access points never clump in one spot.
func _pick_spread_points(candidates: Array[Vector2], count: int) -> Array[Vector2]:
	var chosen: Array[Vector2] = []
	if candidates.is_empty() or count <= 0:
		return chosen
	chosen.append(candidates[0])
	while chosen.size() < count and chosen.size() < candidates.size():
		var best_point: Vector2 = candidates[0]
		var best_distance: float = -1.0
		for candidate in candidates:
			if candidate in chosen:
				continue
			var nearest: float = INF
			for picked in chosen:
				nearest = minf(nearest, candidate.distance_to(picked))
			if nearest > best_distance:
				best_distance = nearest
				best_point = candidate
		chosen.append(best_point)
	return chosen


# Pick the `count` open cells of `zone` that sit CLOSEST to that zone's outer corner — a tight
# huddle, used for the sewer corner pockets (the opposite of _pick_spread_points). Sorting by
# distance to the corner anchor pulls the entrances together in the corner.
func _corner_pocket_points(zone: Zone, count: int) -> Array[Vector2]:
	var centers := _open_centers_in_zone(zone)
	var pocket: Array[Vector2] = []
	if centers.is_empty() or count <= 0:
		return pocket
	var anchor := _zone_corner_anchor(zone)
	centers.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_squared_to(anchor) < b.distance_squared_to(anchor))
	for i in mini(count, centers.size()):
		pocket.append(centers[i])
	return pocket


# The centre of the OPEN cell nearest to `target` (grid coords). Used to keep hardcoded
# feature spots (like the corner spawns) safe on ANY layout: if the target cell is solid,
# we simply slide to the closest walkable cell instead of placing something inside a wall.
func _nearest_open_cell_center(target: Vector2i) -> Vector2:
	if target.x >= 0 and target.x < _cols() and target.y >= 0 and target.y < _rows() \
			and not _is_solid(target.x, target.y):
		return _cell_center(target.x, target.y)
	var best := Vector2i(1, 1)
	var best_distance := INF
	for row in _rows():
		for col in _cols():
			if _is_solid(col, row):
				continue
			var d := float((Vector2i(col, row) - target).length_squared())
			if d < best_distance:
				best_distance = d
				best = Vector2i(col, row)
	return _cell_center(best.x, best.y)


# How many walkable cells this layout has. The crowd spawners read this to size the crowd
# to the map (NPCs per open cell), so density stays consistent across maps of any size.
func open_cell_count() -> int:
	var count := 0
	for row in _rows():
		for col in _cols():
			if not _is_solid(col, row):
				count += 1
	return count


# The world position of a zone's OUTER corner (the corner of the map nearest that quarter).
func _zone_corner_anchor(zone: Zone) -> Vector2:
	match zone:
		Zone.NW: return Vector2(-play_half_width, -play_half_height)
		Zone.NE: return Vector2(play_half_width, -play_half_height)
		Zone.SW: return Vector2(-play_half_width, play_half_height)
		Zone.SE: return Vector2(play_half_width, play_half_height)
		_: return Vector2.ZERO


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
	if stylized_render:
		# Solid FULL-CELL building collision so it matches the solid drawn blocks (and closes the
		# interior seam gaps the inset per-cell boxes leave). Players can't enter a building.
		for row in _rows():
			for col in _cols():
				if _is_building(col, row):
					var r := _cell_rect(col, row)
					_add_static_box(r.get_center(), r.size)
	else:
		for rect in _building_rects():
			_add_static_box(rect.get_center(), rect.size)
	# Canal WATER cells are solid too (you can't walk on water — cross via the bridge cells, which
	# are open). Full-cell boxes so the water edge lines up with the drawn water.
	for row in _rows():
		for col in _cols():
			if _is_water(col, row):
				var w := _cell_rect(col, row)
				_add_static_box(w.get_center(), w.size)


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
	# Teleporter pads — TOP ↔ BOTTOM cross-map jump, exposure cost + 15s shared cooldown
	# (teal). Notes 2/10/§7.3. Skipped on maps that opt out (enable_teleporters = false).
	if enable_teleporters:
		_spawn_portal_pair(_teleport_pads[0], _teleport_pads[1], Color(0.2, 0.8, 0.85, 0.85), teleporter_cost, teleporter_radius, teleporter_cooldown)
	# Trapdoor — a medium diagonal hop with a small exposure tell (orange): NW alley
	# to SE alley. No cooldown.
	_spawn_portal_pair(_cell_center(4, 5), _cell_center(_cols() - 7, _rows() - 6), Color(0.95, 0.55, 0.2, 0.85), trapdoor_cost, trapdoor_radius, 0.0)
	# (REMOVED) the cross-map underground passage that linked the two sewer corners — it turned the
	# sewer into a map-spanning tunnel. Sewers are corner pockets for cover now, not a highway.


func _spawn_portal_pair(a: Vector2, b: Vector2, color: Color, cost: float, radius: float, cooldown: float) -> void:
	# Skip a pair whose endpoint would land in a wall/building — keeps ANY layout safe.
	if not _is_point_walkable(a) or not _is_point_walkable(b):
		return
	var portal_a := _make_portal(a, color, cost, radius, cooldown)
	var portal_b := _make_portal(b, color, cost, radius, cooldown)
	portal_a.link = portal_b
	portal_b.link = portal_a
	# Remember the pair so the mini-map can draw it (matching colour links the two ends).
	_portal_links.append({"a": a, "b": b, "color": color})


func _make_portal(pos: Vector2, color: Color, cost: float, radius: float, cooldown: float) -> Portal:
	var portal := Portal.new()
	portal.position = pos
	portal.portal_color = color
	portal.exposure_cost = cost
	portal.portal_radius = radius
	portal.global_cooldown = cooldown
	add_child(portal)
	return portal


# === connectivity safety net ===============================================
# Flood-fill the open cells from the centre; warn if any open cell is unreachable.
# This catches a future LAYOUT edit that accidentally seals off a pocket of street
# (the bug that has sunk top-down crowd games before). It only PRINTS — it never
# changes the map — so it's a safe, beginner-friendly tripwire.
func _verify_connectivity() -> void:
	var start := Vector2i(_center_col(), _center_row() - 1)  # just above the fountain
	if _is_solid(start.x, start.y):
		return
	var seen := {}
	seen[start] = true
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := cell + offset
			if next.x < 0 or next.x >= _cols() or next.y < 0 or next.y >= _rows():
				continue
			if _is_solid(next.x, next.y) or seen.has(next):
				continue
			seen[next] = true
			stack.append(next)
	var open_count: int = 0
	for row in _rows():
		for col in _cols():
			if not _is_solid(col, row):
				open_count += 1
	if seen.size() < open_count:
		push_warning("TestMap01: %d open cells unreachable from centre — a pocket is walled off. Check LAYOUT." % (open_count - seen.size()))


# === stylized render (smooth AC:B look — opt-in) ===========================
# A clean, low-frequency look instead of repeating tiles: one sand ground with broad SOFT
# noise variation (no repetition), buildings drawn as extruded blocks (roof + side + shadow)
# with a per-building shade so no two are identical, a plaza decal, and water-coloured margins.
# Purely visual; collision/nav still come from the grid. On for all maps (the clean AC:B look).
@export var stylized_render: bool = true
## Stylized palette (warm sand + terracotta-ish blocks + teal water), tuned to the reference.
@export var sand_light: Color = Color(0.85, 0.78, 0.59)
@export var sand_dark: Color = Color(0.72, 0.64, 0.46)
@export var block_roof: Color = Color(0.62, 0.50, 0.34)
@export var block_side: Color = Color(0.40, 0.32, 0.21)
@export var water_color: Color = Color(0.17, 0.43, 0.47)
## Fake height of buildings (px the roof is lifted) and the soft shadow offset. Each building
## jitters its own height around block_height (see _building_styles) so the skyline isn't flat.
@export var block_height: float = 18.0
@export var block_shadow_offset: Vector2 = Vector2(16, 18)
## A palette of roof colours. Each building picks ONE (stable, hashed) so the rooftops read as a
## varied tiled town — terracotta, tan, weathered grey, slate — instead of one flat colour. This
## is the main "roof variety" knob the top-down view lives on.
@export var roof_palette: Array[Color] = [
	Color(0.62, 0.50, 0.34),  # tan
	Color(0.71, 0.41, 0.30),  # terracotta
	Color(0.56, 0.53, 0.46),  # weathered grey-brown
	Color(0.49, 0.46, 0.55),  # slate blue-grey
	Color(0.67, 0.55, 0.31),  # ochre
]
## Colour of the plank BRIDGES that cross the canal (the canal itself is grid 'W'/'B' cells now).
@export var bridge_color: Color = Color(0.55, 0.42, 0.27)
## QUADRANT IDENTITY (orientation aid): each quarter tints its street floor very slightly with its
## zone colour so you can tell at a glance which district you're in ("my mark lives in the rust
## quarter"). This is the alpha of that tint — keep it LOW so characters stay readable (Pillar #6).
@export_range(0.0, 0.3, 0.005) var zone_ground_tint_alpha: float = 0.06
## …and each quarter biases its roofs toward ONE palette colour (NW terracotta, NE slate, SW ochre,
## SE weathered grey) with this probability; the rest stay hash-random so no quarter is uniform.
@export_range(0.0, 1.0, 0.05) var zone_roof_bias: float = 0.65
## Floor colour of a roofed ALLEY cut-through ('a' cells) — darker paving, so when the roof fades
## for you (you're inside), the passage floor reads as a distinct covered walkway.
@export var alley_floor_color: Color = Color(0.42, 0.38, 0.30)

var _noise_tex: ImageTexture = null
## Cached per-cell building style {Vector2i(col,row) -> {"roof","side","height"}}. Cells of one
## connected building share a style, so a multi-cell L-shape reads as ONE block with one roof.
var _building_style_cache: Dictionary = {}


# A baked, smooth two-tone sand texture (broad patches). Stretched over the whole map with
# LINEAR filtering, so variation reads at MAP scale — never a repeating stamp.
func _stylized_ground() -> ImageTexture:
	if _noise_tex != null:
		return _noise_tex
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.022
	n.seed = 1207
	var size := 160
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var v: float = n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5  # 0..1
			img.set_pixel(x, y, sand_light.lerp(sand_dark, v))
	_noise_tex = ImageTexture.create_from_image(img)
	return _noise_tex


# Cheap deterministic 0..1 hash so each building gets a stable, repeatable shade.
func _hash01(i: int) -> float:
	return fmod(abs(sin(float(i) * 12.9898) * 43758.5453), 1.0)


func _draw_stylized() -> void:
	var ox := play_half_width + solid_clearance
	var oy := play_half_height + solid_clearance
	# Teal "water" margin around the play area (echoes the reference's edges).
	draw_rect(Rect2(Vector2(-ox, -oy), Vector2(2 * ox, 2 * oy)), water_color, true)
	# Sand ground with broad soft variation (one stretched, smoothed noise texture).
	var play := Rect2(Vector2(-play_half_width, -play_half_height),
		Vector2(2 * play_half_width, 2 * play_half_height))
	draw_texture_rect(_stylized_ground(), play, false)
	# QUADRANT tint: a faint wash of each zone's colour over its open cells, so the four
	# districts read apart at a glance (orientation is a skill — callouts like "the rust
	# quarter" need the quarters to actually look different).
	if zone_ground_tint_alpha > 0.0:
		for row in _rows():
			for col in _cols():
				if _is_solid(col, row):
					continue
				var zone := _cell_zone(col, row)
				if zone == Zone.HUB:
					continue  # the hub keeps the plain sand — it's the neutral centre
				var tint := _zone_floor_color(zone)
				tint.a = zone_ground_tint_alpha
				draw_rect(_cell_rect(col, row), tint, true)
	# Central plaza decal — a lighter paved circle to anchor the eye.
	var centre := _fountain_center() if _has_fountain() else Vector2.ZERO
	draw_circle(centre, 360.0, Color(sand_light.r, sand_light.g, sand_light.b, 0.55))
	draw_arc(centre, 360.0, 0.0, TAU, 64, Color(0.58, 0.52, 0.38, 0.6), 4.0)
	# A lighter paved band across the central horizontal avenue, so the main street reads as a
	# paved road rather than more open sand (floor variety, like the reference's streets).
	var pave := sand_light.lightened(0.12)
	pave.a = 0.45
	var avenue := _cell_rect(0, _center_row())
	draw_rect(Rect2(Vector2(-play_half_width, avenue.position.y), Vector2(2 * play_half_width, avenue.size.y)), pave, true)
	# The canal feeding the fountain (drawn on the ground, under the buildings/fountain).
	_draw_canal_and_bridges()
	# ALLEY floors: darker paving under each roofed cut-through, so the passage reads as a
	# covered walkway when its roof fades for the player standing inside it.
	for row in _rows():
		for col in _cols():
			if _is_alley(col, row):
				var alley_rect := _cell_rect(col, row)
				draw_rect(alley_rect, alley_floor_color, true)
				draw_rect(alley_rect, alley_floor_color.darkened(0.25), false, 2.0)
	# Buildings as solid extruded blocks with PER-BUILDING colour + height (see _building_styles).
	# Drawn in passes so adjacent cells of one building merge cleanly: shadows, side faces, roofs,
	# then per-building roof detail (lit top edge + an overhang shadow on the front edge).
	var styles := _building_styles()
	for row in _rows():
		for col in _cols():
			if _is_building(col, row):
				var r := _cell_rect(col, row)
				draw_rect(Rect2(r.position + block_shadow_offset, r.size), Color(0, 0, 0, 0.18), true)
	for row in _rows():
		for col in _cols():
			if _is_building(col, row):
				draw_rect(_cell_rect(col, row), styles[Vector2i(col, row)]["side"], true)
	for row in _rows():
		for col in _cols():
			if _is_building(col, row):
				var style: Dictionary = styles[Vector2i(col, row)]
				var r := _cell_rect(col, row)
				var h: float = style["height"]
				draw_rect(Rect2(r.position + Vector2(0, -h), r.size), style["roof"], true)
	# Roof detail per cell: a lit edge where the roof is exposed to the sky above, an OVERHANG
	# shadow cast on the ground below a building's front (south) edge — the bit assassins hide
	# under — and a faint ridge seam so the roof reads as tiled, not a flat colour fill.
	for row in _rows():
		for col in _cols():
			if not _is_building(col, row):
				continue
			var style2: Dictionary = styles[Vector2i(col, row)]
			var r2 := _cell_rect(col, row)
			var h2: float = style2["height"]
			var roof2: Color = style2["roof"]
			if not _building_at(col, row - 1):  # open sky above → bright top lip
				draw_rect(Rect2(r2.position + Vector2(0, -h2), Vector2(r2.size.x, 6.0)), roof2.lightened(0.22), true)
			if not _building_at(col, row + 1):  # open ground below → overhang shadow on the street
				draw_rect(Rect2(Vector2(r2.position.x, r2.end.y), Vector2(r2.size.x, 14.0)), Color(0, 0, 0, 0.22), true)
			# ridge seam across the roof (subtle tiling tell)
			var ridge_y := r2.position.y - h2 + r2.size.y * 0.5
			draw_line(Vector2(r2.position.x + 4, ridge_y), Vector2(r2.end.x - 4, ridge_y), Color(0, 0, 0, 0.10), 2.0)
	_draw_fountain()


# The CANAL: a narrow water channel running up the map's central avenue from the bottom water
# margin to the fountain (so the water visibly "feeds" the fountain), with a couple of plank
# bridges crossing it near the bottom. Purely visual — it sits on the open central road, so it
# never changes navigation or collision (you walk the avenue and cross on the bridges).
func _draw_canal_and_bridges() -> void:
	# WATER cells (solid — collision matches this exactly, so what looks like water IS water).
	for row in _rows():
		for col in _cols():
			if _is_water(col, row):
				var r := _cell_rect(col, row)
				draw_rect(r, water_color, true)
				draw_rect(r, water_color.darkened(0.30), false)  # darker stone edge
				var y: float = r.position.y + 18.0
				while y < r.end.y - 8.0:  # ripple lines
					draw_line(Vector2(r.position.x + r.size.x * 0.18, y), Vector2(r.end.x - r.size.x * 0.18, y), water_color.lightened(0.28), 2.0)
					y += 22.0
	# BRIDGE cells (walkable planks crossing the canal).
	for row in _rows():
		for col in _cols():
			if _is_bridge(col, row):
				_draw_bridge_cell(_cell_rect(col, row))


# One plank-deck bridge filling a bridge cell, with plank seams.
func _draw_bridge_cell(r: Rect2) -> void:
	draw_rect(r, bridge_color, true)
	draw_rect(r, bridge_color.darkened(0.4), false)
	var y: float = r.position.y + 8.0
	while y < r.end.y - 4.0:
		draw_line(Vector2(r.position.x + 3.0, y), Vector2(r.end.x - 3.0, y), bridge_color.darkened(0.3), 2.0)
		y += 14.0


# Group connected building cells and give each group ONE stable (hashed) roof colour + height,
# so a multi-cell building reads as a single block and the town gets roof-to-roof variety. Cached.
func _building_styles() -> Dictionary:
	if not _building_style_cache.is_empty():
		return _building_style_cache
	var visited := {}
	for row in _rows():
		for col in _cols():
			if not _is_building(col, row) or visited.has(Vector2i(col, row)):
				continue
			# Flood-fill this one connected building (4-directional).
			var group: Array[Vector2i] = []
			var stack: Array[Vector2i] = [Vector2i(col, row)]
			visited[Vector2i(col, row)] = true
			while not stack.is_empty():
				var cell: Vector2i = stack.pop_back()
				group.append(cell)
				for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nb := cell + off
					if nb.x < 0 or nb.x >= _cols() or nb.y < 0 or nb.y >= _rows():
						continue
					if visited.has(nb) or not _is_building(nb.x, nb.y):
						continue
					visited[nb] = true
					stack.append(nb)
			# Stable per-building style from a hash of its anchor cell. QUADRANT BIAS: most
			# buildings in a quarter take that quarter's signature roof colour (NW terracotta,
			# NE slate, SW ochre, SE grey); the rest stay hash-random so no quarter is uniform.
			var anchor: Vector2i = group[0]
			var roof: Color
			if _hash01(anchor.x * 7 + anchor.y * 23 + 11) < zone_roof_bias:
				roof = _zone_roof_color(_cell_zone(anchor.x, anchor.y))
			else:
				roof = _roof_palette_color(_hash01(anchor.x * 31 + anchor.y * 17 + 7))
			var height: float = block_height * lerpf(0.7, 1.5, _hash01(anchor.x * 13 + anchor.y * 29 + 3))
			var style := {"roof": roof, "side": roof.darkened(0.42), "height": height}
			for cell in group:
				_building_style_cache[cell] = style
	return _building_style_cache


# Each quarter's signature roof colour, picked from the palette by index (safe on any
# palette size). NW=terracotta(1), NE=slate(3), SW=ochre(4), SE=weathered grey(2), HUB=tan(0).
func _zone_roof_color(zone: Zone) -> Color:
	if roof_palette.is_empty():
		return block_roof
	var index := 0
	match zone:
		Zone.NW: index = 1
		Zone.NE: index = 3
		Zone.SW: index = 4
		Zone.SE: index = 2
		_: index = 0
	return roof_palette[index % roof_palette.size()]


# Pick a roof colour from the palette by a 0..1 hash (falls back to block_roof if the palette is empty).
func _roof_palette_color(h: float) -> Color:
	if roof_palette.is_empty():
		return block_roof
	return roof_palette[int(h * roof_palette.size()) % roof_palette.size()]


# === drawing ===============================================================
func _draw() -> void:
	if stylized_render:
		_draw_stylized()
		return
	var ox := play_half_width + solid_clearance
	var oy := play_half_height + solid_clearance
	draw_rect(Rect2(Vector2(-ox, -oy), Vector2(2 * ox, 2 * oy)), exposed_color, true)
	# Per-zone floor: fill each OPEN cell with its zone's colour so the four corners
	# read at a glance (the four-colour quarters from the concept).
	for row in _rows():
		for col in _cols():
			if _is_solid(col, row):
				continue
			draw_rect(_cell_rect(col, row), _zone_floor_color(_cell_zone(col, row)), true)
	for zone in _density_zones:
		draw_rect(zone, density_color, true)
	_draw_grid()
	for rect in _building_rects():
		draw_rect(rect, building_color, true)
	for rect in _outer_wall_rects():
		draw_rect(rect, wall_color, true)
	_draw_fountain()


# Draws the central fountain on TOP of the plaza floor: a stone basin ring, water
# inside, a soft rim highlight, and a little central spout — a landmark to orient by.
func _draw_fountain() -> void:
	if not _has_fountain():
		return
	var c := _fountain_center()
	draw_circle(c, fountain_radius, fountain_stone_color)
	draw_circle(c, fountain_radius * 0.72, fountain_water_color)
	draw_arc(c, fountain_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.25), 4.0)
	draw_circle(c, fountain_radius * 0.18, fountain_stone_color)


# === OVERHANG concealment (master_plan §8 cover) ==========================
# Build (once) the overhead concealment overlay and point it at the LOCAL player. Safe to call the
# moment the local player is known (online) or right after they spawn (offline). No-op unless
# enable_overhangs. The overlay draws above players (z 500) with flat placeholder roof colours.
func setup_roof_overlay(local_player: Node2D) -> void:
	if not enable_overhangs:
		return
	if _roof_overlay == null:
		_roof_overlay = RoofOverlay.new()
		_roof_overlay.name = "RoofOverlay"
		add_child(_roof_overlay)
		for r in overhang_rects():
			_roof_overlay.add_overhang(r)  # no texture → flat placeholder clay roof
		for r in alley_rects():
			_roof_overlay.add_alley(r)      # roofed secret passages (same shadow-cover behaviour)
	if local_player != null:
		_roof_overlay.set_local_player(local_player)


# The overhang cover zones: for every BUILDING cell, a roof lip reaching over the adjacent WALKABLE
# street cell on the side facing the MAP CENTRE (so cover hangs inward over the streets). Each zone is
# the near strip of that street cell, right against the building.
func overhang_rects() -> Array:
	var rects: Array = []
	if not enable_overhangs:
		return rects
	var cc := _center_col()
	var cr := _center_row()
	var depth := 0.5  # how far the overhang reaches into the street (fraction of a cell)
	for row in _rows():
		for col in _cols():
			if not _is_building(col, row):
				continue
			# Thin out overhangs near the map border — less cover at the edges, more toward the centre.
			if mini(mini(col, _cols() - 1 - col), mini(row, _rows() - 1 - row)) < overhang_border_margin:
				continue
			var dx := signi(cc - col)  # horizontal step toward the centre
			var dy := signi(cr - row)  # vertical step toward the centre
			if dx != 0 and _is_walkable_cell(col + dx, row):
				rects.append(_overhang_strip(col + dx, row, -dx, 0, depth))
			if dy != 0 and _is_walkable_cell(col, row + dy):
				rects.append(_overhang_strip(col, row + dy, 0, -dy, depth))
	return rects


# The roofed ALLEY cut-through cells (secret passages carved through buildings) as world-space rects.
func alley_rects() -> Array:
	var rects: Array = []
	for row in _rows():
		for col in _cols():
			if _is_alley(col, row):
				rects.append(_cell_rect(col, row))
	return rects


# In-bounds AND not solid — a walkable cell an actor can stand in (and thus under an overhang).
func _is_walkable_cell(col: int, row: int) -> bool:
	if col < 0 or col >= _cols() or row < 0 or row >= _rows():
		return false
	return not _is_solid(col, row)


# The near strip of a street cell against the building. (bdx/bdy point FROM the street TO the building;
# `depth` = fraction of the cell the overhang covers.) Returns the world-space Rect2.
func _overhang_strip(street_col: int, street_row: int, bdx: int, bdy: int, depth: float) -> Rect2:
	var cell := _cell_rect(street_col, street_row)
	var pos := cell.position
	var size := cell.size
	if bdx > 0:
		pos.x = cell.position.x + cell.size.x * (1.0 - depth)
		size.x = cell.size.x * depth
	elif bdx < 0:
		size.x = cell.size.x * depth
	if bdy > 0:
		pos.y = cell.position.y + cell.size.y * (1.0 - depth)
		size.y = cell.size.y * depth
	elif bdy < 0:
		size.y = cell.size.y * depth
	return Rect2(pos, size)


# Spawn an AccessPoint node at each rooftop-stair / sewer-entrance location. They draw
# their own marker (orange ▲ / green grate) and join the "access_point" group so a nearby
# player can use them (the layer mechanics live on the player + LayerComponent, §7.2).
func _spawn_access_points() -> void:
	# Index them in a fixed order so the same point has the same id on every peer (the online
	# match replicates claim/cooldown by this index — buildplan §7.3).
	var index := 0
	for pos in _rooftop_stairs:
		_make_access_point(pos, AccessPoint.Kind.ROOFTOP_STAIR, index)
		index += 1
	for pos in _sewer_entrances:
		_make_access_point(pos, AccessPoint.Kind.SEWER_ENTRANCE, index)
		index += 1


func _make_access_point(pos: Vector2, kind: int, index: int) -> void:
	var point := AccessPoint.new()
	point.position = pos
	point.kind = kind
	point.access_index = index
	point.name = "AccessPoint%d" % index  # deterministic name → matches across peers
	add_child(point)


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
