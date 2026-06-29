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

enum Tool { SMOKE, DISGUISE, MORPH, DECOY, POISON }

## The TWO tools this player brought, by slot (0 = item_primary key, 1 = item_secondary key).
## Set from the lobby pick (online: stamped into spawn data; offline: left at this default).
@export var equipped: Array[int] = [Tool.SMOKE, Tool.DECOY]

## True once this player is eliminated (set by Player.die on every machine). A dead player reads no
## keys and can't activate a tool — but the authority's timers keep ticking so any tool that was
## already active still expires/reverts cleanly.
var owner_dead: bool = false

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
## DISGUISE — look like a random commoner to others for this long.
@export var disguise_charges: int = 1
@export var disguise_cooldown_seconds: float = 0.0
@export var disguise_seconds: float = 30.0
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

## Exposure (0-100) ADDED to the user each time a tool is used — tools aren't free. Tuned so a tool
## or two is fine but leaning on them pushes you toward the 100% reveal. Applied by the authority.
@export var smoke_exposure_cost: float = 10.0
@export var disguise_exposure_cost: float = 14.0
@export var morph_exposure_cost: float = 16.0
@export var decoy_exposure_cost: float = 8.0
@export var poison_exposure_cost: float = 12.0

## Input actions (one per slot). Local co-op assigns each player its own (p1_/p2_).
@export var item_primary_action: String = "item_primary"
@export var item_secondary_action: String = "item_secondary"

## Fired when a tool is used (the authority applies the world effect) and when its duration ends.
signal tool_activated(tool: int, slot: int)
signal tool_expired(tool: int, slot: int)
## (Online) THIS machine's player pressed a slot key but isn't the authority — the Player relays
## this slot index to the host as a request (server-authoritative).
signal item_requested(slot: int)

# Per-SLOT live state (index 0 / 1).
var _charges: Array[int] = [0, 0]
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


func apply_equipped(tools: Array) -> void:
	if tools.size() >= 2:
		equipped = [int(tools[0]), int(tools[1])]
	_refill_charges()


# === per-tool config lookups (one place, so tunables never drift) ==========================
func charges_for_tool(tool: int) -> int:
	match tool:
		Tool.SMOKE: return smoke_charges
		Tool.DISGUISE: return disguise_charges
		Tool.MORPH: return morph_charges
		Tool.DECOY: return decoy_charges
		Tool.POISON: return poison_charges
	return 1

func exposure_for_tool(tool: int) -> float:
	match tool:
		Tool.SMOKE: return smoke_exposure_cost
		Tool.DISGUISE: return disguise_exposure_cost
		Tool.MORPH: return morph_exposure_cost
		Tool.DECOY: return decoy_exposure_cost
		Tool.POISON: return poison_exposure_cost
	return 0.0

func cooldown_for_tool(tool: int) -> float:
	match tool:
		Tool.SMOKE: return smoke_cooldown_seconds
		Tool.DISGUISE: return disguise_cooldown_seconds
		Tool.MORPH: return morph_cooldown_seconds
		Tool.DECOY: return decoy_cooldown_seconds
		Tool.POISON: return poison_cooldown_seconds
	return 0.0

# Duration of the slot's "active" readout (0 for instant tools). Smoke counts the cloud's life.
func duration_for_tool(tool: int) -> float:
	match tool:
		Tool.SMOKE: return smoke_cloud_seconds
		Tool.DISGUISE: return disguise_seconds
		Tool.MORPH: return morph_seconds
	return 0.0

static func tool_name(tool: int) -> String:
	match tool:
		Tool.SMOKE: return "SMOKE"
		Tool.DISGUISE: return "DISGUISE"
		Tool.MORPH: return "MORPH"
		Tool.DECOY: return "DECOY"
		Tool.POISON: return "POISON"
	return "—"

# A MatchHud icon id for each tool (we reuse the existing PixelLab UI icons).
static func tool_icon(tool: int) -> String:
	match tool:
		Tool.SMOKE: return "ui_hide"
		Tool.DISGUISE: return "ui_disguise"
		Tool.MORPH: return "ui_intel"
		Tool.DECOY: return "ui_flag"
		Tool.POISON: return "ui_target"
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
		if _active_left[slot] > 0.0:
			_active_left[slot] = maxf(0.0, _active_left[slot] - delta)
			if _active_left[slot] == 0.0:
				tool_expired.emit(_tool(slot), slot)


# A press on the controlling machine: act if we're the authority, else relay a request to the host.
func _on_press(slot: int) -> void:
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
	if _charges[slot] <= 0 or _cooldown_left[slot] > 0.0 or _active_left[slot] > 0.0:
		return
	var tool := _tool(slot)
	_charges[slot] -= 1
	_cooldown_left[slot] = cooldown_for_tool(tool)
	_active_left[slot] = duration_for_tool(tool)
	# Tools cost exposure. We run only on the authority, so adding it here is server-authoritative
	# and covers BOTH online (host) and offline — the one place every tool pays its tell.
	var exposure: Node = get_parent().get_node_or_null("ExposureComponent")
	if exposure != null and exposure.has_method("add_exposure"):
		exposure.add_exposure(exposure_for_tool(tool), "tool")
	tool_activated.emit(tool, slot)
