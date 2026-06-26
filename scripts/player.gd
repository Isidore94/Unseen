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

# === networking (Phase 6 — see MULTIPLAYER_PLAN.md) =========================
## When true, this character runs in ONLINE mode: instead of moving itself, the
## machine that controls it reads input and SENDS it to the host, and the HOST
## moves every character (server-authoritative — MULTIPLAYER_PLAN.md §2). Offline
## play (single-player / local co-op) leaves this false and is unchanged.
@export var network_controlled: bool = false
## (Online) Which peer controls this character. The host knows this for everyone and
## uses it to verify that input arrived from the right player (anti-cheat §4). NOTE:
## in 6.0 this value is visible to all peers — fine while there's no crowd to hide
## in; it becomes host-only (owner secret) in 6.1 when NPCs arrive.
@export var controlling_peer_id: int = 0
## (Online) Which sprite sheet (0-4) this character wears. The host assigns it; every
## peer receives the same value at spawn, so the crowd looks identical on all screens.
@export var appearance_index: int = 0

## True only on the machine whose local human controls THIS character. Set in _ready.
var _is_locally_controlled: bool = false
## The latest input the host has for this character (set by the input RPC, applied by
## the host each physics frame). Ignored on clients.
var _net_input_direction: Vector2 = Vector2.ZERO
var _net_run_held: bool = false

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

	# Online mode wires up who-controls-whom, the camera, the look, and the
	# position replicator. Offline mode skips all of this and behaves as before.
	if network_controlled:
		_setup_network_role()


# Online setup, run on EVERY machine for EVERY networked character (each machine
# decides locally whether this character is "mine"). See MULTIPLAYER_PLAN.md §5.
func _setup_network_role() -> void:
	# Is this character controlled by the human sitting at THIS machine?
	_is_locally_controlled = (controlling_peer_id == multiplayer.get_unique_id())

	# Wear the sheet the host assigned (every peer got the same number at spawn).
	var visual := get_node_or_null("CharacterVisual")
	if visual != null and visual.has_method("set_appearance"):
		visual.call("set_appearance", appearance_index)

	# Only my own character gets the camera; the others are just people I watch.
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.enabled = _is_locally_controlled
		if _is_locally_controlled:
			camera.make_current()

	# Kills are server-validated (MULTIPLAYER_PLAN.md §4). The kill component runs ONLY
	# on the machine that controls this player: it picks a target and asks the host to
	# resolve it. On every other machine we switch it off so it can't read the local
	# keyboard and act on a character that isn't ours.
	var kill_component := get_node_or_null("KillComponent")
	if kill_component != null:
		if _is_locally_controlled:
			kill_component.call("enable_network_local_control")
		else:
			kill_component.set_physics_process(false)

	_build_position_synchronizer()


# Builds the node that copies this character's position + velocity FROM the host TO
# everyone else, every network tick. Velocity is included so the shared CharacterVisual
# (which reads velocity to face/animate) works for remote characters too.
func _build_position_synchronizer() -> void:
	var replication := SceneReplicationConfig.new()
	replication.add_property(NodePath(".:position"))
	replication.add_property(NodePath(".:velocity"))
	var synchronizer := MultiplayerSynchronizer.new()
	synchronizer.name = "NetSync"
	synchronizer.replication_config = replication
	add_child(synchronizer)


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
	# Two worlds, one movement rule. Offline we read input and move ourselves.
	# Online we split it: the controlling machine sends input, the host moves
	# everyone. Both paths end in the SAME _apply_movement() so the feel is identical.
	if network_controlled:
		_network_physics(delta)
	else:
		_offline_physics(delta)


# OFFLINE (single-player / local co-op): read this machine's input and move now.
func _offline_physics(delta: float) -> void:
	var direction: Vector2 = Input.get_vector(
		move_left_action, move_right_action, move_up_action, move_down_action
	)
	var is_run_held: bool = Input.is_action_pressed(run_action)
	_apply_movement(direction, is_run_held, delta)


# ONLINE: if this is my character I sample input and send it to the host; the host
# (and only the host) actually moves characters. Everyone else just displays the
# replicated position — they do nothing here. (MULTIPLAYER_PLAN.md §2.)
func _network_physics(delta: float) -> void:
	if _is_locally_controlled:
		var direction: Vector2 = Input.get_vector(
			move_left_action, move_right_action, move_up_action, move_down_action
		)
		var is_run_held: bool = Input.is_action_pressed(run_action)
		# rpc_id(1, ...) = "run this on the host." call_local means it also runs here
		# when WE are the host, so the host's own input takes the same path.
		_receive_input.rpc_id(1, direction, is_run_held)

	if multiplayer.is_server():
		_apply_movement(_net_input_direction, _net_run_held, delta)


# The host's record of a character's latest input. Only the host accepts it, and
# only from the peer that actually controls this character (never trust the client).
@rpc("any_peer", "call_local", "unreliable_ordered")
func _receive_input(direction: Vector2, run_held: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	# A sender id of 0 means "called locally" — that's the host's own input.
	var effective_sender: int = sender_id if sender_id != 0 else multiplayer.get_unique_id()
	if effective_sender != controlling_peer_id:
		return  # someone tried to puppet a character they don't control — ignore it
	_net_input_direction = direction
	_net_run_held = run_held


# The shared movement rule (used by BOTH offline and online paths).
#
# WHY abstract action names feed in from the caller instead of reading Input here:
# online, the host moves a character using input that arrived over the network, not
# from a keyboard. Keeping the math here and the input-source in the caller is what
# lets the exact same code serve a local keyboard AND a remote player (Principle #1/#6).
func _apply_movement(direction: Vector2, run_held: bool, delta: float) -> void:
	# By DEFAULT you move at the calm blend-walk pace; holding run speeds you up.
	# Making running a deliberate, held choice reinforces "acting is exposing".
	var is_moving: bool = direction != Vector2.ZERO
	var is_running: bool = is_moving and run_held
	var speed: float = run_speed if run_held else walk_speed

	velocity = direction * speed

	# move_and_slide() reads `velocity`, moves the body, and resolves wall collisions.
	# Motion Mode is Floating (no gravity) — correct for a top-down game.
	move_and_slide()

	# Hand movement state to the exposure brain (Door 1). Other influences (density,
	# kills, tools) plug into the SAME component via its other doors later.
	exposure_component.update(is_running, is_moving, direction, delta)


func _remove_killable_groups() -> void:
	for group in get_groups():
		var group_name := String(group)
		if group_name == "killable" or group_name.begins_with("killable_for_"):
			remove_from_group(group)
