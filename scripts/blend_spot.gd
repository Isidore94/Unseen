extends Node2D
class_name BlendSpot

# BlendSpot — UNSEEN. A visible "hide here" zone (a haystack / blend-group / bench equivalent). Stand
# in it and stay still to BLEND: your exposure bleeds off fast and a kill from here is a BLEND KILL.
# Purely a marker — the HOST owns the actual blend check from the replicated spot positions.

## Radius of the zone (matches OnlineMatch.blend_radius so what you see is what blends).
@export var radius: float = 90.0
## Fill + ring colours (a soft straw/haystack tone that reads as cover, not a threat).
@export var fill_color: Color = Color(0.85, 0.74, 0.4, 0.16)
@export var ring_color: Color = Color(0.85, 0.74, 0.4, 0.55)


func _ready() -> void:
	z_index = -1  # a ground decal, drawn under the characters


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, fill_color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, ring_color, 2.0, true)
