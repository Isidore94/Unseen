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
## When true this NPC CROSSES the map (long paths, spawns at an edge); when false it's
## a "homebody" that makes short trips around home_position. Set by the spawner.
@export var is_traveler: bool = false
## A homebody's anchor (usually its spawn spot) and how far it strays from it (pixels).
@export var home_position: Vector2 = Vector2.ZERO
@export var wander_radius: float = 350.0

# === anti-stuck (so NPCs never grind into a wall) ===========================
## If, while trying to travel, the NPC moves LESS than this many pixels in one physics frame, that
## frame counts as "made no progress" (it's jammed against a wall/corner or stuck in a crowd pinch).
@export var stuck_min_progress_px: float = 0.6
## After this many seconds of no progress, give up on the current path and pick a NEW destination —
## which turns the NPC away from the obstacle. Kept short so it never grinds a wall for long.
@export var stuck_seconds_before_repath: float = 0.25

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

## Anti-stuck bookkeeping: our position last physics frame, and how long we've been making no
## headway. When _stuck_time crosses stuck_seconds_before_repath we repath (see _physics_process).
var _last_position: Vector2 = Vector2.ZERO
var _stuck_time: float = 0.0

## Phase 9 (9E) — a temporary "react to a nearby kill" state. While _react_timer > 0 the NPC
## drives in _react_direction instead of wandering, then returns to normal. Driven entirely by the
## crowd_reaction experiment calling react_to_kill(); zero effect if nothing ever calls it.
var _react_timer: float = 0.0
var _react_direction: Vector2 = Vector2.ZERO
var _react_speed_scale: float = 1.0

## Set once killed, so we stop behaving and can't be killed twice.
var _dead: bool = false

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

	# A homebody anchors to wherever it spawned. Online sets this explicitly; offline
	# NPCs leave it at zero, so default it to our spawn position here.
	if home_position == Vector2.ZERO:
		home_position = global_position

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


# Phase 9 (9E) HOOK — the crowd_reaction experiment asks this NPC to flinch in response to a
# nearby kill. The NPC doesn't know WHY (direction experiment → core, §1.2); it just performs the
# brief move. `away` true = flee outward (scatter); false = bolt toward (cluster). Host-only in
# practice: the host owns NPC motion and the move replicates to clients as ordinary position updates.
func react_to_kill(kill_position: Vector2, away: bool, duration_seconds: float, speed_scale: float) -> void:
	if _dead:
		return
	var to_kill := global_position - kill_position
	if to_kill.length() < 1.0:
		to_kill = Vector2.RIGHT.rotated(randf() * TAU)  # right on top of it: pick any direction
	_react_direction = to_kill.normalized() * (1.0 if away else -1.0)
	_react_speed_scale = speed_scale
	_react_timer = duration_seconds


# Phase 9 (9B) HOOK — head to `point` as a one-way traveler (crowd_thinning uses this to send a
# retiring NPC toward a map exit before it despawns). A neutral "go here" command; the NPC doesn't
# know why. Host-only in practice, since the host owns NPC navigation.
func walk_off_to(point: Vector2) -> void:
	is_traveler = true
	can_wander = true
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

	# Phase 9 (9E) — reacting to a nearby kill: flee/cluster for a moment, then resume normal.
	# Checked before the mark/wander logic so even a standing mark visibly flinches.
	if _react_timer > 0.0:
		_react_timer -= delta
		_drive(_react_direction * move_speed * _react_speed_scale)
		return

	# A non-wandering NPC (a mark) just stands at its spot.
	if not can_wander:
		_drive(Vector2.ZERO)
		return

	# CASE 1 — we're pausing at a spot: count down, stand still, and when the
	# timer runs out, choose somewhere new to go.
	if _pause_timer > 0.0:
		_pause_timer -= delta
		_stuck_time = 0.0  # not travelling → a fresh trip starts with a clean stuck timer
		_drive(Vector2.ZERO)
		if _pause_timer <= 0.0:
			_pick_new_destination()
		return

	# CASE 2 — we've arrived at our destination: stop and begin a pause.
	if navigation_agent.is_navigation_finished():
		_pause_timer = randf_range(min_pause_seconds, max_pause_seconds)
		_stuck_time = 0.0
		_drive(Vector2.ZERO)
		return

	# CASE 3 — still travelling: walk toward the next point along the path. ANTI-STUCK: if we wanted
	# to travel but barely moved this frame, we're jammed against a wall/corner (or pinched in a
	# crowd). Count that time; once it exceeds the threshold, abandon this path and pick a NEW
	# destination — which steers us away instead of grinding the wall for more than a few frames.
	if moved_since_last < stuck_min_progress_px:
		_stuck_time += delta
		if _stuck_time >= stuck_seconds_before_repath:
			_stuck_time = 0.0
			_pick_new_destination()
			return
	else:
		_stuck_time = 0.0
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


# Picks a random destination spread EVENLY across the whole map and routes there.
#
# WHY NOT the navigation server's map_get_random_point: it can bias toward the map
# origin (and returns the origin outright if the nav map isn't fully synced yet), which
# made the entire crowd drift into the middle. The map's own random_walkable_point()
# samples every open cell evenly, so the crowd actually fills the streets.
func _pick_new_destination() -> void:
	var map := _map_node()
	if map == null:
		# Fallback if the map isn't found for some reason.
		navigation_agent.target_position = NavigationServer2D.map_get_random_point(
			navigation_agent.get_navigation_map(), 1, true
		)
		return

	if is_traveler:
		# Crosses the map: a destination anywhere on it.
		navigation_agent.target_position = map.random_walkable_point()
	elif map.has_method("random_walkable_point_near"):
		# Homebody: a short trip near home, so it stays in its own patch.
		navigation_agent.target_position = map.random_walkable_point_near(home_position, wander_radius)
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
