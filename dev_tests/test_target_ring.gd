extends Node
# TARGET RING TEST (plan.md §3.2 — see dev_tests/README.md).
# Proves the pure TargetRing math both modes of the lobby's "Rotating targets" option rely on:
#   STATIC   — from_seats(): next-living-seat rings, dead-skipping, mutual 2-player pairs.
#   ROTATING — rotating(): a fresh (non-forbidden) prey whenever one exists, a clean WAIT
#              (targetless tail) when it doesn't, and never a stalled match.


var _failures: Array[String] = []


func _check(label: String, ok: bool) -> void:
	print("  %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures.append(label)


# A structurally sound assignment: nobody self-targets, every prey is living, and no prey has
# two hunters. (Cycles AND paths both must satisfy this.)
func _is_sound(ring: Dictionary, living: Array) -> bool:
	var hunted: Array = []
	for hunter in ring:
		var prey: int = int(ring[hunter])
		if prey == int(hunter) or not living.has(prey) or hunted.has(prey):
			return false
		hunted.append(prey)
	return true


func _ready() -> void:
	# --- STATIC (from_seats) ---------------------------------------------------------------
	var seats: Array = [10, 20, 30, 40]
	var ring: Dictionary = TargetRing.from_seats(seats, [10, 20, 30, 40])
	_check("static: full ring follows seat order",
		ring == {10: 20, 20: 30, 30: 40, 40: 10})
	ring = TargetRing.from_seats(seats, [10, 30, 40])
	_check("static: dead seat is skipped (hunter and prey)",
		ring == {10: 30, 30: 40, 40: 10})
	ring = TargetRing.from_seats(seats, [20, 40])
	_check("static: two living = mutual pair", ring == {20: 40, 40: 20})
	_check("static: one living = empty ring", TargetRing.from_seats(seats, [10]).is_empty())

	# --- ROTATING: basics --------------------------------------------------------------------
	var living: Array = [1, 2, 3, 4]
	var ok := true
	for _i in 50:
		ring = TargetRing.rotating(living, {})
		if not _is_sound(ring, living) or ring.size() != 4:
			ok = false
	_check("rotating: no constraints = always a sound full cycle", ok)
	ring = TargetRing.rotating([1, 2], {1: 2, 2: 1})
	_check("rotating: 2 players = mutual pair even when forbidden", ring == {1: 2, 2: 1})

	# --- ROTATING: freshness is guaranteed when a fresh cycle exists --------------------------
	ok = true
	for _i in 50:
		ring = TargetRing.rotating([1, 2, 3, 4], {1: 2})
		if ring.size() != 4 or int(ring[1]) == 2 or not _is_sound(ring, living):
			ok = false
	_check("rotating: forbidden prey never dealt when avoidable (4p)", ok)
	# 3 players with one constraint: exactly one cycle satisfies it — must always be chosen.
	ok = true
	for _i in 25:
		ring = TargetRing.rotating([1, 2, 3], {1: 2})
		if ring != {1: 3, 3: 2, 2: 1}:
			ok = false
	_check("rotating: 3p single constraint picks the only valid cycle", ok)

	# --- ROTATING: impossible cycle degrades to a WAIT, never a violation ---------------------
	# 3 players where 1 and 2 forbid each other: both 3-cycles are blocked, so someone waits.
	ok = true
	var waited: Array = []
	for _i in 50:
		var forbidden := {1: 2, 2: 1}
		ring = TargetRing.rotating([1, 2, 3], forbidden)
		var waiting: Array = TargetRing.waiting_peers(ring, [1, 2, 3])
		if ring.size() != 2 or waiting.size() != 1 or not _is_sound(ring, [1, 2, 3]):
			ok = false
		for hunter in ring:
			if forbidden.has(hunter) and int(ring[hunter]) == int(forbidden[hunter]):
				ok = false  # a violation slipped through
		for w in waiting:
			if not waited.has(w):
				waited.append(w)
	_check("rotating: blocked cycle -> exactly one waits, zero violations", ok)
	_check("rotating: the waiter varies (not always the same player)", waited.size() >= 2)

	# --- ROTATING: total impossibility still returns a playable ring --------------------------
	# Every hunter forbids every possible... closest we can get with one entry each: a 2-ring
	# is exempt, so force it via 3 players all forbidding their only path-tail options is not
	# constructible — instead prove the documented fallback: even absurd constraints yield a
	# non-empty assignment (the match must never stall with zero contracts).
	ring = TargetRing.rotating([1, 2, 3], {1: 2, 2: 3, 3: 1})
	_check("rotating: heavy constraints still yield contracts", not ring.is_empty())
	_check("rotating: heavy-constraint result is sound", _is_sound(ring, [1, 2, 3]))

	if _failures.is_empty():
		print("ALL PASS (target ring)")
	else:
		print("FAILURES: %d" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
