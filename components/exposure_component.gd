extends Node
class_name ExposureComponent

# Exposure — UNSEEN. THE CORE TENSION SYSTEM (master_plan.md §3).
#
# WHAT THIS IS, in plain terms:
# "Exposure" is a single number from 0 to 100 that measures how much you stand
# out from the crowd. 0 = a calm, invisible civilian. 100 = a screaming beacon.
# Hunters use it to decide how easily they can spot you.
#
# *** EXPOSURE HAS THREE POOLS (the key design rule) ***
# Everything decays — nothing is permanent — but each pool at its own speed:
#   1. MOVEMENT exposure — RECOVERABLE, the FASTEST to fall. Running (and erratic
#      movement, and lurking) raise it; walking calmly brings it back down fast.
#   2. COMMITTED exposure — tools/abilities and NPC kills. A one-off spike that
#      bleeds at `committed_decay_per_second` (+25 clears in ~100s at 0.25/s).
#      A lasting tell you out-wait by going quiet, not a lifelong scar.
#   3. PLAYER-KILL heat — the SLOWEST (kill_decay_per_second, ~0.1/s). Each
#      assassination keeps you readable to YOUR hunter for most of the round:
#      the more you kill, the easier you are to find (a snowball brake).
#
# Your TOTAL exposure (what everyone reads) = all three summed, clamped 0–100.
#
# ---------------------------------------------------------------------------
# THIS COMPONENT IS A HUB — three "doors" for the rest of the game to push it:
#   DOOR 1 — update(...)            Movement, every frame → the RECOVERABLE part.
#   DOOR 2 — add_exposure(amount)   Instant one-off → the PERMANENT (committed) part.
#                                   e.g. a kill: add_exposure(30.0, "kill").
#   DOOR 3 — set_continuous_modifier(name, rate) → ongoing rise into the movement
#                                   part (e.g. while channeling a teleport).
# It is the ONE place exposure changes, which keeps bugs traceable (Principle #9)
# and every other system decoupled (Principles #3/#4).
# ---------------------------------------------------------------------------

# --- MOVEMENT TUNABLES (the recoverable part) ---
## Exposure built per second while RUNNING. Running is the biggest single source — it builds FAST.
@export var run_rise_per_second: float = 28.0

## Extra exposure per second while changing direction sharply/erratically.
@export var erratic_rise_per_second: float = 18.0

## Movement exposure bled AWAY per second while blend-walking calmly. Cut to ~1/3 of the old 16 so
## heat WEARS OFF SLOWLY — running (and lurking under a roof) build fast but linger, keeping a loud
## moment a lasting tell instead of something you shrug off in a couple of seconds.
@export var walk_fall_per_second: float = 5.3

## Movement exposure bled away per second while standing completely still. Also ~1/3 of the old 8,
## for the same slow wear-off.
@export var idle_fall_per_second: float = 2.7

## The COMMITTED (tool/NPC-kill) spike bleeds away at this many points per second, always — no
## input needed. 0.25 ≈ a +25 spike clearing in ~100s: MUCH slower than movement heat (walking
## it off), so committed actions are a lasting tell. Matches the GameRules profile value online
## (pushed at spawn); this default keeps single-player/offline on the same economy.
@export var committed_decay_per_second: float = 0.25

## The PLAYER-KILL pool bleeds away at this many points per second — the SLOWEST of all three
## pools BY DESIGN: each assassination makes you more visible to YOUR hunter for most of the
## round (0.1 ≈ a +25 kill taking ~250s to clear; two un-decayed kills sit you at the 50
## Exposed threshold). A snowball brake: the more you kill, the easier you are to find.
@export var kill_decay_per_second: float = 0.1

## A direction change bigger than this many degrees between frames counts as
## "erratic" (0 = straight line, 180 = full reverse).
@export var erratic_angle_threshold_degrees: float = 75.0

## Turn this on to print every committed (Door 2) change to the Output panel.
@export var debug_print_changes: bool = false

## Emitted whenever the TOTAL exposure value changes. The HUD listens to this.
signal exposure_changed(new_value: float)

## The live TOTAL exposure (0–100) — what the HUD, hunters, and arrow all read.
var exposure: float = 0.0

## The recoverable part (running up, walking down). Kept separate so walking can
## never erase a kill/tool commitment.
var _movement_exposure: float = 0.0

## The spike added by NPC kills/tools. Decays over time (committed_decay_per_second), not permanent.
var _committed_exposure: float = 0.0

## The spike added by PLAYER kills (Door 2b). Decays the SLOWEST (kill_decay_per_second) —
## kill heat that keeps a serial killer readable to their hunter for most of the round.
var _kill_exposure: float = 0.0

## Remembers last frame's direction so we can measure how sharply you turned.
var _last_direction: Vector2 = Vector2.ZERO

## Ongoing per-second rises from other systems, keyed by name.
var _continuous_modifiers: Dictionary = {}


# === DOOR 1: MOVEMENT (recoverable) ========================================
func update(is_running: bool, is_moving: bool, direction: Vector2, delta: float) -> void:
	var rate_per_second: float = _movement_rate_per_second(is_running, is_moving, direction)
	rate_per_second += _total_continuous_rate()
	_movement_exposure = clampf(_movement_exposure + rate_per_second * delta, 0.0, 100.0)
	# Both spike pools always bleed away over time (nothing is a permanent floor) — the
	# committed (tool/NPC-kill) pool at its rate, the player-kill pool at its slower one.
	if _committed_exposure > 0.0:
		_committed_exposure = maxf(0.0, _committed_exposure - committed_decay_per_second * delta)
	if _kill_exposure > 0.0:
		_kill_exposure = maxf(0.0, _kill_exposure - kill_decay_per_second * delta)
	_recompute_total()


# === DOOR 2: COMMITTED ONE-OFF SPIKES (then decay over time) ===============
# NPC kills and tools call this. It adds an instant spike that then bleeds away on its
# own (committed_decay_per_second) — a temporary tell, not a permanent floor.
func add_exposure(amount: float, reason: String = "") -> void:
	_committed_exposure = clampf(_committed_exposure + amount, 0.0, 100.0)
	if debug_print_changes:
		print("[Exposure] committed %+.1f (%s) -> floor %.1f, total %.1f" % [amount, reason, _committed_exposure, exposure])
	_recompute_total()


# === DOOR 2b: PLAYER-KILL HEAT (the slowest-decaying pool) ==================
# Assassinating a PLAYER calls this. Same idea as Door 2, but the spike lands in its own pool
# with the slowest decay (kill_decay_per_second) — so the more players you kill this life, the
# more visible you stay to YOUR hunter, for most of the round.
func add_kill_exposure(amount: float, reason: String = "") -> void:
	_kill_exposure = clampf(_kill_exposure + amount, 0.0, 100.0)
	if debug_print_changes:
		print("[Exposure] kill-heat %+.1f (%s) -> pool %.1f, total %.1f" % [amount, reason, _kill_exposure, exposure])
	_recompute_total()


# RESPAWN MODE (RESPAWN_MODE_PLAN.md §2): wipe ALL exposure — the recoverable movement heat AND
# both spike pools — back to zero for a fresh life. "Keep nothing" on death.
func reset() -> void:
	_movement_exposure = 0.0
	_committed_exposure = 0.0
	_kill_exposure = 0.0
	_recompute_total()


# === DOOR 3: ONGOING MODIFIERS (into the recoverable part) =================
func set_continuous_modifier(source_name: String, rate_per_second: float) -> void:
	_continuous_modifiers[source_name] = rate_per_second


func remove_continuous_modifier(source_name: String) -> void:
	_continuous_modifiers.erase(source_name)


# --- internal helpers ------------------------------------------------------

func _total_continuous_rate() -> float:
	var total: float = 0.0
	for rate in _continuous_modifiers.values():
		total += rate
	return total


# The per-second movement rate: running/erratic raise, walking/idle lower.
func _movement_rate_per_second(is_running: bool, is_moving: bool, direction: Vector2) -> float:
	var rate: float = 0.0

	# Running raises it fast.
	if is_running:
		rate += run_rise_per_second

	# Sharp/erratic turns add on top.
	if is_moving and _last_direction != Vector2.ZERO:
		var angle_change_degrees: float = abs(rad_to_deg(direction.angle_to(_last_direction)))
		if angle_change_degrees > erratic_angle_threshold_degrees:
			rate += erratic_rise_per_second

	# When NOT running, exposure cools off: standing still slowly, blend-walking faster.
	if not is_moving:
		rate -= idle_fall_per_second
	elif not is_running:
		rate -= walk_fall_per_second

	_last_direction = direction
	return rate


# Combines the two parts into the total, clamps, and announces real changes. Both parts
# decay on their own, so the total always trends back toward 0 when you go quiet.
func _recompute_total() -> void:
	var total: float = clampf(_movement_exposure + _committed_exposure + _kill_exposure, 0.0, 100.0)
	if total == exposure:
		return
	exposure = total
	exposure_changed.emit(exposure)
