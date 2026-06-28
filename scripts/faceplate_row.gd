extends Control
class_name FaceplateRow

# Faceplate row — UNSEEN, buildplan.md §7.4. A top-of-screen row of KNOWN identities:
#   RED  plate = your post-contract target (the first-to-finish reward — you learn what
#               your human target looks like, a real edge for moving fast).
#   BLUE plates = opponents revealed by hitting 100% exposure (shown to everyone else).
#
# Each plate shows the sprite-sheet FACE (the down-facing frame) so you can scan the crowd
# for that look. It reads straight off the SAME appearance index the crowd wears (§0.3) —
# today that's a soft narrowing (only 5 sheets), and it sharpens for free when cosmetics land.


@export var plate_size: float = 56.0
@export var plate_gap: float = 8.0
@export var red_color: Color = Color(1.0, 0.30, 0.25)
@export var blue_color: Color = Color(0.30, 0.62, 1.0)

## The target's appearance (red plate), -1 = none yet.
var _target_index: int = -1
## Appearance indices revealed by exposure (blue plates), in reveal order.
var _exposed_indices: Array[int] = []


func _ready() -> void:
	# Crisp pixel faces when we scale the 32px frame up to plate_size.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


# Your human target's look — the first-to-finish reward (red).
func set_target_face(appearance_index: int) -> void:
	_target_index = appearance_index
	queue_redraw()


# An opponent who hit 100% exposure (blue). Ignored if we already show that look.
func add_exposed_face(appearance_index: int) -> void:
	if appearance_index in _exposed_indices:
		return
	_exposed_indices.append(appearance_index)
	queue_redraw()


func _draw() -> void:
	var x: float = 0.0
	if _target_index >= 0:
		_draw_plate(x, _target_index, red_color)
		x += plate_size + plate_gap
	for index in _exposed_indices:
		_draw_plate(x, index, blue_color)
		x += plate_size + plate_gap


func _draw_plate(x: float, appearance_index: int, border: Color) -> void:
	var sheets := CharacterVisual.SHEET_TEXTURES
	var sheet: Texture2D = sheets[wrapi(appearance_index, 0, sheets.size())]
	var destination := Rect2(x, 0.0, plate_size, plate_size)
	# Crop the FULL down-facing frame 0 (top-left cell). Derive the frame size from the sheet
	# (width / columns) so it's correct for any sheet size — 48px now, not the old hardcoded 32.
	var frame_px: float = float(sheet.get_width()) / float(CharacterVisual.SHEET_COLUMNS)
	var source := Rect2(0.0, 0.0, frame_px, frame_px)  # down-facing, frame 0, whole cell
	draw_rect(destination, Color(0, 0, 0, 0.55), true)
	draw_texture_rect_region(sheet, destination, source)
	draw_rect(destination, border, false, 3.0)
