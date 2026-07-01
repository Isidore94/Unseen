extends Node2D
class_name RoofOverlay

# RoofOverlay — UNSEEN, CITADEL map (ART_PIPELINE.md §10.2/§10.3). Draws building ROOFS above the player,
# and owns the citadel's CONCEALMENT ZONES — overhangs and alley cut-throughs — which work like SHADOWS:
#
#   A concealment zone is a roof (an OVERHANG reaching over a street cell, or the roof over an ALLEY cut
#   through a building) that is drawn ON TOP of the characters and is FULLY OPAQUE. So on everyone ELSE's
#   screen it completely HIDES whoever is standing under it — you vanish into it like stepping into shadow.
#   On YOUR OWN screen, the moment your player is actually under it, it fades translucent so you can see
#   what's going on around you — and it snaps back to opaque the instant you step out.
#
# WHY THIS IS SAFE (and why the fade is LOCAL-ONLY): each machine runs its own RoofOverlay for its own
# player. Your zone fades only for YOU (your player is under it); on an opponent's machine that same zone
# stays opaque, hiding you. So the reveal can never be used to see or track an opponent — it only ever
# opens your own view of a zone you personally occupy. Purely visual (Aaron: no exposure/detection effect).
#
# It works TODAY with flat placeholder colours (test the hide/reveal feel before any PixelLab art exists)
# and takes real tile textures later via the same add_* calls — nothing else changes.
#
# WIRING (from the map, e.g. test_map_01.gd): make one RoofOverlay high in the tree, set_local_player(you),
# then add each building's roof + its inward-facing overhang(s) + any alley as world-space Rect2s (the map
# knows each cell's rect via _cell_rect). Overhangs face the map centre — see the sketch generator.

## Placeholder roof colour until a real tile texture is supplied (locked clay-roof tone #b08a5e).
@export var placeholder_roof_color: Color = Color("b08a5e")
## Soft shadow an OVERHANG casts onto the ground just past the building edge — sells the "roof reaches out
## and shades this spot" read even when nobody is under it.
@export var overhang_shadow_color: Color = Color(0.0, 0.0, 0.0, 0.22)
## Roof opacity of a concealment zone while YOUR player is under it (the see-out reveal). Low = see-through.
@export var cover_revealed_alpha: float = 0.16
## Roof opacity of a concealment zone when your player is NOT under it — FULLY opaque so it hides others.
@export var cover_hidden_alpha: float = 1.0
## How fast a zone fades between hidden/revealed (per second, feeds lerp). Higher = snappier.
@export var cover_fade_speed: float = 10.0
## World-px slack around a zone that still counts as "under it". Small on purpose — it should reveal only
## when you are ACTUALLY under the roof, not merely near the mouth. Tune to the cell size.
@export var cover_enter_margin: float = 10.0

## ROOF = a building top (nobody stands under it → always opaque). OVERHANG / ALLEY = concealment zones
## (the "shadow" cover that hides others and reveals to you when you're under it).
enum Kind { ROOF, OVERHANG, ALLEY }

## The player THIS machine controls. ONLY their position reveals a zone (keeps the reveal local + safe).
var _local_player: Node2D = null

## Every overhead section. One dictionary per section:
##   {rect:Rect2, texture:Texture2D|null, kind:int, alpha:float, target_alpha:float}
## `alpha` is the live (animated) opacity; `target_alpha` is where a concealment zone is lerping to.
var _sections: Array[Dictionary] = []


func _ready() -> void:
	# Draw ABOVE everything in the world so roofs cover the player. z_as_relative off + a high z_index
	# keeps this overlay on top regardless of the map/players' own Y-sort ordering.
	z_as_relative = false
	z_index = 500


# Tell the overlay which body is the local player — only this one reveals a concealment zone, so the
# see-out can never expose where an OPPONENT is. Call once after the local player spawns.
func set_local_player(player: Node2D) -> void:
	_local_player = player


# Add a plain building ROOF (drawn over the footprint, always opaque). `texture` null = flat placeholder.
func add_roof(world_rect: Rect2, texture: Texture2D = null) -> void:
	_add_section(world_rect, texture, Kind.ROOF)


# Add a walkable OVERHANG concealment zone (a roof lip over a street cell). Leave that cell walkable in
# the map/nav — the roof is visual cover only, no collision underneath.
func add_overhang(world_rect: Rect2, texture: Texture2D = null) -> void:
	_add_section(world_rect, texture, Kind.OVERHANG)


# Add an ALLEY concealment zone (roof over a passable cut-through). Same shadow behaviour as an overhang.
func add_alley(world_rect: Rect2, texture: Texture2D = null) -> void:
	_add_section(world_rect, texture, Kind.ALLEY)


# Drop every section (e.g. when rebuilding the map / changing arenas).
func clear_sections() -> void:
	_sections.clear()
	queue_redraw()


# A concealment zone (hides others / reveals to you). Roofs proper are NOT — they're always opaque.
func _is_cover(kind: int) -> bool:
	return kind == Kind.OVERHANG or kind == Kind.ALLEY


func _add_section(world_rect: Rect2, texture: Texture2D, kind: int) -> void:
	_sections.append({
		"rect": world_rect,
		"texture": texture,
		"kind": kind,
		"alpha": cover_hidden_alpha,        # everything starts opaque (fully hiding)
		"target_alpha": cover_hidden_alpha,
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
		if not _is_cover(int(section["kind"])):
			continue  # plain roofs never fade
		# Reveal ONLY while the local player is actually under this zone (small slack, not "nearby").
		var hit_rect: Rect2 = (section["rect"] as Rect2).grow(cover_enter_margin)
		var under := player_pos != Vector2.INF and hit_rect.has_point(player_pos)
		section["target_alpha"] = cover_revealed_alpha if under else cover_hidden_alpha
		# Ease current opacity toward the target so the reveal fades smoothly instead of snapping.
		var current := float(section["alpha"])
		var goal := float(section["target_alpha"])
		if not is_equal_approx(current, goal):
			section["alpha"] = lerpf(current, goal, clampf(cover_fade_speed * delta, 0.0, 1.0))
			needs_redraw = true
	if needs_redraw:
		queue_redraw()


func _draw() -> void:
	for section in _sections:
		var rect: Rect2 = section["rect"]
		var kind: int = int(section["kind"])
		var alpha: float = float(section["alpha"])
		# OVERHANG: a soft cast shadow first, so the spot reads as shaded cover even at full opacity.
		if kind == Kind.OVERHANG:
			draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), overhang_shadow_color, true)
		var texture: Texture2D = section["texture"]
		if texture != null:
			# Real tile art: tint carries the animated opacity (the reveal); tiled to fill the footprint.
			draw_texture_rect(texture, rect, true, Color(1, 1, 1, alpha))
		else:
			# Placeholder until PixelLab tiles land — flat clay colour at the section's opacity.
			var col := placeholder_roof_color
			col.a *= alpha
			draw_rect(rect, col, true)
