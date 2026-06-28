extends RefCounted
class_name PlayerProfile

# PlayerProfile — UNSEEN, Phase 8 (COSMETIC_SYSTEM_SPEC.md §7). The player's ACCOUNT-LEVEL
# identity: their banner, badge and title. This is deliberately SEPARATE from the character
# rig (CharacterVisual) — it's who the account is, not what the body in the crowd looks like.
# It surfaces in menus and around the match (scoreboard, results screen, name tag), never on
# the in-world disguised body (that would break Pillar #1's "everyone looks alike" rule).
#
# Like everything in Phase 8 it's pure data: three cosmetic ids, looked up in the registry
# for their display text/art. Placeholder content for now.

## The three identity slots, each a cosmetic id (see CosmeticItem.Slot BANNER/BADGE/TITLE).
var banner: StringName = &""
var badge: StringName = &""
var title: StringName = &""


# A profile wearing the free DEFAULT identity items (everyone owns these at start).
static func new_default() -> PlayerProfile:
	var profile := PlayerProfile.new()
	profile.banner = &"banner_default"
	profile.badge = &"badge_none"
	profile.title = &"title_none"
	return profile


# Set one identity slot from a CosmeticItem.Slot int. Returns false if the slot isn't an
# identity slot (so callers can't mis-file an outfit into the profile). Ownership is checked
# by the inventory before this is called (CosmeticInventory.equip_profile).
func set_slot(slot: int, id: StringName) -> bool:
	match slot:
		CosmeticItem.Slot.BANNER:
			banner = id
		CosmeticItem.Slot.BADGE:
			badge = id
		CosmeticItem.Slot.TITLE:
			title = id
		_:
			return false
	return true


# === display hooks (where identity surfaces) ================================
# Each returns the display TEXT for a slot by looking the id up in the registry, or "" if
# nothing meaningful is set. The scoreboard / results / name tag call these. Real banner/
# badge ART later reads the same ids — these text hooks are the placeholder surface.

func title_text() -> String:
	return _display_name(title)


func badge_text() -> String:
	return _display_name(badge)


func banner_text() -> String:
	return _display_name(banner)


# Compact one-line identity label, e.g. "Rookie · the Unseen" — handy for a name tag /
# scoreboard row. Skips the "none" placeholders so it stays clean when nothing is equipped.
func label() -> String:
	var parts: Array[String] = []
	var b := badge_text()
	var t := title_text()
	if b != "":
		parts.append(b)
	if t != "":
		parts.append(t)
	return " · ".join(parts)


# Look up an id's display_name in the registry, treating the "_none" placeholders as blank.
# CosmeticRegistry is an autoload, so it's a global identifier usable even from this
# RefCounted (no scene-tree access needed).
func _display_name(id: StringName) -> String:
	if id == &"" or String(id).ends_with("_none"):
		return ""
	var item: CosmeticItem = CosmeticRegistry.get_item(id)
	if item != null:
		return item.display_name
	return ""
