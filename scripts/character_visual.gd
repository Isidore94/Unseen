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
# All 48px PixelLab bodies, index-aligned with CosmeticRegistry.BODY_IDS. Indices 0–10 are the
# Roman COMMONER crowd looks; 11–14 are the premium ASSASSIN player skins (battlepass/shop).
const SHEET_TEXTURES := [
	preload("res://assets/sprites/civilian_base_sheet.png"),      # 0  civilian (commoner)
	preload("res://assets/sprites/crowd/com_brown.png"),          # 1
	preload("res://assets/sprites/crowd/com_shawl.png"),          # 2
	preload("res://assets/sprites/crowd/com_red.png"),            # 3
	preload("res://assets/sprites/crowd/com_hooded.png"),         # 4
	preload("res://assets/sprites/crowd/com_toga.png"),           # 5
	preload("res://assets/sprites/crowd/com_merchant.png"),       # 6
	preload("res://assets/sprites/crowd/com_green.png"),          # 7
	preload("res://assets/sprites/crowd/com_laborer.png"),        # 8
	preload("res://assets/sprites/crowd/com_elder.png"),          # 9
	preload("res://assets/sprites/crowd/com_water.png"),          # 10
	preload("res://assets/sprites/assassins/norse_hammer.png"),       # 11 assassin
	preload("res://assets/sprites/assassins/crusader_longsword.png"), # 12 assassin
	preload("res://assets/sprites/assassins/revolution_rapiers.png"), # 13 assassin
	preload("res://assets/sprites/assassins/egyptian_maces.png"),     # 14 assassin
]

# Optional ATTACK sheets (same 4x4 layout) keyed by body index — only the player-capable looks have
# one (civilian + the 4 assassins). On an attack the rig swaps the body to this sheet, plays its 4
# swing frames once, then reverts to the walk sheet. Commoners have no entry → they never attack.
const ATTACK_SHEETS := {
	0: preload("res://assets/sprites/civilian_base_attack.png"),
	11: preload("res://assets/sprites/assassins/norse_hammer_attack.png"),
	12: preload("res://assets/sprites/assassins/crusader_longsword_attack.png"),
	13: preload("res://assets/sprites/assassins/revolution_rapiers_attack.png"),
	14: preload("res://assets/sprites/assassins/egyptian_maces_attack.png"),
}
## How long one attack swing plays before reverting to the walk sheet (seconds).
const ATTACK_DURATION := 0.5

const FRAME_PX := 48          ## FALLBACK frame size (px) used ONLY before a sheet is loaded.
                              ## The real on-screen scale is DERIVED from each layer's actual
                              ## texture (see _rescale_layer), so 32px and 48px art both render
                              ## at display_height with no second constant to hand-sync. The art
                              ## pipeline target is 48px (tools/ingest_sprite.py).
                             ## (ART_PIPELINE.md §2) — flip this to 48 (sheets become 192x192) when the
                             ## first real 48px sheets replace the 32px placeholders. Don't flip earlier.
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
## Once movement is detected, keep the walk cycle playing for this long even if the next frames read
## "not moving". Bridges the gaps where neither velocity nor displacement registers — render frames
## between physics ticks (high-refresh) and packet gaps on a CLIENT's replicated puppets — so they
## don't glide without a walk cycle. Only after this much continuous stillness do we go idle.
@export var move_grace_seconds: float = 0.18
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
var _move_grace: float = 0.0      ## Seconds left of the "treat as moving" grace window (see export).
var _strike_timer: float = 0.0    ## Counts down a quick "I just struck" pop.
var _attack_timer: float = 0.0    ## While >0, the body plays its ATTACK sheet (swing) instead of walk.
var _highlighted: bool = false    ## Draw the mark ring this frame?
var _highlight_pulse: float = 0.0 ## Animates the ring so it reads as "alive".
## Per-layer tint multiplied into every layer each frame (set by set_layer_visual).
var _layer_tint: Color = Color(1, 1, 1, 1)
## Alpha factor for the smoke grenade (1 = normal, low = nearly invisible).
var _smoke_alpha: float = 1.0
## Last frame's parent world position + whether we have one yet. Facing is derived from the
## ACTUAL movement between frames (this position minus last), not the reported velocity — so a
## figure can never face one way while sliding the other ("glide backwards"). This is robust for
## host NPCs (whose velocity gets rewritten by collision/avoidance) AND client puppets (which
## interpolate toward a throttled position, so their reported velocity lags the visible motion).
var _last_parent_pos: Vector2 = Vector2.ZERO
var _has_last_pos: bool = false
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


# --- Map colour cohesion (tunable; tweak with the artist after seeing the tiled map) ---
## Saturation of every character sprite. 1.0 = original colours; <1 desaturates so sprites sit in the
## warm map palette (the dev's "same saturation ramp as the map"). saturation=1.0 + tint_strength=0 disables it.
@export var cohesion_saturation: float = 0.9
## The warm hue sprites are nudged toward (≈ the map's sand tone).
@export var cohesion_tint: Color = Color(1.0, 0.94, 0.82)
## How strongly that warm tint is applied (0 = none).
@export_range(0.0, 1.0) var cohesion_tint_strength: float = 0.12
const SPRITE_GRADE_SHADER := "res://assets/shaders/sprite_grade.gdshader"
var _grade_material: ShaderMaterial = null


func _ready() -> void:
	# One shared grade material for all rig layers, so every character matches the map's colour world.
	_grade_material = _build_grade_material()
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


# Build the shared saturation/tint material that pulls sprites into the map's palette. Returns null
# (→ sprites render untouched) if the shader asset is missing, so this can never break the rig.
func _build_grade_material() -> ShaderMaterial:
	var shader := load(SPRITE_GRADE_SHADER) as Shader
	if shader == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("saturation", cohesion_saturation)
	mat.set_shader_parameter("tint", cohesion_tint)
	mat.set_shader_parameter("tint_strength", cohesion_tint_strength)
	return mat


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
	sprite.z_index = z
	if _grade_material != null:
		sprite.material = _grade_material  # map-cohesion grade (shared across all layers)
	add_child(sprite)
	# Initial scale uses the FRAME_PX fallback; once a texture is assigned, _rescale_layer
	# recomputes it from the real sheet so the size is correct for 32px OR 48px art.
	_rescale_layer(sprite)
	return sprite


# Scale a layer so one animation frame renders at `display_height` on screen, DERIVED from the
# layer's actual sheet (frame height = texture height / rows). This is what lets us swap a 32px
# sheet for a 48px one with zero code changes — there is no second frame-size constant to keep
# in sync with the art pipeline. Falls back to FRAME_PX only when the layer has no texture yet.
func _rescale_layer(sprite: Sprite2D) -> void:
	if sprite == null:
		return
	var frame_height_px := float(FRAME_PX)
	if sprite.texture != null and sprite.vframes > 0:
		frame_height_px = float(sprite.texture.get_height()) / float(sprite.vframes)
	if frame_height_px > 0.0:
		sprite.scale = Vector2.ONE * (display_height / frame_height_px)


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
	_rescale_layer(layer)  # overlay art may be 32px or 48px — derive its scale from the sheet

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
		_rescale_layer(_sprite)  # match the on-screen size to this sheet's real frame size


# Which body sheet this character is currently wearing.
func get_appearance() -> int:
	return _appearance_index


# Turn the "this is your mark" highlight ring on/off (playtest aid).
func set_highlight(enabled: bool) -> void:
	_highlighted = enabled
	queue_redraw()


# Called by the kill component when this character swings: the quick scale "pop" plus, if this
# body has an attack sheet (player-capable looks), a one-shot weapon-swing animation.
func play_strike() -> void:
	_strike_timer = STRIKE_DURATION
	if ATTACK_SHEETS.has(_appearance_index):
		_attack_timer = ATTACK_DURATION


# Tint the body to read its current layer (buildplan §7.2). The LayerComponent calls this.
func set_layer_visual(layer: int) -> void:
	match layer:
		LAYER_ROOFTOP:
			_layer_tint = Color(0.85, 0.95, 1.15, 1.0)   # up high: brighter, cool
		LAYER_SEWER:
			_layer_tint = Color(0.45, 0.50, 0.55, 0.55)  # underground: dim + translucent
		_:
			_layer_tint = Color(1, 1, 1, 1)              # ground: normal


# Smoke grenade: fade the whole rig. Folded into the per-frame modulate alpha of every layer.
# `alpha_when_on` lets the caller pick how faint: offline uses the near-invisible default (it
# fakes invisibility on the one shared body); online uses a stronger value as a SELF-ONLY cue,
# since the real hiding is done per-viewer on other machines and you must still see yourself play.
func set_smoked(on: bool, alpha_when_on: float = 0.12) -> void:
	_smoke_alpha = alpha_when_on if on else 1.0


func _process(delta: float) -> void:
	# Two separate signals, on purpose:
	#  • is_moving / the WALK CYCLE use the REPORTED velocity — reliable on every render frame.
	#  • FACING uses the ACTUAL displacement, which can't disagree with the drawn glide (no more
	#    moonwalk) — but reads zero on a render frame with no physics step, so we only TURN when
	#    there was real movement and otherwise hold the last facing. (Driving is_moving off
	#    displacement was the bug that froze the walk animation on high-refresh displays.)
	var reported := _parent_velocity()
	var motion := _parent_motion(delta)
	# Did we move THIS frame, by EITHER signal (reported velocity OR real displacement)?
	var moved_now := reported.length() > moving_threshold or motion.length() > moving_threshold
	if moved_now:
		_move_grace = move_grace_seconds
		# FACING — prefer real displacement (can't moonwalk); fall back to velocity if no displacement.
		if motion.length() > moving_threshold:
			_facing_row = _facing_row_from(motion)
		elif reported.length() > moving_threshold:
			_facing_row = _facing_row_from(reported)
	else:
		_move_grace = maxf(0.0, _move_grace - delta)
	# Keep animating through brief gaps (high-refresh frames with no physics tick, packet gaps on a
	# client puppet) — the flicker that reset the walk cycle and made puppets glide. Idle only after
	# the grace window fully elapses with no movement.
	var is_moving := _move_grace > 0.0

	# WALK CYCLE — step through the 4 columns while moving; rest on column 0 when not.
	var column := 0
	if is_moving:
		_walk_time += delta * walk_frames_per_second
		column = int(_walk_time) % SHEET_COLUMNS
	else:
		_walk_time = 0.0
	# ATTACK overrides the walk: while the timer runs, swap the body to its attack sheet and play
	# its 4 swing frames once; revert to the walk sheet when done. Commoners have no attack sheet.
	var attacking := _attack_timer > 0.0 and ATTACK_SHEETS.has(_appearance_index)
	if _attack_timer > 0.0:
		_attack_timer -= delta
	var body_frame := _facing_row * SHEET_COLUMNS + column
	if attacking:
		var progress := 1.0 - clampf(_attack_timer / ATTACK_DURATION, 0.0, 1.0)  # 0..1 over the swing
		body_frame = _facing_row * SHEET_COLUMNS + mini(int(progress * SHEET_COLUMNS), SHEET_COLUMNS - 1)
	if _sprite != null:
		var want_tex: Texture2D = ATTACK_SHEETS[_appearance_index] if attacking else (SHEET_TEXTURES[_appearance_index] if _appearance_index >= 0 else _sprite.texture)
		if want_tex != null and _sprite.texture != want_tex:
			_sprite.texture = want_tex
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


# The parent's ACTUAL movement this frame expressed as pixels/second (displacement ÷ delta). This
# is what the eye sees, so facing derived from it can never contradict the visible glide. Falls
# back to the reported velocity on the very first frame (no previous position yet) or for a parent
# that isn't a Node2D. A teleport shows one frame of large motion — harmless for facing.
func _parent_motion(delta: float) -> Vector2:
	var parent := get_parent()
	if not (parent is Node2D) or delta <= 0.0:
		return _parent_velocity()
	var pos := (parent as Node2D).global_position
	if not _has_last_pos:
		_last_parent_pos = pos
		_has_last_pos = true
		return _parent_velocity()
	var motion := (pos - _last_parent_pos) / delta
	_last_parent_pos = pos
	return motion


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
