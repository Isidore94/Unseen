# NPC Sprite Sheets — Format Spec

5 NPCs: villager, merchant, guard, mage, townswoman.

## Sheet layout (each *_sheet.png)
- Image size: 128 x 128 px
- Frame size: 32 x 32 px
- Grid: 4 columns x 4 rows
- Transparent background (RGBA PNG)

### Rows (directions), top to bottom
- Row 0 (y 0-31):   walk DOWN
- Row 1 (y 32-63):  walk UP
- Row 2 (y 64-95):  walk LEFT
- Row 3 (y 96-127): walk RIGHT  (mirror of LEFT)

### Columns (walk-cycle frames), left to right
- Col 0: contact pose A
- Col 1: passing pose  (body bobs up 1px)
- Col 2: contact pose B
- Col 3: passing pose
Loop 0 -> 1 -> 2 -> 3 -> 0 at ~8-10 fps for a smooth walk.
No idle frames (per request) — hold col 1 (or col 0) as a standing frame if you need one.

## Frame index formula
frame_x = col * 32
frame_y = row * 32

## Engine notes
- Use NEAREST / point filtering when scaling (no smoothing) to keep crisp pixels.
- RIGHT row is the LEFT row flipped horizontally; you can drop Row 3 and flip
  Row 2 at runtime if you prefer fewer frames.
- All characters share the same rig and feet baseline, so they align on a tile grid.

Files:
  villager_sheet.png  merchant_sheet.png  guard_sheet.png
  mage_sheet.png      townswoman_sheet.png
  *_walk.gif          = animated previews (not for import)
  _all_sheets_preview.png = overview of the whole set
