extends Node
class_name KillComponent

# Kill — UNSEEN, Phase 3/4 (master_plan §6). "Aim & commit" targeting.
#
# THE LOOP (controller-first, no mouse needed):
#   1. You read the crowd and pick a SUSPECT — press the kill button to LOCK the
#      character you're facing / nearest in front of you.
#   2. You close in. The moment you're in range it RESOLVES on its own:
#        - if that suspect really is your valid target -> clean kill.
#        - if it was just a civilian -> you committed to the wrong person and pay
#          an exposure cost (a suspicious lunge at an innocent — acting is exposing).
#   3. If your suspect gets away (too far / out of view), the lock drops and you
#      have to read them again.
#
# This makes the kill about SUSSING OUT who your target is, not waiting on a ping.

## How close you must get to your locked suspect for the kill/whiff to resolve.
@export var kill_range: float = 90.0
## How far away you can LOCK a suspect from.
@export var prime_range: float = 520.0
## A suspect must be within this angle (degrees) of the way you're facing to lock.
@export var prime_cone_degrees: float = 70.0
## If your locked suspect gets this far away, you lose them and the lock drops
## (a stand-in for "left your screen" that works the same for both split players).
@export var lose_range: float = 800.0

## Permanent exposure when a real kill lands (your mark, or a real player).
@export var kill_exposure_spike: float = 30.0
## Permanent exposure when you kill the WRONG person (an innocent civilian NPC). Big on
## purpose: cutting down innocents is a glaring tell, and this is the downside that
## punishes spamming the kill button in a crowd.
@export var wrong_commit_exposure: float = 40.0

## Input action that locks/commits. Local co-op assigns each player their own.
@export var action_primary_action: String = "action_primary"
## Group of actors THIS killer may actually kill. Co-op: "killable_for_1/2".
@export var valid_target_group_name: String = "killable"

## Emitted each time a real kill lands (used by scoring).
signal kill_landed

## Emitted when a suspect lock is gained/lost, so the HUD can show "LOCKED".
signal lock_changed(is_locked: bool)

@onready var _body: CharacterBody2D = get_parent() as CharacterBody2D
@onready var _exposure: ExposureComponent = get_parent().get_node("ExposureComponent")

## The suspect we've locked (or null). We resolve on them when we get close.
var _primed: Node2D = null
## The way we're facing, used to pick "the one in front" when locking.
var _last_facing: Vector2 = Vector2.RIGHT

## Online only: true on the machine that locally controls this killer. When set, we
## send a kill REQUEST to the host instead of resolving the kill ourselves.
var _network_local_control: bool = false


# Called by the player on the machine that controls it, to switch this component into
# "ask the host" mode (MULTIPLAYER_PLAN.md §4 — the client never self-confirms a kill).
func enable_network_local_control() -> void:
	_network_local_control = true


func _physics_process(_delta: float) -> void:
	if _network_local_control:
		_network_kill_input()
		return

	if _body.velocity.length() > 5.0:
		_last_facing = _body.velocity.normalized()

	if Input.is_action_just_pressed(action_primary_action):
		_lock_suspect()

	_update_locked()


# ONLINE: pick who we mean locally (using the replicated crowd we can see), then ask
# the HOST to resolve it. We only fire when actually in range, for immediate feel.
func _network_kill_input() -> void:
	if _body.velocity.length() > 5.0:
		_last_facing = _body.velocity.normalized()

	if not Input.is_action_just_pressed(action_primary_action):
		return

	var suspect := _best_suspect_in_front()
	if suspect == null:
		return
	var distance := _body.global_position.distance_to(suspect.global_position)
	if distance > kill_range:
		return  # not close enough to commit (the host enforces this as well)

	_play_strike()  # instant local feedback; the host decides the actual outcome
	request_kill.rpc_id(1, suspect.get_path())


# HOST-ONLY: validate and resolve a kill request. Never trust the client — re-check
# that the sender controls this killer, the target is genuinely in range, and that it
# really is this player's mark. A wrong target costs exposure instead.
@rpc("any_peer", "call_local", "reliable")
func request_kill(target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	var effective_sender := sender_id if sender_id != 0 else multiplayer.get_unique_id()
	var controller := int(_body.get("controlling_peer_id"))
	if effective_sender != controller:
		return  # someone tried to kill on behalf of a player they don't control

	var target := get_node_or_null(target_path) as Node2D
	if target == null or target == _body or not is_instance_valid(target):
		return
	var distance := _body.global_position.distance_to(target.global_position)
	if distance > kill_range:
		return

	if target.is_in_group("player") or target.is_in_group("killable_for_%d" % controller):
		# A real player (always fair game) or your designated NPC mark — a clean kill.
		_exposure.add_exposure(kill_exposure_spike, "kill")
		kill_landed.emit()
		if target.has_method("die"):
			target.die()
	else:
		# An innocent civilian — they still die, but you take a HEAVY exposure hit.
		# This is the cost of a sloppy or spammed kill: cutting down the wrong person
		# lights you up for everyone.
		_exposure.add_exposure(wrong_commit_exposure, "innocent_kill")
		if target.has_method("die"):
			target.die()


# Lock the best suspect in front of us (any character — you might be wrong).
func _lock_suspect() -> void:
	var suspect := _best_suspect_in_front()
	if suspect != null:
		var was_unlocked := _primed == null
		_primed = suspect
		if was_unlocked:
			lock_changed.emit(true)


func _update_locked() -> void:
	if _primed == null:
		return
	# Lost them (dead, freed, or out of view).
	if not is_instance_valid(_primed) or (_primed.has_method("is_dead") and _primed.is_dead()):
		_clear_lock()
		return
	var distance: float = _body.global_position.distance_to(_primed.global_position)
	if distance > lose_range:
		_clear_lock()
		return
	# Close enough — resolve.
	if distance <= kill_range:
		_resolve_on(_primed)
		_clear_lock()


func _clear_lock() -> void:
	if _primed != null:
		_primed = null
		lock_changed.emit(false)


func _resolve_on(target: Node2D) -> void:
	_play_strike()
	if target.is_in_group("player") or target.is_in_group(valid_target_group_name):
		# A real player (always fair game) or your mark — clean kill (full permanent
		# spike). Count it before they die (killing a player ends the round).
		_exposure.add_exposure(kill_exposure_spike, "kill")
		kill_landed.emit()
		if target.has_method("die"):
			target.die()
	else:
		# An innocent civilian — they still die, but you take a HEAVY exposure hit
		# (the downside of a sloppy or spammed kill).
		_exposure.add_exposure(wrong_commit_exposure, "innocent_kill")
		if target.has_method("die"):
			target.die()


# Finds the best character to lock: roughly in front of us, within range, closest
# to our facing line. Returns null if there's nobody suitable in front.
func _best_suspect_in_front() -> Node2D:
	var space := _body.get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = prime_range
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, _body.global_position)
	query.collision_mask = 6  # player (layer 2) + npc (layer 4)
	query.collide_with_bodies = true

	var cos_limit: float = cos(deg_to_rad(prime_cone_degrees))
	var best: Node2D = null
	var best_score: float = -INF
	for result in space.intersect_shape(query, 48):
		var collider := result.get("collider") as Node2D
		if collider == null or collider == _body or not (collider is CharacterBody2D):
			continue
		var to_target: Vector2 = collider.global_position - _body.global_position
		var distance: float = to_target.length()
		if distance < 1.0:
			continue
		var alignment: float = (to_target / distance).dot(_last_facing)
		if alignment < cos_limit:
			continue  # not in front of us
		# Prefer suspects that are well in front and nearby.
		var score: float = alignment - (distance / prime_range) * 0.5
		if score > best_score:
			best_score = score
			best = collider
	return best


# A quick "strike" pop on our body so the resolve reads as an action. The visual
# drives its own pop/flash so it doesn't fight the per-frame bob & facing.
func _play_strike() -> void:
	var visual := _body.get_node_or_null("CharacterVisual")
	if visual != null and visual.has_method("play_strike"):
		visual.play_strike()
