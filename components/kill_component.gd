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
## Counter-stunning the player HUNTING you is more forgiving than a kill — you can turn and strike
## them from a bit further out (a deliberate skill window: spot your hunter early, punish the approach).
## TODO(AC): copy AC Rearmed's circle-width-around-the-player stun proximity instead of a flat radius.
@export var counter_stun_range: float = 160.0
## How far away you can LOCK a suspect from.
@export var prime_range: float = 520.0
## A suspect must be within this angle (degrees) of the way you're facing to lock.
@export var prime_cone_degrees: float = 70.0
## If your locked suspect gets this far away, you lose them and the lock drops
## (a stand-in for "left your screen" that works the same for both split players).
@export var lose_range: float = 800.0

## Permanent exposure when a real kill lands (your mark, or a real player). Tuned so your two NPC
## marks (2 × this) PLUS using both equipped abilities stays comfortably under 100 — leaving headroom
## that only EXTRA actions cross: running (recoverable) or a wrong-target kill (below). 2×22 = 44.
@export var kill_exposure_spike: float = 22.0
## Permanent exposure when you kill the WRONG person — an innocent civilian (e.g. one you mistook
## for your player target). Big on purpose: from a player's normal contract floor (~2 marks + 2
## abilities), one wrong-target kill pushes them over the 100 exposure cliff and lights them up.
@export var wrong_commit_exposure: float = 40.0

## After you kill an NPC (a crowd member — your NPC MARK, or an innocent you whiff on) you're locked
## out of BOTH killing and stunning for this long: a forced lay-low window so you can't chain-strike
## through the crowd. Killing or counter-stunning a real PLAYER (your prey / your hunter) never STARTS
## this cooldown — only NPC kills do. Host-authoritative. Unit: seconds.
@export var npc_kill_cooldown_seconds: float = 5.0

## Input action that locks/commits. Local co-op assigns each player their own.
@export var action_primary_action: String = "action_primary"
## Controller-friendly target lock: tap to switch the soft-lock to the next nearby character.
@export var cycle_action: String = "cycle_target"
## After a manual cycle, hold that lock this long before the auto soft-lock is allowed to re-snap.
@export var cycle_hold_seconds: float = 2.5
## Group of actors THIS killer may actually kill. Co-op: "killable_for_1/2".
@export var valid_target_group_name: String = "killable"

## Emitted each time a real kill lands (used by scoring).
signal kill_landed

## Emitted when a suspect lock is gained/lost, so the HUD can show "LOCKED".
signal lock_changed(is_locked: bool)

## The peer id of the player who is HUNTING us. You can't assassinate the one hunting you — striking
## them STUNS them instead (a counter, worth kill-level points). Set by OnlineMatch (host) on the ring.
var stun_only_peer: int = 0
## Emitted (host) when a strike lands on your hunter: OnlineMatch freezes them + scores the counter.
signal counter_stun_requested(target: Node2D)

## Phase 9 HOOK (PHASE_9_EXPERIMENTS.md §9A/§9E). Announces EVERY resolved kill and its outcome,
## so experiments can react WITHOUT core knowing they exist (the one-way dependency rule, §1.2).
## `was_valid_target` = true for a clean kill (a player or your own mark), false for a whiff (an
## innocent civilian). Emitted on the machine that resolves the kill (the host, online).
signal kill_resolved(killer: Node, victim: Node, was_valid_target: bool)

# === Phase 9 gates core OWNS (default = no effect, so the base game is unchanged) =============
# Generic, harmless values an experiment may flip; nothing here references an experiment.
## When false, this killer cannot land a kill. 9A (whiff recovery) sets it false during the
## brief recovery window after a wrong commit, then restores it.
var can_kill: bool = true
## Multiplies the WRONG-target exposure penalty (1.0 = full hit). 9A lowers this when its recovery
## window fires, so the same mistake isn't punished at full weight twice (exposure + window).
var exposure_penalty_multiplier: float = 1.0

@onready var _body: CharacterBody2D = get_parent() as CharacterBody2D
@onready var _exposure: ExposureComponent = get_parent().get_node("ExposureComponent")

## The suspect we've locked (or null). We resolve on them when we get close.
var _primed: Node2D = null
## The way we're facing, used to pick "the one in front" when locking.
var _last_facing: Vector2 = Vector2.RIGHT
## Seconds left of a manual-cycle hold (auto soft-lock pauses so it doesn't snap back instantly).
var _cycle_hold: float = 0.0

## Online only: true on the machine that locally controls this killer. When set, we
## send a kill REQUEST to the host instead of resolving the kill ourselves.
var _network_local_control: bool = false

## Set by the ItemComponent: true while a smoke grenade is up (you can't attack while
## you're hidden — buildplan §7.6). Blocks locking a new suspect.
var attacks_disabled: bool = false

## Host-side only: wall-clock time (Time.get_ticks_msec) until which this killer is on the NPC-kill
## cooldown — no kill OR stun resolves before it. 0 = not on cooldown. Set only after killing an NPC.
var _npc_kill_cooldown_until_msec: int = 0


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

	if Input.is_action_just_pressed(action_primary_action) and not attacks_disabled:
		_lock_suspect()

	_update_locked()


# ONLINE (controller-friendly): keep a sticky SOFT-LOCK on the best nearby character (drives the
# private reticle), let the cycle key switch targets, and ASSASSINATE on the action press when the
# locked character is in range. We pick locally (the crowd we can see) and the HOST re-validates.
func _network_kill_input() -> void:
	if _body.velocity.length() > 5.0:
		_last_facing = _body.velocity.normalized()

	_maintain_soft_lock()  # auto-acquire/keep _primed → the reticle tracks it

	if Input.is_action_just_pressed(cycle_action):
		_cycle_lock()  # switch the lock to the next nearby character

	if attacks_disabled:
		return
	# Press to strike when we have a lock in reach. We fire at the LARGER counter_stun_range and let
	# the HOST resolve it: a kill needs the tight kill_range, but striking the player hunting US stuns
	# them from a bit further out. We never learn who our hunter is — we just strike what we've locked
	# and the authority decides kill / counter-stun / nothing (so no identity leak through the client).
	if Input.is_action_just_pressed(action_primary_action) and _primed != null and is_instance_valid(_primed):
		if _body.global_position.distance_to(_primed.global_position) <= maxf(kill_range, counter_stun_range):
			_play_strike()  # instant local feedback; the host decides the actual outcome
			request_kill.rpc_id(NetworkManager.HOST_PEER_ID, _primed.get_path())


# Keep a sticky soft-lock: drop one that's gone/dead/too far, otherwise auto-snap to the best
# candidate in front (unless we're inside a manual-cycle hold window).
func _maintain_soft_lock() -> void:
	if _primed != null and (not is_instance_valid(_primed) \
			or (_primed.has_method("is_dead") and _primed.is_dead()) \
			or _body.global_position.distance_to(_primed.global_position) > lose_range):
		_clear_lock()
	if _cycle_hold > 0.0:
		_cycle_hold = maxf(0.0, _cycle_hold - get_physics_process_delta_time())
		return
	var best := _best_suspect_in_front()
	if best != _primed:
		var had_lock := _primed != null
		_primed = best
		if had_lock != (best != null):
			lock_changed.emit(best != null)


# Cycle the lock to the next character in front (controller target switching).
func _cycle_lock() -> void:
	var candidates := _candidates_in_front()
	if candidates.is_empty():
		return
	var idx := candidates.find(_primed)
	var next: Node2D = candidates[0]
	if idx >= 0:
		next = candidates[(idx + 1) % candidates.size()]
	if next != _primed:
		var had_lock := _primed != null
		_primed = next
		_cycle_hold = cycle_hold_seconds
		if not had_lock:
			lock_changed.emit(true)


# The character currently soft-locked (or null), and whether it's within striking range — read by the
# private reticle so a controller player can SEE who they'll hit and when to press.
func locked_target() -> Node2D:
	return _primed


func lock_in_range() -> bool:
	return _primed != null and is_instance_valid(_primed) \
		and _body.global_position.distance_to(_primed.global_position) <= kill_range


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

	# A STUN (standing in a smoke cloud) locks out attacks. The flag is set on the HOST's copy of
	# this component (OnlineMatch._set_player_stunned), so we enforce it HERE — the client's own copy
	# never learns it (it isn't replicated), so the client-side check alone is bypassable. Without
	# this, a stunned CLIENT could still land a kill.
	if attacks_disabled:
		return

	# Round-start freeze: no kills until the countdown ends (the host clears _net_frozen for all).
	if bool(_body.get("_net_frozen")):
		return

	# Phase 9 (9A) gate — disarmed during a whiff recovery window. Default true = no effect.
	if not can_kill:
		return

	# NPC-KILL COOLDOWN: after cutting down a crowd member you must lay low — no kill OR counter-stun
	# resolves until it elapses. (Killing/stunning a real player never STARTS it; see the resolution
	# below.) Placed above the counter-stun branch so it blocks stuns too, per the rule "no kill/stun".
	if Time.get_ticks_msec() < _npc_kill_cooldown_until_msec:
		return

	var target := get_node_or_null(target_path) as Node2D
	if target == null or target == _body or not is_instance_valid(target):
		return
	# RESPAWN grace (RESPAWN_MODE_PLAN.md §4C): a freshly-respawned player is briefly immune. The host
	# owns grace_active, so checking it here blocks BOTH a clean kill and a whiff on a graced target.
	# NOTE: NPC marks have no `grace_active` property, so .get() returns null on them — test it as a
	# truthy value (null = falsy), NOT bool(null), which crashes with "Nonexistent 'bool' constructor".
	if target.get("grace_active") == true:
		return
	var distance := _body.global_position.distance_to(target.global_position)
	# Beyond even the (larger) counter-stun reach — nothing to resolve.
	if distance > maxf(kill_range, counter_stun_range):
		return
	if not _layers_allow_kill(target):
		return  # different plane, or you're in the no-kill sewer (buildplan §7.2c)

	# COUNTER-STUN: you can't assassinate the player hunting YOU — striking them STUNS them instead
	# (worth kill-level points), and from a MORE FORGIVING range than a kill (counter_stun_range >
	# kill_range — a deliberate skill window). The host knows the relationship; the prey just acts on
	# the threat. (NPC marks have no controlling_peer_id, so this never catches them.)
	# NPC marks have no `controlling_peer_id` (.get() returns null on them), so guard before int() —
	# int(null) would crash the same way bool(null) does. A null target peer can never be our hunter.
	var target_peer = target.get("controlling_peer_id")
	if stun_only_peer != 0 and target_peer != null and int(target_peer) == stun_only_peer:
		if distance <= counter_stun_range:
			counter_stun_requested.emit(target)
		return

	# A normal kill or whiff needs the tighter kill_range.
	if distance > kill_range:
		return
	if target.is_in_group("player") or target.is_in_group("killable_for_%d" % controller):
		# A real player (always fair game) or your designated NPC mark — a clean kill.
		# Pass `controller` so a killed PLAYER gets stamped for kill attribution.
		# A player prey is in BOTH "player" and "killable_for_N"; an NPC mark is only in the latter —
		# so is_in_group("player") is what tells a player-kill (no cooldown) from an NPC-mark kill.
		var victim_is_player := target.is_in_group("player")
		_apply_clean_kill(target, controller)
		if not victim_is_player:
			_begin_npc_kill_cooldown()  # killed an NPC mark → lay low; a player kill does NOT trigger it
	else:
		_apply_whiff(target)
		_begin_npc_kill_cooldown()  # cut down an innocent NPC → same lay-low window


# Host-side: start the NPC-kill lay-low window. Called ONLY when the victim was an NPC (a mark or an
# innocent whiff) — never for killing/stunning a real player. Blocks the next kill AND counter-stun
# (checked at the top of request_kill) for npc_kill_cooldown_seconds.
func _begin_npc_kill_cooldown() -> void:
	_npc_kill_cooldown_until_msec = Time.get_ticks_msec() + int(maxf(0.0, npc_kill_cooldown_seconds) * 1000.0)


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
	if not _layers_allow_kill(target):
		return  # different plane, or you're in the no-kill sewer (buildplan §7.2c)
	if not can_kill:
		return  # Phase 9 (9A) gate — disarmed during a whiff recovery window. Default = no effect.
	_play_strike()
	if target.is_in_group("player") or target.is_in_group(valid_target_group_name):
		# A real player (always fair game) or your mark — clean kill (full permanent
		# spike). Offline has no peer to attribute to, so pass -1 (no stamp).
		_apply_clean_kill(target, -1)
	else:
		_apply_whiff(target)


# === shared kill resolution (one rule, used by BOTH the offline resolve and the host's =====
# === validated request, so the clean/whiff outcome can never drift between the two) ========

# A clean kill: full permanent exposure spike + the clean-kill cosmetics, then the target dies.
# `attacker_peer` >= 0 (online host path) stamps who eliminated a PLAYER for kill attribution;
# -1 (offline) skips the stamp because there's no peer.
func _apply_clean_kill(target: Node2D, attacker_peer: int) -> void:
	kill_landed.emit()
	kill_resolved.emit(_body, target, true)  # Phase 9 hook — clean outcome
	_on_clean_kill(target)  # cosmetic KILL_ANIM (us) + kill_card (victim) — §6
	if attacker_peer >= 0 and target.is_in_group("player"):
		target.set("last_attacker_peer", attacker_peer)
		target.set("last_attacker_method", "blade")  # a melee assassination, for the death screen
	# die() fires `died` synchronously → the host scores this kill (_award_kill_bonuses) NOW. We apply
	# the killer's own exposure spike AFTERWARDS so the exposure modifier reflects your APPROACH
	# exposure (an unseen approach = the full bonus), not the unavoidable post-kill spike.
	if target.has_method("die"):
		target.die()
	_exposure.add_exposure(kill_exposure_spike, "kill")


# POISON (host-authoritative): a validated, DELAYED, QUIET kill. The target is committed NOW (pulled
# out of the killable groups so it can't be double-killed and you can walk away), then drops after
# `delay`. It deliberately NEVER emits kill_resolved, so the crowd-reaction panic never fires — a
# poisoning goes unnoticed. No big exposure spike either (the tool's own cost is the tell); poisoning
# an INNOCENT still applies the wrong-commit penalty when the body drops. Returns true if it landed.
func host_poison(target: Node2D, delay: float) -> bool:
	if target == null or target == _body or not is_instance_valid(target):
		return false
	var controller := int(_body.get("controlling_peer_id"))
	var is_valid: bool = target.is_in_group("player") or target.is_in_group("killable_for_%d" % controller)
	# NO strike animation: poison is a totally silent, deniable kill. The poisoner gets text feedback
	# ("Target poisoned…") from the match instead, and the crowd never panics (is_poisoned, below) — so
	# nothing about applying poison reads as an action to onlookers. The only visible thing is the
	# victim quietly dropping later, by which point you've walked away.
	if target.get("is_poisoned") != null:
		target.set("is_poisoned", true)  # crowd-reaction skips a poisoned death
	_strip_killable(target)  # committed — no second kill, and they keep walking until they drop
	var tree := get_tree()
	tree.create_timer(maxf(0.05, delay)).timeout.connect(func() -> void:
		if not is_instance_valid(target):
			return
		if is_valid:
			kill_landed.emit()  # scoring credited when the body drops
			if controller >= 0 and target.is_in_group("player"):
				target.set("last_attacker_peer", controller)
				target.set("last_attacker_method", "poison")  # a delayed poison, for the death screen
		else:
			_exposure.add_exposure(wrong_commit_exposure * exposure_penalty_multiplier, "innocent_kill")
		if target.has_method("die"):
			target.die())  # die() fires `died` → mark completion / elimination (no kill_resolved = no panic)
	return true


# Pull a target out of every killable group so it can't be killed again (used by poison's commit).
func _strip_killable(target: Node) -> void:
	for group in target.get_groups():
		var group_name := String(group)
		if group_name == "killable" or group_name.begins_with("killable_for_"):
			target.remove_from_group(group)


# A whiff: you committed to the WRONG person. They still die, but you take a HEAVY exposure
# hit (softened only if Phase 9's 9A experiment lowered exposure_penalty_multiplier; it's 1.0
# by default). Cutting down an innocent in the crowd is a glaring tell.
func _apply_whiff(target: Node2D) -> void:
	_exposure.add_exposure(wrong_commit_exposure * exposure_penalty_multiplier, "innocent_kill")
	kill_resolved.emit(_body, target, false)  # Phase 9 hook — whiff outcome
	if target.has_method("die"):
		target.die()


# Physics layers the kill-targeting query scans: PLAYER (layer 2, bit value 2) +
# NPC (layer 4, bit value 4) = 6. Named so the query below isn't a mystery `6`.
const KILL_TARGET_LAYERS := 2 | 4

# Finds the best character to lock: roughly in front of us, within range, closest
# to our facing line. Returns null if there's nobody suitable in front.
# The single best suspect in front (the auto soft-lock target). Just the top of the candidate list.
func _best_suspect_in_front() -> Node2D:
	var candidates := _candidates_in_front()
	return candidates[0] if not candidates.is_empty() else null


# Every valid character in front, sorted best-first (well-centred + nearby wins). Used by both the
# auto soft-lock and the cycle. Skips dead bodies and anyone on a different plane / in the sewer.
func _candidates_in_front() -> Array:
	var out: Array = []
	var my_layer: int = _layer_of(_body)
	if my_layer == LayerComponent.Layer.SEWER:
		return out  # the sewer is a strict no-kill zone — nothing is targetable here
	var space := _body.get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = prime_range
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, _body.global_position)
	query.collision_mask = KILL_TARGET_LAYERS
	query.collide_with_bodies = true
	var cos_limit: float = cos(deg_to_rad(prime_cone_degrees))
	var scored: Array = []
	for result in space.intersect_shape(query, 48):
		var collider := result.get("collider") as Node2D
		if collider == null or collider == _body or not (collider is CharacterBody2D):
			continue
		if collider.has_method("is_dead") and collider.is_dead():
			continue  # don't lock a corpse
		if _layer_of(collider) != my_layer:
			continue  # you can only target someone on your own plane (ground/rooftop)
		var to_target: Vector2 = collider.global_position - _body.global_position
		var distance: float = to_target.length()
		if distance < 1.0:
			continue
		var alignment: float = (to_target / distance).dot(_last_facing)
		if alignment < cos_limit:
			continue  # not in front of us
		scored.append({"node": collider, "score": alignment - (distance / prime_range) * 0.5})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	for s in scored:
		out.append(s["node"])
	return out


# Which plane a character is on. Anything without a LayerComponent (every NPC) is
# treated as GROUND, so the crowd is always killable from the ground as before.
func _layer_of(node: Node) -> int:
	var component := node.get_node_or_null("LayerComponent")
	if component != null:
		return int(component.current_layer)
	return LayerComponent.Layer.GROUND


# Kills only land on your OWN plane, and never while you're in the sewer (§7.2c).
func _layers_allow_kill(target: Node) -> bool:
	var my_layer: int = _layer_of(_body)
	if my_layer == LayerComponent.Layer.SEWER:
		return false
	return _layer_of(target) == my_layer


# A quick "strike" pop on our body so the resolve reads as an action. The visual
# drives its own pop/flash so it doesn't fight the per-frame bob & facing.
func _play_strike() -> void:
	var visual := _body.get_node_or_null("CharacterVisual")
	if visual != null and visual.has_method("play_strike"):
		visual.play_strike()


# Trigger path for a clean assassination (COSMETIC_SYSTEM_SPEC.md §6). Fires the KILLER's
# equipped KILL_ANIM on our own rig, and the kill_card the VICTIM sees on death on theirs.
# Both are stubs today (a placeholder pop / a no-op card) — the point is that the events
# are wired to the real kill, so dropping in real animations later is content-only.
func _on_clean_kill(target: Node) -> void:
	var my_visual := _body.get_node_or_null("CharacterVisual")
	if my_visual != null and my_visual.has_method("play_cosmetic_animation"):
		my_visual.play_cosmetic_animation(CosmeticItem.Slot.KILL_ANIM)
	if target == null:
		return
	var victim_visual := target.get_node_or_null("CharacterVisual")
	if victim_visual != null and victim_visual.has_method("show_kill_card"):
		var killer_appearance := -1
		if _body.get("appearance_index") != null:
			killer_appearance = int(_body.get("appearance_index"))
		victim_visual.show_kill_card(killer_appearance)
