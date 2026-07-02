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

## Fallback crowd size, used only when the map can't report its walkable area.
@export var npc_count: int = 25

## Crowd DENSITY: NPCs per open street cell, when the map reports its size
## (TestMap01.open_cell_count). Sizing by density instead of a fixed count keeps the
## "haystack" equally thick on every map — a bigger map automatically gets a bigger crowd.
## 0 = always use npc_count.
@export var npcs_per_open_cell: float = 0.45
## Bounds on the derived crowd (readability floor / simulation-cost ceiling).
@export var crowd_size_min: int = 30
@export var crowd_size_max: int = 110


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

	var map := get_tree().get_first_node_in_group("map")
	var navigation_map: RID = get_world_2d().navigation_map

	# Size the crowd to the map's walkable area when it can tell us (density model —
	# matches how the online match sizes its crowd, so offline feel mirrors online).
	var crowd_size := npc_count
	if map != null and npcs_per_open_cell > 0.0 and map.has_method("open_cell_count"):
		crowd_size = clampi(int(round(float(map.call("open_cell_count")) * npcs_per_open_cell)), crowd_size_min, crowd_size_max)

	# EVEN spread: one spawn per NPC spaced across the whole map, so the crowd starts
	# corner-to-corner. From there the errand system keeps them flowing (npc.gd).
	var even_points: Array = []
	if map != null and map.has_method("even_spawn_points"):
		even_points = map.call("even_spawn_points", crowd_size)

	for i in crowd_size:
		var npc: Node2D = npc_scene.instantiate()
		# Choose the spawn spot FIRST, then set it BEFORE add_child, so the NPC's _ready()
		# captures the right home/anchor position the moment it enters the tree.
		var spawn_point: Vector2
		if i < even_points.size():
			spawn_point = even_points[i]
		elif map != null and map.has_method("random_walkable_point"):
			spawn_point = map.call("random_walkable_point")
		else:
			spawn_point = NavigationServer2D.map_get_random_point(navigation_map, 1, true)
		npc.position = spawn_point
		add_child(npc)


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
