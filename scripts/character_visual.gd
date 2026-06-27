extends Node2D
class_name CharacterVisual

# CharacterVisual — UNSEEN. The shared "rig" worn by the PLAYER and EVERY NPC
# (Pillar #1: everyone looks identical-in-kind, just a person in the crowd). It is the
# ONE rig used everywhere a person is drawn — local player, remote players, NPC crowd,
# and (later) menu previews / scoreboard portraits. There is no separate NPC art path.
# As always, gameplay logic never touches this node (Principle #1).
#
# ===========================================================================
# COMPOSABLE RIG (Phase 8 — COSMETIC_SYSTEM_SPEC.md §1)
# ===========================================================================
# The character is built from FOUR stacked layers, composited against ONE shared origin:
#
#   z=0  body   — legs / base               (the animated sprite sheet)
#   z=1  outfit — top + bottom (one layer)   (overlay, recolourable)
#   z=2  head   — head / hat                 (overlay, recolourable)
#   z=3  weapon — static holstered look      (rides the body; not independently animated)
#
# *** LOCKED ANCHOR / ORIGIN — DO NOT CHANGE (the single most painful thing to fix later) ***
#   The rig's origin (this Node2D's 0,0) is the character's CENTRE (hips), sitting at the
#   parent body's position. EVERY layer is a `centered` Sprite2D placed at `sprite_offset`
#   with the SAME scale, so all four layers composite against that identical point.
#   Because every layer shares one transform, swapping a hat or outfit cannot shift the
#   character by a single pixel. New art must be authored to this same 32px-frame, centred
#   convention so it drops in without re-aligning anything.
#
# APPEARANCE IS DATA, NOT IDENTITY (Pillar #1 + the cosmetics system):
#   What the rig wears is a `Loadout` — pure data (ids per slot), applied through the ONE
#   entry point `apply_loadout()`. Players, NPCs and previews all feed it the same way.
#   `set_appearance(index)` is kept as a thin BODY-only shim so the existing int-based
#   crowd netcode keeps working unchanged while the loadout system layers on top.

# === the body sprite sheets (assets/sprites/README.txt) =====================
# Each sheet is 128x128, made of 32x32 frames in a 4-column x 4-row grid.
#   Rows = facing direction.  Columns = walk-cycle frames.
# These double as the placeholder BODY cosmetics in CosmeticRegistry (same order).
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

# Explicit, fixed z-order per rig layer (see the header diagram). Higher = drawn on top.
const Z_BODY := 0
const Z_OUTFIT := 1
const Z_HEAD := 2
const Z_WEAPON := 3

# Layer ints, kept in sync with LayerComponent.Layer (we don't depend on that class here,
# we just mirror the same order — Principle #1, visuals stay decoupled from gameplay).
const LAYER_GROUND := 0
const LAYER_ROOFTOP := 1
const LAYER_SEWER := 2

## On-screen height of the character in pixels (the 32px art is scaled up to this).
@export var display_height: float = 80.0
## Nudges the sprite relative to the body centre (e.g. to sit the feet right).
@export var sprite_offset: Vector2 = Vector2.ZERO
## Walk-cycle speed. The README suggests ~8-10 fps for a natural step.
@export var walk_frames_per_second: float = 9.0
## Below this speed (px/s) the character is treated as standing still.
@export var moving_threshold: float = 5.0
## If true, a character with no appearance set picks a random sheet on spawn, so the
## crowd looks varied with zero wiring. Turn OFF once a loadout is assigned explicitly.
@export var randomize_on_ready: bool = true

## Colour of the "this is your mark" highlight ring (a playtest aid, see set_highlight).
@export var highlight_color: Color = Color(1.0, 0.84, 0.25)

# The four layer sprites, all built in code (kept out of the .tscn so the scene stays
# tiny and every character — player and NPC — gets the identical rig).
var _sprite: Sprite2D = null     ## BODY layer (animated sheet). Name kept for back-compat.
var _outfit: Sprite2D = null     ## OUTFIT overlay.
var _head: Sprite2D = null       ## HEAD overlay.
var _weapon: Sprite2D = null     ## WEAPON overlay (static, rides the body).

var _appearance_index: int = -1   ## Which body sheet we're wearing (-1 = none yet).
var _facing_row: int = ROW_DOWN   ## Held between steps so a stopped body keeps facing.
var _walk_time: float = 0.0       ## Drives which walk-cycle column we show.
var _strike_timer: float = 0.0    ## Counts down a quick "I just struck" pop.
var _highlighted: bool = false    ## Draw the mark ring this frame?
var _highlight_pulse: float = 0.0 ## Animates the ring so it reads as "alive".
## Per-layer tint multiplied into every layer each frame (set by set_layer_visual).
var _layer_tint: Color = Color(1, 1, 1, 1)
## Alpha factor for the smoke grenade (1 = normal, low = nearly invisible).
var _smoke_alpha: float = 1.0
## The loadout currently worn (pure data). Drives apply_loadout; never reaches back here.
var _loadout: Loadout = null
## Each overlay layer's base recolour (its cosmetic's palette). Folded with the live FX
## (strike/layer/smoke) every frame so cosmetics and gameplay tints coexist.
var _outfit_palette: Color = Color(1, 1, 1, 1)
var _head_palette: Color = Color(1, 1, 1, 1)
var _weapon_palette: Color = Color(1, 1, 1, 1)

## Emitted when a cosmetic animation is triggered (KILL_ANIM / WIN_ANIM / EMOTE). The
## type is a CosmeticItem.Slot int; the id is the equipped animation cosmetic. Future
## real animations / VFX listen here — today the handler just plays a placeholder pop.
signal cosmetic_animation_played(animation_slot: int, cosmetic_id: StringName)

## Emitted on the VICTIM's rig the moment they're killed — the seam for the brief
## "kill card" the victim sees on death (§6). Carries the killer's body index so a real
## card can later show who got them. A no-op today; the event is what we wire now.
signal kill_card_requested(killer_appearance: int)


func _ready() -> void:
	# BODY — the animated sheet. Built first so it sits at the bottom (z=0).
	_sprite = _make_layer("Body", SHEET_COLUMNS, SHEET_ROWS, Z_BODY)
	# OUTFIT / HEAD — overlays that animate in LOCKSTEP with the body (same frame grid),
	# so when real layered art arrives it steps with the walk cycle automatically.
	_outfit = _make_layer("Outfit", SHEET_COLUMNS, SHEET_ROWS, Z_OUTFIT)
	_head = _make_layer("Head", SHEET_COLUMNS, SHEET_ROWS, Z_HEAD)
	# WEAPON — a single static frame (1x1 grid): it rides the body, never animated alone.
	_weapon = _make_layer("Weapon", 1, 1, Z_WEAPON)

	# Default: nothing in the overlays (placeholder content), only the body shows — which
	# is exactly the pre-Phase-8 look, so there's no visual regression.
	_outfit.visible = false
	_head.visible = false
	_weapon.visible = false

	# ## SEAM (per-viewer cosmetics): the online layer assigns a loadout explicitly. Until
	# then we self-assign a random body so an unconfigured crowd is varied with zero wiring.
	if randomize_on_ready and _appearance_index < 0:
		set_appearance(randi() % SHEET_TEXTURES.size())


# Builds one rig layer (a Sprite2D) with the shared, LOCKED transform. `hframes`/`vframes`
# set its frame grid; `z` fixes its draw order. Every layer goes through here so they are
# guaranteed pixel-aligned against the one origin (see the header's locked-anchor note).
func _make_layer(layer_name: String, hframes: int, vframes: int, z: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = layer_name
	# NEAREST filtering keeps the pixel art crisp when we scale it up (README note).
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.hframes = hframes
	sprite.vframes = vframes
	sprite.centered = true
	sprite.position = sprite_offset
	sprite.scale = Vector2.ONE * (display_height / float(FRAME_PX))
	sprite.z_index = z
	add_child(sprite)
	return sprite


# ===========================================================================
# THE ONE ENTRY POINT — apply a loadout to the rig (COSMETIC_SYSTEM_SPEC.md §1)
# ===========================================================================
# Sets texture + modulate on each visual layer from a Loadout. This is the ONLY place
# cosmetics touch the rig. Used identically by players, NPCs and previews.
func apply_loadout(loadout: Loadout) -> void:
	_loadout = loadout if loadout != null else Loadout.new()

	# BODY — reuse the existing sheet path via the back-compat index shim, so the body
	# animates exactly as before and the int-based netcode stays valid.
	var body_id := _loadout.get_item(CosmeticItem.Slot.BODY)
	if body_id != &"":
		set_appearance(_registry_index_for_body(body_id))

	# OVERLAYS — outfit/head/weapon. Each: look up the item, set its art + base palette.
	_outfit_palette = _apply_overlay(_outfit, CosmeticItem.Slot.OUTFIT)
	_head_palette = _apply_overlay(_head, CosmeticItem.Slot.HEAD)
	_weapon_palette = _apply_overlay(_weapon, CosmeticItem.Slot.WEAPON)


# Configure one overlay layer from the loadout's item in `slot`. Returns the base palette
# to fold into the per-frame modulate. Hides the layer if the slot is empty or has no art
# (the expected placeholder case today). Loads art_path at runtime — data, never baked in.
func _apply_overlay(layer: Sprite2D, slot: int) -> Color:
	if layer == null:
		return Color(1, 1, 1, 1)
	var id := _loadout.get_item(slot)
	var item: CosmeticItem = _registry_item(id)
	if item == null or item.art_path == "":
		# Nothing equipped (or no art yet) → draw nothing for this layer.
		layer.visible = false
		layer.texture = null
		return Color(1, 1, 1, 1)

	var texture: Texture2D = load(item.art_path) as Texture2D
	if texture == null:
		layer.visible = false
		return Color(1, 1, 1, 1)
	layer.texture = texture
	layer.visible = true

	# A player override beats the item's default palette; else use the item's default.
	var override := _loadout.get_palette(slot)
	var base := override if override != CosmeticItem.NO_RECOLOR else item.default_palette
	return base


# ===========================================================================
# ANIMATION TRIGGER HOOKS (COSMETIC_SYSTEM_SPEC.md §6) — slots, not content
# ===========================================================================
# ONE entry point for the three animation cosmetic types. The trigger PATH is the point:
# it's wired to real game events now (on_kill / on_match_won / emote input), and the
# animation itself is a stub. Dropping in real animations later is content-only.
#   `animation_slot` is a CosmeticItem.Slot: KILL_ANIM, WIN_ANIM or EMOTE.
func play_cosmetic_animation(animation_slot: int) -> void:
	var id := &""
	if _loadout != null:
		id = _loadout.get_item(animation_slot)
	# STUB animation: a readable scale pop so you can see the trigger fired. Real kill /
	# win / emote animations replace this body without changing any caller.
	_strike_timer = STRIKE_DURATION
	cosmetic_animation_played.emit(animation_slot, id)


# The brief card the VICTIM sees when killed (§6). STUB: a no-op handler that just fires
# the event — real kill-card art/VFX listen on `kill_card_requested` later, content-only.
# `killer_appearance` is the killer's body index (-1 if unknown).
func show_kill_card(killer_appearance: int = -1) -> void:
	kill_card_requested.emit(killer_appearance)


# Put on one of the body sheets. `index` is just data — kept as the BODY-only shim used by
# the existing int-based netcode. Safe to call before or after _ready.
func set_appearance(index: int) -> void:
	_appearance_index = wrapi(index, 0, SHEET_TEXTURES.size())
	if _sprite != null:
		_sprite.texture = SHEET_TEXTURES[_appearance_index]


# Which body sheet this character is currently wearing.
func get_appearance() -> int:
	return _appearance_index


# Turn the "this is your mark" highlight ring on/off (playtest aid).
func set_highlight(enabled: bool) -> void:
	_highlighted = enabled
	queue_redraw()


# Called by the kill component when this character swings, for a readable "pop".
func play_strike() -> void:
	_strike_timer = STRIKE_DURATION


# Tint the body to read its current layer (buildplan §7.2). The LayerComponent calls this.
func set_layer_visual(layer: int) -> void:
	match layer:
		LAYER_ROOFTOP:
			_layer_tint = Color(0.85, 0.95, 1.15, 1.0)   # up high: brighter, cool
		LAYER_SEWER:
			_layer_tint = Color(0.45, 0.50, 0.55, 0.55)  # underground: dim + translucent
		_:
			_layer_tint = Color(1, 1, 1, 1)              # ground: normal


# Smoke grenade: fade the whole rig to near-invisible (placeholder for true per-viewer
# invisibility). Folded into the per-frame modulate alpha of every layer.
func set_smoked(on: bool) -> void:
	_smoke_alpha = 0.12 if on else 1.0


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
	var body_frame := _facing_row * SHEET_COLUMNS + column
	if _sprite != null:
		_sprite.frame = body_frame
	# Animated overlays share the body's frame exactly — ONE animation clock, no desync.
	if _outfit != null and _outfit.visible:
		_outfit.frame = body_frame
	if _head != null and _head.visible:
		_head.frame = body_frame

	# STRIKE POP — a quick scale punch + brighten so a kill / cosmetic anim reads.
	var strike_ratio := 0.0
	if _strike_timer > 0.0:
		_strike_timer -= delta
		strike_ratio = clampf(_strike_timer / STRIKE_DURATION, 0.0, 1.0)
	scale = Vector2.ONE * (1.0 + strike_ratio * 0.30)

	# Shared FX folded over every layer this frame: brighten (strike), layer tint, smoke.
	var brighten := 1.0 + strike_ratio * 0.9
	_apply_layer_modulate(_sprite, Color(1, 1, 1, 1), brighten)
	_apply_layer_modulate(_outfit, _outfit_palette, brighten)
	_apply_layer_modulate(_head, _head_palette, brighten)
	_apply_layer_modulate(_weapon, _weapon_palette, brighten)

	# Keep the highlight ring animating while it's on.
	if _highlighted:
		_highlight_pulse += delta
		queue_redraw()


# Fold a layer's base cosmetic palette together with the live gameplay FX (strike
# brighten, layer tint, smoke alpha) into its final modulate for this frame.
func _apply_layer_modulate(layer: Sprite2D, base_palette: Color, brighten: float) -> void:
	if layer == null:
		return
	layer.modulate = Color(
		brighten * _layer_tint.r * base_palette.r,
		brighten * _layer_tint.g * base_palette.g,
		brighten * _layer_tint.b * base_palette.b,
		_layer_tint.a * _smoke_alpha * base_palette.a)


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


# === registry access, guarded so the rig still works if the autoload is absent =====
# (e.g. opening character_visual.tscn alone in the editor). The rig degrades to "body
# only" rather than erroring — visuals never hard-depend on the cosmetics catalogue.
func _registry_item(id: StringName) -> CosmeticItem:
	if id == &"":
		return null
	var reg := get_node_or_null("/root/CosmeticRegistry")
	if reg != null and reg.has_method("get_item"):
		return reg.call("get_item", id)
	return null


func _registry_index_for_body(id: StringName) -> int:
	var reg := get_node_or_null("/root/CosmeticRegistry")
	if reg != null and reg.has_method("index_for_body_id"):
		return int(reg.call("index_for_body_id", id))
	return 0


func _draw() -> void:
	# Only the mark draws anything here: a pulsing ring around the sprite so you can
	# pick your target out of the crowd while we prototype.
	if not _highlighted:
		return
	var pulse := 0.5 + 0.5 * sin(_highlight_pulse * 4.0)
	var radius := display_height * 0.55
	var ring := Color(highlight_color.r, highlight_color.g, highlight_color.b, 0.45 + 0.45 * pulse)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, ring, 4.0, true)
