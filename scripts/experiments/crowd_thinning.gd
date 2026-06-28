extends Node

# 9B — CROWD THINNING (PHASE_9_EXPERIMENTS.md §9B). NPCs leave the map as the round ages, so the
# cover decays toward the endgame and confrontation happens naturally — the world forces the
# climax instead of a UI reveal. Lowest-risk, highest-impact item: it breaks stalls through the
# environment and never touches the hidden-identity pillar.
#
# REMOVABILITY (§1): does nothing unless ExperimentFlags.crowd_thinning_enabled is true. Host-only
# (the host owns the crowd); the despawn replicates to clients as an ordinary node removal. It
# DRIVES the crowd via neutral commands (group lookups + npc.walk_off_to) and never modifies it.
# Delete this file + its flag line and the game is unchanged.

## Don't remove anyone until the round is this far along (early game keeps full cover).
@export var thinning_starts_at_round_fraction: float = 0.5
## How many NPCs remain when the round clock expires — NOT zero, so a few cover pockets survive and
## identification stays a read, not a process of elimination.
@export var target_npc_count_at_round_end: int = 6
## Optional shaping of the removal rate across the thinning window (0..1 in → 0..1 out). Null =
## remove linearly from the start fraction to round end.
@export var thin_curve: Curve = null
## true: a retiring NPC paths to a map edge and then despawns (believable, telegraphs the thinning).
## false: it simply despawns at its spot (cheaper, less natural). Prefer walk-off.
@export var despawn_style_walk_off: bool = true
## Remove NPCs from SPARSE areas first, so the designed dense zones are the last cover standing
## (rewards players who know where the crowd pools).
@export var protect_dense_zones_last: bool = true
## Seconds between thinning checks. Coarse on purpose — thinning is gradual, not per-frame.
@export var retire_check_interval_seconds: float = 2.0
## Radius (px) used to measure how "dense" an NPC's surroundings are when picking who leaves.
@export var density_neighbor_radius_px: float = 400.0
## After a walk-off NPC is sent to an exit, free it this many seconds later (it has left view).
@export var walk_off_seconds: float = 6.0

var _match: Node = null
var _check_timer: float = 0.0
var _full_count: int = 0  ## the crowd size at full strength, captured once the crowd has spawned
var _retiring: Dictionary = {}  ## npc -> seconds left before it despawns (walk-off mode)


func _process(delta: float) -> void:
	# OFF, or not the referee → do nothing. With the flag off this is a single bool check/frame.
	if not ExperimentFlags.crowd_thinning_enabled:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	# Tick down any walk-off NPCs and free them once they've had time to leave the screen.
	for npc in _retiring.keys():
		if not is_instance_valid(npc):
			_retiring.erase(npc)
			continue
		_retiring[npc] -= delta
		if _retiring[npc] <= 0.0:
			_retiring.erase(npc)
			npc.queue_free()

	_check_timer -= delta
	if _check_timer > 0.0:
		return
	_check_timer = retire_check_interval_seconds
	_thin_step()


func _thin_step() -> void:
	if _match == null or not is_instance_valid(_match):
		_match = get_tree().get_first_node_in_group("online_match")
	if _match == null or not _match.has_method("round_fraction"):
		return

	var living := _living_npcs()
	# Capture the full crowd size the first time we see a populated crowd (it spawns all at once).
	if _full_count == 0:
		_full_count = living.size()
		if _full_count == 0:
			return

	var desired := _desired_population(_match.round_fraction())
	var surplus := living.size() - desired
	if surplus <= 0:
		return

	# Choose who leaves: sparsest-surroundings first if protecting dense zones, else arbitrary.
	# Precompute each NPC's neighbour count ONCE (not inside the comparator) to keep this cheap.
	if protect_dense_zones_last:
		var density: Dictionary = {}
		for npc in living:
			density[npc] = _neighbor_count(npc, living)
		living.sort_custom(func(a, b): return int(density[a]) < int(density[b]))
	for i in mini(surplus, living.size()):
		_retire(living[i])


# Desired live population for the current round fraction. Full until the start fraction, then
# eases down to target_npc_count_at_round_end by round end (curve-shaped if a curve is set).
func _desired_population(fraction: float) -> int:
	if fraction <= thinning_starts_at_round_fraction:
		return _full_count
	var span := maxf(0.0001, 1.0 - thinning_starts_at_round_fraction)
	var t := clampf((fraction - thinning_starts_at_round_fraction) / span, 0.0, 1.0)
	if thin_curve != null:
		t = clampf(thin_curve.sample(t), 0.0, 1.0)
	return int(round(lerp(float(_full_count), float(target_npc_count_at_round_end), t)))


func _retire(npc: Node) -> void:
	if npc == null or not is_instance_valid(npc) or _retiring.has(npc):
		return
	if despawn_style_walk_off and npc.has_method("walk_off_to"):
		var exit_point := _exit_point_for(npc)
		npc.call("walk_off_to", exit_point)
		_retiring[npc] = walk_off_seconds  # freed after it has had time to leave the view
	else:
		npc.queue_free()  # quiet despawn


# Live, retire-eligible crowd: NPCs that are not dead, not already retiring, and NOT marks (we must
# never despawn a player's contract target — that would break the round).
func _living_npcs() -> Array:
	var out: Array = []
	for node in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(node):
			continue
		if node.has_method("is_dead") and node.is_dead():
			continue
		if _retiring.has(node):
			continue
		if _is_mark(node):
			continue
		out.append(node)
	return out


func _is_mark(node: Node) -> bool:
	for group in node.get_groups():
		if String(group).begins_with("killable_for_"):
			return true
	return false


func _neighbor_count(npc: Node, pool: Array) -> int:
	var count := 0
	var here: Vector2 = npc.global_position
	# Compare SQUARED distances to avoid a square root per pair in this O(n^2) scan:
	# (dist <= radius) is identical to (dist*dist <= radius*radius), so we square the
	# radius once and use distance_squared_to (no sqrt) for the same neighbour test.
	var radius_squared := density_neighbor_radius_px * density_neighbor_radius_px
	for other in pool:
		if other != npc and here.distance_squared_to(other.global_position) <= radius_squared:
			count += 1
	return count


func _exit_point_for(npc: Node) -> Vector2:
	var map := get_tree().get_first_node_in_group("map")
	if map != null and map.has_method("random_edge_walkable_point"):
		return map.call("random_edge_walkable_point")
	return npc.global_position  # no map exit available → it'll just be freed after the timer
