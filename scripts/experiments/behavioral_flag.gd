extends Node

# 9F — BEHAVIORAL FLAG (PHASE_9_EXPERIMENTS.md §9F). A directional flag on a target, but rebuilt so
# it (a) fires from the target's OWN behavior (a recent tell), not a phase/timer, (b) scales with
# their exposure (reckless = brighter/longer; careful = barely flags), and (c) is RECIPROCAL — the
# flagged player gets a "spotted" cue so they can react. That inversion makes it reward discipline
# instead of revealing everyone. It points toward their AREA and dies the instant they're on-screen.
#
# NOTE (§9F): this overlaps the existing exposure arrow (master_plan §3.1) — treat it as an
# experimental VARIANT. Don't judge both at once; decide which owns "high exposure → findable."
#
# REMOVABILITY (§1): inert unless ExperimentFlags.behavioral_flag_enabled. HOST decides who flags
# (reads BehaviorHistory + exposure) and sends the hunter a direction + the target a spotted cue.
# Core never references this. Delete the file + flag line → you fall back to the standard arrow.

## Flag only when the target produced a recent tell (ran / sharp-turned / killed / used a tool).
@export var flag_trigger_tells: bool = true
## How recent that tell must be.
@export var flag_lookback_seconds: float = 3.0
## Brightness/duration scale with the target's exposure (reckless = stronger, careful = weak/none).
@export var flag_scales_with_exposure: bool = true
## How long the directional cue shows per trigger.
@export var flag_duration_seconds: float = 1.0
## Keep true: point toward the target's AREA and vanish once they're on the hunter's screen (never
## says which figure — matches the §3.1 arrow guardrail).
@export var flag_points_to_area_not_figure: bool = true
## Keep true: the flagged player gets a "you've been spotted" cue so they can re-blend or bolt.
## Without it this is a counter-less reveal (breaks Pillar #4).
@export var reciprocal_spotted_cue: bool = true
## Only flag a target to a hunter who has finished their marks (endgame aid, like the hunt arrow).
@export var require_hunter_ready: bool = true
## Host evaluation rate (seconds).
@export var send_interval_seconds: float = 0.2

var _match: Node = null
var _send_timer: float = 0.0
var _ensure_timer: float = 0.0

# client — hunter's directional flag
var _flag_marker: ColorRect = null
var _flag_world_pos: Vector2 = Vector2.ZERO
var _flag_intensity: float = 0.0
var _flag_timer: float = 0.0
# client — target's reciprocal "spotted" cue
var _spotted_label: Label = null
var _spotted_timer: float = 0.0


func _process(delta: float) -> void:
	if not ExperimentFlags.behavioral_flag_enabled:
		return
	if _match == null or not is_instance_valid(_match):
		_match = get_tree().get_first_node_in_group("online_match")
	if _is_host():
		_host_tick(delta)
	_client_render(delta)


func _is_host() -> bool:
	return (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()


func _local_peer() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1


# === HOST: decide who flags whom ============================================================
func _host_tick(delta: float) -> void:
	_ensure_timer -= delta
	if _ensure_timer <= 0.0:
		_ensure_timer = 0.5
		for actor in get_tree().get_nodes_in_group("player"):
			BehaviorHistory.ensure_on(actor)  # needs history to have been recording

	_send_timer -= delta
	if _send_timer > 0.0:
		return
	_send_timer = send_interval_seconds
	if _match == null or not _match.has_method("host_hunt_edges"):
		return

	for e in _match.host_hunt_edges():
		if require_hunter_ready and not bool(e["hunter_ready"]):
			continue
		var target: Node2D = e["target"]
		if target == null or not is_instance_valid(target):
			continue
		if flag_trigger_tells and not _had_recent_tell(target):
			continue
		var intensity := 1.0
		if flag_scales_with_exposure:
			intensity = clampf(_exposure_of(target) / 100.0, 0.0, 1.0)
		if intensity <= 0.02:
			continue  # a clean target barely flags — the reward for discipline
		_deliver_flag(int(e["hunter_peer"]), target.global_position, intensity)
		if reciprocal_spotted_cue:
			_deliver_spotted(int(e["target_peer"]))


func _had_recent_tell(target: Node) -> bool:
	var history := target.get_node_or_null("BehaviorHistory") as BehaviorHistory
	return history != null and history.had_tell_within(flag_lookback_seconds)


func _deliver_flag(peer: int, area: Vector2, intensity: float) -> void:
	if peer == _local_peer():
		_apply_flag(area, intensity)
	else:
		_receive_flag.rpc_id(peer, area, intensity)


func _deliver_spotted(peer: int) -> void:
	if peer == _local_peer():
		_apply_spotted()
	else:
		_receive_spotted.rpc_id(peer)


@rpc("authority", "call_remote", "unreliable")
func _receive_flag(area: Vector2, intensity: float) -> void:
	_apply_flag(area, intensity)


@rpc("authority", "call_remote", "reliable")
func _receive_spotted() -> void:
	_apply_spotted()


func _apply_flag(area: Vector2, intensity: float) -> void:
	_flag_world_pos = area
	_flag_intensity = intensity
	_flag_timer = flag_duration_seconds


func _apply_spotted() -> void:
	_spotted_timer = flag_duration_seconds + 0.5


# === CLIENT: render the directional flag (hunter) + the spotted cue (target) =================
func _client_render(delta: float) -> void:
	_render_flag(delta)
	_render_spotted(delta)


func _render_flag(delta: float) -> void:
	if _flag_timer <= 0.0:
		if _flag_marker != null:
			_flag_marker.visible = false
		return
	_flag_timer -= delta
	var hud := _hud()
	if hud == null:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	# World → screen via the active camera's canvas transform.
	var screen_pos: Vector2 = viewport.get_canvas_transform() * _flag_world_pos
	var view_size: Vector2 = viewport.get_visible_rect().size
	# Guardrail: once the target's area is ON the hunter's screen, the flag vanishes.
	if flag_points_to_area_not_figure and Rect2(Vector2.ZERO, view_size).has_point(screen_pos):
		if _flag_marker != null:
			_flag_marker.visible = false
		return
	_ensure_flag_marker(hud)
	if _flag_marker == null:
		return
	# Place a marker at the screen edge along the direction to the target's area.
	var center := view_size * 0.5
	var dir := (screen_pos - center)
	if dir.length() < 1.0:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var edge := center + dir * (minf(view_size.x, view_size.y) * 0.42)
	_flag_marker.visible = true
	_flag_marker.position = edge - _flag_marker.size * 0.5
	_flag_marker.color = Color(0.95, 0.3, 0.2, 0.35 + 0.6 * _flag_intensity)


func _render_spotted(delta: float) -> void:
	if _spotted_timer <= 0.0:
		if _spotted_label != null:
			_spotted_label.visible = false
		return
	_spotted_timer -= delta
	var hud := _hud()
	if hud == null:
		return
	if _spotted_label == null or not is_instance_valid(_spotted_label):
		_spotted_label = Label.new()
		_spotted_label.name = "SpottedCue"
		_spotted_label.add_theme_font_size_override("font_size", 22)
		_spotted_label.modulate = Color(1.0, 0.4, 0.35)
		_spotted_label.position = Vector2(24.0, 150.0)
		hud.add_child(_spotted_label)
	_spotted_label.visible = true
	_spotted_label.text = "SPOTTED — re-blend"


func _ensure_flag_marker(hud: CanvasLayer) -> void:
	if _flag_marker != null and is_instance_valid(_flag_marker):
		return
	_flag_marker = ColorRect.new()
	_flag_marker.name = "BehavioralFlagMarker"
	_flag_marker.size = Vector2(26.0, 26.0)
	_flag_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_flag_marker)


func _hud() -> CanvasLayer:
	if _match == null or not _match.has_method("local_hud_layer"):
		return null
	return _match.local_hud_layer()


func _exposure_of(player: Node) -> float:
	var exp := player.get_node_or_null("ExposureComponent")
	return float(exp.get("exposure")) if exp != null else 0.0
