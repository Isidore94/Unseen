extends Node
class_name BehaviorHistory

# BehaviorHistory — UNSEEN, Phase 9 SHARED INFRASTRUCTURE (PHASE_9_EXPERIMENTS.md §9C impl).
# A tiny rolling memory of an actor's recent "tells": did this character RUN, SHARP-TURN, KILL,
# or USE A TOOL in the last few seconds? Attached to any actor (player or NPC) that an experiment
# wants to read. It is NOT an experiment itself — it stores nothing useful until an experiment
# (9C earned-read, 9F behavioral-flag) attaches it and reads it. With no experiment on, it is
# never created, so the base game is untouched (the delete test, §1.4).
#
# WHY THIS EXISTS: 9C and 9F both ask the same question — "is this figure behaving like a player
# right now?" Rather than each re-deriving it, they share this one component. No experiment edits
# another; they just read this neutral record (§1.3).
#
# AUTHORITY: it records only on the HOST (the referee owns the true motion of every character),
# matching the server-authoritative model. Clients never need it — they only render cues the host
# sends. So recording is host-only and cheap (a few floats per physics frame).

## A speed (px/s) above which the actor counts as "running" for the run tell. NPCs walk at ~90,
## so this sits above that — only a genuine sprint (or a fleeing player) trips it.
@export var run_speed_threshold_px: float = 140.0
## A frame-to-frame heading change bigger than this (degrees) counts as a sharp turn.
@export var sharp_turn_threshold_degrees: float = 80.0

# The most recent time (on our own clock) each kind of tell happened. 0 = never. We keep them
# separate so a reader could weight them differently later, but most readers just want "any tell".
var _last_run_time: float = 0.0
var _last_turn_time: float = 0.0
var _last_kill_time: float = 0.0
var _last_tool_time: float = 0.0

## Our own match clock (seconds), advanced by delta. Avoids any wall-clock dependency and keeps
## "how long ago" math simple and self-contained.
var _clock: float = 0.0
var _last_direction: Vector2 = Vector2.ZERO
var _body: CharacterBody2D = null
var _record: bool = false  ## only true on the authority (host, or offline) — see _ready


# Attach a BehaviorHistory to `actor` if it doesn't already have one, and return it. The one entry
# point experiments use, so they never duplicate the wiring or fight over who created it (§1.3).
static func ensure_on(actor: Node) -> BehaviorHistory:
	if actor == null:
		return null
	var existing := actor.get_node_or_null("BehaviorHistory") as BehaviorHistory
	if existing != null:
		return existing
	var history := BehaviorHistory.new()
	history.name = "BehaviorHistory"
	actor.add_child(history)
	return history


func _ready() -> void:
	_body = get_parent() as CharacterBody2D
	# Record only where the truth lives: the host online, or anyone offline. A client copy stays
	# inert (it would only see interpolated puppets anyway).
	_record = (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()
	if not _record:
		return
	# Listen for discrete tells from the actor's own components, if it has them (NPCs don't).
	var kill := get_parent().get_node_or_null("KillComponent")
	if kill != null and kill.has_signal("kill_resolved"):
		kill.connect("kill_resolved", Callable(self, "_on_kill_resolved"))
	var item := get_parent().get_node_or_null("ItemComponent")
	if item != null and item.has_signal("tool_activated"):
		item.connect("tool_activated", Callable(self, "_on_item_activated"))


func _physics_process(delta: float) -> void:
	if not _record or _body == null:
		return
	_clock += delta
	var velocity: Vector2 = _body.velocity
	# Compare SQUARED speed against SQUARED thresholds so we skip the square root that
	# velocity.length() costs every physics frame on every NPC. (speed >= threshold) is
	# the same test as (speed*speed >= threshold*threshold), so the run/move gates are
	# unchanged — most frames now do zero sqrt.
	var speed_squared := velocity.length_squared()
	# The minimum speed (px/s) below which we treat the actor as "not really moving" and
	# skip the turn check. Squared so it compares directly against length_squared above.
	const MOVE_GATE_SPEED_PX := 5.0
	const MOVE_GATE_SPEED_PX_SQUARED := MOVE_GATE_SPEED_PX * MOVE_GATE_SPEED_PX  # 25.0
	if speed_squared >= run_speed_threshold_px * run_speed_threshold_px:
		_last_run_time = _clock
	if speed_squared > MOVE_GATE_SPEED_PX_SQUARED:
		# Only here — when the actor is genuinely moving — do we pay for the sqrt-based
		# normalize, because the turn check needs a real heading (a unit direction) to
		# measure a real angle. Below the move gate we never reach this, so most frames
		# cost no square root at all.
		var direction := velocity.normalized()
		if _last_direction != Vector2.ZERO:
			var turn_degrees := absf(rad_to_deg(direction.angle_to(_last_direction)))
			if turn_degrees > sharp_turn_threshold_degrees:
				_last_turn_time = _clock
		_last_direction = direction


func _on_kill_resolved(_killer: Node, _victim: Node, _was_valid: bool) -> void:
	_last_kill_time = _clock

func _on_item_activated(_item: int, _duration: float) -> void:
	_last_tool_time = _clock


# === what readers (9C / 9F) call ===========================================

# Did this actor produce ANY tell within the last `lookback_seconds`? This is the core "acting
# like a player" question both 9C and 9F ask.
func had_tell_within(lookback_seconds: float) -> bool:
	return _seconds_since_last_tell() <= lookback_seconds


# How many seconds since the most recent tell of any kind (a big number if none yet). Lets a
# reader fade a cue out as the tell ages.
func _seconds_since_last_tell() -> float:
	var most_recent := maxf(maxf(_last_run_time, _last_turn_time), maxf(_last_kill_time, _last_tool_time))
	if most_recent <= 0.0:
		return INF
	return _clock - most_recent
