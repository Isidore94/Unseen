extends Node2D

# Test map — UNSEEN, Phase 2. A greybox "plaza" for the crowd to live in.
#
# This script does two jobs for the greybox:
#   1. Draws the floor + a reference GRID, so you can actually SEE yourself moving
#      (a flat single-colour floor looks identical as you move — no landmarks).
#   2. Builds the NavigationPolygon (the "walkable floor plan" NPCs path on).
#
# WHAT NAVIGATION IS, in plain terms:
# NPCs (added next) don't move by physics like the player — they need a map of
# which ground is walkable so they can plot routes without crossing walls. In
# Godot that's a NavigationPolygon held by a NavigationRegion2D. We MEASURE the
# four walls and fill the gap between them, so resizing the walls auto-updates the
# walkable area — one source of truth, no second number to keep in sync (Principle #7).

## How far to keep the walkable floor back from the walls, in pixels, so NPCs
## don't try to stand half-inside a wall.
@export var nav_margin: float = 30.0

## Colour of the floor fill.
@export var floor_color: Color = Color(0.16, 0.16, 0.18, 1)

## Colour of the reference grid lines drawn on the floor.
@export var grid_color: Color = Color(0.24, 0.24, 0.29, 1)

## Distance between grid lines, in pixels. Bigger = fewer lines.
@export var grid_spacing: float = 200.0

@onready var navigation_region: NavigationRegion2D = $NavigationRegion2D


func _ready() -> void:
	_build_navigation()
	# Ask Godot to run _draw() once to paint the floor + grid (they don't change,
	# so we only need to draw them a single time).
	queue_redraw()


# _draw() is Godot's low-level "paint directly on screen" hook. Because this runs
# on the TestMap node itself, everything we paint here sits BEHIND the child nodes
# (the walls) and behind the player — exactly right for a floor.
func _draw() -> void:
	var area: Rect2 = _inner_bounds()

	# Solid floor fill first...
	draw_rect(area, floor_color, true)

	# ...then the grid lines on top of it. We start each set of lines at the first
	# multiple of grid_spacing inside the area, so the grid lines up tidily.
	var x: float = ceilf(area.position.x / grid_spacing) * grid_spacing
	while x <= area.end.x:
		draw_line(Vector2(x, area.position.y), Vector2(x, area.end.y), grid_color, 2.0)
		x += grid_spacing

	var y: float = ceilf(area.position.y / grid_spacing) * grid_spacing
	while y <= area.end.y:
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), grid_color, 2.0)
		y += grid_spacing


# Builds the walkable floor plan as a rectangle just inside the walls.
func _build_navigation() -> void:
	# Shrink the open area by the margin so agents keep clearance off the walls.
	var bounds: Rect2 = _inner_bounds().grow(-nav_margin)

	var nav_polygon: NavigationPolygon = NavigationPolygon.new()
	nav_polygon.vertices = PackedVector2Array([
		Vector2(bounds.position.x, bounds.position.y),  # top-left
		Vector2(bounds.end.x, bounds.position.y),       # top-right
		Vector2(bounds.end.x, bounds.end.y),            # bottom-right
		Vector2(bounds.position.x, bounds.end.y),       # bottom-left
	])
	nav_polygon.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation_region.navigation_polygon = nav_polygon


# The open rectangle BETWEEN the four walls (their inner faces) — the floor area.
func _inner_bounds() -> Rect2:
	var left_inner: float = _wall_rect($WallLeft).end.x
	var right_inner: float = _wall_rect($WallRight).position.x
	var top_inner: float = _wall_rect($WallTop).end.y
	var bottom_inner: float = _wall_rect($WallBottom).position.y
	return Rect2(
		Vector2(left_inner, top_inner),
		Vector2(right_inner - left_inner, bottom_inner - top_inner)
	)


# Returns a wall's rectangle (position + size) in the map's coordinates, read from
# its collision shape — so we always know exactly where each wall's edges are.
func _wall_rect(wall: StaticBody2D) -> Rect2:
	var collision: CollisionShape2D = wall.get_node("CollisionShape2D")
	var shape: RectangleShape2D = collision.shape
	var center: Vector2 = wall.position + collision.position
	return Rect2(center - shape.size / 2.0, shape.size)
