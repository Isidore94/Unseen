extends Node

# 9A — WHIFF RECOVERY (PHASE_9_EXPERIMENTS.md §9A). Killing the WRONG target (an innocent civilian)
# briefly disarms the killer, so a hunter who was already shadowing them can capitalize. Turns the
# kill into a real commitment with a punishable mistake — and opens the bluff layer (baiting an
# opponent into a wrong commit). It's an ADDITIONAL contextual layer on top of the existing
# civilian-kill exposure penalty, designed to avoid double-jeopardy (see witness + soften below).
#
# REMOVABILITY (§1): inert unless ExperimentFlags.whiff_recovery_enabled. Host-only. It only reads
# core state and flips two values core already owns on the killer's KillComponent (can_kill,
# exposure_penalty_multiplier) — core never references this. Delete the file + flag line → unchanged.

## Recovery window (seconds) for a whiff at ZERO exposure. Keep 1.5–2.5 — 5s is a death sentence,
## and a death sentence for any uncertain swing is exactly what causes turtling.
@export var recovery_seconds_base: float = 2.0
## Recovery window (seconds) for a whiff at MAX exposure (reckless players pay more).
@export var recovery_seconds_max: float = 4.0
## If true, the window scales base→max by the whiffer's exposure/100 (clean read = short, survivable).
@export var scale_recovery_with_exposure: bool = true
## false (default) = disarmed-but-mobile (can flee, can't kill). true = also rooted. NOTE: root needs
## a player movement-lock hook that doesn't exist yet, so today root falls back to disarm + a warning.
@export var mode_root_instead_of_disarm: bool = false
## If true, the window only fires when a WITNESS (another player in range + line of sight) saw the
## whiff. Whiffing alone falls back to the exposure penalty only — the anti-double-jeopardy split.
@export var witness_context_enabled: bool = true
## How close another player must be to count as a witness.
@export var witness_range_px: float = 350.0
## Physics collision mask of WALLS, for the line-of-sight check (a wall between you and a player
## means they didn't witness it). Set to match your map's wall layer.
@export var wall_collision_mask: int = 1
## When the window fires (witnessed), reduce the civilian-kill exposure penalty so the same mistake
## isn't punished twice at full weight.
@export var soften_exposure_penalty_on_window: bool = true
## How much of the normal exposure penalty still applies when the window fired (0 = waived, 1 = none).
@export var exposure_penalty_multiplier_when_windowed: float = 0.5

var _match: Node = null
var _windows: Dictionary = {}  ## KillComponent -> seconds left in its recovery window
## True while we've written non-default state (penalty multiplier / can_kill) onto KillComponents.
## Lets us cleanly UNDO everything if the flag is toggled off mid-session, so no player is left
## with a stuck 0.5 multiplier or a permanent disarm (keeps the "delete/flip test" honest).
var _effects_applied: bool = false


func _ready() -> void:
	# Hear about every resolved kill once, at the match level (the match re-announces them).
	call_deferred("_connect_to_match")


func _connect_to_match() -> void:
	_match = get_tree().get_first_node_in_group("online_match")
	if _match != null and _match.has_signal("host_kill_resolved"):
		if not _match.is_connected("host_kill_resolved", Callable(self, "_on_kill_resolved")):
			_match.connect("host_kill_resolved", Callable(self, "_on_kill_resolved"))


func _process(delta: float) -> void:
	if not ExperimentFlags.whiff_recovery_enabled:
		# Flag is off. If we'd previously applied effects, undo them ONCE so nobody is left with
		# a stuck penalty multiplier or disarm (so flipping the flag off truly restores vanilla).
		if _effects_applied:
			_restore_all()
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if _match == null:
		_connect_to_match()
	_effects_applied = true  # from here on we may write multiplier/can_kill state worth undoing

	# Keep each player's penalty multiplier in step with whether they'd be windowed RIGHT NOW, so
	# the value is already correct at the instant a whiff resolves (the penalty is applied then).
	if soften_exposure_penalty_on_window:
		for player in get_tree().get_nodes_in_group("player"):
			var kill := _kill_of(player)
			if kill == null:
				continue
			var windowed := (not witness_context_enabled) or _has_witness(player)
			kill.set("exposure_penalty_multiplier", exposure_penalty_multiplier_when_windowed if windowed else 1.0)

	# Count down active recovery windows; restore the killer when theirs ends.
	for kill in _windows.keys():
		if not is_instance_valid(kill):
			_windows.erase(kill)
			continue
		_windows[kill] -= delta
		if _windows[kill] <= 0.0:
			_windows.erase(kill)
			kill.set("can_kill", true)


# Put every KillComponent back to its default state (full penalty, able to kill) and drop all
# active windows. Called when the experiment is switched off mid-session so it leaves no trace.
func _restore_all() -> void:
	for player in get_tree().get_nodes_in_group("player"):
		var kill := _kill_of(player)
		if kill != null:
			kill.set("exposure_penalty_multiplier", 1.0)
			kill.set("can_kill", true)
	_windows.clear()
	_effects_applied = false


func _on_kill_resolved(killer: Node, _victim: Node, was_valid: bool) -> void:
	if not ExperimentFlags.whiff_recovery_enabled:
		return
	if was_valid:
		return  # only a WRONG commit (civilian) triggers recovery
	if witness_context_enabled and not _has_witness(killer):
		return  # whiffed unseen → the exposure penalty stands alone (no double jeopardy)

	var kill := _kill_of(killer)
	if kill == null:
		return
	var exposure := _exposure_of(killer)
	var window := recovery_seconds_base
	if scale_recovery_with_exposure:
		window = lerp(recovery_seconds_base, recovery_seconds_max, clampf(exposure / 100.0, 0.0, 1.0))
	kill.set("can_kill", false)
	_windows[kill] = window
	if mode_root_instead_of_disarm:
		push_warning("[9A] root mode requested but not wired (no player movement-lock hook) — disarm only.")


# --- helpers ---------------------------------------------------------------

func _kill_of(player: Node) -> Node:
	return player.get_node_or_null("KillComponent")


func _exposure_of(player: Node) -> float:
	var exp := player.get_node_or_null("ExposureComponent")
	return float(exp.get("exposure")) if exp != null else 0.0


# Did any OTHER living player see `whiffer` from within witness range (clear line of sight)?
func _has_witness(whiffer: Node) -> bool:
	if whiffer == null or not is_instance_valid(whiffer):
		return false
	var here: Vector2 = whiffer.global_position
	for other in get_tree().get_nodes_in_group("player"):
		if other == whiffer or not is_instance_valid(other):
			continue
		if here.distance_to(other.global_position) > witness_range_px:
			continue
		if _clear_line_of_sight(here, other.global_position):
			return true
	return false


func _clear_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var space := get_viewport().world_2d.direct_space_state if get_viewport() != null else null
	if space == null:
		return true  # can't test → assume seen (fail toward "witnessed", the safer punish)
	var query := PhysicsRayQueryParameters2D.create(from, to, wall_collision_mask)
	var hit := space.intersect_ray(query)
	return hit.is_empty()  # nothing (no wall) in between → clear sight
