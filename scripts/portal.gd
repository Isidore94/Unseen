extends Area2D
class_name Portal

# Portal — UNSEEN, Phase 3 (master_plan §8). One reusable "step here, appear over
# there" mechanic that powers ALL the map-control travel features:
#   - teleporter pads      (cross-map, exposure cost)
#   - trapdoors            (a quick escape hop, small exposure tell)
#   - underground passages (free traversal — pure map knowledge)
# They differ only in range, colour, and exposure cost — all set when spawned.
#
# HOW IT WORKS: each portal is linked to a partner. Step onto one and you're moved
# to the partner (and pay any exposure cost). To stop you instantly bouncing back,
# the partner ignores you until you walk off it.

## Exposure added when a player uses this portal (0 = free, e.g. an underground
## passage; higher for teleporters — a permanent commitment via the kill/tool door).
@export var exposure_cost: float = 0.0

## Visual colour of the pad.
@export var portal_color: Color = Color(0.2, 0.8, 0.85, 0.85)

## Radius of the pad (also its trigger size), in pixels.
@export var portal_radius: float = 50.0

## Global lockout (seconds) after any use, shared by BOTH ends of the pair, so a
## teleporter can't be chained during a chase (buildplan §7.3). 0 = always ready
## (free passages stay spammable; the map sets 15s only on the teleporter pair).
@export var global_cooldown: float = 0.0

## The partner portal you travel to. Set by whoever spawns the pair.
var link: Portal = null

## Bodies that JUST arrived here — ignored until they step off (stops the bounce).
var _arrivals: Array = []

## Seconds left on the shared lockout (0 = ready).
var _cooldown_remaining: float = 0.0


func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
		queue_redraw()


func _ready() -> void:
	# Join "portal" so the online match can find every pad and switch teleporting OFF
	# on clients — only the host (referee) may move a body through a portal.
	add_to_group("portal")
	collision_layer = 0
	collision_mask = 2  # detect the "player" physics layer (players are layer 2)
	monitoring = true
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = portal_radius
	collision.shape = shape
	add_child(collision)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if link == null or body in _arrivals:
		return
	if not body.is_in_group("player"):
		return  # only players travel; the crowd never teleports
	if _cooldown_remaining > 0.0:
		return  # on global lockout — can't use it again yet (buildplan §7.3)

	# Pay the exposure cost (teleporters/trapdoors raise it; passages are free).
	if exposure_cost > 0.0:
		var exposure := body.get_node_or_null("ExposureComponent") as ExposureComponent
		if exposure != null:
			exposure.add_exposure(exposure_cost, "portal")

	link.receive(body)
	_start_cooldown()
	link._start_cooldown()


# Begin the shared lockout on this pad (called on both ends after a trip).
func _start_cooldown() -> void:
	if global_cooldown > 0.0:
		_cooldown_remaining = global_cooldown
		queue_redraw()


# Called by the partner portal to place an arriving body here without it
# immediately triggering us back.
func receive(body: Node2D) -> void:
	if not _arrivals.has(body):
		_arrivals.append(body)
	body.global_position = global_position


func _on_body_exited(body: Node2D) -> void:
	_arrivals.erase(body)


func _draw() -> void:
	# Dim while on the shared cooldown so you can see it's locked out.
	var dim: float = 0.4 if _cooldown_remaining > 0.0 else 1.0
	var fill := portal_color
	fill.a *= dim
	draw_circle(Vector2.ZERO, portal_radius, fill)
	draw_arc(Vector2.ZERO, portal_radius, 0.0, TAU, 32, Color(1, 1, 1, 0.5 * dim), 2.0)

	# While locked out, draw the whole-seconds countdown over the pad so a player can see exactly
	# when it comes back up. _process redraws each frame while the cooldown ticks down.
	if _cooldown_remaining > 0.0:
		var font := ThemeDB.fallback_font
		var font_size := 26
		var text := str(int(ceil(_cooldown_remaining)))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
		var pos := Vector2(-width * 0.5, font_size * 0.35)
		for offset in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
			draw_string(font, pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.9))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 1))
