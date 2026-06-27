extends Node

# 9D — MUTUAL PROXIMITY (PHASE_9_EXPERIMENTS.md §9D). When two players are each other's target and
# both have finished their contracts, BOTH get a hot/cold proximity cue — warmer as they close, with
# NO direction and NO figure. Forces the endgame to converge without gifting anyone the kill; the
# final identification at the meeting point is still a pure crowd read. It's symmetric, so it rewards
# nobody — it just breaks the stall.
#
# REMOVABILITY (§1): inert unless ExperimentFlags.mutual_proximity_enabled. The HOST computes the
# distance (it owns every position) and sends each player an INTENSITY only — never a direction. The
# client renders a simple meter from that number. No new infrastructure; reads existing state.

enum SignalStyle { METER, PULSE, AUDIO_TEMPO }

## Only activate once BOTH players have finished their marks (keeps it an endgame tool).
@export var activates_after_contracts_complete: bool = true
## Beyond this distance (px) there is no signal (fully cold).
@export var max_signal_range_px: float = 1200.0
## Optional distance→intensity shaping (0..1 in = closeness, 0..1 out). Null = linear. A curve that
## stays low until fairly close keeps this a nudge, not a tracker.
@export var signal_curve: Curve = null
## How the cue reads. METER (a fill bar) and PULSE (a throb) are implemented; AUDIO_TEMPO is a TODO.
@export var signal_style: SignalStyle = SignalStyle.METER
## Keep true: both players get the cue or neither does. A one-sided version is a free kill (Pillar #4).
@export var mutual_only: bool = true
## Host send rate (seconds). The cue is a slow nudge, so we don't need per-frame updates.
@export var send_interval_seconds: float = 0.15

var _match: Node = null
var _send_timer: float = 0.0

# --- client-side cue state ---
var _local_intensity: float = 0.0
var _intensity_target: float = 0.0
var _seconds_since_signal: float = 999.0
var _cue_root: Control = null
var _cue_fill: ColorRect = null
var _pulse_clock: float = 0.0


func _process(delta: float) -> void:
	if not ExperimentFlags.mutual_proximity_enabled:
		return
	# The host is ALSO a player, so it runs host logic AND renders its own cue (not an else).
	if _is_host():
		_host_tick(delta)
	_client_render(delta)


func _is_host() -> bool:
	return (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()


func _local_peer() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1


# === HOST: compute symmetric intensity for each mutual, contract-complete pair ===============
func _host_tick(delta: float) -> void:
	_send_timer -= delta
	if _send_timer > 0.0:
		return
	_send_timer = send_interval_seconds
	if _match == null or not is_instance_valid(_match):
		_match = get_tree().get_first_node_in_group("online_match")
	if _match == null or not _match.has_method("host_hunt_edges"):
		return

	var edges: Array = _match.host_hunt_edges()
	# Index hunter→target so we can detect mutual pairs (A hunts B AND B hunts A).
	var by_hunter: Dictionary = {}
	for e in edges:
		by_hunter[int(e["hunter_peer"])] = e

	for e in edges:
		var a: int = int(e["hunter_peer"])
		var b: int = int(e["target_peer"])
		if a >= b:
			continue  # process each pair once
		if mutual_only:
			var reverse = by_hunter.get(b, null)
			if reverse == null or int(reverse["target_peer"]) != a:
				continue  # not mutual
		if activates_after_contracts_complete and not (bool(e["hunter_ready"]) and bool(e["target_ready"])):
			continue
		var hunter: Node2D = e["hunter"]
		var target: Node2D = e["target"]
		if hunter == null or target == null:
			continue
		var distance := hunter.global_position.distance_to(target.global_position)
		var intensity := _intensity_for(distance)
		# Symmetric: both ends get the SAME intensity, no direction.
		_deliver_intensity(a, intensity)
		_deliver_intensity(b, intensity)


# Send intensity to a peer — directly if it's the host's own player, else over the wire.
func _deliver_intensity(peer: int, intensity: float) -> void:
	if peer == _local_peer():
		_receive_intensity(intensity)
	else:
		_receive_intensity.rpc_id(peer, intensity)


func _intensity_for(distance: float) -> float:
	if distance >= max_signal_range_px:
		return 0.0
	var closeness := 1.0 - clampf(distance / max_signal_range_px, 0.0, 1.0)
	if signal_curve != null:
		return clampf(signal_curve.sample(closeness), 0.0, 1.0)
	return closeness


# === CLIENT: render the intensity as a no-direction cue ======================================
@rpc("authority", "call_remote", "unreliable")
func _receive_intensity(intensity: float) -> void:
	_intensity_target = clampf(intensity, 0.0, 1.0)
	_seconds_since_signal = 0.0


func _client_render(delta: float) -> void:
	_seconds_since_signal += delta
	# No fresh signal for a moment → treat as cold (the pair separated or the phase ended).
	if _seconds_since_signal > 0.5:
		_intensity_target = 0.0
	_local_intensity = lerp(_local_intensity, _intensity_target, clampf(delta * 6.0, 0.0, 1.0))
	_pulse_clock += delta

	if _local_intensity < 0.02:
		if _cue_root != null:
			_cue_root.visible = false
		return
	_ensure_cue()
	if _cue_root == null:
		return
	_cue_root.visible = true

	match signal_style:
		SignalStyle.PULSE:
			# Throb the whole cue faster/brighter as it warms.
			var throb := 0.5 + 0.5 * sin(_pulse_clock * lerp(2.0, 12.0, _local_intensity))
			_cue_fill.color.a = 0.25 + 0.65 * throb * _local_intensity
			_cue_fill.size.x = _cue_root.size.x
		_:  # METER (default) and AUDIO_TEMPO fall back to a fill bar for now
			_cue_fill.size.x = _cue_root.size.x * _local_intensity
			_cue_fill.color.a = 0.85


# Build the cue lazily in the local HUD layer the first time we need it.
func _ensure_cue() -> void:
	if _cue_root != null and is_instance_valid(_cue_root):
		return
	if _match == null or not is_instance_valid(_match):
		_match = get_tree().get_first_node_in_group("online_match")
	if _match == null or not _match.has_method("local_hud_layer"):
		return
	var hud := _match.local_hud_layer()
	if hud == null:
		return
	_cue_root = Control.new()
	_cue_root.name = "ProximityCue"
	_cue_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cue_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_cue_root.position = Vector2(-120.0, -70.0)
	_cue_root.size = Vector2(240.0, 10.0)
	var back := ColorRect.new()
	back.color = Color(0.0, 0.0, 0.0, 0.35)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cue_root.add_child(back)
	_cue_fill = ColorRect.new()
	_cue_fill.color = Color(1.0, 0.45, 0.2, 0.85)  # warm = close
	_cue_fill.position = Vector2.ZERO
	_cue_fill.size = Vector2(0.0, 10.0)
	_cue_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cue_root.add_child(_cue_fill)
	hud.add_child(_cue_root)
