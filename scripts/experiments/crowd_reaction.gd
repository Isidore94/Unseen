extends Node

# 9E — CROWD REACTION TO KILLS (PHASE_9_EXPERIMENTS.md §9E). When a kill happens, nearby NPCs PANIC
# and scatter outward — a fleeing knot of civilians points back at where a kill just occurred, a
# directional tell delivered through crowd behaviour. Rewards watching the crowd; makes killing leave
# a visible wake (Pillar #2).
#
# REMOVABILITY (§1): inert unless ExperimentFlags.crowd_reaction_enabled. Host/offline owns NPC
# motion and the flee replicates to clients as ordinary movement. Core never references this.
#
# TRIGGER (the multiplayer fix): ONLINE we listen to the match's `host_kill_resolved` signal, which
# the host emits for EVERY validated kill by EVERY player — so a client's kills scatter the crowd just
# like the host's. OFFLINE (no match) we fall back to each NPC's own `died` signal. The panic feedback
# is broadcast to ALL peers' HUD logs (it used to show only on the host's screen).

@export var reaction_radius_px: float = 560.0
@export var reaction_style_scatter: bool = true
@export var reaction_duration_seconds: float = 6.0
@export var reaction_falloff_with_distance: bool = true
@export var reaction_speed_scale: float = 2.2

var _match: Node = null
var _hooked_match := false
var _connected: Dictionary = {}  # offline: NPCs whose `died` we've hooked


func _ready() -> void:
	set_process(true)


func _is_authority() -> bool:
	return (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()


func _process(_delta: float) -> void:
	if not ExperimentFlags.crowd_reaction_enabled or not _is_authority():
		return
	# ONLINE: hook the match's per-kill signal (covers EVERY player's kills reliably).
	if _match == null:
		_match = get_tree().get_first_node_in_group("online_match")
	if _match != null:
		if not _hooked_match and _match.has_signal("host_kill_resolved"):
			_match.connect("host_kill_resolved", Callable(self, "_on_kill_resolved"))
			_hooked_match = true
		return  # online: don't also hook `died` (would double-fire)
	# OFFLINE: hook each NPC's own death.
	for node in get_tree().get_nodes_in_group("npc"):
		if _connected.has(node) or not node.has_signal("died"):
			continue
		node.connect("died", Callable(self, "_on_npc_died").bind(node))
		_connected[node] = true


# ONLINE: the host resolved a kill (any player, any victim). Scatter the crowd around it.
func _on_kill_resolved(_killer: Node, victim: Node, _was_valid: bool) -> void:
	if victim != null and is_instance_valid(victim):
		_panic_around(victim.global_position)


# OFFLINE: an NPC died.
func _on_npc_died(victim: Node) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	if victim.get("is_poisoned") == true:
		return  # a poisoning is silent — no panic scatter
	_panic_around(victim.global_position)


# Make every nearby living NPC flee (host/offline owns the motion; it replicates to clients), then
# tell EVERY player's HUD the crowd reacted.
func _panic_around(kill_position: Vector2) -> void:
	if not ExperimentFlags.crowd_reaction_enabled or not _is_authority():
		return
	var panicked := 0
	for node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(node):
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
		node.call("react_to_kill", kill_position, reaction_style_scatter, reaction_duration_seconds, scale)
		panicked += 1
	if panicked > 0:
		if multiplayer.has_multiplayer_peer():
			_announce_panic.rpc(panicked)   # every peer's HUD log
		else:
			_announce_panic(panicked)       # offline


# Show the panic message on THIS peer's HUD (called on everyone via rpc).
@rpc("authority", "call_local", "reliable")
func _announce_panic(count: int) -> void:
	var toast := get_tree().get_first_node_in_group("experiment_toast")
	if toast != null and toast.has_method("show_message"):
		toast.call("show_message", "The crowd panics and scatters! (%d)" % count)
