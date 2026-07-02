extends Node
class_name ItemComponent

# Item kit — UNSEEN, the class/tool system (master_plan §9). Each player brings TWO tools, picked
# in the lobby, fired by item_primary (slot 0) / item_secondary (slot 1). Tools are CHARGE-BASED
# (a fixed number of uses per match) AND most have a COOLDOWN between uses, so timing matters.
#
# THE TOOL POOL (AC-Rearmed-style):
#   SMOKE    — deploy a cloud at your feet; anyone caught inside (a lunging hunter included) is
#              STUNNED for a few seconds and can't kill. Offensive (stun your mark, walk in) or
#              defensive (pop it as a hunter closes, walk away). The cloud is wide (~4-5 bodies).
#   DISGUISE — for 30s you look like a generic NPC to everyone else, breaking a pursuer's lock.
#   MORPH    — turn nearby civilians into copies of YOU, so a hunter can't tell which is real.
#   DECOY    — used on an NPC in kill range: it bolts, baiting the hunter into a wrong kill.
#   POISON   — kill on a delay: the target drops a few seconds later, so you're long gone.
#
# THIS COMPONENT owns only the BOOKKEEPING (which tools, charges, cooldowns, active timers). The
# actual WORLD EFFECT (spawning the cloud, stunning a player, re-skinning NPCs, the delayed death)
# is applied by the AUTHORITY's match script via the `tool_activated` / `tool_expired` signals —
# that's where the world access + server-authority live (Principle #1/#3, buildplan §7.6).
#
# Authority: offline this copy acts directly. Online the controlling client only READS its keys and
# sends a request; the HOST owns charges + effects and applies them (server-authoritative).

enum Tool { SMOKE, DISGUISE, MORPH, DECOY, POISON, FIRECRACKER, CLONES }

## The TWO tools this player brought, by slot (0 = item_primary key, 1 = item_secondary key).
## Set from the lobby pick (online: stamped into spawn data; offline: left at this default).
@export var equipped: Array[int] = [Tool.SMOKE, Tool.DECOY]

## True once this player is eliminated (set by Player.die on every machine). A dead player reads no
## keys and can't activate a tool — but the authority's timers keep ticking so any tool that was
## already active still expires/reverts cleanly.
var owner_dead: bool = false

## True while this player is STUNNED (smoke cloud / firecracker / counter-stun). Set by the host on
## its authoritative copy (OnlineMatch._set_player_stunned), so a stunned player can't fire tools —
## stunned means can't move, can't kill, AND can't tool your way out (no smoke-inside-a-smoke).
## The client's own copy never learns it; the host rejecting the relayed request is what counts.
var owner_stunned: bool = false

# === per-tool tunables (charges / cooldown / effect, all editable — Principle #6) ============
## SMOKE
@export var smoke_charges: int = 1
@export var smoke_cooldown_seconds: float = 18.0
## Cloud radius in world px. ~2 character-widths — tight enough to be a deliberate placement
## (covers a hunter right on top of you, not half the street).
@export var smoke_cloud_radius: float = 110.0
## How long the cloud lingers (and keeps catching people who walk in), and how long a caught
## person stays stunned (can't move, can't kill).
@export var smoke_cloud_seconds: float = 4.5
@export var smoke_stun_seconds: float = 3.0
## DISGUISE — look like the targeted civilian to others for this long. Was 30s: at half a
## minute (with charge regen) a player could be visually anonymous ~40% of a 5-minute round,
## which hard-countered the reveal/faceplate system — the hunter's only ID tool. 14s turns it
## into a "walk calmly past your hunter" window instead of a passive identity eraser.
@export var disguise_charges: int = 1
@export var disguise_cooldown_seconds: float = 0.0
@export var disguise_seconds: float = 14.0
## Moving faster than this (px/s) BREAKS an active disguise — running blows your cover, the
## classic AC rule. Sits between the walk speed (90) and run speed (220), so blend-walking
## keeps the disguise and sprinting sheds it. Enforced by the authority (host online).
@export var disguise_break_speed: float = 140.0
## MORPH — re-skin this many nearby NPCs to your look, for this long.
@export var morph_charges: int = 1
@export var morph_cooldown_seconds: float = 0.0
@export var morph_seconds: float = 12.0
@export var morph_npc_count: int = 4
@export var morph_radius: float = 360.0
## DECOY — how far an NPC must be to be "in kill range" to spook, and how long it bolts.
@export var decoy_charges: int = 2
@export var decoy_cooldown_seconds: float = 8.0
@export var decoy_range: float = 110.0
@export var decoy_flee_seconds: float = 4.0
## POISON — delay before the poisoned target drops.
@export var poison_charges: int = 1
@export var poison_cooldown_seconds: float = 0.0
@export var poison_delay_seconds: float = 4.0
## FIRECRACKER — instant flashbang burst that briefly stuns nearby players (its radius + stun length
## live on OnlineMatch since the effect is applied there).
@export var firecracker_charges: int = 1
@export var firecracker_cooldown_seconds: float = 12.0
## CLONES — turn the nearest crowd NPCs into moving copies of YOU that mirror your heading for a few
## seconds, so a hunter sees several identical bodies and can't tell which is real. The spawn + the
## per-frame "drive them in your direction" effect are applied by the authority's match script; this
## component just owns the charge/cooldown bookkeeping (Principle #1/#3).
@export var clones_charges: int = 1
@export var clones_cooldown_seconds: float = 20.0
## How long the clones keep mirroring you before they revert to ordinary crowd (seconds).
@export var clones_seconds: float = 6.0
## How many copies to make (the two the design calls for).
@export var clones_count: int = 2
## Only crowd NPCs within this many world px of you can be converted into a clone.
@export var clones_radius: float = 300.0
## Safety cap on a clone's speed, as a multiple of an NPC's normal walk speed, so a sprinting caster's
## clones can keep pace without teleporting. 1.0 = NPC walk speed.
@export var clones_max_speed_scale: float = 3.0
## How far (px) each clone's DIVERGING walk target sits from the caster. Clones now fan out on
## their own navigation paths (left/right/behind your heading) at your pace, instead of mirroring
## your heading in lockstep — a synchronized trio was itself a tell that marked the whole group.
@export var clones_scatter_distance_px: float = 420.0

## Exposure (0-100) ADDED to the user each time an ability is used — a FLAT spike for every tool, so
## any ability use reads the same on your hunter's arrow. It then decays over ~a minute
## (ExposureComponent.committed_decay_per_second). POISON is the deliberate exception (a silent kill:
## NO spike — see exposure_for_tool). Applied by the authority.
@export var ability_exposure_spike: float = 25.0

## Input actions (one per slot). Local co-op assigns each player its own (p1_/p2_).
@export var item_primary_action: String = "item_primary"
@export var item_secondary_action: String = "item_secondary"

## Fired when a tool is used (the authority applies the world effect) and when its duration ends.
signal tool_activated(tool: int, slot: int)
signal tool_expired(tool: int, slot: int)
## (Online) THIS machine's player pressed a slot key but isn't the authority — the Player relays
## this slot index to the host as a request (server-authoritative).
signal item_requested(slot: int)
## Emitted (host) when a spent charge regenerates, so the match can refresh the owner's ability HUD.
signal charges_regenerated(slot: int)

## CHARGE REGEN: a spent charge comes back after this many seconds (0 = no regen — the classic
## consumable kit). One charge regenerates at a time, up to each tool's max. Host-authoritative.
## 30s (was 60): in a 5-minute round a minute-long recharge read as "my tool is gone forever" —
## half that keeps tools in rotation while still making each use a real decision.
@export var charge_regen_seconds: float = 30.0

# Per-SLOT live state (index 0 / 1).
var _charges: Array[int] = [0, 0]
var _regen_left: Array[float] = [0.0, 0.0]  ## seconds until the next charge regenerates, per slot
## PvE LADDER (RESPAWN_MODE_PLAN.md §6): which tool slots are usable THIS life. Base respawn life
## unlocks only slot 0 (your first lobby tool); the ladder's TOOL upgrade unlocks slot 1. [true, true]
## (the default) = both usable, so classic/elimination play is unchanged.
var slot_unlocked: Array[bool] = [true, true]
## SWIFT perk: multiplies every tool's cooldown (1.0 = normal). Set by OnlineMatch on the host copy.
var cooldown_scale: float = 1.0
var _cooldown_left: Array[float] = [0.0, 0.0]
var _active_left: Array[float] = [0.0, 0.0]   # seconds the slot's durational effect has left (HUD)

## Online wiring, set by Player._setup_network_role. Offline leaves the defaults so this component
## reads input AND applies effects locally, exactly as a single-player kit.
var network_mode: bool = false
var server_authoritative: bool = true   ## this copy owns charges + timers (host online; everyone offline)
var local_input: bool = true            ## this copy reads THIS machine's keys


func _ready() -> void:
	_refill_charges()


# (Re)stock each slot from its tool's charge count. Called on ready and whenever `equipped` changes
# (the host sets equipped from spawn data, then calls this).
func _refill_charges() -> void:
	for slot in 2:
		_charges[slot] = charges_for_tool(_tool(slot))
		_regen_left[slot] = charge_regen_seconds  # full now → the regen timer is ready for the next spend


func apply_equipped(tools: Array) -> void:
	if tools.size() >= 2:
		equipped = [int(tools[0]), int(tools[1])]
	_refill_charges()


# RESPAWN MODE (RESPAWN_MODE_PLAN.md §2): restock a fresh life — refill every charge and clear all
# cooldown/active timers, back to the lobby-picked loadout. (The core loop never mutates `equipped`;
# the PvE ladder will, and should re-apply the base loadout before calling this.)
func reset_to_base() -> void:
	_refill_charges()
	for slot in 2:
		_cooldown_left[slot] = 0.0
		_active_left[slot] = 0.0


# PvE LADDER: base respawn life uses only slot 0 (your first lobby tool); the ladder unlocks slot 1.
func set_base_life_lock() -> void:
	slot_unlocked = [true, false]

func unlock_slot(slot: int) -> void:
	if slot >= 0 and slot < slot_unlocked.size():
		slot_unlocked[slot] = true


# === per-tool config lookups (one place, so tunables never drift) ==========================
func charges_for_tool(tool: int) -> int:
	match tool:
		Tool.SMOKE: return smoke_charges
		Tool.DISGUISE: return disguise_charges
		Tool.MORPH: return morph_charges
		Tool.DECOY: return decoy_charges
		Tool.POISON: return poison_charges
		Tool.FIRECRACKER: return firecracker_charges
		Tool.CLONES: return clones_charges
	return 1

func exposure_for_tool(tool: int) -> float:
	# POISON is silent — no exposure spike (that's the whole point of a quiet kill). Every other
	# ability adds the same flat spike.
	if tool == Tool.POISON:
		return 0.0
	return ability_exposure_spike

func cooldown_for_tool(tool: int) -> float:
	match tool:
		Tool.SMOKE: return smoke_cooldown_seconds
		Tool.DISGUISE: return disguise_cooldown_seconds
		Tool.MORPH: return morph_cooldown_seconds
		Tool.DECOY: return decoy_cooldown_seconds
		Tool.POISON: return poison_cooldown_seconds
		Tool.FIRECRACKER: return firecracker_cooldown_seconds
		Tool.CLONES: return clones_cooldown_seconds
	return 0.0

# Duration of the slot's "active" readout (0 for instant tools). Smoke counts the cloud's life.
func duration_for_tool(tool: int) -> float:
	match tool:
		Tool.SMOKE: return smoke_cloud_seconds
		Tool.DISGUISE: return disguise_seconds
		Tool.MORPH: return morph_seconds
		Tool.CLONES: return clones_seconds
	return 0.0

static func tool_name(tool: int) -> String:
	match tool:
		Tool.SMOKE: return "SMOKE"
		Tool.DISGUISE: return "DISGUISE"
		Tool.MORPH: return "MORPH"
		Tool.DECOY: return "DECOY"
		Tool.POISON: return "POISON"
		Tool.FIRECRACKER: return "FIRECRACKER"
		Tool.CLONES: return "CLONES"
	return "—"

# A MatchHud icon id for each tool (we reuse the existing PixelLab UI icons).
static func tool_icon(tool: int) -> String:
	match tool:
		Tool.SMOKE: return "ui_hide"
		Tool.DISGUISE: return "ui_disguise"
		Tool.MORPH: return "ui_intel"
		Tool.DECOY: return "ui_flag"
		Tool.POISON: return "ui_target"
		Tool.FIRECRACKER: return "ui_flag"
		Tool.CLONES: return "ui_intel"
	return "ui_coin"


# === slot helpers the HUD reads ============================================================
func _tool(slot: int) -> int:
	return int(equipped[slot]) if slot >= 0 and slot < equipped.size() else Tool.SMOKE

func tool_in_slot(slot: int) -> int:
	return _tool(slot)

func charges_left_slot(slot: int) -> int:
	return _charges[slot]

func cooldown_left_slot(slot: int) -> float:
	return _cooldown_left[slot]

func active_left_slot(slot: int) -> float:
	return _active_left[slot]

# Seconds until this slot's next charge regenerates, or 0 when it's already full (so the HUD
# only shows a recharge countdown while one is actually pending).
func regen_left_slot(slot: int) -> float:
	if charge_regen_seconds <= 0.0 or _charges[slot] >= charges_for_tool(_tool(slot)):
		return 0.0
	return maxf(0.0, _regen_left[slot])

func is_active_slot(slot: int) -> bool:
	return _active_left[slot] > 0.0


func _physics_process(delta: float) -> void:
	# Read this machine's slot keys (only on the copy that controls this player, and not when dead).
	if local_input and not owner_dead:
		if Input.is_action_just_pressed(item_primary_action):
			_on_press(0)
		if Input.is_action_just_pressed(item_secondary_action):
			_on_press(1)

	# Only the authority (host online, or everyone offline) owns cooldown + active timers.
	if not server_authoritative:
		return
	for slot in 2:
		if _cooldown_left[slot] > 0.0:
			_cooldown_left[slot] = maxf(0.0, _cooldown_left[slot] - delta)
		# DISGUISE breaks on RUNNING (the classic AC rule): the authority watches the owner's
		# actual body speed, so a sprint sheds the disguise immediately. Checked before the
		# normal countdown so the expiry fires this same frame (and only once — the countdown
		# below skips a slot already at 0).
		if _active_left[slot] > 0.0 and _tool(slot) == Tool.DISGUISE:
			var body := get_parent() as CharacterBody2D
			if body != null and body.velocity.length() > disguise_break_speed:
				_active_left[slot] = 0.0
				tool_expired.emit(Tool.DISGUISE, slot)
		if _active_left[slot] > 0.0:
			_active_left[slot] = maxf(0.0, _active_left[slot] - delta)
			if _active_left[slot] == 0.0:
				tool_expired.emit(_tool(slot), slot)
		# CHARGE REGEN: while below the tool's max, count down and refill ONE charge each interval.
		if charge_regen_seconds > 0.0:
			var max_charges := charges_for_tool(_tool(slot))
			if _charges[slot] < max_charges:
				_regen_left[slot] -= delta
				if _regen_left[slot] <= 0.0:
					_charges[slot] += 1
					_regen_left[slot] = charge_regen_seconds  # arm the next charge's timer
					charges_regenerated.emit(slot)            # → host refreshes the owner's HUD
			else:
				_regen_left[slot] = charge_regen_seconds  # full → keep the timer ready for the next spend


# A press on the controlling machine: act if we're the authority, else relay a request to the host.
func _on_press(slot: int) -> void:
	if slot >= 0 and slot < slot_unlocked.size() and not slot_unlocked[slot]:
		return  # PvE ladder: this slot isn't unlocked this life
	if server_authoritative:
		_activate(slot)
	else:
		item_requested.emit(slot)


# Host entry point: a slot request from the controlling client, already verified by the Player.
func server_activate(slot: int) -> void:
	_activate(slot)


# Give back a slot's charge + clear its cooldown/active timers — used by the authority when a tool
# that NEEDS a target (disguise, decoy) was fired with nothing valid in the ring, so it isn't wasted.
func refund(slot: int) -> void:
	if slot < 0 or slot > 1:
		return
	_charges[slot] += 1
	_cooldown_left[slot] = 0.0
	_active_left[slot] = 0.0


# Spend a charge + start the cooldown/active timer for the slot, then announce it so the AUTHORITY's
# match script applies the actual world effect. Refuses if out of charges, on cooldown, or active.
func _activate(slot: int) -> void:
	if slot < 0 or slot > 1:
		return
	if owner_dead:
		return  # server-authoritative guard: a dead player can't fire a tool (covers the relayed request too)
	if owner_stunned:
		return  # stunned = frozen: no kills, no movement, and no tools (covers the relayed request too)
	# NOTE: compared with `== true` (not bool()) because a parent without the property returns
	# null, and bool(null) crashes — same trap documented in KillComponent.request_kill.
	if get_parent().get("_net_frozen") == true:
		return  # round-start countdown: kills are blocked (KillComponent checks this) — tools are too
	if not slot_unlocked[slot]:
		return  # PvE ladder: slot not unlocked this life (host-authoritative — rejects the relayed request too)
	if _charges[slot] <= 0 or _cooldown_left[slot] > 0.0 or _active_left[slot] > 0.0:
		return
	var tool := _tool(slot)
	_charges[slot] -= 1
	_cooldown_left[slot] = cooldown_for_tool(tool) * cooldown_scale  # SWIFT perk scales this
	_active_left[slot] = duration_for_tool(tool)
	# Tools cost exposure. We run only on the authority, so adding it here is server-authoritative
	# and covers BOTH online (host) and offline — the one place every tool pays its tell.
	var exposure: Node = get_parent().get_node_or_null("ExposureComponent")
	if exposure != null and exposure.has_method("add_exposure"):
		exposure.add_exposure(exposure_for_tool(tool), "tool")
	tool_activated.emit(tool, slot)
