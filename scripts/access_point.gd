extends Node2D
class_name AccessPoint

# AccessPoint — a rooftop stair or a sewer entrance (buildplan.md §7.2). It is a passive
# WORLD MARKER: it draws itself and joins the "access_point" group so a nearby player can
# find and use it. The PLAYER owns the interaction (it knows its own input + current layer),
# so this node stays dumb — one responsibility (Principle #3).
#
# §7.3 mounts the claim/ownership + global-cooldown state on top of this same node.

enum Kind { ROOFTOP_STAIR, SEWER_ENTRANCE }

## What this access point does. The map sets it when it spawns the markers.
@export var kind: int = Kind.ROOFTOP_STAIR
## How close a player must be (px) to use it with `interact`.
@export var use_radius: float = 80.0
@export var rooftop_color: Color = Color(0.91, 0.56, 0.18)   # orange ▲
@export var sewer_color: Color = Color(0.30, 0.62, 0.36)     # green grate


func _ready() -> void:
	add_to_group("access_point")
	queue_redraw()


func is_rooftop_stair() -> bool:
	return kind == Kind.ROOFTOP_STAIR

func is_sewer_entrance() -> bool:
	return kind == Kind.SEWER_ENTRANCE


func _draw() -> void:
	if kind == Kind.ROOFTOP_STAIR:
		var s := 30.0
		var apex := Vector2(0.0, -s)
		var left := Vector2(-s * 0.9, s * 0.7)
		var right := Vector2(s * 0.9, s * 0.7)
		draw_colored_polygon(PackedVector2Array([apex, left, right]), rooftop_color)
		draw_polyline(PackedVector2Array([apex, left, right, apex]), Color(0, 0, 0, 0.6), 3.0)
	else:
		draw_circle(Vector2.ZERO, 26.0, sewer_color)
		draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 20, Color(0, 0, 0, 0.5), 3.0)
		for offset in [-12.0, 0.0, 12.0]:
			draw_line(Vector2(offset, -18.0), Vector2(offset, 18.0), Color(0.05, 0.15, 0.08), 4.0)
