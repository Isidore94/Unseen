extends CharacterBody2D

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

## Pixels/second at full speed. This is the DEFAULT state (not holding blend).
## Running is what makes you stand out from the walking crowd in later phases.
@export var run_speed: float = 220.0

## Pixels/second while holding the blend key. Matches the crowd's walk pace
## later, so a walking player disappears into the NPCs.
@export var walk_speed: float = 90.0


func _physics_process(_delta: float) -> void:
	# Read movement as a single 2D vector built from the four abstract actions.
	# WHY abstract action names instead of raw keys: this exact line works for
	# keyboard AND gamepad with zero changes, because both are bound to these
	# actions in the Input Map. That keyboard/controller parity is non-negotiable
	# for the console + mobile roadmap (Principle #2).
	#
	# get_vector() also normalizes the result, so moving diagonally is not faster
	# than moving straight — a classic beginner bug it quietly prevents.
	var direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)

	# Hold blend_walk to slow to a calm walk; otherwise run. We resolve speed
	# every frame so the player can blend/unblend instantly.
	var speed: float = walk_speed if Input.is_action_pressed("blend_walk") else run_speed

	velocity = direction * speed

	# move_and_slide() reads `velocity`, moves the body, and resolves collisions
	# (sliding along walls). Because Motion Mode is Floating, there's no gravity —
	# correct for a top-down game.
	move_and_slide()
