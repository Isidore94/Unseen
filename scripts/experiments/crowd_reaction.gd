extends Node

# 9E — CROWD REACTION TO KILLS (PHASE_9_EXPERIMENTS.md §9E). When a kill happens, nearby NPCs flinch
# and scatter (or cluster), leaving a directional tell — a fleeing knot of civilians points back at
# where a kill just occurred, delivered through crowd behavior with ZERO UI. Rewards the hunter who
# watches the crowd, and makes killing (which should expose you) leave a visible wake (Pillar #2).
#
# REMOVABILITY (§1): inert unless ExperimentFlags.crowd_reaction_enabled. Host-only: it listens for
# the match's kill signal and asks nearby NPCs (via the neutral npc.react_to_kill command) to flinch.
# The motion replicates to clients as ordinary NPC movement. Core never references this.

## How close an NPC must be to a kill to react.
@export var reaction_radius_px: float = 250.0
## true: NPCs flee OUTWARD (a clear directional tell). false: NPCs bolt toward / cluster (subtler).
@export var reaction_style_scatter: bool = true
## How long an NPC stays in the reaction before returning to normal wander.
@export var reaction_duration_seconds: float = 2.5
## Closer NPCs react harder, so the SHAPE of the reaction points back toward the kill.
@export var reaction_falloff_with_distance: bool = true
## Flee speed as a multiple of the NPC's normal walk speed (a brief panic burst).
@export var reaction_speed_scale: float = 1.5

var _match: Node = null


func _ready() -> void:
	call_deferred("_connect_to_match")


func _connect_to_match() -> void:
	_match = get_tree().get_first_node_in_group("online_match")
	if _match != null and _match.has_signal("host_kill_resolved"):
		if not _match.is_connected("host_kill_resolved", Callable(self, "_on_kill_resolved")):
			_match.connect("host_kill_resolved", Callable(self, "_on_kill_resolved"))


func _process(_delta: float) -> void:
	# Lazily (re)connect if the match wasn't ready at _ready time. Cheap once connected.
	if _match == null and ExperimentFlags.crowd_reaction_enabled:
		_connect_to_match()


func _on_kill_resolved(_killer: Node, victim: Node, _was_valid: bool) -> void:
	if not ExperimentFlags.crowd_reaction_enabled:
		return
	if not ((not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()):
		return  # host owns NPC motion
	if victim == null or not is_instance_valid(victim):
		return
	var kill_position: Vector2 = victim.global_position

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
		# Closer = harder/longer flinch, so the cluster's shape points back at the kill.
		var closeness := 1.0 - clampf(distance / reaction_radius_px, 0.0, 1.0)
		var scale := reaction_speed_scale
		var duration := reaction_duration_seconds
		if reaction_falloff_with_distance:
			scale = lerp(reaction_speed_scale * 0.5, reaction_speed_scale, closeness)
			duration = lerp(reaction_duration_seconds * 0.5, reaction_duration_seconds, closeness)
		node.call("react_to_kill", kill_position, reaction_style_scatter, duration, scale)
