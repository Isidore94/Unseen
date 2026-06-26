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

## Exposure (0-100) the target must exceed before its arrow can appear.
@export var arrow_threshold: float = 55.0

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
@export var appear_delay: float = 2.5
## How long the arrow takes to fade fully in / out once it starts.
@export var fade_in_time: float = 1.0
@export var fade_out_time: float = 0.7

var _target: Node2D = null
var _target_exposure: ExposureComponent = null

var _alpha: float = 0.0
var _offscreen_timer: float = 0.0
var _arrow_pos: Vector2 = Vector2.ZERO
var _arrow_dir: Vector2 = Vector2.RIGHT


func _process(delta: float) -> void:
	_acquire_target()
	if _should_show():
		_offscreen_timer += delta
		if _offscreen_timer >= appear_delay:
			_alpha = minf(1.0, _alpha + delta / maxf(0.01, fade_in_time))
	else:
		_offscreen_timer = 0.0
		_alpha = maxf(0.0, _alpha - delta / maxf(0.01, fade_out_time))
	queue_redraw()


func track_target(target: Node2D) -> void:
	_target = target
	_target_exposure = _find_exposure_component(target)


# True when the target is a valid, exposed, OFF-SCREEN actor — and when so, also
# updates where on the screen edge the arrow should sit and which way it points.
func _should_show() -> bool:
	if _target == null or not is_instance_valid(_target) or _target_exposure == null:
		return false
	if _target.has_method("is_dead") and _target.is_dead():
		return false
	if _target_exposure.exposure < arrow_threshold:
		return false

	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return false

	var viewport_size: Vector2 = get_viewport_rect().size
	var camera_center: Vector2 = camera.get_screen_center_position()
	var visible_half: Vector2 = viewport_size * 0.5 / camera.zoom
	var view_rect := Rect2(camera_center - visible_half, visible_half * 2.0)
	if view_rect.has_point(_target.global_position):
		return false  # on-screen: you can see them, no arrow

	var screen_center: Vector2 = viewport_size * 0.5
	var target_on_screen: Vector2 = (_target.global_position - camera_center) * camera.zoom + screen_center
	var direction: Vector2 = target_on_screen - screen_center
	if direction.length() < 1.0:
		return false
	_arrow_dir = direction.normalized()
	var radius: float = minf(viewport_size.x, viewport_size.y) * 0.5 - edge_margin
	_arrow_pos = screen_center + _arrow_dir * radius
	return true


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
