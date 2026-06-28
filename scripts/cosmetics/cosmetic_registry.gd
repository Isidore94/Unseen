extends Node

# CosmeticRegistry — UNSEEN, Phase 8 (COSMETIC_SYSTEM_SPEC.md §2). The single catalogue
# of every CosmeticItem in the game, looked up by id. It is an AUTOLOAD ("singleton"):
# one copy exists for the whole app, reachable everywhere as `CosmeticRegistry`.
#
# WHAT IT DOES, in plain terms:
# On startup it builds the master list of cosmetics (today: placeholders) and files them
# two ways — by id (so "give me item 'hat_cap'" is instant) and by slot (so "give me a
# random HEAD for an NPC" is easy). Nothing here draws or owns anything; it's the phone
# book the rig, the crowd, the inventory and (later) the shop all read from.
#
# WHY BUILT IN CODE, not 30 hand-authored .tres files:
# Same reason the map and crowd are built in code — it keeps the placeholder content in
# one readable place while we have no real art. When real cosmetics arrive they can be
# authored as .tres and loaded here instead; callers won't notice (they only ask by id).

## Fired once the catalogue has finished building (in case something wants to wait).
signal registry_ready

# id (StringName) -> CosmeticItem.
var _by_id: Dictionary = {}
# slot (int) -> Array[StringName] of the ids in that slot (the "pool" the crowd draws from).
var _by_slot: Dictionary = {}

# === body art (PixelLab, 48px) ==============================================
# Index order MUST match CharacterVisual.SHEET_TEXTURES (the rig maps a BODY id -> this index ->
# that texture) and is preserved for the int-based `appearance_index` netcode. Indices 0–10 are
# the Roman COMMONER crowd looks; 11–14 are the premium ASSASSIN player skins.
const BODY_SHEETS := [
	"res://assets/sprites/civilian_base_sheet.png",
	"res://assets/sprites/crowd/com_brown.png",
	"res://assets/sprites/crowd/com_shawl.png",
	"res://assets/sprites/crowd/com_red.png",
	"res://assets/sprites/crowd/com_hooded.png",
	"res://assets/sprites/crowd/com_toga.png",
	"res://assets/sprites/crowd/com_merchant.png",
	"res://assets/sprites/crowd/com_green.png",
	"res://assets/sprites/crowd/com_laborer.png",
	"res://assets/sprites/crowd/com_elder.png",
	"res://assets/sprites/crowd/com_water.png",
	"res://assets/sprites/assassins/norse_hammer.png",
	"res://assets/sprites/assassins/crusader_longsword.png",
	"res://assets/sprites/assassins/revolution_rapiers.png",
	"res://assets/sprites/assassins/egyptian_maces.png",
]
const BODY_IDS: Array[StringName] = [
	&"body_civilian", &"body_com_brown", &"body_com_shawl", &"body_com_red", &"body_com_hooded",
	&"body_com_toga", &"body_com_merchant", &"body_com_green", &"body_com_laborer",
	&"body_com_elder", &"body_com_water",
	&"body_norse_hammer", &"body_crusader", &"body_revolution", &"body_egyptian",
]
## Commoner looks the NPC crowd draws from (indices 0–10). Assassins are deliberately NOT here.
const COMMONER_BODY_IDS: Array[StringName] = [
	&"body_civilian", &"body_com_brown", &"body_com_shawl", &"body_com_red", &"body_com_hooded",
	&"body_com_toga", &"body_com_merchant", &"body_com_green", &"body_com_laborer",
	&"body_com_elder", &"body_com_water",
]
## Premium assassin player skins (indices 11–14) — battlepass / item-shop tier.
const ASSASSIN_BODY_IDS: Array[StringName] = [
	&"body_norse_hammer", &"body_crusader", &"body_revolution", &"body_egyptian",
]

## The 3–5 commoner looks chosen for the CURRENT match (see roll_filler_bodies). Empty = all of
## them. A real street has a few recurring faces, not 11 — this keeps each game's crowd coherent
## while varying between games.
var active_filler_bodies: Array[StringName] = []
## The assassin looks the crowd uses this match (so player-assassins blend in). All four by default.
var active_assassin_bodies: Array[StringName] = []
## Fraction of crowd NPCs that wear an ASSASSIN look (the rest are commoners). 0.5 = a 50/50 mix.
var assassin_crowd_fraction: float = 0.5


# Pick this match's crowd looks: a fresh 3–5 commoner subset + the assassin set. Call at match start.
func roll_filler_bodies() -> void:
	var pool := COMMONER_BODY_IDS.duplicate()
	pool.shuffle()
	var count: int = clampi(3 + (randi() % 3), 3, pool.size())  # 3..5
	active_filler_bodies = pool.slice(0, count)
	active_assassin_bodies = ASSASSIN_BODY_IDS.duplicate()


# A body id for one crowd NPC: assassin_crowd_fraction of the time an assassin look (so player
# assassins have look-alikes to hide among), otherwise one of this match's commoner looks.
func random_crowd_body() -> StringName:
	var commoners: Array = active_filler_bodies if not active_filler_bodies.is_empty() else COMMONER_BODY_IDS
	var assassins: Array = active_assassin_bodies if not active_assassin_bodies.is_empty() else ASSASSIN_BODY_IDS
	if not assassins.is_empty() and randf() < assassin_crowd_fraction:
		return assassins[randi() % assassins.size()]
	return commoners[randi() % commoners.size()]


func _ready() -> void:
	_build_catalogue()
	registry_ready.emit()


# Build the placeholder catalogue. 2–3 items per slot, as the spec asks — enough to test
# the plumbing, nothing more. Real art = add rows here (or load .tres) and nothing else.
func _build_catalogue() -> void:
	var S := CosmeticItem.Slot
	var DEFAULT := CosmeticItem.Acquisition.DEFAULT
	var PURCHASE := CosmeticItem.Acquisition.PURCHASE
	var EARNABLE := CosmeticItem.Acquisition.EARNABLE

	# BODY — commoner looks everyone owns (the crowd needs variety); assassin skins are PREMIUM
	# (PURCHASE) end-game player skins, not granted by default and not in the NPC filler pool.
	for i in BODY_IDS.size():
		var is_assassin := BODY_IDS[i] in ASSASSIN_BODY_IDS
		var how := PURCHASE if is_assassin else DEFAULT
		_register(CosmeticItem.make(BODY_IDS[i], S.BODY, str(BODY_IDS[i]).replace("body_", ""), BODY_SHEETS[i], CosmeticItem.NO_RECOLOR, how))

	# OUTFIT — overlay layer. "none" is the free default; the others are recolour-only
	# placeholders (no art yet, so they draw nothing until an SVG is dropped in).
	_register(CosmeticItem.make(&"outfit_none", S.OUTFIT, "No Outfit", "", CosmeticItem.NO_RECOLOR, DEFAULT))
	_register(CosmeticItem.make(&"outfit_drab", S.OUTFIT, "Drab Cloak", "", Color(0.55, 0.55, 0.60), PURCHASE))
	_register(CosmeticItem.make(&"outfit_crimson", S.OUTFIT, "Crimson Coat", "", Color(0.80, 0.20, 0.25), PURCHASE))

	# HEAD — hats. "none" default; placeholders for the rest.
	_register(CosmeticItem.make(&"hat_none", S.HEAD, "No Hat", "", CosmeticItem.NO_RECOLOR, DEFAULT))
	_register(CosmeticItem.make(&"hat_cap", S.HEAD, "Flat Cap", "", Color(0.30, 0.35, 0.45), PURCHASE))
	_register(CosmeticItem.make(&"hat_hood", S.HEAD, "Drawn Hood", "", Color(0.20, 0.22, 0.25), PURCHASE))

	# WEAPON — static holstered look. "none" default; placeholders for the rest.
	_register(CosmeticItem.make(&"weapon_none", S.WEAPON, "Unarmed Look", "", CosmeticItem.NO_RECOLOR, DEFAULT))
	_register(CosmeticItem.make(&"weapon_dagger", S.WEAPON, "Holstered Dagger", "", Color(0.70, 0.72, 0.78), PURCHASE))
	_register(CosmeticItem.make(&"weapon_blade", S.WEAPON, "Slung Blade", "", Color(0.85, 0.80, 0.55), PURCHASE))

	# KILL_ANIM / WIN_ANIM / EMOTE — animation cosmetics. Content is stubbed (the rig's
	# play_cosmetic_animation just pops a placeholder); these rows make the slots real.
	_register(CosmeticItem.make(&"kill_default", S.KILL_ANIM, "Clean Kill", "", CosmeticItem.NO_RECOLOR, DEFAULT))
	_register(CosmeticItem.make(&"kill_flourish", S.KILL_ANIM, "Flourish", "", CosmeticItem.NO_RECOLOR, PURCHASE))
	_register(CosmeticItem.make(&"win_default", S.WIN_ANIM, "Standard Bow", "", CosmeticItem.NO_RECOLOR, DEFAULT))
	_register(CosmeticItem.make(&"win_flaunt", S.WIN_ANIM, "Flaunt", "", CosmeticItem.NO_RECOLOR, PURCHASE))
	_register(CosmeticItem.make(&"emote_wave", S.EMOTE, "Wave", "", CosmeticItem.NO_RECOLOR, DEFAULT))
	_register(CosmeticItem.make(&"emote_taunt", S.EMOTE, "Taunt", "", CosmeticItem.NO_RECOLOR, PURCHASE))

	# BANNER / BADGE / TITLE — account-level identity (PlayerProfile). Placeholder text/art.
	_register(CosmeticItem.make(&"banner_default", S.BANNER, "Plain Banner", "", CosmeticItem.NO_RECOLOR, DEFAULT))
	_register(CosmeticItem.make(&"banner_crimson", S.BANNER, "Crimson Banner", "", Color(0.80, 0.20, 0.25), PURCHASE))
	_register(CosmeticItem.make(&"badge_none", S.BADGE, "No Badge", "", CosmeticItem.NO_RECOLOR, DEFAULT))
	_register(CosmeticItem.make(&"badge_rookie", S.BADGE, "Rookie", "", CosmeticItem.NO_RECOLOR, EARNABLE))
	_register(CosmeticItem.make(&"title_none", S.TITLE, "No Title", "", CosmeticItem.NO_RECOLOR, DEFAULT))
	_register(CosmeticItem.make(&"title_shadow", S.TITLE, "the Unseen", "", CosmeticItem.NO_RECOLOR, PURCHASE))


func _register(item: CosmeticItem) -> void:
	_by_id[item.id] = item
	var slot := int(item.slot)
	if not _by_slot.has(slot):
		_by_slot[slot] = [] as Array[StringName]
	(_by_slot[slot] as Array).append(item.id)


# === lookups (what everyone else calls) =====================================

# The CosmeticItem for an id, or null if unknown (caller should treat null as "skip").
func get_item(id: StringName) -> CosmeticItem:
	return _by_id.get(id, null)


# True if `id` names a real registered item (used by the inventory's equip gate).
func has_item(id: StringName) -> bool:
	return _by_id.has(id)


# All ids in a slot — the "pool" the NPC crowd randomises over (§4) and the shop lists.
func ids_in_slot(slot: int) -> Array:
	return _by_slot.get(slot, [])


# Every id of a given acquisition kind (e.g. all DEFAULT items → the starter inventory).
func ids_with_acquisition(how: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in _by_id:
		if int((_by_id[id] as CosmeticItem).acquisition) == how:
			out.append(id)
	return out


# === NPC crowd pool (§4) ====================================================

# The pool the NPC crowd draws random loadouts from. CONFIG HOOK (§4): today it's the
# global default — every visual item in the catalogue. Later this can return the lobby
# players' equipped cosmetics instead, WITHOUT changing the crowd spawner. The seam is
# here on purpose; we just don't implement the lobby-sourced version yet.
func npc_pool_by_slot() -> Dictionary:
	# BODY: this match's 3–5 chosen commoner looks (or all commoners if none rolled yet). Assassins
	# are excluded so a premium skin never spawns as random filler. Overlays stay "none" — our
	# commoner art is whole baked looks, so we don't stack art-less placeholder overlays on them.
	var bodies: Array = active_filler_bodies if not active_filler_bodies.is_empty() else COMMONER_BODY_IDS
	return {
		CosmeticItem.Slot.BODY: bodies.duplicate(),
		CosmeticItem.Slot.OUTFIT: [&"outfit_none"],
		CosmeticItem.Slot.HEAD: [&"hat_none"],
		CosmeticItem.Slot.WEAPON: [&"weapon_none"],
	}


# PILLAR INVARIANT (§0.3 hidden identity): the NPC crowd may ONLY wear CROWD_SAFE cosmetics. This
# guarantees no equippable in-world look can ever exist on a HUMAN that the crowd can't also wear —
# which would turn that human into a visible "tell" (a pay-to-be-spotted / identity leak). Every
# visual item defaults to CROWD_SAFE (CosmeticItem.bucket_for_slot), so this is a no-op today; it
# exists so the rule is ENFORCED, not assumed, the moment a reveal-moment or paid item is added.
func _crowd_safe_ids_in_slot(slot: int) -> Array:
	var safe: Array = []
	for id in ids_in_slot(slot):
		var item := get_item(id)
		if item != null and item.is_crowd_safe():
			safe.append(id)
	return safe


# === back-compat with the existing int-based appearance netcode =============
# The Phase 6/7 crowd replicates a body as a single int (`appearance_index` 0–4). These
# two helpers bridge that int to the new BODY cosmetic ids so both systems agree, and so
# we don't have to rip the working netcode apart in this foundation pass.

func body_id_for_index(index: int) -> StringName:
	return BODY_IDS[wrapi(index, 0, BODY_IDS.size())]


func index_for_body_id(id: StringName) -> int:
	var i := BODY_IDS.find(id)
	return i if i >= 0 else 0
