extends CharacterBody2D
class_name HunterAi

# Hunter — UNSEEN, Phase 2. A bot that hunts the player. It stands in for a human
# hunter until online multiplayer (Phase 6). See master_plan §5.
#
# THE WHOLE IDEA, in plain terms:
# The hunter WANDERS around like an ordinary civilian, but it's secretly scanning
# for the player. While it can SEE the player it builds up "suspicion" — faster
# the more EXPOSED the player is and the CLOSER they are. When suspicion fills up,
# it LOCKS ON and starts CHASING. If it loses sight of you, or you calm down
# (low exposure), suspicion drains away and it gives up and goes back to wandering.
#
# This is the cat-and-mouse core of the game. Detection lives in its own clearly
# separated functions because we WILL rewrite it many times while tuning (§5).

# --- movement speeds ---
## Calm searching pace — matches the crowd so the hunter blends while looking.
@export var wander_speed: float = 90.0
## Faster pace once it has locked onto you and is actively chasing.
@export var chase_speed: float = 160.0

## How close (pixels) the hunter must get while chasing to CATCH and kill you.
@export var catch_distance: float = 70.0

# --- wander pauses (same gentle randomness as the civilians) ---
@export var min_pause_seconds: float = 0.5
@export var max_pause_seconds: float = 2.0

# --- detection tuning (expect to rewrite these a lot — §5) ---
## How far away the hunter can possibly notice the player, in pixels.
@export var vision_range: float = 650.0
## Suspicion gained PER SECOND in the best case (player fully exposed, right next
## to the hunter, clear line of sight). It's scaled down by exposure and distance.
@export var suspicion_rise_rate: float = 90.0
## Suspicion lost per second whenever the hunter can't read the player.
@export var suspicion_fall_rate: float = 35.0
## Suspicion (0–100) at which the hunter locks on and starts chasing.
@export var lock_threshold: float = 100.0
## Once chasing, the hunter gives up if suspicion falls back below this.
@export var unlock_threshold: float = 25.0

## Chance (0–1) that the hunter RUNS to its next wander spot instead of walking.
## Running raises the hunter's OWN exposure, which makes the exposure arrow point
## to it — handy for testing the arrow.
@export var wander_run_chance: float = 0.5

## DEV ONLY: tint the hunter by its state (green→yellow→red) so you can watch it
## hunt. A real hunter looks identical to everyone else — switch this off to test
## that you can still feel it without the colour cue.
@export var debug_show_state: bool = true

@onready var navigation_agent: NavigationAgent2D = $NavigationAgent2D
@onready var exposure_component: ExposureComponent = $ExposureComponent

## 0–100 "how sure am I that's the player" meter.
var suspicion: float = 0.0
## true while running (not walking) to the current wander spot.
var _is_running_wander: bool = false
## true = locked on and chasing; false = calmly wandering and scanning.
var _is_chasing: bool = false
## Counts down while paused at a wander spot.
var _pause_timer: float = 0.0
## The player we're hunting (found via the "player" group).
var _player: Player = null
## Throttles how often we recompute the path to the player while chasing.
var _retarget_timer: float = 0.0


## Emitted the moment we're killed (before the death animation).
signal died

## Set once we've been killed, so we stop behaving and can't be killed twice.
var _dead: bool = false


func _ready() -> void:
	# Join the "hunter" group so the exposure arrow can find and point to us. We do
	# NOT join "killable" yet — the contract makes us killable only once it assigns
	# us as the player's target (after the marks are done).
	add_to_group("hunter")
	call_deferred("_begin")


# Called by the player's KillComponent once we're a valid target. Plays a brief
# death fade, then removes us. (One hunter for now; restart to test again.)
func die() -> void:
	if _dead:
		return
	_dead = true
	died.emit()
	set_physics_process(false)
	_remove_killable_groups()
	remove_from_group("hunter")
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.parallel().tween_property(self, "scale", Vector2.ZERO, 0.4)
	tween.tween_callback(queue_free)


func is_dead() -> bool:
	return _dead


func _begin() -> void:
	# Wait one physics frame so navigation is ready, then start wandering.
	await get_tree().physics_frame
	_pick_new_wander_point()


func _physics_process(delta: float) -> void:
	_find_player_if_needed()
	_update_suspicion(delta)
	_update_lock_state()

	# Behave according to our state.
	if _is_chasing:
		_chase(delta)
	else:
		_wander(delta)

	_feed_exposure(delta)

	if debug_show_state:
		_update_debug_tint()


# Feed our movement into our own exposure brain. Chasing and running-to-a-wander-
# spot both count as "running" and raise our exposure; calm walking does not. Once
# our exposure crosses the arrow threshold, the player's HUD arrow points to us.
func _feed_exposure(delta: float) -> void:
	var is_moving: bool = velocity.length() > 1.0
	var is_running: bool = is_moving and (_is_chasing or _is_running_wander)
	var direction: Vector2 = velocity.normalized() if is_moving else Vector2.ZERO
	exposure_component.update(is_running, is_moving, direction, delta)


# === DETECTION =============================================================

func _find_player_if_needed() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player


func _update_suspicion(delta: float) -> void:
	if _player == null:
		return

	var distance: float = global_position.distance_to(_player.global_position)
	var can_read_player: bool = distance <= vision_range and _has_line_of_sight()

	if can_read_player:
		# How exposed is the player right now? 0 = invisible civilian, 1 = beacon.
		# THIS is why standing still in a crowd keeps you safe: low exposure means
		# suspicion barely rises even when the hunter is looking right at you.
		var exposure_amount: float = _player.exposure_component.exposure / 100.0
		# How close within vision range? 1 = right on top of us, 0 = at the edge.
		var proximity: float = 1.0 - (distance / vision_range)
		suspicion += suspicion_rise_rate * exposure_amount * proximity * delta
	else:
		suspicion -= suspicion_fall_rate * delta

	suspicion = clampf(suspicion, 0.0, 100.0)


# Fires an invisible ray from the hunter to the player that only stops on WALLS
# (the "world" physics layer). If it reaches the player without hitting a wall,
# we have clear line of sight. Walls block sight; the crowd does NOT.
func _has_line_of_sight() -> bool:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, _player.global_position, 1)
	var result := space_state.intersect_ray(query)
	return result.is_empty()


func _update_lock_state() -> void:
	if not _is_chasing and suspicion >= lock_threshold:
		_is_chasing = true
	elif _is_chasing and suspicion <= unlock_threshold:
		# Lost them — give up and go back to wandering from where we are.
		_is_chasing = false
		_pick_new_wander_point()


# === MOVEMENT: CHASING =====================================================

func _chase(delta: float) -> void:
	if _player == null:
		return

	# If we've closed to catching range, we catch the prey — they lose.
	if global_position.distance_to(_player.global_position) <= catch_distance:
		_player.die()
		return

	# Recompute the path to the player a few times a second — not every frame,
	# which would be wasteful (matters once there are many hunters).
	_retarget_timer -= delta
	if _retarget_timer <= 0.0:
		navigation_agent.target_position = _player.global_position
		_retarget_timer = 0.25

	var next_point: Vector2 = navigation_agent.get_next_path_position()
	velocity = global_position.direction_to(next_point) * chase_speed
	move_and_slide()


# === MOVEMENT: WANDERING (same loop as the civilian NPC) ===================

func _wander(delta: float) -> void:
	if _pause_timer > 0.0:
		_pause_timer -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		if _pause_timer <= 0.0:
			_pick_new_wander_point()
		return

	if navigation_agent.is_navigation_finished():
		_pause_timer = randf_range(min_pause_seconds, max_pause_seconds)
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Run or walk to the spot depending on the choice made when we picked it.
	var speed: float = chase_speed if _is_running_wander else wander_speed
	var next_point: Vector2 = navigation_agent.get_next_path_position()
	velocity = global_position.direction_to(next_point) * speed
	move_and_slide()


func _pick_new_wander_point() -> void:
	# Randomly decide whether to RUN or walk to the next spot (running exposes us).
	_is_running_wander = randf() < wander_run_chance
	var navigation_map: RID = navigation_agent.get_navigation_map()
	navigation_agent.target_position = NavigationServer2D.map_get_random_point(navigation_map, 1, true)


# === DEV VISUALISATION =====================================================

func _update_debug_tint() -> void:
	if _is_chasing:
		modulate = Color(1.0, 0.3, 0.3)  # red = locked on, chasing you
	else:
		# Green (calm) shading toward yellow as suspicion climbs toward a lock.
		var t: float = suspicion / lock_threshold
		modulate = Color(0.4, 1.0, 0.4).lerp(Color(1.0, 1.0, 0.3), t)


func _remove_killable_groups() -> void:
	for group in get_groups():
		var group_name := String(group)
		if group_name == "killable" or group_name.begins_with("killable_for_"):
			remove_from_group(group)
