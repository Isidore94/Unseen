extends Node

# CosmeticInventory — UNSEEN, Phase 8 (COSMETIC_SYSTEM_SPEC.md §8). The account-level record
# of WHICH cosmetics this player owns, what they currently have equipped, and their profile
# identity. An AUTOLOAD ("singleton"): one per app, reachable everywhere as `CosmeticInventory`.
#
# WHAT IT DOES, in plain terms:
# - Keeps a SET of owned cosmetic ids (everyone starts owning the free DEFAULT items).
# - Keeps the player's currently EQUIPPED Loadout (their chosen look) and PlayerProfile
#   (banner / badge / title).
# - Gates equipping on ownership: you can only wear what you own. That single rule is the
#   ONLY thing standing between "free items" and "a shop" — the shop later just GRANTS
#   ownership (and a currency check), and equipping already works. Nothing else changes.
#
# WHAT IT DELIBERATELY IS NOT (out of scope, §8 / "Out of scope"):
# No shop, no currency, no purchase flow, no unlock conditions. Just: an owned-set,
# defaults granted to all, and equip gated on ownership. The seam, not the store.

## Fired when the equipped loadout changes (e.g. the player swaps a hat). The menu /
## preview / online layer listen so they can re-apply the look. Past-tense (Principle #4).
signal loadout_changed
## Fired when the profile (banner/badge/title) changes.
signal profile_changed
## Fired when a new item is granted (the seam a shop/progression will emit through).
signal item_granted(id: StringName)

## The set of owned cosmetic ids. A Dictionary used as a set: owned[id] == true.
var _owned: Dictionary = {}
## The player's currently equipped look (pure data — see Loadout).
var _equipped: Loadout = null
## NPC-disguise (lobby): when non-empty, the equipped BODY is a commoner and this is the hidden
## assassin id, sent to the match so it ALSO gets cloned as crowd decoys. "" = not disguised.
var decoy_body_id: StringName = &""
## The player's account identity (banner/badge/title — see PlayerProfile, §7).
var _profile: PlayerProfile = null


func _ready() -> void:
	# Grant the free baseline so the player can always field a complete look, then equip a
	# sensible default loadout + profile out of those owned items.
	_grant_defaults()
	_equipped = _build_default_loadout()
	_profile = PlayerProfile.new_default()


# Grant every DEFAULT-acquisition item (the free starter set). The registry tags which
# items are free; we just own all of them. (CosmeticRegistry is an autoload global.)
func _grant_defaults() -> void:
	for id in CosmeticRegistry.ids_with_acquisition(CosmeticItem.Acquisition.DEFAULT):
		_owned[id] = true
	# TEMP (no shop yet): grant the premium assassin skins so players can pick one in the lobby.
	# Remove this once a real shop/battlepass grants them — they're PURCHASE-tier on purpose.
	for id in CosmeticRegistry.ASSASSIN_BODY_IDS:
		_owned[id] = true


# A complete starter loadout built only from owned DEFAULT items, so the gate below always
# passes for it. Body 0 + the "none" outfit/head/weapon + default animations.
func _build_default_loadout() -> Loadout:
	var loadout := Loadout.new()
	loadout.set_item(CosmeticItem.Slot.BODY, CosmeticRegistry.body_id_for_index(0))
	loadout.set_item(CosmeticItem.Slot.OUTFIT, &"outfit_none")
	loadout.set_item(CosmeticItem.Slot.HEAD, &"hat_none")
	loadout.set_item(CosmeticItem.Slot.WEAPON, &"weapon_none")
	loadout.set_item(CosmeticItem.Slot.KILL_ANIM, &"kill_default")
	loadout.set_item(CosmeticItem.Slot.WIN_ANIM, &"win_default")
	loadout.set_item(CosmeticItem.Slot.EMOTE, &"emote_wave")
	return loadout


# === ownership ==============================================================

# True if this account owns `id`.
func owns(id: StringName) -> bool:
	return _owned.get(id, false)


# Grant ownership of an item (the seam the shop / progression bolts onto — they call this
# AFTER a purchase or unlock; equipping then already works through equip() below).
func grant(id: StringName) -> void:
	if id == &"" or _owned.get(id, false):
		return
	if not CosmeticRegistry.has_item(id):
		push_warning("CosmeticInventory: tried to grant unknown item '%s'." % id)
		return
	_owned[id] = true
	item_granted.emit(id)


# All owned ids in a given slot (the menu lists these as the "wearable now" options).
func owned_in_slot(slot: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in CosmeticRegistry.ids_in_slot(slot):
		if _owned.get(id, false):
			out.append(id)
	return out


# === equipping (gated on ownership, §8) =====================================

# Equip `id` into `slot`. THE GATE: refuses unless the account owns the item. Returns true
# on success. This is the only path that mutates the equipped look, so the rule lives here
# once and everything (menu, shop, defaults) goes through it.
func equip(slot: int, id: StringName) -> bool:
	if not owns(id):
		push_warning("CosmeticInventory: can't equip unowned item '%s'." % id)
		return false
	if int(CosmeticRegistry.get_item(id).slot) != slot:
		push_warning("CosmeticInventory: item '%s' doesn't fit slot %d." % [id, slot])
		return false
	_equipped.set_item(slot, id)
	loadout_changed.emit()
	return true


# Recolour an equipped slot (the item must already be equipped + owned). Palette is a
# player choice layered on top of ownership; it doesn't need its own grant.
func set_palette(slot: int, color: Color) -> void:
	_equipped.set_palette(slot, color)
	loadout_changed.emit()


# The currently equipped loadout (the live object — treat as read-only; mutate via equip()).
func equipped_loadout() -> Loadout:
	return _equipped


# The equipped look as a compact payload for the network layer (§5). OnlineMatch calls this
# to tell the host what this player looks like.
func equipped_payload() -> Dictionary:
	var payload := _equipped.to_payload() if _equipped != null else {}
	# NPC-disguise: when set, the player's visible BODY is a commoner and THIS hidden assassin id
	# rides along so the match also clones it into the crowd as decoys (online_match reads it).
	if decoy_body_id != &"":
		payload["decoy_body"] = decoy_body_id
	return payload


# === profile identity (§7) ==================================================

# The account's profile (banner/badge/title). Account-level, separate from the rig.
func profile() -> PlayerProfile:
	return _profile


# Equip a profile identity item (banner/badge/title), gated on ownership like everything else.
func equip_profile(slot: int, id: StringName) -> bool:
	if not owns(id):
		push_warning("CosmeticInventory: can't equip unowned profile item '%s'." % id)
		return false
	if not _profile.set_slot(slot, id):
		return false
	profile_changed.emit()
	return true
