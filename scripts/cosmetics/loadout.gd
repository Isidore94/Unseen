extends RefCounted
class_name Loadout

# Loadout — UNSEEN, Phase 8 (COSMETIC_SYSTEM_SPEC.md §3). The set of cosmetic ids a
# character currently has equipped, one per slot, plus any colour overrides.
#
# WHAT THIS IS, in plain terms:
# A Loadout is JUST DATA — a little lookup of "in the HEAD slot I'm wearing
# 'hat_none', in the OUTFIT slot 'outfit_drab'…". It owns no textures and no nodes,
# so it can be copied, saved, or shipped across the network as a tiny bundle of ids.
# The rig (CharacterVisual.apply_loadout) READS a Loadout to know what to paint; the
# Loadout never reaches back into the rig. That one-way relationship is what lets the
# same data describe the local player, a remote player, an NPC, or a menu preview.
#
# WHY IT MUST STAY POINTERS-ONLY (netcode, §5):
# When a player joins we send their appearance ONCE as a compact payload of ids — never
# textures, never node state. `to_payload()` / `from_payload()` are that conversion,
# and they go both directions so the receiving machine can rebuild the exact look.

## equipped[slot:int] = cosmetic id (StringName). A slot missing from the dict means
## "nothing equipped there" (e.g. no hat) — the rig hides that layer.
var equipped: Dictionary = {}

## palettes[slot:int] = Color. OPTIONAL per-slot colour override chosen by the player
## (e.g. a red shirt vs the item's default). A slot missing here uses the item's own
## `default_palette`. Kept separate from `equipped` so the common case (no override)
## ships nothing extra.
var palettes: Dictionary = {}


# --- editing ---------------------------------------------------------------

# Equip `id` in `slot`. Pass an empty id to clear the slot (wear nothing there).
func set_item(slot: int, id: StringName) -> void:
	if id == &"":
		equipped.erase(slot)
	else:
		equipped[slot] = id


# The id equipped in `slot`, or &"" if nothing is.
func get_item(slot: int) -> StringName:
	return equipped.get(slot, &"")


# Choose a colour override for a slot (e.g. the player recolours their outfit). Passing
# the NO_RECOLOR sentinel clears the override (fall back to the item's default).
func set_palette(slot: int, color: Color) -> void:
	if color == CosmeticItem.NO_RECOLOR:
		palettes.erase(slot)
	else:
		palettes[slot] = color


# The colour override for a slot, or NO_RECOLOR if the player hasn't overridden it.
func get_palette(slot: int) -> Color:
	return palettes.get(slot, CosmeticItem.NO_RECOLOR)


# A deep copy, so handing a Loadout to another system can't mutate ours by reference.
func duplicate_loadout() -> Loadout:
	var copy := Loadout.new()
	copy.equipped = equipped.duplicate()
	copy.palettes = palettes.duplicate()
	return copy


# --- compact serialization (the netcode seam, §5) --------------------------

# Pack into the smallest plain-data bundle: ids and (only-if-overridden) colours.
# No textures, no node refs — safe to RPC and cheap to send once on join/change.
func to_payload() -> Dictionary:
	# `equipped`/`palettes` are already pure id→value maps; copy so the receiver can't
	# alias our live dictionaries.
	var payload := {"items": equipped.duplicate()}
	if not palettes.is_empty():
		payload["palettes"] = palettes.duplicate()
	return payload


# Rebuild a Loadout from a payload made by to_payload() (the other direction).
static func from_payload(payload: Dictionary) -> Loadout:
	var loadout := Loadout.new()
	var items: Dictionary = payload.get("items", {})
	# Keys can arrive as floats over the wire; normalise slot keys back to ints.
	for key in items:
		loadout.equipped[int(key)] = StringName(items[key])
	var pals: Dictionary = payload.get("palettes", {})
	for key in pals:
		loadout.palettes[int(key)] = pals[key]
	return loadout


# --- factories -------------------------------------------------------------

# Build a random loadout for the four VISUAL slots by drawing one owned item per slot
# from a pool (used by the NPC crowd, §4). `pool_by_slot` maps slot:int → Array of ids.
# An optional RandomNumberGenerator lets the host seed the crowd deterministically so
# every client builds the same NPC without per-NPC replication (§5).
static func randomized(pool_by_slot: Dictionary, rng: RandomNumberGenerator = null) -> Loadout:
	var loadout := Loadout.new()
	for slot in [
			CosmeticItem.Slot.BODY,
			CosmeticItem.Slot.OUTFIT,
			CosmeticItem.Slot.HEAD,
			CosmeticItem.Slot.WEAPON]:
		var ids: Array = pool_by_slot.get(slot, [])
		if ids.is_empty():
			continue
		var pick: int
		if rng != null:
			pick = rng.randi_range(0, ids.size() - 1)
		else:
			pick = randi() % ids.size()
		loadout.equipped[slot] = StringName(ids[pick])
	return loadout
