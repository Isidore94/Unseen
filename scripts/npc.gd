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
## looks identical on every screen.
@export var appearance_index: int = 0

# === wander behaviour ======================================================
## When true this NPC CROSSES the map (long paths, spawns at an edge); when false it's
## a "homebody" that makes short trips around home_position. Set by the spawner.
@export var is_traveler: bool = false
## A homebody's anchor (usually its spawn spot) and how far it strays from it (pixels).
@export var home_position: Vector2 = Vector2.ZERO
@export var wander_radius: float = 350.0

## Emitted the moment this NPC is killed (before the death animation). The
## contract uses it to know a mark is down.
signal died

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D

## Counts DOWN while the NPC is standing still at a spot. 0 or below = walking.
var _pause_timer: float = 0.0

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

	# Marks don't wander; the crowd does. The navigation mesh isn't registered on
	# the very first frame, so we defer the first destination pick a frame.
	if can_wander:
		call_deferred("_begin_wandering")


# Online setup, run on every machine. The host keeps simulating; clients freeze the
# local AI and let the position replicator drive the body. (MULTIPLAYER_PLAN.md §2.)
func _setup_network_role() -> void:
	# Wear the sheet the host assigned (sent identically to every peer at spawn).
	var visual := get_node_or_null("CharacterVisual")
	if visual != null and visual.has_method("set_appearance"):
		visual.call("set_appearance", appearance_index)

	_build_position_synchronizer()

	if multiplayer.is_server():
		# Host: run the wandering AI normally; the synchronizer ships positions out.
		if can_wander:
			call_deferred("_begin_wandering")
	else:
		# Client: this NPC is a puppet the host moves — switch off our local AI so it
		# can't fight the replicated position.
		set_physics_process(false)


# Copies this NPC's position + velocity FROM the host TO every client each tick.
# Velocity is included so the shared CharacterVisual faces/animates on clients too.
func _build_position_synchronizer() -> void:
	var replication := SceneReplicationConfig.new()
	replication.add_property(NodePath(".:position"))
	replication.add_property(NodePath(".:velocity"))
	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "NetSync"
	synchronizer.replication_config = replication
	add_child(synchronizer)


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


func _begin_wandering() -> void:
	# Wait one physics frame so the map's navigation is ready to answer queries.
	await get_tree().physics_frame
	_pick_new_destination()


func _physics_process(delta: float) -> void:
	# A non-wandering NPC (a mark) just stands at its spot.
	if not can_wander:
		_drive(Vector2.ZERO)
		return

	# CASE 1 — we're pausing at a spot: count down, stand still, and when the
	# timer runs out, choose somewhere new to go.
	if _pause_timer > 0.0:
		_pause_timer -= delta
		_drive(Vector2.ZERO)
		if _pause_timer <= 0.0:
			_pick_new_destination()
		return

	# CASE 2 — we've arrived at our destination: stop and begin a pause.
	if navigation_agent.is_navigation_finished():
		_pause_timer = randf_range(min_pause_seconds, max_pause_seconds)
		_drive(Vector2.ZERO)
		return

	# CASE 3 — still travelling: walk toward the next point along the path.
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
