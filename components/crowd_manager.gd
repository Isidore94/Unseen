extends Node2D
class_name CrowdManager

# CrowdManager — UNSEEN, Phase 2. Spawns and owns the civilian crowd.
#
# WHAT IT DOES, in plain terms:
# On start, it stamps out a number of NPC copies and drops each one at a random
# spot on the walkable floor. The NPCs become its children, so the whole crowd is
# tidily grouped under this one node in the scene tree. It also answers the
# question "how many NPCs are near this point?" — which the exposure system will
# use next to make dense crowds good cover (master_plan §3/§4).
#
# WHY A MANAGER instead of placing NPCs by hand:
# 20–30 hand-placed NPCs would be tedious and rigid. A manager lets us change the
# crowd size with one number, spawn at valid navigation points automatically, and
# later maintain the population (respawn, density zones) from one place (Principle #3).

## The NPC scene to spawn copies of. Set in the Inspector to npc.tscn.
@export var npc_scene: PackedScene

## How many civilians to spawn. One knob to make the crowd denser or sparser.
@export var npc_count: int = 25


func _ready() -> void:
	# Wait until after the map's navigation has synced before spawning, so we can
	# ask the navigation system for valid floor positions.
	call_deferred("_spawn_crowd")


func _spawn_crowd() -> void:
	if npc_scene == null:
		push_warning("CrowdManager has no npc_scene assigned — no crowd spawned.")
		return

	# Let the navigation mesh finish registering (it's set up this same frame).
	await get_tree().physics_frame

	# Prefer the map's EVEN spawn spread (scatters the crowd across the whole map);
	# fall back to a navigation random point if the map doesn't provide one.
	var map := get_tree().get_first_node_in_group("map")
	var use_map_spread: bool = map != null and map.has_method("random_walkable_point")
	var navigation_map: RID = get_world_2d().navigation_map

	for i in npc_count:
		var npc: Node2D = npc_scene.instantiate()
		add_child(npc)
		if use_map_spread:
			npc.global_position = map.call("random_walkable_point")
		else:
			npc.global_position = NavigationServer2D.map_get_random_point(navigation_map, 1, true)


# Counts how many living NPCs are within `radius` pixels of a world position.
# The exposure system will call this next: standing inside a dense cluster lowers
# exposure faster (you're camouflaged); being alone in the open is exposing.
func count_npcs_near(world_position: Vector2, radius: float) -> int:
	var count: int = 0
	# Compare SQUARED distances: distance_squared_to skips the square root that
	# distance_to does. We only need to know if each NPC is inside the radius, and
	# (dist <= radius) is the same test as (dist*dist <= radius*radius), so the
	# result is identical — just cheaper, which matters across 60+ NPCs. Square the
	# radius once here instead of un-squaring every NPC's distance in the loop.
	var radius_squared := radius * radius
	for child in get_children():
		if child is Npc and child.global_position.distance_squared_to(world_position) <= radius_squared:
			count += 1
	return count
