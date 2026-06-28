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
## Global lockout (seconds): once ANYONE uses this point, nobody can use it again until
## this elapses — so it can't be camped/chained during a chase (buildplan §7.3).
@export var global_cooldown: float = 15.0
## Committed exposure paid to CLAIM this point for the rest of the match (note 5b: 20%).
@export var claim_exposure_cost: float = 20.0
@export var rooftop_color: Color = Color(0.91, 0.56, 0.18)   # orange ▲
@export var sewer_color: Color = Color(0.30, 0.62, 0.36)     # green grate
@export var claimed_ring_color: Color = Color(1.0, 0.85, 0.2)

## Seconds left on the global lockout (0 = ready). Ticks down in _process.
var _cooldown_remaining: float = 0.0
## Who owns this point for the match (0 = unclaimed). Offline: a player_id; the owner is
## the only one who may use it once claimed.
var _owner_id: int = 0
## Stable id set by the map (points are built in the same order on every peer), so the host
## can tell each client which point changed over the network (buildplan §7.3, online).
var access_index: int = -1

## Past-tense, emitted ONLY on the host when this point is claimed / its lockout starts, so
## OnlineMatch can replicate the new state to every client. Offline nobody listens.
signal claim_changed(owner_id: int)
signal cooldown_started()


func _ready() -> void:
	add_to_group("access_point")
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
		queue_redraw()


func is_rooftop_stair() -> bool:
	return kind == Kind.ROOFTOP_STAIR

func is_sewer_entrance() -> bool:
	return kind == Kind.SEWER_ENTRANCE


# Can `user_id` use this right now? Off cooldown AND (unclaimed OR claimed by them).
func is_available_to(user_id: int) -> bool:
	if _cooldown_remaining > 0.0:
		return false
	return _owner_id == 0 or _owner_id == user_id

func is_claimed() -> bool:
	return _owner_id != 0

# Start the global lockout (called the moment anyone uses the point).
func mark_used() -> void:
	_cooldown_remaining = global_cooldown
	queue_redraw()
	cooldown_started.emit()

# Claim for the rest of the match. The caller pays the exposure; we just record the owner.
func claim(user_id: int) -> void:
	_owner_id = user_id
	queue_redraw()
	claim_changed.emit(user_id)


# Client-side: apply the host's authoritative claim/lockout WITHOUT re-emitting (the signals
# are the host's broadcast trigger; re-emitting on a client would loop). OnlineMatch calls
# these from the replication RPCs.
func apply_claim_replicated(owner_id: int) -> void:
	_owner_id = owner_id
	queue_redraw()

func apply_cooldown_replicated() -> void:
	_cooldown_remaining = global_cooldown
	queue_redraw()


func _draw() -> void:
	# Dim while on cooldown so you can see at a glance that it's locked out.
	var dim: float = 0.4 if _cooldown_remaining > 0.0 else 1.0
	if kind == Kind.ROOFTOP_STAIR:
		var s := 30.0
		var apex := Vector2(0.0, -s)
		var left := Vector2(-s * 0.9, s * 0.7)
		var right := Vector2(s * 0.9, s * 0.7)
		draw_colored_polygon(PackedVector2Array([apex, left, right]), Color(rooftop_color, dim))
		draw_polyline(PackedVector2Array([apex, left, right, apex]), Color(0, 0, 0, 0.6 * dim), 3.0)
	else:
		draw_circle(Vector2.ZERO, 26.0, Color(sewer_color, dim))
		draw_arc(Vector2.ZERO, 26.0, 0.0, TAU, 20, Color(0, 0, 0, 0.5 * dim), 3.0)
		for offset in [-12.0, 0.0, 12.0]:
			draw_line(Vector2(offset, -18.0), Vector2(offset, 18.0), Color(0.05, 0.15, 0.08, dim), 4.0)
	# A bright ring marks a point someone has claimed for the match (note 5b).
	if is_claimed():
		draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 28, claimed_ring_color, 3.0)

	# While locked out, draw the whole-seconds countdown over the marker so a player can see
	# exactly when it comes back up (not just that it's dimmed). _process redraws each frame.
	if _cooldown_remaining > 0.0:
		_draw_cooldown_seconds(_cooldown_remaining)


# Shared helper: draw the remaining whole seconds, centred, with a dark outline for legibility.
func _draw_cooldown_seconds(seconds: float) -> void:
	var font := ThemeDB.fallback_font
	var font_size := 26
	var text := str(int(ceil(seconds)))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	var pos := Vector2(-width * 0.5, font_size * 0.35)  # roughly centred on the marker
	# Cheap outline: draw the text offset in black 4 ways, then white on top.
	for offset in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		draw_string(font, pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 1))
