extends Node2D
class_name RoofOverlay

# RoofOverlay — UNSEEN, CITADEL map (ART_PIPELINE.md §10.2/§10.3). The layer that draws building ROOFS
# (and roof OVERHANGS and ALLEY cut-throughs) ABOVE the player, plus the two signature citadel mechanics:
#
#   • OVERHANG (cover): a roof edge that reaches out over a walkable street cell. It's drawn on top of
#     the player, with NO collision underneath (collision is the map's job), so you can duck under it and
#     an onlooker's clean top-down read of who's there is broken. Pure visual cover.
#   • ALLEY (cutaway): a roof over a passable alley cut through a building. When YOUR OWN player walks in,
#     that roof fades translucent so you can see yourself move through — like the interior reveals in AC /
#     top-down stealth games. It fades on the LOCAL player only (never on other bodies), so it can never
#     be used to spot or identify an opponent — hidden-identity stays intact (the §5 server rule in spirit).
#
# It works TODAY with flat placeholder colours (so you can test the overhang/alley feel before any PixelLab
# art exists) and takes real tile textures later via the same add_* calls — nothing else changes.
#
# HOW TO WIRE IT (from the map, e.g. test_map_01.gd): create one RoofOverlay, add it high in the tree,
# call set_local_player(your_player), then for each building add a roof/overhang/alley section as a world-
# space Rect2 (the map already knows each cell's rect via _cell_rect). See add_roof / add_overhang / add_alley.

## Placeholder roof colour used until a real tile texture is supplied (locked clay-roof tone #b08a5e).
@export var placeholder_roof_color: Color = Color("b08a5e")
## Soft shadow an OVERHANG casts onto the ground just past a building edge (sells the "roof reaches out").
@export var overhang_shadow_color: Color = Color(0.0, 0.0, 0.0, 0.18)
## Roof opacity when the local player is standing in an ALLEY (the cutaway). Lower = see-through-er.
@export var alley_faded_alpha: float = 0.16
## Roof opacity when nobody local is in the alley (normal, solid roof).
@export var alley_solid_alpha: float = 1.0
## How fast the alley roof fades in/out (per second, feeds lerp). Higher = snappier reveal.
@export var alley_fade_speed: float = 8.0
## Extra world-px margin around an alley rect that still counts as "inside" (so the fade starts as you
## reach the mouth, not only dead-centre). Tune to the cell size.
@export var alley_enter_margin: float = 24.0

## The three kinds of overhead section. ROOF = a building top. OVERHANG = a roof edge over walkable
## street (cover). ALLEY = a roof over a passable cut-through (fades for the local player).
enum Kind { ROOF, OVERHANG, ALLEY }

## The player THIS machine controls. Only their position drives the alley cutaway (identity-safe).
var _local_player: Node2D = null

## Every overhead section we draw. One dictionary per section:
##   {rect:Rect2, texture:Texture2D|null, kind:int, alpha:float, target_alpha:float}
## `alpha` is the live (animated) opacity; `target_alpha` is where it's lerping to (alleys only).
var _sections: Array[Dictionary] = []


func _ready() -> void:
	# Draw ABOVE everything in the world so roofs cover the player. z_as_relative off + a high z_index
	# keeps this overlay on top regardless of the map/players' own Y-sort ordering.
	z_as_relative = false
	z_index = 500


# Tell the overlay which body is the local player — only this one triggers the alley cutaway, so the
# reveal can never leak where an OPPONENT is. Call once after the local player spawns.
func set_local_player(player: Node2D) -> void:
	_local_player = player


# Add a plain building ROOF (drawn over the footprint, on top of the player). `texture` null = flat
# placeholder colour for now; pass a real tile texture later and it renders that instead.
func add_roof(world_rect: Rect2, texture: Texture2D = null) -> void:
	_add_section(world_rect, texture, Kind.ROOF)


# Add a walkable OVERHANG (cover): a roof edge over a street cell. Same drawing as a roof, plus a soft
# ground shadow. Remember: NO collision here — leave that cell walkable in the map/nav.
func add_overhang(world_rect: Rect2, texture: Texture2D = null) -> void:
	_add_section(world_rect, texture, Kind.OVERHANG)


# Add an ALLEY roof (cutaway): fades translucent while the LOCAL player is inside `world_rect`.
func add_alley(world_rect: Rect2, texture: Texture2D = null) -> void:
	_add_section(world_rect, texture, Kind.ALLEY)


# Drop every section (e.g. when rebuilding the map / changing arenas).
func clear_sections() -> void:
	_sections.clear()
	queue_redraw()


func _add_section(world_rect: Rect2, texture: Texture2D, kind: int) -> void:
	var start_alpha := alley_solid_alpha
	_sections.append({
		"rect": world_rect,
		"texture": texture,
		"kind": kind,
		"alpha": start_alpha,
		"target_alpha": start_alpha,
	})
	queue_redraw()


func _process(delta: float) -> void:
	if _sections.is_empty():
		return
	var needs_redraw := false
	var player_pos := Vector2.INF
	if _local_player != null and is_instance_valid(_local_player):
		player_pos = _local_player.global_position
	for section in _sections:
		if int(section["kind"]) != Kind.ALLEY:
			continue  # only alleys animate; roofs/overhangs are steady
		# Is the local player inside this alley (with a small entry margin)? If so, aim for see-through.
		var hit_rect: Rect2 = (section["rect"] as Rect2).grow(alley_enter_margin)
		var inside := player_pos != Vector2.INF and hit_rect.has_point(player_pos)
		section["target_alpha"] = alley_faded_alpha if inside else alley_solid_alpha
		# Ease the current opacity toward the target so the reveal fades smoothly instead of snapping.
		var current := float(section["alpha"])
		var goal := float(section["target_alpha"])
		if not is_equal_approx(current, goal):
			section["alpha"] = lerpf(current, goal, clampf(alley_fade_speed * delta, 0.0, 1.0))
			needs_redraw = true
	if needs_redraw:
		queue_redraw()


func _draw() -> void:
	for section in _sections:
		var rect: Rect2 = section["rect"]
		var kind: int = int(section["kind"])
		var alpha: float = float(section["alpha"])
		# OVERHANG: a soft shadow first, so the roof reads as reaching out over the ground below it.
		if kind == Kind.OVERHANG:
			var shadow := Rect2(rect.position + Vector2(3, 4), rect.size)
			draw_rect(shadow, overhang_shadow_color, true)
		var texture: Texture2D = section["texture"]
		if texture != null:
			# Real tile art: tint carries the animated alpha (alley fade); tiled to fill the footprint.
			draw_texture_rect(texture, rect, true, Color(1, 1, 1, alpha))
		else:
			# Placeholder until PixelLab tiles land — flat clay colour at the section's opacity.
			var col := placeholder_roof_color
			col.a *= alpha
			draw_rect(rect, col, true)
