extends Node
# CONTRACT RULES TEST (plan.md §3.1/§3.3 — see dev_tests/README.md).
# Proves the attack matrix on a real KillComponent: assigned prey dies; a stranger (human,
# not your contract) survives but rattles the blade for interference_lockout_seconds; your
# hunter gets counter-stunned even mid-lockout; an innocent NPC dies (whiff) with the full
# npc_kill_cooldown_seconds lock; and a player kill starts NO lockout.


class TestBody:
	extends CharacterBody2D
	var controlling_peer_id: int = 0
	var _net_frozen: bool = false
	var dead: bool = false

	func die() -> void:
		dead = true

	func is_dead() -> bool:
		return dead


var _failures: Array[String] = []


func _check(label: String, ok: bool) -> void:
	print("  %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures.append(label)


func _make_body(peer: int, groups: Array, at: Vector2) -> TestBody:
	var body := TestBody.new()
	body.controlling_peer_id = peer
	add_child(body)
	body.global_position = at
	for group_name in groups:
		body.add_to_group(group_name)
	return body


func _ready() -> void:
	var attacker := _make_body(1, [], Vector2(100, 100))
	var exposure := ExposureComponent.new()
	exposure.name = "ExposureComponent"
	attacker.add_child(exposure)
	var kill := KillComponent.new()
	kill.name = "KillComponent"
	attacker.add_child(kill)

	var interfered: Array[int] = [0]
	kill.interference_committed.connect(func(_victim: Node2D) -> void: interfered[0] += 1)
	var lockouts: Array = []
	kill.kill_lockout_started.connect(func(seconds: float, reason: String) -> void:
		lockouts.append([seconds, reason]))
	var stuns: Array[int] = [0]
	kill.counter_stun_requested.connect(func(_target: Node2D) -> void: stuns[0] += 1)

	var near := attacker.global_position + Vector2(10, 0)

	# 1) Strike a HUMAN who is neither prey nor hunter -> interference + short lockout.
	var stranger := _make_body(2, ["player"], near)
	kill.request_kill(stranger.get_path())
	_check("stranger survives (interference)", stranger.dead == false)
	_check("interference signal fired once", interfered[0] == 1)
	_check("interference adds NO exposure", exposure.exposure == 0.0)
	_check("interference lockout ~%.1fs" % kill.interference_lockout_seconds,
		absf(kill.kill_lockout_left() - kill.interference_lockout_seconds) < 0.2)
	_check("lockout reason = interference",
		lockouts.size() == 1 and String(lockouts[0][1]) == "interference")

	# 2) While rattled, even your ASSIGNED PREY is safe.
	var prey := _make_body(3, ["player", "killable_for_1"], near)
	kill.request_kill(prey.get_path())
	_check("prey safe while blade rattled", prey.dead == false)

	# 3) Counter-stunning your HUNTER stays legal during the lockout.
	kill.stun_only_peer = 4
	var hunter := _make_body(4, ["player"], near)
	kill.request_kill(hunter.get_path())
	_check("counter-stun legal during lockout", stuns[0] == 1)

	# 4) Lockout over -> the prey kill lands, and a PLAYER kill starts NO lockout.
	kill._kill_lockout_until_msec = 0
	kill.request_kill(prey.get_path())
	_check("prey dies once blade is free", prey.dead == true)
	_check("player kill starts no lockout", kill.kill_lockout_left() == 0.0)
	_check("player kill heats the SLOW kill pool",
		absf(exposure._kill_exposure - kill.player_kill_exposure_spike) < 0.01)
	_check("player kill leaves the committed pool alone", exposure._committed_exposure == 0.0)

	# 5) An innocent NPC still dies (whiff), spikes exposure, and locks the blade FULLY.
	var npc := _make_body(0, [], near)
	kill.request_kill(npc.get_path())
	_check("innocent NPC dies (whiff)", npc.dead == true)
	_check("npc-kill lockout ~%.1fs" % kill.npc_kill_cooldown_seconds,
		absf(kill.kill_lockout_left() - kill.npc_kill_cooldown_seconds) < 0.2)
	_check("second lockout reason = npc_kill",
		lockouts.size() == 2 and String(lockouts[1][1]) == "npc_kill")
	_check("civilian whiff adds wrong_commit_exposure (committed pool)",
		absf(exposure._committed_exposure - kill.wrong_commit_exposure) < 0.01)

	# 6) Your NPC MARK: a clean kill, but the NOISY kind — committed spike + blade lock.
	kill._kill_lockout_until_msec = 0
	var committed_before_mark: float = exposure._committed_exposure
	var mark := _make_body(0, ["killable_for_1"], near)
	kill.request_kill(mark.get_path())
	_check("NPC mark dies (clean kill)", mark.dead == true)
	_check("NPC mark kill adds kill_exposure_spike (committed pool)",
		absf(exposure._committed_exposure - (committed_before_mark + kill.kill_exposure_spike)) < 0.01)
	_check("NPC mark kill locks the blade",
		absf(kill.kill_lockout_left() - kill.npc_kill_cooldown_seconds) < 0.2)

	# 7) DECAY ORDERING: one calm 10-second tick — everything falls, at three different speeds.
	var committed_before_tick: float = exposure._committed_exposure
	var kill_heat_before_tick: float = exposure._kill_exposure
	exposure.update(false, false, Vector2.ZERO, 10.0)
	_check("committed pool bled at committed_decay_per_second",
		absf((committed_before_tick - exposure._committed_exposure) - exposure.committed_decay_per_second * 10.0) < 0.01)
	_check("player-kill heat bled at kill_decay_per_second",
		absf((kill_heat_before_tick - exposure._kill_exposure) - exposure.kill_decay_per_second * 10.0) < 0.01)
	_check("decay ordering: movement fastest, player-kill slowest",
		exposure.walk_fall_per_second > exposure.committed_decay_per_second \
		and exposure.committed_decay_per_second > exposure.kill_decay_per_second)

	if _failures.is_empty():
		print("ALL PASS (contract rules)")
	else:
		print("FAILURES: %d" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
