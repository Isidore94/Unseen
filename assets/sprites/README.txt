# Character Sprite Sheets — Format Spec

> Updated 2026-06-29. The old spec here (128×128 / 32px frames; villager/merchant/guard/mage/townswoman)
> was stale — those NPC sheets no longer exist. Current format and roster below match the rig
> (`scripts/character_visual.gd`) and registry (`scripts/cosmetics/cosmetic_registry.gd`).

## Sheet layout (each *_sheet / body sheet PNG)
- Image size: 192 x 192 px
- Frame size: 48 x 48 px
- Grid: 4 columns x 4 rows
- Transparent background (RGBA PNG), NEAREST/point filtering (no smoothing)

### Rows (directions), top to bottom
- Row 0 (y   0-47):  walk DOWN
- Row 1 (y  48-95):  walk UP
- Row 2 (y  96-143): walk LEFT
- Row 3 (y 144-191): walk RIGHT  (may be a mirror of LEFT)

### Columns (walk-cycle frames), left to right
- 4 frames per direction; loop col 0 -> 1 -> 2 -> 3 -> 0 at ~8-10 fps.
- No idle frames — hold col 0 as a standing pose if needed.

## Frame index formula
frame_x = col * 48
frame_y = row * 48
(The rig also derives frame height from the texture at runtime, so non-48px art still slices,
but author at 48px to match the locked grid — see ART_PIPELINE.md §2.)

## Roster (15 body sheets, index order matches CharacterVisual.SHEET_TEXTURES / registry BODY_IDS)
Commoner crowd looks (indices 0-10):
  civilian_base_sheet.png (0)        crowd/com_brown.png (1)    crowd/com_shawl.png (2)
  crowd/com_red.png (3)              crowd/com_hooded.png (4)   crowd/com_toga.png (5)
  crowd/com_merchant.png (6)         crowd/com_green.png (7)    crowd/com_laborer.png (8)
  crowd/com_elder.png (9)            crowd/com_water.png (10)
Premium assassin skins (indices 11-14, each with a matching *_attack sheet):
  assassins/norse_hammer.png (11)    assassins/crusader_longsword.png (12)
  assassins/revolution_rapiers.png (13)  assassins/egyptian_maces.png (14)

## Engine notes
- All characters share one rig (body z0 / outfit z1 / head z2 / weapon z3), one locked centre/feet origin.
- Attack sheets exist only for player-capable looks (civilian_base + the 4 assassins); ~4 swing frames, ~0.5s.
- Overlay cosmetics (outfit/head/weapon) are placeholder (empty art) and recolour via modulate when added.
