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

@onready var _body: Node = get_parent()
@onready var _visual: Node = get_parent().get_node_or_null("CharacterVisual")
@onready var _kill: Node = get_parent().get_node_or_null("KillComponent")

var _smoke_timer: float = 0.0
var _cloak_timer: float = 0.0
var _smoke_left: int = 0
var _cloak_left: int = 0
## Online: only the machine that controls this player reads its input (set by the player).
var _network_local_control: bool = true


func _ready() -> void:
	_smoke_left = smoke_charges
	_cloak_left = cloak_charges


# Called by the player on the controlling machine (online). Offline stays true by default.
func enable_network_local_control() -> void:
	_network_local_control = true


func smoke_active() -> bool:
	return _smoke_timer > 0.0

func cloak_active() -> bool:
	return _cloak_timer > 0.0

func charges_left(item: int) -> int:
	return _smoke_left if item == Item.SMOKE else _cloak_left


func _physics_process(delta: float) -> void:
	if _network_local_control:
		if Input.is_action_just_pressed(item_primary_action):
			_activate(Item.SMOKE)
		if Input.is_action_just_pressed(item_secondary_action):
			_activate(Item.CLOAK)

	# Count the active effects down and switch them off when they run out.
	if _smoke_timer > 0.0:
		_smoke_timer = maxf(0.0, _smoke_timer - delta)
		if _smoke_timer == 0.0:
			_end_smoke()
	if _cloak_timer > 0.0:
		_cloak_timer = maxf(0.0, _cloak_timer - delta)
		if _cloak_timer == 0.0:
			item_expired.emit(Item.CLOAK)


func _activate(item: int) -> void:
	if item == Item.SMOKE:
		if _smoke_left <= 0 or smoke_active():
			return
		_smoke_left -= 1
		_smoke_timer = smoke_duration
		# Vanish from others + lock out your own attack (you can't kill while hidden).
		if _visual != null and _visual.has_method("set_smoked"):
			_visual.call("set_smoked", true)
		if _kill != null:
			_kill.set("attacks_disabled", true)
		item_activated.emit(Item.SMOKE, smoke_duration)
	else:
		if _cloak_left <= 0 or cloak_active():
			return
		_cloak_left -= 1
		_cloak_timer = cloak_duration
		item_activated.emit(Item.CLOAK, cloak_duration)


func _end_smoke() -> void:
	if _visual != null and _visual.has_method("set_smoked"):
		_visual.call("set_smoked", false)
	if _kill != null:
		_kill.set("attacks_disabled", false)
	item_expired.emit(Item.SMOKE)
