extends Resource
class_name CosmeticItem

# CosmeticItem — UNSEEN, Phase 8 (COSMETIC_SYSTEM_SPEC.md §2). The data definition
# of ONE cosmetic thing you can own / equip: a body, an outfit, a hat, a holstered
# weapon, a kill animation, a profile banner, a title, etc.
#
# WHAT THIS IS, in plain terms:
# A "Resource" is Godot's word for a chunk of pure DATA (no behaviour, no place in the
# scene tree) — like a row in a spreadsheet. A CosmeticItem is one such row: it says
# "this hat has this id, this art file, this default colour." It never draws anything
# and never touches gameplay. The rig (CharacterVisual) reads these rows to know what
# to paint; the registry (CosmeticRegistry) holds the whole catalogue of them.
#
# WHY DATA, NOT CODE (the whole point of Phase 8):
# Adding a new hat later must be "add one art file + one data row" — never a code
# change. Keeping every cosmetic as a CosmeticItem (the same way the map keeps its
# layout as data) is what makes that true. This is the seam the shop bolts onto later.

## Which kind of cosmetic this is. Determines which rig layer / system consumes it.
##   BODY / OUTFIT / HEAD / WEAPON — the four visual rig layers (see CharacterVisual).
##   KILL_ANIM / WIN_ANIM / EMOTE  — animation cosmetics fired on events / input.
##   BANNER / BADGE / TITLE        — account-level profile identity (PlayerProfile).
enum Slot { BODY, OUTFIT, HEAD, WEAPON, KILL_ANIM, WIN_ANIM, EMOTE, BANNER, BADGE, TITLE }

## How this item is meant to be obtained. METADATA ONLY for now — there is NO logic
## behind it yet (no shop, no unlock conditions). It exists so the shop/progression
## built later can sort/filter on it without re-tagging every item.
##   DEFAULT  — everyone owns it from the start (the free baseline look).
##   EARNABLE — unlocked through play later (progression bolts on here).
##   PURCHASE — bought later (the shop bolts on here).
enum Acquisition { DEFAULT, EARNABLE, PURCHASE }

## The MONETIZATION SAFETY bucket (PHASE_8_MONETIZATION.md §0/§2 — the crowd-safe veto). The single
## most important tag: it decides whether a cosmetic may touch the in-match civilian silhouette.
##   CROWD_SAFE    — the in-match look (body/outfit/head/weapon). Neutral by construction because
##                   every NPC is a clone of a player's look (§2A): you always hide among NPCs in
##                   your exact outfit, so a skin can't make you stand out (not pay-to-lose/win).
##   REVEAL_MOMENT — only shows once stealth is broken (kill/win/emote anims, tool skins, own-HUD
##                   themes). The money-makers: flashy AND blend-safe (§2B).
##   OUT_OF_MATCH  — lobby/profile flair (banner/badge/title). Always safe (§2C).
enum Bucket { CROWD_SAFE, REVEAL_MOMENT, OUT_OF_MATCH }

## Cosmetic rarity — metadata for battle-pass / store sorting + presentation (§4.1). NEVER gameplay
## weight (cosmetic-only model, §1).
enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

## The sentinel meaning "leave the art's own colours alone". We can't use `null` for a
## typed Color @export, so opaque-white (the modulate identity) plays that role: tinting
## by white changes nothing. `recolors()` below reads intent from this. Declared up here
## because the `default_palette` export below uses it as its default value.
const NO_RECOLOR := Color(1, 1, 1, 1)

## Stable unique id, e.g. "body_villager" or "hat_none". NEVER reused or renamed once
## shipped — saves, inventories and net payloads all refer to items by this string.
@export var id: StringName = &""

## Which slot this item fills (see the Slot enum above).
@export var slot: Slot = Slot.BODY

## Human-readable name shown in menus / the future shop. Safe to change anytime.
@export var display_name: String = ""

## Path to the art. For visual slots this is an SVG/PNG texture; for the animation
## slots it's a reference to an animation resource. "" = no art (a valid "none" item,
## e.g. the empty HEAD slot meaning "no hat").
@export var art_path: String = ""

## Default recolour applied to the layer via `modulate` (SVGs are drawn white and
## tinted at runtime — one art file, infinite palettes). Use the fully-opaque white
## sentinel below to mean "no recolour, draw the art as authored".
@export var default_palette: Color = NO_RECOLOR

## How this item is acquired (metadata only — see the Acquisition enum).
@export var acquisition: Acquisition = Acquisition.PURCHASE

## The crowd-safe bucket (§0/§2). Defaults from the slot via `bucket_for_slot()` in `make()`, so
## existing rows get the right bucket for free; override it on a row only for a deliberate exception.
@export var bucket: Bucket = Bucket.CROWD_SAFE

## Rarity + battle-pass season (§4.1). season 0 = base / no season; >0 = the season it belongs to.
@export var rarity: Rarity = Rarity.COMMON
@export var season: int = 0


# The default bucket for a slot (§2): the four rig layers are the in-match civilian look (crowd-safe);
# the animation slots only fire when stealth is already broken (reveal-moment); profile slots are
# out-of-match. One place so the rule is consistent and a new slot can't be mis-bucketed by accident.
static func bucket_for_slot(s: Slot) -> Bucket:
	match s:
		Slot.BODY, Slot.OUTFIT, Slot.HEAD, Slot.WEAPON:
			return Bucket.CROWD_SAFE
		Slot.KILL_ANIM, Slot.WIN_ANIM, Slot.EMOTE:
			return Bucket.REVEAL_MOMENT
		_:  # BANNER / BADGE / TITLE
			return Bucket.OUT_OF_MATCH


# Convenience constructor so the registry can build placeholder items in code without a
# hand-authored .tres file per item (consistent with building the map/crowd in code).
static func make(
		item_id: StringName,
		item_slot: Slot,
		name: String,
		path: String = "",
		palette: Color = NO_RECOLOR,
		how: Acquisition = Acquisition.PURCHASE) -> CosmeticItem:
	var item := CosmeticItem.new()
	item.id = item_id
	item.slot = item_slot
	item.display_name = name
	item.art_path = path
	item.default_palette = palette
	item.acquisition = how
	item.bucket = bucket_for_slot(item_slot)  # §2 default; override per-row for exceptions
	return item


# True if this item wants its layer tinted (a real palette was set, not the sentinel).
func recolors() -> bool:
	return default_palette != NO_RECOLOR


# The §0 VETO in one call: may this cosmetic touch the in-match civilian silhouette? Only crowd-safe
# items may. Downstream equip/store code can gate on this so a reveal-moment effect never leaks into
# the blend phase. (An animated CROWD_SAFE layer still needs the render-parity check in §2A.1.)
func is_crowd_safe() -> bool:
	return bucket == Bucket.CROWD_SAFE


# True for the four slots the character RIG draws (body/outfit/head/weapon). The other
# slots are animations or account identity and are consumed elsewhere.
func is_visual() -> bool:
	return slot == Slot.BODY or slot == Slot.OUTFIT or slot == Slot.HEAD or slot == Slot.WEAPON
