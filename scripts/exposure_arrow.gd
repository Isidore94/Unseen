extends Node2D
class_name ExposureArrow

# Exposure Arrow - UNSEEN, Phase 4.
#
# When the other assassin gets too exposed, this HUD node points toward their
# area. It is NOT a hard on/off: when the target leaves your view the arrow does
# not snap on (which would reveal exactly which figure just left). Instead there's
# a delay, then it FADES in — and it fades out smoothly when they're on-screen.
# By the time the arrow is visible they've moved, so it gives a fuzzy hint, never
# a precise "that one is your target".

## Exposure (0-100) the target must exceed before its arrow can appear. Set to 100 so you only
## become visible to enemy assassins at FULL exposure — letting players spend exposure on tools
## freely without lighting up the moment they tick over halfway.
@export var arrow_threshold: float = 100.0

## How far in from the screen edge the arrow sits, in pixels.
@export var edge_margin: float = 90.0

## Size of the arrow triangle, in pixels.
@export var arrow_size: float = 34.0

## The arrow's colour for this target.
@export var arrow_color: Color = Color(1.0, 0.3, 0.3)

## Actor to point at. If empty, target_group_name is used for legacy tests.
@export var target_path: NodePath

## Fallback group used when target_path is empty.
@export var target_group_name: String = "hunter"

## Seconds the target must be off-screen before the arrow STARTS appearing. This
## delay is the whole point: it breaks the correlation between "a figure just left
## my screen" and "the arrow lit up", so you can't tell who it was.
@export var appear_delay: float = 2.0
## How long the arrow takes to fade fully in / out once it starts.
@export var fade_in_time: float = 0.8
@export var fade_out_time: float = 2.0

# --- flashing style (the stronger tracking earned by finishing your mark) ---
## When true, IGNORE exposure and instead FLASH toward the off-screen target every
## flash_interval seconds. (master_plan §7.1.)
@export var flashing_mode: bool = false
## How often the flash appears, and how long each flash lasts, in seconds.
@export var flash_interval: float = 2.5
@export var flash_duration: float = 0.8

var _target: Node2D = null
var _target_exposure: ExposureComponent = null

## When true (the owner is in a SEWER), the arrow points at the target at FULL strength,
## ignoring the exposure threshold AND the on-screen gate (buildplan §7.2d — you trade
## sight for a perfect bearing). Toggled by the owner's LayerComponent.
var _sewer_mode: bool = false

## When true, the target has a CLOAK up: suppress the post-mark "hunt" (flashing) arrow
## that points at them, while leaving the normal exposure arrow alone (buildplan §7.6 —
## cloak kills only non-exposure arrows; run loud and your exposure still gives you away).
var _suppressed: bool = false

var _alpha: float = 0.0
var _offscreen_timer: float = 0.0
var _flash_timer: float = 0.0
var _arrow_pos: Vector2 = Vector2.ZERO
var _arrow_dir: Vector2 = Vector2.RIGHT


func _process(delta: float) -> void:
	_acquire_target()
	if _sewer_mode:
		_process_sewer()
	elif flashing_mode:
		if _suppressed:
			_alpha = 0.0  # cloak: the hunt arrow is hidden
		else:
			_process_flashing(delta)
	else:
		_process_exposure(delta)  # exposure arrow always fires, even through a cloak
	queue_redraw()


# The target's cloak toggles this. Only the flashing "hunt" arrow is suppressed.
func set_suppressed(on: bool) -> void:
	_suppressed = on


# SEWER STYLE — 100% uptime: a full-strength bearing on the target at all times, ignoring
# both exposure and the on-screen gate (you can't see the world down here anyway).
func _process_sewer() -> void:
	_alpha = 1.0 if _compute_offscreen_arrow(true) else 0.0


# The owner's LayerComponent flips this when entering/leaving the sewer.
func set_sewer_mode(on: bool) -> void:
	_sewer_mode = on
	if not on:
		_offscreen_timer = 0.0
		_alpha = 0.0


func track_target(target: Node2D) -> void:
	_target = target
	_target_exposure = _find_exposure_component(target)


# Switch styles at runtime: exposure-gated solid arrow while you still have a mark,
# then a periodic flash once your mark is dead.
func set_flashing(on: bool) -> void:
	flashing_mode = on
	_offscreen_timer = 0.0
	_flash_timer = 0.0
	_alpha = 0.0


# EXPOSURE STYLE — a steady arrow that appears (after a short delay) when the target
# is off-screen AND exposed past the threshold, and fades out when they're visible.
func _process_exposure(delta: float) -> void:
	var exposed: bool = _target_exposure != null and _target_exposure.exposure >= arrow_threshold
	if exposed and _compute_offscreen_arrow():
		_offscreen_timer += delta
		if _offscreen_timer >= appear_delay:
			_alpha = minf(1.0, _alpha + delta / maxf(0.01, fade_in_time))
	else:
		_offscreen_timer = 0.0
		_alpha = maxf(0.0, _alpha - delta / maxf(0.01, fade_out_time))


# FLASHING STYLE — ignores exposure; pulses toward the target every flash_interval
# while they're off-screen (no hint at all when they're on-screen). This is the post-mark
# "hunt your human target" arrow, so it is deliberately IMPRECISE: it points in only one of
# four directions (up/down/left/right) — the cardinal that best matches the target's relative
# bearing — instead of an exact angle. A rough "they're that way", never "that exact figure".
func _process_flashing(delta: float) -> void:
	if not _compute_offscreen_arrow():
		_alpha = 0.0
		_flash_timer = 0.0
		return
	_snap_to_cardinal()
	_flash_timer += delta
	var t: float = fmod(_flash_timer, flash_interval)
	if t < flash_duration:
		_alpha = sin((t / flash_duration) * PI)  # smooth 0 -> 1 -> 0 pulse
	else:
		_alpha = 0.0


# Works out whether the target is valid, alive, and OFF-screen — and if so, where on
# the screen edge the arrow sits and which way it points. No exposure check here.
func _compute_offscreen_arrow(ignore_onscreen: bool = false) -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	if _target.has_method("is_dead") and _target.is_dead():
		return false

	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return false

	var viewport_size: Vector2 = get_viewport_rect().size
	var camera_center: Vector2 = camera.get_screen_center_position()
	var visible_half: Vector2 = viewport_size * 0.5 / camera.zoom
	var view_rect := Rect2(camera_center - visible_half, visible_half * 2.0)
	if not ignore_onscreen and view_rect.has_point(_target.global_position):
		return false  # on-screen: you can see them, no arrow (sewer mode ignores this)

	var screen_center: Vector2 = viewport_size * 0.5
	var target_on_screen: Vector2 = (_target.global_position - camera_center) * camera.zoom + screen_center
	var direction: Vector2 = target_on_screen - screen_center
	if direction.length() < 1.0:
		return false
	_arrow_dir = direction.normalized()
	var radius: float = minf(viewport_size.x, viewport_size.y) * 0.5 - edge_margin
	_arrow_pos = screen_center + _arrow_dir * radius
	return true


# Round the bearing to the nearest of the four cardinal directions and re-place the arrow on the
# middle of that screen edge. Used only by the hunt (flashing) arrow — the dominant axis wins, so a
# target up-and-slightly-right reads as a clean "UP". Keeping it mid-edge also dodges the corner
# HUD panels. The exposure arrow never calls this, so it stays a precise bearing.
func _snap_to_cardinal() -> void:
	if absf(_arrow_dir.x) >= absf(_arrow_dir.y):
		_arrow_dir = Vector2(signf(_arrow_dir.x), 0.0)
	else:
		_arrow_dir = Vector2(0.0, signf(_arrow_dir.y))
	if _arrow_dir == Vector2.ZERO:
		_arrow_dir = Vector2.RIGHT
	var viewport_size: Vector2 = get_viewport_rect().size
	var screen_center: Vector2 = viewport_size * 0.5
	var radius: float = minf(viewport_size.x, viewport_size.y) * 0.5 - edge_margin
	_arrow_pos = screen_center + _arrow_dir * radius


func _draw() -> void:
	if _alpha <= 0.01:
		return
	var perpendicular := Vector2(-_arrow_dir.y, _arrow_dir.x)
	var tip: Vector2 = _arrow_pos + _arrow_dir * arrow_size
	var left: Vector2 = _arrow_pos - _arrow_dir * (arrow_size * 0.5) + perpendicular * (arrow_size * 0.6)
	var right: Vector2 = _arrow_pos - _arrow_dir * (arrow_size * 0.5) - perpendicular * (arrow_size * 0.6)
	var col := Color(arrow_color.r, arrow_color.g, arrow_color.b, arrow_color.a * _alpha)
	draw_colored_polygon(PackedVector2Array([tip, left, right]), col)


func _acquire_target() -> void:
	if _target != null and is_instance_valid(_target) and _target_exposure != null:
		return
	if target_path != NodePath(""):
		var path_target := get_node_or_null(target_path) as Node2D
		if path_target != null:
			track_target(path_target)
			return
	var group_target := get_tree().get_first_node_in_group(target_group_name) as Node2D
	if group_target != null:
		track_target(group_target)


func _find_exposure_component(target: Node2D) -> ExposureComponent:
	var player := target as Player
	if player != null:
		return player.exposure_component
	return target.get_node_or_null("ExposureComponent") as ExposureComponent
