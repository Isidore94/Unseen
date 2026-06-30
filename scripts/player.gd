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

## Radius (px) of the tight INTERACTION RING drawn around you (AC-Rearmed style). Tools that act on
## a crowd member (decoy, poison) hit the NPC inside this ring you're facing — see interaction_target().
@export var interaction_radius: float = 110.0

## Abstract movement actions for this player. Local co-op assigns each player a
## different Input Map action set while the movement code stays identical.
@export var move_left_action: String = "move_left"
@export var move_right_action: String = "move_right"
@export var move_up_action: String = "move_up"
@export var move_down_action: String = "move_down"
@export var run_action: String = "run"
## Use the access point you're standing on (climb a rooftop stair / enter-exit a sewer).
@export var interact_action: String = "interact"
## Drop off a rooftop back to the ground (to commit a kill). buildplan §7.2.
@export var drop_down_action: String = "drop_down"
## Claim the access point you're on for the rest of the match (pays exposure). §7.3.
@export var secondary_action: String = "action_secondary"
## Play your equipped EMOTE cosmetic (Input Map action — never a hardcoded key). §6.
@export var emote_action: String = "emote"
## Per-player debounce (seconds) between access-point uses, so a press can't flip-flop you.
@export var access_reuse_cooldown: float = 0.8

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
## (Online) Zoom of YOUR OWN camera. Greater than 1 tightens the view (zoom IN); LOWER pulls the
## camera back to show MORE of the map. Set to 1.4 for a close, zoomed-in view. Only affects
## the online local camera — offline play uses its own camera (single_player_game.camera_zoom), so
## this leaves offline play unchanged.
@export var network_camera_zoom: Vector2 = Vector2(1.4, 1.4)
## (Online) Which sprite sheet (0-4) this character wears. The host assigns it; every
## peer receives the same value at spawn, so the crowd looks identical on all screens.
## Kept for back-compat; the full look now travels as `loadout_payload` (which wins
## when present).
@export var appearance_index: int = 0

## (Online) The compact cosmetic loadout the host replicated for this player at spawn
## (§5). Ids only, no textures — reconstructed into a Loadout and applied to the rig.
## Empty = fall back to the legacy body-only appearance_index above.
@export var loadout_payload: Dictionary = {}

# --- client-side prediction tuning (the "feel" pass, MULTIPLAYER_PLAN.md §2) ---
## (Online) How fast a character you DON'T control slides toward its latest replicated
## position each second (smooths motion between the host's updates).
@export var remote_follow_per_second: float = 22.0
## Safety cap on how many un-acknowledged inputs we keep/replay (a few seconds' worth).
const MAX_PENDING_INPUTS := 240

## True only on the machine whose local human controls THIS character. Set in _ready.
var _is_locally_controlled: bool = false
## The latest input the host has for this character (set by the input RPC, applied by
## the host each physics frame). Ignored on clients.
var _net_input_direction: Vector2 = Vector2.ZERO
var _net_run_held: bool = false

## The host's authoritative state for this character, streamed to clients by the
## synchronizer. Clients NEVER snap the body straight to this — your own character
## predicts and REPLAYS toward it; other characters smoothly follow it.
var _net_position: Vector2 = Vector2.ZERO
var _net_velocity: Vector2 = Vector2.ZERO
## The input sequence number the host's `_net_position` reflects (its "receipt"): the
## owner discards inputs up to here and replays the rest on top of the host's position.
var _net_ack_seq: int = 0

## --- owner-side prediction bookkeeping (the machine that controls this character) ---
## Ever-increasing id stamped on each input we send, so the host can tell us which ones
## it has accounted for.
var _input_seq: int = 0
## Inputs we've predicted locally but the host hasn't confirmed yet: [{seq, dir, run}, …].
var _pending_inputs: Array[Dictionary] = []
## The last ack we reconciled against (so we only re-sync when a NEW host state arrives).
var _last_reconciled_seq: int = -1

## --- host-side: the latest input id received for this character ---
var _server_latest_seq: int = 0

## A reference to our child ExposureComponent (the "are we standing out?" brain).
## @onready grabs it once the scene is live. $ExposureComponent = the child node
## of that name. We hand it our movement state each frame; it does the math.
@onready var exposure_component: ExposureComponent = $ExposureComponent

## Which plane we're on (GROUND/ROOFTOP/SEWER). Optional child — if the scene has no
## LayerComponent, all the layer features simply no-op and play is unchanged.
@onready var layer_component: LayerComponent = get_node_or_null("LayerComponent") as LayerComponent

## (Online) The host's authoritative layer, replicated to every machine. The controlling
## client asks the host to change it; the host sets the LayerComponent + this mirror.
var _net_layer: int = 0
## (Online) Host-authoritative "is this player hidden by a smoke grenade?" flag, replicated
## to everyone. Other machines use it to hide this character via the per-viewer visibility
## system (buildplan §7.6) — the smoker still sees themselves normally.
var _net_smoked: bool = false
## (Online) Host-authoritative "is this player STUNNED by a smoke cloud?" flag, replicated to
## everyone. While true the player can't move (frozen) and the host blocks their kills. Set + timed
## by OnlineMatch on the host; every machine reads it to freeze the body so there's no rubber-band.
var _net_stunned: bool = false
## (Online) Host-authoritative ROUND-START freeze, replicated to everyone. While true the player
## can't move (frozen at spawn) — the host holds everyone for the start-of-round countdown so the
## per-viewer reskin + replication settle before play begins, then clears it for all at once.
var _net_frozen: bool = false
## (Online) Host-authoritative DISGUISE: the commoner body index this player shows to OTHERS while
## disguised (−1 = not disguised). Replicated; every OTHER machine swaps this player's body to it,
## while the owner's own machine keeps the real look (you always see yourself). Breaks a visual lock.
var _net_disguise_body: int = -1
## Counts down the per-player access-point debounce (see access_reuse_cooldown).
var _access_reuse_timer: float = 0.0

## Emitted when the player is caught and killed (the round-loss trigger).
signal died

## Set once caught, so we stop and can't die twice.
var _dead: bool = false
## RESPAWN MODE: true during the post-respawn grace window. The HOST sets/clears it; KillComponent
## reads it on the host to reject kills on a freshly-respawned (briefly immune) player.
var grace_active: bool = false

## Last meaningful heading, held while standing still so interaction_target() still knows which way
## you face (you can't read facing from a zero velocity).
var _last_interaction_facing: Vector2 = Vector2.RIGHT

## (Online) The NPC this player had targeted when it asked the host to use a tool. The controlling
## client computes it from ITS OWN view (what it saw highlighted) and sends it with the request, so
## the host acts on the exact same NPC — no "host picked a different one" mismatch. Consumed per use.
var _pending_tool_target: NodePath = NodePath("")

## (Online, host-side) The peer whose kill eliminated us. The host stamps this in
## KillComponent.request_kill just before we die, so OnlineMatch can attribute the kill (and
## award a completed-contract bonus if our killer was our assigned hunter). −1 = not killed
## by a player (e.g. an offline hunter bot).
var last_attacker_peer: int = -1

## (Online, host-side) HOW we were killed — "blade" (a melee assassination) or "poison" — stamped
## by KillComponent alongside last_attacker_peer, so the death screen can say what got us. "" = unknown.
var last_attacker_method: String = ""


func _ready() -> void:
	# Join the "player" group so other systems (like hunter bots) can find us by
	# asking the scene tree, without us needing to know they exist (Principle #5 —
	# stay decoupled).
	add_to_group("player")
	add_to_group("player_%d" % player_id)

	# Size the interaction ring to our KILL REACH (the KillComponent's kill_range), so the ring is
	# exactly "how far the attack button reaches" — if it's in your ring, you can kill it. One source
	# of truth: tools (decoy/disguise/poison) then share that same reach automatically.
	var kill_component := get_node_or_null("KillComponent")
	if kill_component != null and kill_component.get("kill_range") != null:
		interaction_radius = float(kill_component.get("kill_range"))

	# Online mode wires up who-controls-whom, the camera, the look, and the
	# position replicator. Offline mode skips all of this and behaves as before.
	if network_controlled:
		_setup_network_role()
	else:
		# Offline: this IS the local player, so show its interaction ring.
		_add_interaction_ring()


# Online setup, run on EVERY machine for EVERY networked character (each machine
# decides locally whether this character is "mine"). See MULTIPLAYER_PLAN.md §5.
func _setup_network_role() -> void:
	# Is this character controlled by the human sitting at THIS machine?
	_is_locally_controlled = (controlling_peer_id == multiplayer.get_unique_id())

	# STAGE 8 (partial, flag-gated): on a CLIENT, forget the owner id of every body that isn't ours, so
	# node state can't reveal which figures are human. The HOST keeps all ids (it validates kills with
	# them); our own body keeps its id (we just used it above). Default OFF — see GameModeFlags.
	if GameModeFlags.hide_peer_ids_enabled and not multiplayer.is_server() and not _is_locally_controlled:
		controlling_peer_id = 0

	# Only OUR own character shows the interaction ring (it's a private targeting aid).
	if _is_locally_controlled:
		_add_interaction_ring()

	# Wear what the host assigned at spawn (every peer got the same data). Prefer the full
	# loadout (all four rig layers); fall back to the legacy body-only index if none.
	var visual := get_node_or_null("CharacterVisual")
	if visual != null:
		if not loadout_payload.is_empty() and visual.has_method("apply_loadout"):
			visual.call("apply_loadout", Loadout.from_payload(loadout_payload))
		elif visual.has_method("set_appearance"):
			visual.call("set_appearance", appearance_index)

	# Only my own character gets the camera; the others are just people I watch.
	var camera := get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.enabled = _is_locally_controlled
		if _is_locally_controlled:
			camera.zoom = network_camera_zoom  # tighter view for the four-zone map (§7.0)
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

	# Items are now server-authoritative (§7.6): the controlling client only READS its keys
	# and sends a request; the HOST owns every player's charges + effect timers and applies
	# them. So this copy ticks effects if we're the host, reads input if we control it, and
	# the controlling client relays each press to the host as a request.
	var item_component := get_node_or_null("ItemComponent") as ItemComponent
	if item_component != null:
		item_component.network_mode = true
		item_component.server_authoritative = multiplayer.is_server()
		item_component.local_input = _is_locally_controlled
		item_component.set_physics_process(item_component.server_authoritative or item_component.local_input)
		if _is_locally_controlled and not multiplayer.is_server():
			item_component.item_requested.connect(_on_item_requested)

	# Start the prediction/follow target at our spawn position (the spawn function set it
	# on every machine), so nothing lurches from (0,0) on the first frame.
	_net_position = position
	_net_velocity = Vector2.ZERO

	_build_position_synchronizer()


# Builds the node that copies this character's position + velocity FROM the host TO
# everyone else, every network tick. Velocity is included so the shared CharacterVisual
# (which reads velocity to face/animate) works for remote characters too.
func _build_position_synchronizer() -> void:
	var replication := SceneReplicationConfig.new()
	# Replicate the host's truth into shadow fields (NOT the live position), so the
	# synchronizer never fights the client's local prediction of its own character.
	# The ack seq rides along so the owner knows which inputs the position accounts for.
	replication.add_property(NodePath(".:_net_position"))
	replication.add_property(NodePath(".:_net_velocity"))
	replication.add_property(NodePath(".:_net_ack_seq"))
	replication.add_property(NodePath(".:_net_layer"))
	replication.add_property(NodePath(".:_net_smoked"))
	replication.add_property(NodePath(".:_net_stunned"))
	replication.add_property(NodePath(".:_net_disguise_body"))
	replication.add_property(NodePath(".:_net_frozen"))
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
	_disable_actions_on_death()
	# Ghost the corpse on every screen so a downed player reads as "out" (not an idle live one).
	# Runs once — die() guards re-entry — and the tween is independent of physics being off.
	var fade := create_tween()
	fade.tween_property(self, "modulate:a", 0.35, 0.5)
	died.emit()


# A dead player can't act. die() runs on EVERY machine (the host's resolve + the replicated
# _freeze_player), so flipping these here blocks kills/tools on the host (server-authoritative)
# AND stops the dead player's own client from reading the keys — no ghost strikes or tools.
func _disable_actions_on_death() -> void:
	var kill_component := get_node_or_null("KillComponent")
	if kill_component != null:
		kill_component.set("attacks_disabled", true)  # request_kill + local kill input both honour this
	var item_component := get_node_or_null("ItemComponent") as ItemComponent
	if item_component != null:
		item_component.owner_dead = true  # refuses new activations + stops local key reading


func is_dead() -> bool:
	return _dead


# RESPAWN MODE (RESPAWN_MODE_PLAN.md §2): bring a killed player back to a FRESH life at
# `spawn_position`. Reverses die() and wipes per-life state (exposure + tools) so the new life starts
# at base. Runs on EVERY machine via OnlineMatch._revive_player (so the corpse un-fades and the
# owner's own body regains control + snaps to the spawn point). The host's _net_position then keeps
# remote puppets in sync.
func revive(spawn_position: Vector2) -> void:
	_dead = false
	global_position = spawn_position
	_net_position = spawn_position
	_net_velocity = Vector2.ZERO
	velocity = Vector2.ZERO
	modulate.a = 1.0
	set_physics_process(true)
	# Re-enable acting (die() disabled these).
	var kill_component := get_node_or_null("KillComponent")
	if kill_component != null:
		kill_component.set("attacks_disabled", false)
	var item_kit := get_node_or_null("ItemComponent") as ItemComponent
	if item_kit != null:
		item_kit.owner_dead = false
		item_kit.reset_to_base()
	# Wipe exposure (movement heat + committed floor) — keep nothing across a death.
	var exposure := get_node_or_null("ExposureComponent")
	if exposure != null and exposure.has_method("reset"):
		exposure.reset()


# The character inside our interaction ring we'd act on (the ring visual's highlight + tools).
# Prefers the one we're FACING; ties break toward the closest. By default it considers BOTH crowd
# NPCs AND other players (so an enemy assassin in the ring is targetable too); pass include_players
# = false for NPC-only tools like decoy. Works on the host (it reads authoritative velocity for facing).
func interaction_target(include_players: bool = true) -> Node2D:
	if velocity.length() > 5.0:
		_last_interaction_facing = velocity.normalized()
	var groups: Array = ["npc"]
	if include_players:
		groups.append("player")
	var best: Node2D = null
	var best_score: float = -INF
	for group in groups:
		for node in get_tree().get_nodes_in_group(group):
			var character := node as Node2D
			if character == null or character == self or not is_instance_valid(character):
				continue
			if character.has_method("is_dead") and character.is_dead():
				continue
			var to_target: Vector2 = character.global_position - global_position
			var distance: float = to_target.length()
			if distance > interaction_radius or distance < 1.0:
				continue
			# Favour someone straight ahead and close: alignment (−1..1) minus a small distance penalty.
			var score: float = (to_target / distance).dot(_last_interaction_facing) - distance / interaction_radius
			if score > best_score:
				best_score = score
				best = character
	return best


# Give the LOCAL player a visible interaction ring (only for the human at this machine).
func _add_interaction_ring() -> void:
	if has_node("InteractionRing"):
		return
	var ring := InteractionRing.new()
	ring.name = "InteractionRing"
	add_child(ring)


# Diagnostics: how many predicted inputs are still waiting for the host to confirm. It
# rises with latency / packet loss, so the debug overlay uses it as a connection-health
# proxy (a steady single-digit number = healthy; a growing number = trouble).
func get_pending_input_count() -> int:
	return _pending_inputs.size()


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
	_handle_layer_input(delta)


# ONLINE: three roles, decided per character on each machine.
#   • the HOST is the authority for everyone — it moves each character and publishes the
#     result for clients to reconcile/follow;
#   • on a client, MY OWN character predicts from my input immediately (no round-trip lag)
#     and eases toward the host's truth;
#   • on a client, everyone ELSE's character smoothly follows the host's position.
# (MULTIPLAYER_PLAN.md §2 — the server stays authoritative; prediction is purely local, so
# it reveals nothing about who is human.)
func _network_physics(delta: float) -> void:
	# Only the human at this machine reads input to change their own layer.
	if _is_locally_controlled:
		_handle_layer_input(delta)
	# On a CLIENT, the host's replicated layer is the truth for EVERY character — including
	# our own (we asked the host in _request_layer and the result arrives here as _net_layer).
	if not multiplayer.is_server() and layer_component != null and layer_component.current_layer != _net_layer:
		layer_component.set_layer(_net_layer)

	if multiplayer.is_server():
		# The host is the authority for EVERY character. If it also controls this one, it
		# samples + sends its own input (call_local feeds the line below). Then it moves
		# the character and publishes the result + which input id that result reflects.
		if _is_locally_controlled:
			_sample_and_send_input()
		_apply_movement(_net_input_direction, _net_run_held, delta)
		_net_position = position
		_net_velocity = velocity
		_net_ack_seq = _server_latest_seq
	elif _is_locally_controlled:
		_predict_local()
	else:
		_follow_server(delta)


# Sample this machine's input, stamp it with the next sequence id, and send it to the
# host. Returns the sample so the predictor can record/replay the very same input.
func _sample_and_send_input() -> Dictionary:
	var direction: Vector2 = Input.get_vector(
		move_left_action, move_right_action, move_up_action, move_down_action
	)
	var run_held: bool = Input.is_action_pressed(run_action)
	_input_seq += 1
	# rpc_id(HOST_PEER_ID, ...) = "run this on the host." call_local also runs it here when WE are
	# the host, so the host's own input takes the same path.
	_receive_input.rpc_id(NetworkManager.HOST_PEER_ID, _input_seq, direction, run_held)
	return {"seq": _input_seq, "dir": direction, "run": run_held}


# CLIENT-SIDE PREDICTION + REPLAY for your OWN avatar (MULTIPLAYER_PLAN.md §2). Move from
# your input the instant you press — never waiting on the round-trip — then, each time a
# fresh host state arrives, snap to that authoritative position and REPLAY every input the
# host hasn't confirmed yet. After the replay you land exactly where prediction had you,
# so there is no rubber-band tug toward a latency-old position (the old "wall on start /
# glide on stop"). It leaks nothing: it's purely local, and you already know it's you.
func _predict_local() -> void:
	var sample := _sample_and_send_input()
	_pending_inputs.append(sample)
	if _pending_inputs.size() > MAX_PENDING_INPUTS:
		_pending_inputs.pop_front()

	if _net_ack_seq != _last_reconciled_seq:
		# A new host snapshot arrived → reconcile.
		_last_reconciled_seq = _net_ack_seq
		# Drop inputs the host has already accounted for.
		while not _pending_inputs.is_empty() and int(_pending_inputs[0]["seq"]) <= _net_ack_seq:
			_pending_inputs.pop_front()
		# Rewind to the host's truth, then replay everything it hasn't seen yet (this
		# includes the input we just sampled), arriving back at the correct prediction.
		position = _net_position
		velocity = _net_velocity
		for pending in _pending_inputs:
			_move_with(pending["dir"], pending["run"])
	else:
		# No new snapshot this frame — just advance the prediction with this input.
		_move_with(sample["dir"], sample["run"])


# Smoothly slide a character we DON'T control toward the host's replicated position, and
# copy its velocity so the shared visual faces/animates correctly between updates.
func _follow_server(delta: float) -> void:
	position = position.lerp(_net_position, clampf(remote_follow_per_second * delta, 0.0, 1.0))
	velocity = _net_velocity


# Anti-cheat gate (server-authoritative, MULTIPLAYER_PLAN.md §4): is the peer that sent the
# RPC we're handling the one that actually CONTROLS this character? A sender id of 0 means the
# call came from our own machine (the host's own input via call_local), which is always allowed
# for its own character. Every host-only RPC handler below gates on this single helper so the
# "did this peer puppet a character it doesn't own?" rule lives in ONE place, not copied four
# times where one could silently drift.
func _remote_sender_controls_this_character() -> bool:
	var sender_id: int = multiplayer.get_remote_sender_id()
	var effective_sender: int = sender_id if sender_id != 0 else multiplayer.get_unique_id()
	return effective_sender == controlling_peer_id


# The host's record of a character's latest input. Only the host accepts it, and only from
# the peer that actually controls this character (never trust the client). It also remembers
# the highest input id seen, which it echoes back as the reconciliation receipt.
@rpc("any_peer", "call_local", "unreliable_ordered")
func _receive_input(seq: int, direction: Vector2, run_held: bool) -> void:
	if not multiplayer.is_server():
		return
	if not _remote_sender_controls_this_character():
		return  # someone tried to puppet a character they don't control — ignore it
	_net_input_direction = direction
	_net_run_held = run_held
	if seq > _server_latest_seq:
		_server_latest_seq = seq


# The shared movement rule (used by BOTH offline and online paths).
#
# WHY abstract action names feed in from the caller instead of reading Input here:
# online, the host moves a character using input that arrived over the network, not
# from a keyboard. Keeping the math here and the input-source in the caller is what
# lets the exact same code serve a local keyboard AND a remote player (Principle #1/#6).
func _apply_movement(direction: Vector2, run_held: bool, delta: float) -> void:
	_move_with(direction, run_held)

	# Hand movement state to the exposure brain (Door 1). Other influences (density,
	# kills, tools) plug into the SAME component via its other doors later.
	var is_moving: bool = direction != Vector2.ZERO
	var is_running: bool = is_moving and run_held
	exposure_component.update(is_running, is_moving, direction, delta)


# Pure movement: set velocity from the input and slide. NO exposure here — client-side
# prediction reuses this, and exposure is owned by the host (predicting it on the client
# too would double-count it). By DEFAULT you move at the calm walk pace; holding run is
# the deliberate, exposing choice.
func _move_with(direction: Vector2, run_held: bool) -> void:
	# Frozen — by a smoke STUN or the round-start FREEZE. One chokepoint so the host's sim AND a
	# client's own prediction both hold still (no rubber-band toward a position you can't reach).
	if _net_stunned or _net_frozen:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var speed: float = run_speed if run_held else walk_speed
	velocity = direction * speed
	# move_and_slide() reads `velocity`, moves the body, and resolves wall collisions.
	# Motion Mode is Floating (no gravity) — correct for a top-down game.
	move_and_slide()


# Play this player's equipped EMOTE through the rig's one animation entry point (§6).
func _play_emote() -> void:
	var visual := get_node_or_null("CharacterVisual")
	if visual != null and visual.has_method("play_cosmetic_animation"):
		visual.call("play_cosmetic_animation", CosmeticItem.Slot.EMOTE)


# === layers: rooftops & sewers (buildplan §7.2) ============================
# Read this player's own input to climb/drop/enter/exit. Called only for the human at
# this machine (offline: always; online: only for the locally-controlled character).
func _handle_layer_input(delta: float) -> void:
	# EMOTE (§6): manual, mid-match, this player's own input. Fires the equipped EMOTE
	# cosmetic on our rig through the one animation entry point — stubbed pop for now.
	if Input.is_action_just_pressed(emote_action):
		_play_emote()

	if layer_component == null:
		return
	if _access_reuse_timer > 0.0:
		_access_reuse_timer -= delta

	# Drop down from a rooftop, anywhere, to come back to the ground and commit a kill.
	if Input.is_action_just_pressed(drop_down_action) and layer_component.is_rooftop():
		_request_layer(LayerComponent.Layer.GROUND)
		return

	var point := _nearest_access_point()
	# CLAIM the point you're standing on for the rest of the match (§7.3).
	if Input.is_action_just_pressed(secondary_action) and point != null:
		_try_claim(point)
		return

	if not Input.is_action_just_pressed(interact_action) or _access_reuse_timer > 0.0:
		return
	if point == null or not point.is_available_to(player_id):
		return  # nothing here, or it's on global cooldown / claimed by someone else
	var used := false
	if point.is_rooftop_stair() and layer_component.is_ground():
		_request_layer(LayerComponent.Layer.ROOFTOP)
		used = true
	elif point.is_sewer_entrance():
		# At a sewer entrance: drop in from the ground, or surface back from the sewer.
		if layer_component.is_ground():
			_request_layer(LayerComponent.Layer.SEWER)
			used = true
		elif layer_component.is_sewer():
			_request_layer(LayerComponent.Layer.GROUND)
			used = true
	if used and not network_controlled:
		# Offline: start the 15s global lockout here. Online the HOST owns the cooldown
		# (it marks the point in _request_set_layer and replicates it), so we don't.
		point.mark_used()


# Claim an access point for the rest of the match, paying its exposure cost (§7.3).
# Offline we claim directly; online we ask the host (server-authoritative, like layers).
func _try_claim(point: AccessPoint) -> void:
	if point == null:
		return
	if network_controlled:
		_request_claim.rpc_id(NetworkManager.HOST_PEER_ID)  # the host finds the point WE'RE standing on and validates
		return
	if point.is_claimed():
		return
	point.claim(player_id)
	if exposure_component != null:
		exposure_component.add_exposure(point.claim_exposure_cost, "claim_access")


# HOST-ONLY: a controlling client asks to claim the access point it's standing on. We verify
# the sender, find the point nearest the player's authoritative position, and (if it's free
# and off cooldown) claim it + charge the 20% committed exposure. The claim replicates via
# the AccessPoint's claim_changed signal (OnlineMatch broadcasts it to every client).
@rpc("any_peer", "call_local", "reliable")
func _request_claim() -> void:
	if not multiplayer.is_server():
		return
	if not _remote_sender_controls_this_character():
		return
	var point := _nearest_access_point()
	# Claiming is independent of the transit cooldown (your design): the 15s lockout only
	# governs UNCLAIMED pass-through (anti-spam); claiming is permanent ownership bought with
	# exposure, so you can claim a point you just used. We only refuse if someone already owns
	# it. (This matches the offline _try_claim path, which never checked the cooldown.)
	if point == null or point.is_claimed():
		return
	point.claim(player_id)
	if exposure_component != null:
		exposure_component.add_exposure(point.claim_exposure_cost, "claim_access")


# The closest access point we're standing on (within its use radius), or null.
func _nearest_access_point() -> AccessPoint:
	var best: AccessPoint = null
	var best_distance: float = INF
	for node in get_tree().get_nodes_in_group("access_point"):
		var point := node as AccessPoint
		if point == null:
			continue
		var distance: float = global_position.distance_to(point.global_position)
		if distance <= point.use_radius and distance < best_distance:
			best_distance = distance
			best = point
	return best


# Apply a layer change. Offline we set it directly; online we ask the host (kept
# server-authoritative — the host owns the truth and replicates it to everyone).
func _request_layer(layer: int) -> void:
	_access_reuse_timer = access_reuse_cooldown
	if network_controlled:
		_request_set_layer.rpc_id(NetworkManager.HOST_PEER_ID, layer)
	elif layer_component != null:
		layer_component.set_layer(layer)


# HOST-ONLY: a controlling client asks to change its layer. We verify the request came
# from the peer that controls this character, validate it against the access points (a
# rooftop enter / sewer enter+exit must happen at an available point; dropping off a roof
# is free anywhere), start the point's global cooldown, then set the LayerComponent + the
# replicated mirror so every machine updates.
@rpc("any_peer", "call_local", "reliable")
func _request_set_layer(layer: int) -> void:
	if not multiplayer.is_server():
		return
	if not _remote_sender_controls_this_character():
		return
	if layer_component == null:
		return
	var from_layer: int = layer_component.current_layer
	# Dropping from a rooftop back to the ground is free and works anywhere (commit a kill).
	var is_free_drop: bool = from_layer == LayerComponent.Layer.ROOFTOP and layer == LayerComponent.Layer.GROUND
	if not is_free_drop:
		var point := _nearest_access_point()
		if point == null or not point.is_available_to(player_id):
			return  # reject: no usable access point here (on cooldown / claimed by another)
		var transition_ok: bool = false
		if layer == LayerComponent.Layer.ROOFTOP and point.is_rooftop_stair() and from_layer == LayerComponent.Layer.GROUND:
			transition_ok = true
		elif layer == LayerComponent.Layer.SEWER and point.is_sewer_entrance() and from_layer == LayerComponent.Layer.GROUND:
			transition_ok = true
		elif layer == LayerComponent.Layer.GROUND and point.is_sewer_entrance() and from_layer == LayerComponent.Layer.SEWER:
			transition_ok = true
		if not transition_ok:
			return
		point.mark_used()  # host starts + replicates the 15s global lockout
	layer_component.set_layer(layer)
	_net_layer = layer


# A locally-controlled client's item press → ask the host to fire it (server-authoritative). We
# also send the NPC we have targeted in our ring, so the host acts on the exact one we saw.
func _on_item_requested(which: int) -> void:
	# Send whatever we have HIGHLIGHTED (NPC or enemy player). The host filters per tool: decoy/
	# disguise use it only if it's an NPC; poison accepts a player target too.
	var target := interaction_target(true)
	var target_path := target.get_path() if target != null else NodePath("")
	_request_item.rpc_id(NetworkManager.HOST_PEER_ID, which, target_path)


# HOST-ONLY: a controlling client asks to use an item slot. Verify the sender, stash the target it
# sent, then let the host's own ItemComponent validate charges + apply the effect (§7.6).
@rpc("any_peer", "call_local", "reliable")
func _request_item(which: int, target_path: NodePath = NodePath("")) -> void:
	if not multiplayer.is_server():
		return
	if not _remote_sender_controls_this_character():
		return
	_pending_tool_target = target_path
	var item_component := get_node_or_null("ItemComponent") as ItemComponent
	if item_component != null:
		item_component.server_activate(which)


func _remove_killable_groups() -> void:
	for group in get_groups():
		var group_name := String(group)
		if group_name == "killable" or group_name.begins_with("killable_for_"):
			remove_from_group(group)
