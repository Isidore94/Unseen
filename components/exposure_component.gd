extends Node
class_name ExposureComponent

# Exposure — UNSEEN. THE CORE TENSION SYSTEM (master_plan.md §3).
#
# WHAT THIS IS, in plain terms:
# "Exposure" is a single number from 0 to 100 that measures how much you stand
# out from the crowd. 0 = a calm, invisible civilian. 100 = a screaming beacon.
# Hunters use it to decide how easily they can spot you.
#
# *** EXPOSURE HAS TWO PARTS (the key design rule) ***
#   1. MOVEMENT exposure — RECOVERABLE. Running (and erratic movement) raise it;
#      walking calmly and standing still bring it back down. This is the heat you
#      build by moving fast, and you can cool it off by moving like a civilian.
#   2. COMMITTED exposure — PERMANENT. Kills and tools add to this, and nothing
#      ever lowers it within the round. It acts as a FLOOR your total can never go
#      below, no matter how much you walk. This is what makes using a tool or
#      taking a kill a hard, lasting decision that locks you into less flexibility.
#
# Your TOTAL exposure (what everyone reads) = movement + committed, clamped 0–100.
# So you can always calm down from a sprint, but every kill/tool permanently
# raises the floor you're stuck above for the rest of the round.
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
## Exposure built per second while RUNNING. Running is the biggest single source.
@export var run_rise_per_second: float = 28.0

## Extra exposure per second while changing direction sharply/erratically.
@export var erratic_rise_per_second: float = 18.0

## Movement exposure bled AWAY per second while blend-walking calmly.
@export var walk_fall_per_second: float = 16.0

## Movement exposure bled away per second while standing completely still.
@export var idle_fall_per_second: float = 8.0

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

## The permanent floor added by kills/tools. Never lowered within a round.
var _committed_exposure: float = 0.0

## Remembers last frame's direction so we can measure how sharply you turned.
var _last_direction: Vector2 = Vector2.ZERO

## Ongoing per-second rises from other systems, keyed by name.
var _continuous_modifiers: Dictionary = {}


# === DOOR 1: MOVEMENT (recoverable) ========================================
func update(is_running: bool, is_moving: bool, direction: Vector2, delta: float) -> void:
	var rate_per_second: float = _movement_rate_per_second(is_running, is_moving, direction)
	rate_per_second += _total_continuous_rate()
	_movement_exposure = clampf(_movement_exposure + rate_per_second * delta, 0.0, 100.0)
	_recompute_total()


# === DOOR 2: COMMITTED, PERMANENT ONE-OFF RISES ============================
# Kills and tools call this. It raises the permanent floor; walking can't undo it.
func add_exposure(amount: float, reason: String = "") -> void:
	_committed_exposure = clampf(_committed_exposure + amount, 0.0, 100.0)
	if debug_print_changes:
		print("[Exposure] committed %+.1f (%s) -> floor %.1f, total %.1f" % [amount, reason, _committed_exposure, clampf(_movement_exposure + _committed_exposure, 0.0, 100.0)])
	_recompute_total()


# RESPAWN MODE (RESPAWN_MODE_PLAN.md §2): wipe ALL exposure — both the recoverable movement heat AND
# the permanent committed floor — back to zero for a fresh life. "Keep nothing" on death.
func reset() -> void:
	_movement_exposure = 0.0
	_committed_exposure = 0.0
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


# Combines the two parts into the total, clamps, and announces real changes. The
# committed floor means the total can never fall below _committed_exposure.
func _recompute_total() -> void:
	var total: float = clampf(_movement_exposure + _committed_exposure, 0.0, 100.0)
	if total == exposure:
		return
	exposure = total
	exposure_changed.emit(exposure)
