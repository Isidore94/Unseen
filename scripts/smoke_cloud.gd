extends Node2D
class_name SmokeCloud

# A deployed SMOKE cloud (UNSEEN tools, master_plan §9). It is purely a WORLD MARKER + a visual:
# it puffs out, lingers, and dissipates, then frees itself. It NEVER decides outcomes — the
# AUTHORITY (the host online / the offline match) reads the "smoke_cloud" group each frame and
# STUNS anyone standing inside (Principle #1: visuals/markers don't own gameplay logic).
#
# It exists on every machine (the host spawns it for everyone) so all players SEE the cloud — that
# is fine and intended: smoke is a loud, public effect, not a hidden one.

## Cloud reach in world px and how long it lingers (set by the deployer via setup()).
@export var radius: float = 110.0
@export var lifetime: float = 4.5
## How long anyone caught inside stays stunned. Set by the deployer right after spawn — MUST exist
## as a real property so `set("stun_seconds", …)` / `get("stun_seconds")` work (a missing var made
## get() return null → float(null) crashed the stun loop).
@export var stun_seconds: float = 3.0
## The peer who deployed it — immune to their own cloud. 0 = nobody (offline / the deployer is local).
var owner_peer: int = 0

var _age: float = 0.0
var _puffs: Array[Vector2] = []   # stable unit offsets so the cloud doesn't shimmer each frame


func _ready() -> void:
	add_to_group("smoke_cloud")
	z_index = 50  # above the ground, well below the HUD layers
	# A handful of fixed puff centres (unit circle) for a soft, non-uniform cloud shape.
	for i in 7:
		var a := TAU * float(i) / 7.0
		_puffs.append(Vector2(cos(a), sin(a)) * 0.55)
	set_process(true)


# Called right after spawning to place + size the cloud and record its deployer.
func setup(world_pos: Vector2, cloud_radius: float, life: float, deployer_peer: int) -> void:
	global_position = world_pos
	radius = cloud_radius
	lifetime = life
	owner_peer = deployer_peer


# The cloud grows quickly for the first 0.4s, then holds at full size.
func current_radius() -> float:
	return radius * lerpf(0.35, 1.0, clampf(_age / 0.4, 0.0, 1.0))


# Is `point` inside the cloud right now? (The authority's stun check uses this.)
func contains(point: Vector2) -> bool:
	return global_position.distance_to(point) <= current_radius()


# Seconds of cloud left. The stun is capped by this so it can never outlast the visible cloud.
func remaining() -> float:
	return maxf(0.0, lifetime - _age)


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var r := current_radius()
	# Fade the whole cloud out over its final second.
	var alpha := clampf((lifetime - _age) / 1.0, 0.0, 1.0) * 0.8
	var body := Color(0.84, 0.86, 0.9, alpha)
	draw_circle(Vector2.ZERO, r, Color(body.r, body.g, body.b, alpha * 0.45))  # soft core
	for puff in _puffs:
		draw_circle(puff * r, r * 0.5, body)
