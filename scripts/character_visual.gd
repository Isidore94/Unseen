extends Node2D
class_name CharacterVisual

# CharacterVisual — UNSEEN. The shared "body" worn by the PLAYER and EVERY NPC
# (Pillar #1: everyone looks identical-in-kind, just a person in the crowd). It now
# renders a real character SPRITE SHEET instead of a greybox circle, but the rule
# that made the greybox work still holds: gameplay logic never touches this node.
#
# IT DRIVES ITSELF: it reads its parent character's velocity each frame to pick the
# facing direction (which row of the sheet) and to animate the walk cycle (which
# column). The movement scripts don't know it exists — they just move; we follow.
#
# APPEARANCE IS DATA, NOT IDENTITY (important for the future cosmetics system):
#   Which sheet a character wears is set by `set_appearance(index)` — a plain number.
#   Today the character picks a random one on spawn so the crowd looks varied.
#   LATER, when players buy skins, the ONLINE layer will call `set_appearance()`
#   per-viewer: every player is shown the OTHER players' looks duplicated across the
#   crowd, and never their own. Nothing in here assumes a fixed look — that seam is
#   marked `## FUTURE` below. The actor's gameplay identity is kept completely
#   separate from what it looks like, which is exactly what Pillar #1 needs.

# === the sprite sheets (assets/sprites/README.txt) =========================
# Each sheet is 128x128, made of 32x32 frames in a 4-column x 4-row grid.
#   Rows = facing direction.  Columns = walk-cycle frames.
const SHEET_TEXTURES := [
	preload("res://assets/sprites/villager_sheet.png"),
	preload("res://assets/sprites/merchant_sheet.png"),
	preload("res://assets/sprites/guard_sheet.png"),
	preload("res://assets/sprites/mage_sheet.png"),
	preload("res://assets/sprites/townswoman_sheet.png"),
]

const FRAME_PX := 32          ## One frame is 32x32 px in the source sheet.
const SHEET_COLUMNS := 4      ## 4 walk-cycle frames per direction.
const SHEET_ROWS := 4         ## 4 directions (down / up / left / right).

# Row index for each facing, matching the README's row order.
const ROW_DOWN := 0
const ROW_UP := 1
const ROW_LEFT := 2
const ROW_RIGHT := 3

const STRIKE_DURATION := 0.22

## On-screen height of the character in pixels (the 32px art is scaled up to this).
@export var display_height: float = 80.0
## Nudges the sprite relative to the body centre (e.g. to sit the feet right).
@export var sprite_offset: Vector2 = Vector2.ZERO
## Walk-cycle speed. The README suggests ~8-10 fps for a natural step.
@export var walk_frames_per_second: float = 9.0
## Below this speed (px/s) the character is treated as standing still.
@export var moving_threshold: float = 5.0
## If true, a character with no appearance set picks a random sheet on spawn, so the
## crowd looks varied with zero wiring. Turn OFF once the per-viewer cosmetics
## system assigns appearances explicitly (see `set_appearance`).
@export var randomize_on_ready: bool = true

## Colour of the "this is your mark" highlight ring (a playtest aid, see set_highlight).
@export var highlight_color: Color = Color(1.0, 0.84, 0.25)

# The Sprite2D we build in code (kept out of the .tscn so the scene stays tiny and
# every character — player and NPC — gets one identically).
var _sprite: Sprite2D = null

var _appearance_index: int = -1   ## Which sheet we're wearing (-1 = none yet).
var _facing_row: int = ROW_DOWN   ## Held between steps so a stopped body keeps facing.
var _walk_time: float = 0.0       ## Drives which walk-cycle column we show.
var _strike_timer: float = 0.0    ## Counts down a quick "I just struck" pop.
var _highlighted: bool = false    ## Draw the mark ring this frame?
var _highlight_pulse: float = 0.0 ## Animates the ring so it reads as "alive".


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sheet"
	# NEAREST filtering keeps the pixel art crisp when we scale it up (README note).
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.hframes = SHEET_COLUMNS
	_sprite.vframes = SHEET_ROWS
	_sprite.centered = true
	_sprite.position = sprite_offset
	_sprite.scale = Vector2.ONE * (display_height / float(FRAME_PX))
	add_child(_sprite)

	# ## FUTURE (per-viewer cosmetics): when the online layer decides what each
	# viewer should see, it will call set_appearance() itself and this fallback
	# stays off. For now we self-assign a random sheet so the crowd is varied.
	if randomize_on_ready and _appearance_index < 0:
		set_appearance(randi() % SHEET_TEXTURES.size())


# Put on one of the sheets. `index` is just data — any system (random now, the
# cosmetics/online layer later) can call this. Safe to call before or after _ready.
func set_appearance(index: int) -> void:
	_appearance_index = wrapi(index, 0, SHEET_TEXTURES.size())
	if _sprite != null:
		_sprite.texture = SHEET_TEXTURES[_appearance_index]


# Which sheet this character is currently wearing (handy for debugging / the future
# rule "never show a player their own look in the crowd").
func get_appearance() -> int:
	return _appearance_index


# Turn the "this is your mark" highlight ring on/off. PLAYTEST AID: it draws in the
# shared world, so right now BOTH split-screen players can see it — see the note in
# contract_manager for the private-view upgrade.
func set_highlight(enabled: bool) -> void:
	_highlighted = enabled
	queue_redraw()


# Called by the kill component when this character swings, for a readable "pop".
func play_strike() -> void:
	_strike_timer = STRIKE_DURATION


func _process(delta: float) -> void:
	var velocity := _parent_velocity()
	var is_moving := velocity.length() > moving_threshold

	# FACING — pick the sheet row from the movement direction; hold it when stopped.
	if is_moving:
		_facing_row = _facing_row_from(velocity)

	# WALK CYCLE — step through the 4 columns while moving; rest on column 0 when not.
	var column := 0
	if is_moving:
		_walk_time += delta * walk_frames_per_second
		column = int(_walk_time) % SHEET_COLUMNS
	else:
		_walk_time = 0.0
	if _sprite != null:
		_sprite.frame = _facing_row * SHEET_COLUMNS + column

	# STRIKE POP — a quick scale punch + brighten so a kill reads as an action.
	var strike_ratio := 0.0
	if _strike_timer > 0.0:
		_strike_timer -= delta
		strike_ratio = clampf(_strike_timer / STRIKE_DURATION, 0.0, 1.0)
	scale = Vector2.ONE * (1.0 + strike_ratio * 0.30)
	if _sprite != null:
		var brighten := 1.0 + strike_ratio * 0.9
		_sprite.modulate = Color(brighten, brighten, brighten, 1.0)

	# Keep the highlight ring animating while it's on.
	if _highlighted:
		_highlight_pulse += delta
		queue_redraw()


# Map a movement vector to one of the four sheet rows (dominant axis wins).
func _facing_row_from(velocity: Vector2) -> int:
	if absf(velocity.x) > absf(velocity.y):
		return ROW_RIGHT if velocity.x > 0.0 else ROW_LEFT
	return ROW_DOWN if velocity.y > 0.0 else ROW_UP


func _parent_velocity() -> Vector2:
	var parent := get_parent()
	if parent is CharacterBody2D:
		return (parent as CharacterBody2D).velocity
	return Vector2.ZERO


func _draw() -> void:
	# Only the mark draws anything here: a pulsing ring around the sprite so you can
	# pick your target out of the crowd while we prototype. Drawn on the body root
	# (under the sprite child) so it reads as a glow around the feet/edges.
	if not _highlighted:
		return
	var pulse := 0.5 + 0.5 * sin(_highlight_pulse * 4.0)
	var radius := display_height * 0.55
	var ring := Color(highlight_color.r, highlight_color.g, highlight_color.b, 0.45 + 0.45 * pulse)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, ring, 4.0, true)
