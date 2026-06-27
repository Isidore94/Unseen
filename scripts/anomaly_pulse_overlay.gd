extends Node2D

# AnomalyPulseOverlay — UNSEEN, Phase 9 (9C earned-read) helper. Draws soft, fading rings at given
# WORLD positions for a short time, then clears itself. It highlights AREAS, never figures (the
# Pillar #1 guardrail): a faint zone that says "something here was acting like a player," not a
# marker on a sprite. Lives only on the machine that earned a pulse; created on demand by 9C.
# (Not under scripts/experiments/, so the experiment loader never mistakes it for an experiment.)

var _spots: Array = []        ## each: {"pos": Vector2 (world), "age": float}
var _life_seconds: float = 1.5
var _radius_px: float = 90.0


func _ready() -> void:
	z_index = 50  # draw the soft zones above the floor/crowd


# Show a fresh pulse over `positions` (world-space), each fading over `life_seconds`.
func show_spots(positions: Array, life_seconds: float, radius_px: float) -> void:
	_spots.clear()
	for p in positions:
		_spots.append({"pos": p, "age": 0.0})
	_life_seconds = maxf(0.1, life_seconds)
	_radius_px = radius_px
	queue_redraw()


func _process(delta: float) -> void:
	if _spots.is_empty():
		return
	var any_alive := false
	for s in _spots:
		s["age"] += delta
		if s["age"] < _life_seconds:
			any_alive = true
	queue_redraw()
	if not any_alive:
		_spots.clear()


func _draw() -> void:
	for s in _spots:
		var t := clampf(s["age"] / _life_seconds, 0.0, 1.0)
		var alpha := (1.0 - t) * 0.55
		if alpha <= 0.0:
			continue
		var local: Vector2 = s["pos"] - global_position
		draw_circle(local, _radius_px, Color(1.0, 0.9, 0.35, alpha * 0.22))         # soft fill
		draw_arc(local, _radius_px, 0.0, TAU, 40, Color(1.0, 0.85, 0.25, alpha), 3.0, true)  # ring
