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

## The partner portal you travel to. Set by whoever spawns the pair.
var link: Portal = null

## Bodies that JUST arrived here — ignored until they step off (stops the bounce).
var _arrivals: Array = []


func _ready() -> void:
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

	# Pay the exposure cost (teleporters/trapdoors raise it; passages are free).
	if exposure_cost > 0.0:
		var exposure := body.get_node_or_null("ExposureComponent") as ExposureComponent
		if exposure != null:
			exposure.add_exposure(exposure_cost, "portal")

	link.receive(body)


# Called by the partner portal to place an arriving body here without it
# immediately triggering us back.
func receive(body: Node2D) -> void:
	if not _arrivals.has(body):
		_arrivals.append(body)
	body.global_position = global_position


func _on_body_exited(body: Node2D) -> void:
	_arrivals.erase(body)


func _draw() -> void:
	draw_circle(Vector2.ZERO, portal_radius, portal_color)
	draw_arc(Vector2.ZERO, portal_radius, 0.0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
