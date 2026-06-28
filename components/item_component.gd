extends Node
class_name ItemComponent

# Item kit — UNSEEN, the start of the class/tool system (buildplan.md §7.6, master_plan §9).
# A base kit of TWO slots fired by item_primary / item_secondary. Items are CHARGE-BASED:
# a fixed number of uses per match, no cooldown reuse — once spent they're gone, so using
# one is a real decision (note 11). Each item is a tiny effect with obvious @export tunables.
#
#   SMOKE GRENADE (slot 1) — you go invisible to others for `smoke_duration` and CANNOT
#       attack during it. Pure escape / reposition.
#   CLOAKING DEVICE (slot 2) — turns off the NPC-completion "hunt" arrow opponents get on
#       you for `cloak_duration`. Your EXPOSURE arrows still fire (run loud and you light up).
#
# Authority note: offline this acts directly. Online it should be host-validated +
# replicated like layers/kills — wired minimally for now (acts on the controlling machine),
# the full server-authoritative path is a TODO.

enum Item { SMOKE, CLOAK }

## Uses per match for each slot (charge-based, no regen — note 11).
@export var smoke_charges: int = 1
@export var cloak_charges: int = 1
## How long each effect lasts, in seconds. Easily fine-tunable (the note asks for this).
@export var smoke_duration: float = 10.0
@export var cloak_duration: float = 15.0
## Input actions. Local co-op assigns each player their own (p1_/p2_).
@export var item_primary_action: String = "item_primary"
@export var item_secondary_action: String = "item_secondary"

## Fired when an item turns ON (carries the item + its duration) and when it expires.
signal item_activated(item: int, duration: float)
signal item_expired(item: int)
## (Online) Fired when THIS machine's player presses an item key but isn't the authority —
## the Player relays it to the host as a request (server-authoritative, buildplan §7.6).
signal item_requested(item: int)

@onready var _body: Node = get_parent()
@onready var _visual: Node = get_parent().get_node_or_null("CharacterVisual")
@onready var _kill: Node = get_parent().get_node_or_null("KillComponent")

var _smoke_timer: float = 0.0
var _cloak_timer: float = 0.0
var _smoke_left: int = 0
var _cloak_left: int = 0

## Online wiring, set by Player._setup_network_role. Offline leaves these defaults so this
## component reads input AND applies effects locally, exactly as before.
var network_mode: bool = false         ## true online: smoke hides via per-viewer visibility, not a local fade
var server_authoritative: bool = true  ## this copy owns charges + effect timers (the host online; everyone offline)
var local_input: bool = true           ## this copy reads THIS machine's item keys


func _ready() -> void:
	_smoke_left = smoke_charges
	_cloak_left = cloak_charges


func smoke_active() -> bool:
	return _smoke_timer > 0.0

func cloak_active() -> bool:
	return _cloak_timer > 0.0

## Seconds left on each active effect (0 = not active). The HUD reads these to show a
## countdown — for SMOKE that's how long until you can attack / be seen again.
func smoke_seconds_left() -> float:
	return _smoke_timer

func cloak_seconds_left() -> float:
	return _cloak_timer

func charges_left(item: int) -> int:
	return _smoke_left if item == Item.SMOKE else _cloak_left


func _physics_process(delta: float) -> void:
	# Read this machine's item keys (only on the copy that controls this player).
	if local_input:
		if Input.is_action_just_pressed(item_primary_action):
			_on_press(Item.SMOKE)
		if Input.is_action_just_pressed(item_secondary_action):
			_on_press(Item.CLOAK)

	# Only the authority (the host online, or everyone offline) owns the effect timers.
	if not server_authoritative:
		return

	# Count the active effects down and switch them off when they run out.
	if _smoke_timer > 0.0:
		_smoke_timer = maxf(0.0, _smoke_timer - delta)
		if _smoke_timer == 0.0:
			_end_smoke()
	if _cloak_timer > 0.0:
		_cloak_timer = maxf(0.0, _cloak_timer - delta)
		if _cloak_timer == 0.0:
			item_expired.emit(Item.CLOAK)


# A press on the controlling machine. If we're the authority (offline, or the host running
# its own player) we fire it directly; otherwise we emit a request the Player relays to the
# host, so the server stays the one true judge of charges + effects (§7.6).
func _on_press(item: int) -> void:
	if server_authoritative:
		_activate(item)
	else:
		item_requested.emit(item)


# Host entry point: a request from the controlling client, already verified by the Player.
func server_activate(item: int) -> void:
	_activate(item)


func _activate(item: int) -> void:
	if item == Item.SMOKE:
		if _smoke_left <= 0 or smoke_active():
			return
		_smoke_left -= 1
		_smoke_timer = smoke_duration
		# Vanish from others + lock out your own attack (you can't kill while hidden).
		_apply_smoke(true)
		item_activated.emit(Item.SMOKE, smoke_duration)
	else:
		if _cloak_left <= 0 or cloak_active():
			return
		_cloak_left -= 1
		_cloak_timer = cloak_duration
		item_activated.emit(Item.CLOAK, cloak_duration)


func _end_smoke() -> void:
	_apply_smoke(false)
	item_expired.emit(Item.SMOKE)


# Make the smoker invisible to others + unable to attack. Online (this runs on the host) we
# set the player's replicated `_net_smoked` flag so each OTHER machine hides it via the
# per-viewer visibility system, and the smoker still sees themselves; offline we fade the
# shared body. Either way the kill is locked out while smoked.
func _apply_smoke(on: bool) -> void:
	if network_mode:
		_body.set("_net_smoked", on)
	elif _visual != null and _visual.has_method("set_smoked"):
		_visual.call("set_smoked", on)
	if _kill != null:
		_kill.set("attacks_disabled", on)
