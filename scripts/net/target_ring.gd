class_name TargetRing
extends RefCounted

# TargetRing — UNSEEN (plan.md §3.2, first bite of the TargetGraph service).
#
# PURE MATH for "who hunts whom". No nodes, no network, no scene access — every function takes
# plain arrays/dictionaries and returns a hunter -> prey Dictionary. That purity is the point:
# dev_tests/ can exercise every ring shape headlessly, and OnlineMatch stays the only place that
# touches players. Peers are ints; 2-4 players is the design range, so the exhaustive searches
# below are tiny (at most 4! = 24 orderings).
#
# Two modes (the lobby's "Rotating targets" option picks one):
#   from_seats() — STATIC: your prey is the next LIVING player in the fixed seat order, so your
#                  target is always the same person whenever both of you are alive.
#   rotating()   — a fresh RANDOM cycle each rebuild that avoids giving any hunter the prey
#                  listed in `forbidden` (the target they had last life). When no full cycle can
#                  satisfy everyone, it degrades to the best PATH: everyone still gets a prey
#                  except the path's tail, who WAITS (absent from the result) until the next
#                  death reshuffles the board.


# STATIC ring: for each living hunter (walking the fixed seat order), prey = the next living
# seat after them. Mirrors the classic behaviour exactly: one valid cycle over the living,
# no self-target, and at exactly 2 alive the pair is mutual.
static func from_seats(seat_order: Array, living: Array) -> Dictionary:
	var ring: Dictionary = {}
	var n := seat_order.size()
	for i in n:
		var hunter: int = int(seat_order[i])
		if not living.has(hunter):
			continue
		for step in range(1, n):
			var cand: int = int(seat_order[(i + step) % n])
			if cand != hunter and living.has(cand):
				ring[hunter] = cand
				break
	return ring


# ROTATING ring: a random assignment over `living` where no hunter gets forbidden[hunter].
# Preference order (first that exists wins):
#   1. a full CYCLE with zero forbidden edges — everyone has one hunter and one prey;
#   2. a PATH with zero forbidden edges — everyone assigned except the tail, who WAITS
#      (no entry in the result; the path's head is temporarily unhunted);
#   3. a plain random cycle ignoring `forbidden` — the match must never stall entirely.
# With 2 living players the pair is mutual regardless of `forbidden` (there IS no other target;
# freshness comes from the respawn look change instead).
static func rotating(living: Array, forbidden: Dictionary) -> Dictionary:
	var peers := living.duplicate()
	if peers.size() < 2:
		return {}
	if peers.size() == 2:
		return {int(peers[0]): int(peers[1]), int(peers[1]): int(peers[0])}
	var orders := _all_orderings(peers)
	orders.shuffle()  # exhaustive but randomised, so valid shapes are picked uniformly
	for order in orders:
		var cycle := _cycle_from(order)
		if _violations(cycle, forbidden) == 0:
			return cycle
	for order in orders:
		var path := _path_from(order)
		if _violations(path, forbidden) == 0:
			return path
	return _cycle_from(orders[0])  # nothing satisfies everyone — a stalled match is worse


# Every living peer that is ALIVE but has no prey in `ring` (rotating mode's WAITING players).
static func waiting_peers(ring: Dictionary, living: Array) -> Array:
	var out: Array = []
	for p in living:
		if not ring.has(int(p)):
			out.append(int(p))
	return out


# --- internals ----------------------------------------------------------------------------------

# order [A,B,C] -> {A:B, B:C, C:A} (a closed loop: the last hunts the first).
static func _cycle_from(order: Array) -> Dictionary:
	var ring: Dictionary = {}
	for i in order.size():
		ring[int(order[i])] = int(order[(i + 1) % order.size()])
	return ring


# order [A,B,C] -> {A:B, B:C} (an open chain: the tail C waits, the head A is unhunted).
static func _path_from(order: Array) -> Dictionary:
	var ring: Dictionary = {}
	for i in order.size() - 1:
		ring[int(order[i])] = int(order[i + 1])
	return ring


# How many hunter->prey edges land on that hunter's forbidden prey.
static func _violations(ring: Dictionary, forbidden: Dictionary) -> int:
	var count := 0
	for hunter in ring:
		if forbidden.has(hunter) and int(ring[hunter]) == int(forbidden[hunter]):
			count += 1
	return count


# All orderings (permutations) of `peers` — at most 24 for a 4-player match, so brute force is
# both the simplest AND a provably complete search (no "random tries" that can miss a shape).
static func _all_orderings(peers: Array) -> Array:
	if peers.size() <= 1:
		return [peers.duplicate()]
	var out: Array = []
	for i in peers.size():
		var rest := peers.duplicate()
		var head = rest.pop_at(i)
		for tail in _all_orderings(rest):
			var order: Array = [head]
			order.append_array(tail)
			out.append(order)
	return out
