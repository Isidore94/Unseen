extends CharacterBody2D
class_name Player

# Player movement — UNSEEN, Phase 0.
#
# Top-down movement with a walk/run "blend" toggle. This is deliberately tiny:
# one script, one job (Build Plan, Principle #3). Exposure, kills, objectives,
# etc. all live in their own scripts/components later.
#
# WHY the speeds are @export and not constants in code:
# the entire game is the tension between moving FAST (which will raise your
# exposure) and walking CALMLY (which keeps you blended into the crowd). You
# will be re-tuning these numbers constantly, so they must be editable from the
# Inspector — never magic numbers buried in a function (Principle #7).

## Pixels/second while HOLDING the run button. Running is what makes you stand
## out from the walking crowd in later phases — the single most exposing action.
@export var run_speed: float = 220.0

## Pixels/second at the DEFAULT calm pace (when you're NOT holding run). Matches
## the crowd's walk pace later, so a calmly-walking player disappears into the NPCs.
@export var walk_speed: float = 90.0

## Local player number. Used for groups/debugging; it never changes the visual.
@export var player_id: int = 1

## Abstract movement actions for this player. Local co-op assigns each player a
## different Input Map action set while the movement code stays identical.
@export var move_left_action: String = "move_left"
@export var move_right_action: String = "move_right"
@export var move_up_action: String = "move_up"
@export var move_down_action: String = "move_down"
@export var run_action: String = "run"

## A reference to our child ExposureComponent (the "are we standing out?" brain).
## @onready grabs it once the scene is live. $ExposureComponent = the child node
## of that name. We hand it our movement state each frame; it does the math.
@onready var exposure_component: ExposureComponent = $ExposureComponent

## Emitted when the player is caught and killed (the round-loss trigger).
signal died

## Set once caught, so we stop and can't die twice.
var _dead: bool = false


func _ready() -> void:
	# Join the "player" group so other systems (like hunter bots) can find us by
	# asking the scene tree, without us needing to know they exist (Principle #5 —
	# stay decoupled).
	add_to_group("player")
	add_to_group("player_%d" % player_id)


# Called by the hunter when it catches us. Stops the player and signals the loss.
func die() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	_remove_killable_groups()
	set_physics_process(false)
	died.emit()


func is_dead() -> bool:
	return _dead


func _physics_process(delta: float) -> void:
	# Read movement as a single 2D vector built from the four abstract actions.
	# WHY abstract action names instead of raw keys: this exact line works for
	# keyboard AND gamepad with zero changes, because both are bound to these
	# actions in the Input Map. That keyboard/controller parity is non-negotiable
	# for the console + mobile roadmap (Principle #2).
	#
	# get_vector() also normalizes the result, so moving diagonally is not faster
	# than moving straight — a classic beginner bug it quietly prevents.
	var direction: Vector2 = Input.get_vector(
		move_left_action, move_right_action, move_up_action, move_down_action
	)

	# Work out our movement state in plain, separately-named steps (Principle #9:
	# one idea per line, easy to read and to trace in the debugger) — instead of
	# cramming it all into one clever expression.
	# By DEFAULT you move at the calm blend-walk pace — that's your safe resting
	# state. You only speed up while actively HOLDING the run button. Making
	# running a deliberate, held choice reinforces "acting is exposing".
	var is_run_held: bool = Input.is_action_pressed(run_action)
	var is_moving: bool = direction != Vector2.ZERO
	# You only count as "running" if you're actually moving AND holding run.
	var is_running: bool = is_moving and is_run_held

	# Default speed is the calm walk; holding run speeds you up. We resolve speed
	# every frame so the player can start/stop running instantly.
	var speed: float = run_speed if is_run_held else walk_speed

	velocity = direction * speed

	# move_and_slide() reads `velocity`, moves the body, and resolves collisions
	# (sliding along walls). Because Motion Mode is Floating, there's no gravity —
	# correct for a top-down game.
	move_and_slide()

	# Hand our movement state to the exposure brain (Door 1). It turns this into a
	# rising/falling exposure number. Other influences — crowd density, kills,
	# tools — will plug into the SAME component later via its other doors
	# (add_exposure / set_continuous_modifier), without touching this movement code.
	exposure_component.update(is_running, is_moving, direction, delta)


func _remove_killable_groups() -> void:
	for group in get_groups():
		var group_name := String(group)
		if group_name == "killable" or group_name.begins_with("killable_for_"):
			remove_from_group(group)
