extends Node

# 9E — CROWD REACTION TO KILLS (PHASE_9_EXPERIMENTS.md §9E). When a kill happens, nearby NPCs PANIC
# and scatter outward — a fleeing knot of civilians points back at where a kill just occurred, a
# directional tell delivered through crowd behaviour. Rewards watching the crowd; makes killing leave
# a visible wake (Pillar #2).
#
# REMOVABILITY (§1): inert unless ExperimentFlags.crowd_reaction_enabled. It listens to each NPC's
# own `died` signal (so it works OFFLINE single-player AND online — earlier it only hooked the online
# match's kill signal, which is why it did nothing offline). Host/offline owns NPC motion; the flee
# replicates to clients as ordinary movement. Core never references this.

## How close an NPC must be to a kill to panic. Wide on purpose — a kill should ripple through a
## whole square, not just the two people next to it.
@export var reaction_radius_px: float = 560.0
## true: NPCs flee OUTWARD (a clear directional tell). false: cluster toward (subtler).
@export var reaction_style_scatter: bool = true
## How long an NPC panics before returning to normal wander.
@export var reaction_duration_seconds: float = 6.0
## Closer NPCs react harder, so the SHAPE of the panic points back at the kill.
@export var reaction_falloff_with_distance: bool = true
## Flee speed as a multiple of normal walk speed — a real panic sprint.
@export var reaction_speed_scale: float = 2.2

var _connected: Dictionary = {}  # NPCs whose `died` we've already hooked


func _ready() -> void:
	set_process(true)


func _is_authority() -> bool:
	# Host (online) or the single machine (offline) owns NPC motion.
	return (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()


func _process(_delta: float) -> void:
	if not ExperimentFlags.crowd_reaction_enabled or not _is_authority():
		return
	# Hook the `died` signal of any NPC we haven't yet (the crowd can arrive over several frames).
	for node in get_tree().get_nodes_in_group("npc"):
		if _connected.has(node) or not node.has_signal("died"):
			continue
		node.connect("died", Callable(self, "_on_npc_died").bind(node))
		_connected[node] = true


func _on_npc_died(victim: Node) -> void:
	if not ExperimentFlags.crowd_reaction_enabled or not _is_authority():
		return
	if victim == null or not is_instance_valid(victim):
		return
	var kill_position: Vector2 = victim.global_position
	var panicked := 0
	for node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(node) or node == victim:
			continue
		if node.has_method("is_dead") and node.is_dead():
			continue
		if not node.has_method("react_to_kill"):
			continue
		var distance: float = node.global_position.distance_to(kill_position)
		if distance > reaction_radius_px:
			continue
		var closeness := 1.0 - clampf(distance / reaction_radius_px, 0.0, 1.0)
		var scale := reaction_speed_scale
		if reaction_falloff_with_distance:
			scale = lerpf(reaction_speed_scale * 0.6, reaction_speed_scale, closeness)  # closer = faster
		# Everyone panics for the full duration; only the SPEED falls off (keeps the directional shape).
		node.call("react_to_kill", kill_position, reaction_style_scatter, reaction_duration_seconds, scale)
		panicked += 1
	# GUI feedback (so the player understands the mechanic fired).
	if panicked > 0:
		var toast := get_tree().get_first_node_in_group("experiment_toast")
		if toast != null and toast.has_method("show_message"):
			toast.call("show_message", "The crowd panics and scatters! (%d)" % panicked)
