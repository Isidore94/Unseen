extends CharacterBody2D
class_name Npc

# NPC — UNSEEN, Phase 2. A wandering civilian (the crowd you hide in).
#
# WHAT IT DOES, in plain terms:
# The NPC picks a random spot on the walkable floor, calmly walks there, pauses
# for a moment, then picks another spot — forever. That simple loop, with a little
# randomness, is what makes a believable crowd. Believable wandering is THE make-
# or-break challenge of this phase (it's what sank AC Rearmed — master_plan §4).
#
# HOW IT FINDS ITS WAY:
# Unlike the player (who moves by raw physics), the NPC uses a NavigationAgent2D —
# a helper that, given a destination, works out the step-by-step path across the
# navigation mesh (the "walkable floor plan" the map built). Each frame we ask the
# agent "what's the next point on the way?" and walk toward it.

## Movement speed in pixels/second. Kept EQUAL to the player's blend-walk speed on
## purpose (master_plan §4): a calmly-walking player is then mechanically identical
## to a civilian — the linchpin of the whole disguise. A running player (faster)
## stands out precisely because no civilian ever moves that fast.
@export var move_speed: float = 90.0

## After reaching a spot, wait a random time in this range (seconds) before moving
## on. Randomised pauses are a big part of NOT looking robotic.
@export var min_pause_seconds: float = 0.5
@export var max_pause_seconds: float = 2.5

## When false, this NPC stands still instead of wandering. Contract MARKS use this
## so they stay put at their location for you to find and kill.
@export var can_wander: bool = true

# === networking (Phase 6.1 — see MULTIPLAYER_PLAN.md §2) ====================
## When true, this NPC is part of an ONLINE crowd: the HOST runs its wandering AI
## and replicates its position; clients just display it as a puppet (no local AI).
## Offline play leaves this false and the NPC behaves exactly as before.
@export var network_controlled: bool = false
## (Online) Which sprite sheet (0-4) this NPC wears. The host assigns it so the crowd
## looks identical on every screen. Kept for back-compat; the full look now travels as
## `loadout_payload` below (which supersedes this when present).
@export var appearance_index: int = 0

## (Online) The compact cosmetic loadout the HOST assigned to this NPC, replicated to
## clients in the spawn data so the whole crowd looks identical on every screen (§5).
## Empty offline — each NPC then randomises its own look locally. Ids only, no textures.
@export var loadout_payload: Dictionary = {}

# === wander behaviour ======================================================
## LEGACY flag (kept so old spawn data still loads): errand NPCs ignore it. Only
## walk_off_to still flips it, purely as a marker that this NPC is leaving the map.
@export var is_traveler: bool = false
## A PINNED NPC's anchor (usually where it was tagged) and how far it strays (pixels).
## Only used when stay_local is true — i.e. by contract MARKS.
@export var home_position: Vector2 = Vector2.ZERO
@export var wander_radius: float = 350.0

# === errand behaviour (the "walking with intent" crowd) =====================
## When true this NPC is PINNED to a small patch around home_position. Contract MARKS use
## this so their patch stays learnable ("my mark lives by the SW well"). Everyone else
## walks ERRANDS: purposeful legs to points of interest in OTHER districts (the map picks
## them — see TestMap01.errand_destination), so the crowd flows through the whole map,
## corners included, instead of milling in place.
@export var stay_local: bool = false
## Chance (0-1) that the NPC stops to LINGER when an errand leg ends. The rest of the time
## it chains straight into the next leg. Lingerers stand at spread-out doorway POIs, so a
## bigger linger share also spreads the crowd (fewer bodies mid-transit at any instant).
@export var linger_chance: float = 0.45
## How long a linger lasts (seconds). Errand POIs are doorway/wall points, so lingerers
## stand at the street edge like a person would — never in the middle of the road.
@export var linger_min_seconds: float = 3.0
@export var linger_max_seconds: float = 8.0
## Tiny beat (seconds) between two CHAINED errand legs, so direction changes read as a
## person deciding where to go next instead of a robot snapping to a new heading.
@export var errand_beat_min_seconds: float = 0.1
@export var errand_beat_max_seconds: float = 0.5
## How many LOCAL legs (neighbourhood business in the current district) this NPC does
## between two CROSSINGS to another district. Dwell is what keeps districts populated:
## if every leg were a crossing, most of the crowd would be mid-commute at any moment and
## the walking routes (which all pass the middle) would hold everyone.
@export var local_legs_between_crossings_min: int = 2
@export var local_legs_between_crossings_max: int = 4
## Per-NPC walk-speed variation (fraction, applied once at spawn). ±7% makes the crowd read
## as individuals, while the band still BRACKETS the player's exact walk speed (90 px/s) —
## so a calmly-walking player sits inside the crowd's speed range and the disguise holds.
@export var walk_speed_jitter: float = 0.07

# === panic / flee (nav-driven, so NPCs never grind into walls) ==============
## How far (px) a panicking NPC tries to get from a kill. The flee target is fed to
## NAVIGATION (not a raw direction), so panickers run around corners like people —
## an NPC between a kill and the outer wall no longer piles straight into the wall.
@export var panic_flee_distance_px: float = 420.0
## How close to the arena edge (px) a flee/errand target may be clamped. Keeps panic
## targets off the outer wall so the path never even aims at it.
@export var flee_edge_margin_px: float = 80.0

# === anti-stuck (so NPCs never grind into a wall) ===========================
## If, while trying to travel, the NPC moves LESS than this many pixels in one physics frame, that
## frame counts as "made no progress" (it's jammed against a wall/corner or stuck in a crowd pinch).
@export var stuck_min_progress_px: float = 0.6
## After this many seconds of no progress, the NPC reacts: it WAITS a moment and continues the
## SAME trip (a crowd jam clears), and only after several consecutive stalls abandons the trip.
## (It used to re-roll its destination on the FIRST stall — in a crowded plaza that re-roll was
## usually a local spot, so jammed NPCs randomized in place forever and the plaza became a
## population sink that swallowed the whole crowd.)
@export var stuck_seconds_before_repath: float = 0.25
## How many consecutive stalls before the NPC gives up on this destination and picks a new one.
@export var stalls_before_reroute: int = 3
## How long (seconds) a stalled NPC stands and lets the jam clear before resuming its trip.
@export var stall_wait_min_seconds: float = 0.2
@export var stall_wait_max_seconds: float = 0.6

# === network smoothing (Phase 6.2 perf pass) ===============================
## (Online) Seconds between the host shipping this NPC's position to clients. Bigger =
## far less host upload (the crowd's bandwidth was the bottleneck when hosting). Clients
## interpolate between updates, so it still looks smooth. 0.05 = 20 sends/sec.
@export var net_send_interval: float = 0.05
## (Online, clients) How fast a client slides this puppet toward the host's latest
## position each second (smooths the gaps between the throttled updates).
@export var remote_follow_per_second: float = 18.0

## (Online) The host's authoritative position/velocity, streamed to clients. Clients
## interpolate the body toward it instead of snapping (which looked laggy/choppy).
var _net_position: Vector2 = Vector2.ZERO
var _net_velocity: Vector2 = Vector2.ZERO

## Emitted the moment this NPC is killed (before the death animation). The
## contract uses it to know a mark is down.
signal died

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D

## Counts DOWN while the NPC is standing still at a spot. 0 or below = walking.
var _pause_timer: float = 0.0

## Anti-stuck bookkeeping: our position last physics frame, how long we've been making no
## headway, and how many stalls in a row this trip has hit (see _physics_process CASE 3).
var _last_position: Vector2 = Vector2.ZERO
var _stuck_time: float = 0.0
var _stall_count: int = 0
## True while a pause should RESUME the current trip when it ends (a stall wait), instead of
## picking a new destination (a normal arrival pause).
var _resume_current_leg: bool = false
## Errand cadence: local legs left before the next district crossing (see the exports above).
## Starts randomized per NPC so the crowd's crossings aren't synchronized.
var _legs_until_crossing: int = -1

## Phase 9 (9E) — a temporary "react" state (panic flee / decoy bolt / clone drive). While
## _react_timer > 0 the NPC overrides its errand. Two modes: _react_use_nav true = follow a
## NAVIGATION path to a flee target at _react_speed_scale (panic/decoy/clone paths — routes
## around walls); false = drive raw _react_direction (the legacy clone-mirror fallback).
var _react_timer: float = 0.0
var _react_direction: Vector2 = Vector2.ZERO
var _react_speed_scale: float = 1.0
var _react_use_nav: bool = false

## Set once killed, so we stop behaving and can't be killed twice.
var _dead: bool = false

## Set true the moment this NPC is POISONED (a delayed, quiet kill). The crowd-reaction experiment
## checks it so a poisoning never triggers the panic scatter — that's the whole point of poison.
var is_poisoned: bool = false

## Cached reference to the map, used to pick wander destinations spread evenly across
## the WHOLE walkable area (so the crowd fills the map instead of bunching).
var _map_ref: Node = null


func _ready() -> void:
	# Join "npc" so the contract can pick a random civilian to be a mark.
	add_to_group("npc")
	# AVOIDANCE: when enabled, we don't move ourselves directly. We tell the agent
	# the velocity we WANT, it works out a collision-free version that steers around
	# nearby NPCs, then hands it back via this signal — and THAT's the one we move
	# with. This is what stops the crowd clumping into a single blob.
	navigation_agent.velocity_computed.connect(_on_velocity_computed)

	# A pinned NPC anchors to wherever it spawned. Online sets this explicitly; offline
	# NPCs leave it at zero, so default it to our spawn position here.
	if home_position == Vector2.ZERO:
		home_position = global_position

	# Individual gait: nudge this NPC's walk speed once, so the crowd isn't a lockstep
	# 90 px/s parade. The band brackets the player's walk speed, so blending still works.
	if walk_speed_jitter > 0.0:
		move_speed *= randf_range(1.0 - walk_speed_jitter, 1.0 + walk_speed_jitter)

	# Online: only the host runs AI; clients display a replicated puppet.
	if network_controlled:
		_setup_network_role()
		return

	# OFFLINE crowd: give this NPC a randomised look across ALL four rig layers (body +
	# outfit + head + weapon) drawn from the global cosmetic pool (§4), so no NPC is
	# guaranteed to mirror any one player's exact outfit. (Online assigns this on the host.)
	_assign_random_loadout()

	# Marks don't wander; the crowd does. The navigation mesh isn't registered on
	# the very first frame, so we defer the first destination pick a frame.
	if can_wander:
		call_deferred("_begin_wandering")


# Online setup, run on every machine. The host keeps simulating; clients freeze the
# local AI and let the position replicator drive the body. (MULTIPLAYER_PLAN.md §2.)
func _setup_network_role() -> void:
	# Wear what the host assigned (sent identically to every peer at spawn). Prefer the
	# full loadout (all four layers); fall back to the legacy body-only index if none.
	var visual := get_node_or_null("CharacterVisual")
	if visual == null:
		return
	if not loadout_payload.is_empty() and visual.has_method("apply_loadout"):
		visual.call("apply_loadout", Loadout.from_payload(loadout_payload))
	elif visual.has_method("set_appearance"):
		visual.call("set_appearance", appearance_index)

	# Start the follow/publish target at our spawn position so nothing lurches on frame 1.
	_net_position = global_position
	_net_velocity = Vector2.ZERO
	_build_position_synchronizer()

	if multiplayer.is_server():
		# Host: run the wandering AI normally; the synchronizer ships positions out.
		if can_wander:
			call_deferred("_begin_wandering")
	# NOTE: clients KEEP processing now, but only to smoothly interpolate toward the
	# host's replicated position (see the top of _physics_process) — never to run AI.


# Copies this NPC's position + velocity FROM the host TO every client each tick.
# Velocity is included so the shared CharacterVisual faces/animates on clients too.
func _build_position_synchronizer() -> void:
	var replication := SceneReplicationConfig.new()
	# Ship shadow fields (not the live position), throttled, so clients interpolate toward
	# them instead of snapping — far less host upload AND smoother than before.
	replication.add_property(NodePath(".:_net_position"))
	replication.add_property(NodePath(".:_net_velocity"))
	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "NetSync"
	synchronizer.replication_config = replication
	synchronizer.replication_interval = net_send_interval
	add_child(synchronizer)


# Build a randomised loadout from the global cosmetic pool and wear it. Used by offline
# NPCs (and reusable by the host online). The pool comes from CosmeticRegistry — the
# CONFIG HOOK for "lobby players' cosmetics later" lives there (§4), so this spawner
# never needs to change when that arrives. Guarded so a missing registry can't break
# the crowd (it just falls back to the visual's own body-only randomiser).
func _assign_random_loadout() -> void:
	var visual := get_node_or_null("CharacterVisual")
	if visual == null or not visual.has_method("apply_loadout"):
		return
	var reg := get_node_or_null("/root/CosmeticRegistry")
	if reg == null or not reg.has_method("random_crowd_body"):
		return
	# Body only (our crowd art is whole baked looks): a 50/50 commoner/assassin pick this match.
	var loadout := Loadout.new()
	loadout.set_item(CosmeticItem.Slot.BODY, reg.call("random_crowd_body"))
	visual.call("apply_loadout", loadout)


# Called by the player's KillComponent when this NPC is a valid (marked) target.
func die() -> void:
	if _dead:
		return
	_dead = true
	died.emit()
	set_physics_process(false)
	_remove_killable_groups()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.parallel().tween_property(self, "scale", Vector2.ZERO, 0.4)
	tween.tween_callback(queue_free)


func is_dead() -> bool:
	return _dead


# Phase 9 (9E) HOOK — this NPC flinches in response to a nearby kill. The NPC doesn't know WHY
# (direction experiment → core, §1.2); it just performs the brief move. `away` true = flee outward
# (scatter); false = bolt toward (cluster). The flee now goes through NAVIGATION: we pick a target
# point away from the kill and PATH there fast, so panickers run around corners instead of grinding
# into walls (the old raw-direction bolt piled NPCs into the outer wall for the whole panic).
# Host-only in practice: the host owns NPC motion and the move replicates as position updates.
func react_to_kill(kill_position: Vector2, away: bool, duration_seconds: float, speed_scale: float) -> void:
	if _dead:
		return
	var to_kill := global_position - kill_position
	if to_kill.length() < 1.0:
		to_kill = Vector2.RIGHT.rotated(randf() * TAU)  # right on top of it: pick any direction
	var direction := to_kill.normalized() * (1.0 if away else -1.0)
	_start_nav_react(direction, duration_seconds, speed_scale, panic_flee_distance_px)


# DECOY HOOK — bolt in `direction` (the way the NPC is already heading) for a moment. Used by the
# decoy tool: the spooked civilian just breaks into a run, drawing a hunter's eye. If it was standing
# still (no heading), pick a random direction so it always visibly reacts. Nav-driven like panic.
func flee_run(direction: Vector2, duration_seconds: float, speed_scale: float) -> void:
	if _dead:
		return
	if direction.length() < 1.0:
		direction = Vector2.RIGHT.rotated(randf() * TAU)
	# Bolt roughly as far as this dash could carry us, capped so the target stays believable.
	var distance := minf(move_speed * speed_scale * duration_seconds, 600.0)
	_start_nav_react(direction.normalized(), duration_seconds, speed_scale, distance)


# Shared entry for every nav-driven reaction: aim at a point `distance_px` away in `direction`,
# clamped inside the arena (so the path never points at the outer wall), and run there via the
# navigation agent. Falls back to the old raw-direction bolt if there's no map/agent to path with.
func _start_nav_react(direction: Vector2, duration_seconds: float, speed_scale: float, distance_px: float) -> void:
	_react_speed_scale = speed_scale
	_react_timer = duration_seconds
	_react_use_nav = false
	_stuck_time = 0.0
	var map := _map_node()
	if navigation_agent != null and map != null:
		var target := global_position + direction * distance_px
		var half_w := float(map.get("play_half_width")) - flee_edge_margin_px
		var half_h := float(map.get("play_half_height")) - flee_edge_margin_px
		if half_w > 0.0 and half_h > 0.0:
			target.x = clampf(target.x, -half_w, half_w)
			target.y = clampf(target.y, -half_h, half_h)
		navigation_agent.target_position = target  # navigation clamps this onto the walkable mesh
		_react_use_nav = true
	else:
		_react_direction = direction  # no map to path on — the old straight bolt is better than nothing


# CLONES HOOK (legacy mirror mode) — drive this NPC as a movement clone. A ZERO `direction` means
# STAND STILL (not bolt randomly), so the clone can mirror a caster who has stopped. Re-issued every
# frame with a short `hold_seconds`; when the caller stops re-issuing, the NPC rejoins the crowd.
func drive_clone(direction: Vector2, speed_scale: float, hold_seconds: float) -> void:
	if _dead:
		return
	_react_use_nav = false
	_react_direction = direction.normalized() if direction.length() >= 0.001 else Vector2.ZERO
	_react_speed_scale = speed_scale
	_react_timer = hold_seconds


# CLONES HOOK (diverging-path mode) — walk toward `target` along NAVIGATION at `speed_scale`, for
# up to `hold_seconds`. The match gives each clone its OWN target fanned away from the caster, so
# the copies scatter like ordinary pedestrians instead of moving in lockstep (lockstep was a tell).
# Re-issued each frame with the caster's live pace; the target only re-paths when it actually moves.
func drive_clone_path(target: Vector2, speed_scale: float, hold_seconds: float) -> void:
	if _dead:
		return
	_react_speed_scale = speed_scale
	_react_timer = hold_seconds
	if navigation_agent != null:
		if navigation_agent.target_position.distance_to(target) > 8.0:
			navigation_agent.target_position = target
		_react_use_nav = true


# Phase 9 (9B) HOOK — head to `point` as a one-way traveler (crowd_thinning uses this to send a
# retiring NPC toward a map exit before it despawns). A neutral "go here" command; the NPC doesn't
# know why. Host-only in practice, since the host owns NPC navigation.
func walk_off_to(point: Vector2) -> void:
	is_traveler = true
	can_wander = true
	stay_local = false  # even a pinned NPC actually leaves when asked to retire
	home_position = point
	if navigation_agent != null:
		navigation_agent.target_position = point


func _begin_wandering() -> void:
	# Wait one physics frame so the map's navigation is ready to answer queries.
	await get_tree().physics_frame
	_pick_new_destination()


func _physics_process(delta: float) -> void:
	# CLIENT puppet (online, not the host): just glide toward the host's latest position.
	# No AI, no pathfinding — that all runs on the host and arrives via the synchronizer.
	if network_controlled and not multiplayer.is_server():
		_follow_net(delta)
		return

	# HOST/offline: publish this NPC's authoritative state for clients before we move it.
	if network_controlled:
		_net_position = global_position
		_net_velocity = velocity

	# ANTI-STUCK measurement: how far did we actually move since the previous physics frame? We
	# compare this against stuck_min_progress_px in the travelling case below to detect grinding a wall.
	var moved_since_last: float = global_position.distance_to(_last_position)
	_last_position = global_position

	# Phase 9 (9E) / DECOY / CLONES — reacting for a moment, then resume normal. Checked before
	# the mark/wander logic so even a standing mark visibly bolts. We move DIRECTLY (bypassing the
	# navigation AVOIDANCE) so a panicking NPC always breaks into a run — avoidance would cancel its
	# velocity in a dense crowd. But in nav mode the run FOLLOWS the navigation PATH, so the sprint
	# still routes around buildings and never grinds the outer wall.
	if _react_timer > 0.0:
		_react_timer -= delta
		if _react_use_nav:
			if navigation_agent.is_navigation_finished():
				# Reached "safety" — end the reaction early and let the wander logic resume.
				_react_timer = 0.0
				_react_use_nav = false
				velocity = Vector2.ZERO
			else:
				# Anti-stuck still applies while fleeing (pinched in a fleeing crowd): give up
				# on the panic run instead of shoving the same spot for its whole duration.
				if moved_since_last < stuck_min_progress_px:
					_stuck_time += delta
					if _stuck_time >= stuck_seconds_before_repath * 2.0:
						_stuck_time = 0.0
						_react_timer = 0.0
						_react_use_nav = false
				else:
					_stuck_time = 0.0
				var flee_point: Vector2 = navigation_agent.get_next_path_position()
				velocity = global_position.direction_to(flee_point) * move_speed * _react_speed_scale
				move_and_slide()
		else:
			velocity = _react_direction * move_speed * _react_speed_scale
			move_and_slide()
		return

	# A non-wandering NPC (a mark) just stands at its spot.
	if not can_wander:
		_drive(Vector2.ZERO)
		return

	# CASE 1 — we're pausing: count down, stand still. When the timer runs out, either
	# RESUME the trip we stalled on (a jam wait — the agent still holds the destination)
	# or choose somewhere new to go (a normal arrival pause).
	if _pause_timer > 0.0:
		_pause_timer -= delta
		_stuck_time = 0.0  # not travelling → a fresh trip starts with a clean stuck timer
		_drive(Vector2.ZERO)
		if _pause_timer <= 0.0 and not _resume_current_leg:
			_pick_new_destination()
		_resume_current_leg = _resume_current_leg and _pause_timer > 0.0
		return

	# CASE 2 — we've arrived at our destination: stop, then either LINGER (a proper stop at
	# a doorway/landmark, the minority) or take a tiny beat and chain into the next errand.
	# Pinned NPCs (marks) keep the old short randomized pause so their patch feel is unchanged.
	if navigation_agent.is_navigation_finished():
		if stay_local:
			_pause_timer = randf_range(min_pause_seconds, max_pause_seconds)
		elif randf() < linger_chance:
			_pause_timer = randf_range(linger_min_seconds, linger_max_seconds)
		else:
			_pause_timer = randf_range(errand_beat_min_seconds, errand_beat_max_seconds)
		_stuck_time = 0.0
		_drive(Vector2.ZERO)
		return

	# CASE 3 — still travelling: walk toward the next point along the path. ANTI-STUCK: if we
	# wanted to travel but barely moved, we're pinched (usually a crowd jam, sometimes a corner).
	# First stalls: STAND for a beat and continue the SAME trip once the jam clears. Only after
	# several stalls in a row do we abandon the trip for a new destination. (Re-rolling on the
	# first stall made crowded plazas absorb the whole crowd — see stuck_seconds_before_repath.)
	if moved_since_last < stuck_min_progress_px:
		_stuck_time += delta
		if _stuck_time >= stuck_seconds_before_repath:
			_stuck_time = 0.0
			_stall_count += 1
			if _stall_count >= stalls_before_reroute:
				_stall_count = 0
				_pick_new_destination()
			else:
				_pause_timer = randf_range(stall_wait_min_seconds, stall_wait_max_seconds)
				_resume_current_leg = true
				_drive(Vector2.ZERO)
			return
	else:
		_stuck_time = 0.0
		_stall_count = 0
	var next_point: Vector2 = navigation_agent.get_next_path_position()
	_drive(global_position.direction_to(next_point) * move_speed)


# Move with a desired velocity. With avoidance ON we hand the wish to the agent and
# the real move happens in _on_velocity_computed; with it OFF we just move directly.
func _drive(desired_velocity: Vector2) -> void:
	if navigation_agent.avoidance_enabled:
		navigation_agent.set_velocity(desired_velocity)
	else:
		velocity = desired_velocity
		move_and_slide()


# The agent's collision-free answer to what we asked for — this is what we move with.
func _on_velocity_computed(safe_velocity: Vector2) -> void:
	velocity = safe_velocity
	move_and_slide()


# CLIENT puppet: smoothly slide toward the host's replicated position between the
# throttled updates, and copy velocity so the shared visual faces/animates correctly.
func _follow_net(delta: float) -> void:
	global_position = global_position.lerp(_net_position, clampf(remote_follow_per_second * delta, 0.0, 1.0))
	velocity = _net_velocity


# Picks the next destination:
#   - a PINNED NPC (a mark) takes a short trip near home, so its patch stays learnable;
#   - everyone else asks the map for an ERRAND — a point of interest in a different,
#     under-populated district (TestMap01.errand_destination) — so the crowd flows with
#     intent through the whole map, corners included, instead of milling randomly.
# Fallbacks keep old maps working: even random_walkable_point() beats the navigation
# server's map_get_random_point, which biases toward the origin and bunched the crowd.
func _pick_new_destination() -> void:
	var map := _map_node()
	if map == null:
		# Fallback if the map isn't found for some reason.
		navigation_agent.target_position = NavigationServer2D.map_get_random_point(
			navigation_agent.get_navigation_map(), 1, true
		)
		return

	if stay_local and map.has_method("random_walkable_point_near"):
		# Pinned (a mark): a short trip near home, so it stays in its own patch.
		navigation_agent.target_position = map.random_walkable_point_near(home_position, wander_radius)
	elif map.has_method("errand_destination"):
		# Errand walker: a few LOCAL legs of neighbourhood business, then one CROSSING to
		# another district, repeat. The map may override a local with an exodus when the
		# district is overcrowded (see TestMap01.errand_overcrowd_ratio).
		if _legs_until_crossing < 0:
			_legs_until_crossing = randi_range(0, local_legs_between_crossings_max)  # desync at spawn
		if _legs_until_crossing > 0:
			_legs_until_crossing -= 1
			navigation_agent.target_position = map.errand_destination(global_position, true)
		else:
			_legs_until_crossing = randi_range(local_legs_between_crossings_min, local_legs_between_crossings_max)
			navigation_agent.target_position = map.errand_destination(global_position, false)
	else:
		navigation_agent.target_position = map.random_walkable_point()


func _map_node() -> Node:
	if _map_ref == null or not is_instance_valid(_map_ref):
		_map_ref = get_tree().get_first_node_in_group("map")
	return _map_ref


func _remove_killable_groups() -> void:
	for group in get_groups():
		var group_name := String(group)
		if group_name == "killable" or group_name.begins_with("killable_for_"):
			remove_from_group(group)
