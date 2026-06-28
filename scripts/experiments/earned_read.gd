extends Node

# 9C — EARNED READ (PHASE_9_EXPERIMENTS.md §9C). A player who stays DISCIPLINED (low exposure for a
# sustained stretch) can trigger a brief pulse that highlights BEHAVIORAL ANOMALIES in the crowd —
# soft zones around figures who recently ran, sharp-turned, or killed. It says "those few are acting
# like players, look closer," never "that one IS the player." Rewards sustained calm; the reckless
# player can never charge it. It amplifies the read-the-crowd skill instead of replacing it.
#
# REMOVABILITY (§1): inert unless ExperimentFlags.earned_read_enabled. The HOST owns the charge and
# the anomaly query (server-authoritative); it sends the requesting client a list of AREA positions,
# which the client draws as fading rings. Reads core state + the shared BehaviorHistory; core never
# references this. Delete the file + its overlay + flag line (+ the input action) → unchanged.

const PULSE_OVERLAY := preload("res://scripts/anomaly_pulse_overlay.gd")

## Must stay at or below this exposure to keep charging the ability.
@export var discipline_threshold_exposure: float = 25.0
## Seconds you must stay disciplined to unlock one pulse.
@export var discipline_charge_seconds: float = 30.0
## How long the highlight lasts.
@export var pulse_duration_seconds: float = 1.5
## How far around you the pulse reaches.
@export var pulse_radius_px: float = 600.0
## How recent a tell (run / sharp-turn / kill / tool) must be to flag a figure.
@export var anomaly_lookback_seconds: float = 4.0
## On-screen radius of each soft highlight zone.
@export var highlight_zone_radius_px: float = 90.0
## Using a pulse resets the discipline charge (not spammable).
@export var consume_on_use: bool = true
## Also flag OTHER players who are suspiciously low-exposure. OFF by default — it can over-reveal
## careful players; behavior tells are the primary signal.
@export var flag_suspiciously_low_exposure: bool = false
## "Suspiciously low" threshold for the option above.
@export var suspicious_low_exposure: float = 8.0
## Cap on highlighted zones per pulse (keeps the cue a suggestion and the payload small).
@export var max_zones_per_pulse: int = 40
## Input action that fires a pulse (added to the Input Map; rebindable — never a hardcoded key).
@export var pulse_action: String = "earned_read_pulse"

var _match: Node = null
var _charge_by_peer: Dictionary = {}   ## host: peer -> seconds of sustained discipline
var _ready_by_peer: Dictionary = {}    ## host: peer -> was-ready (to notify on change)
var _ensure_timer: float = 0.0

# client-side
var _overlay: Node2D = null
var _ready_label: Label = null
var _pulse_ready_local: bool = false


func _process(delta: float) -> void:
	if not ExperimentFlags.earned_read_enabled:
		return
	if _match == null or not is_instance_valid(_match):
		_match = get_tree().get_first_node_in_group("online_match")
	if _is_host():
		_host_tick(delta)
	_local_input_tick()
	_update_ready_label()


func _is_host() -> bool:
	return (not multiplayer.has_multiplayer_peer()) or multiplayer.is_server()


func _local_peer() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1


# === HOST: charge tracking + the anomaly query ==============================================
func _host_tick(delta: float) -> void:
	# Keep a BehaviorHistory on every actor so it's been recording BEFORE any pulse is fired.
	_ensure_timer -= delta
	if _ensure_timer <= 0.0:
		_ensure_timer = 0.5
		for actor in _all_actors():
			BehaviorHistory.ensure_on(actor)

	# Advance each player's discipline charge (reset the instant they break discipline).
	for player in get_tree().get_nodes_in_group("player"):
		var peer := int(player.get("controlling_peer_id"))
		if peer == 0:
			continue
		var exposure := _exposure_of(player)
		if exposure <= discipline_threshold_exposure:
			_charge_by_peer[peer] = minf(discipline_charge_seconds, float(_charge_by_peer.get(peer, 0.0)) + delta)
		else:
			_charge_by_peer[peer] = 0.0
		var ready := float(_charge_by_peer[peer]) >= discipline_charge_seconds
		if ready != bool(_ready_by_peer.get(peer, false)):
			_ready_by_peer[peer] = ready
			_deliver_ready(peer, ready)


# Host resolves a pulse request from `peer` (or the host's own press).
func _resolve_pulse(peer: int) -> void:
	if float(_charge_by_peer.get(peer, 0.0)) < discipline_charge_seconds:
		return  # not charged — ignore
	var requester := _player_of_peer(peer)
	if requester == null:
		return
	var origin: Vector2 = requester.global_position
	var zones: Array = []
	for actor in _all_actors():
		if actor == requester or not is_instance_valid(actor):
			continue
		if origin.distance_to(actor.global_position) > pulse_radius_px:
			continue
		if _is_anomalous(actor):
			zones.append(actor.global_position)
			if zones.size() >= max_zones_per_pulse:
				break
	if consume_on_use:
		_charge_by_peer[peer] = 0.0
		_deliver_ready(peer, false)
		_ready_by_peer[peer] = false
	_deliver_pulse(peer, PackedVector2Array(zones))


# A figure is anomalous if it produced a recent tell, or (optionally) is a suspiciously calm player.
func _is_anomalous(actor: Node) -> bool:
	var history := actor.get_node_or_null("BehaviorHistory") as BehaviorHistory
	if history != null and history.had_tell_within(anomaly_lookback_seconds):
		return true
	if flag_suspiciously_low_exposure and actor.is_in_group("player"):
		return _exposure_of(actor) <= suspicious_low_exposure
	return false


# === delivery (host → the one client that earned it; handles the host being its own player) ====
func _deliver_pulse(peer: int, zones: PackedVector2Array) -> void:
	if peer == _local_peer():
		_apply_pulse(zones)
	else:
		_receive_pulse.rpc_id(peer, zones)


func _deliver_ready(peer: int, ready: bool) -> void:
	if peer == _local_peer():
		_pulse_ready_local = ready
	else:
		_receive_ready.rpc_id(peer, ready)


# === CLIENT: input + rendering ==============================================================
func _local_input_tick() -> void:
	if not InputMap.has_action(pulse_action):
		return
	if Input.is_action_just_pressed(pulse_action):
		_submit_request()


func _submit_request() -> void:
	if _is_host():
		_resolve_pulse(_local_peer())
	else:
		_request_pulse.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_pulse() -> void:
	if not multiplayer.is_server():
		return
	_resolve_pulse(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable")
func _receive_pulse(zones: PackedVector2Array) -> void:
	_apply_pulse(zones)


@rpc("authority", "call_remote", "reliable")
func _receive_ready(ready: bool) -> void:
	_pulse_ready_local = ready


func _apply_pulse(zones: PackedVector2Array) -> void:
	if zones.is_empty():
		return
	if _overlay == null or not is_instance_valid(_overlay):
		if _match == null or not is_instance_valid(_match):
			_match = get_tree().get_first_node_in_group("online_match")
		if _match == null:
			return
		_overlay = PULSE_OVERLAY.new()
		_overlay.name = "AnomalyPulseOverlay"
		_match.add_child(_overlay)  # world-space child of the match → zones pin to the world
	var positions: Array = []
	for v in zones:
		positions.append(v)
	_overlay.call("show_spots", positions, pulse_duration_seconds, highlight_zone_radius_px)


func _update_ready_label() -> void:
	# A faint "PULSE READY [Q]" hint when charged (only on the machine whose player is charged).
	if _match == null or not _match.has_method("local_hud_layer"):
		return
	var hud := _match.local_hud_layer()
	if hud == null:
		return
	if _ready_label == null or not is_instance_valid(_ready_label):
		_ready_label = Label.new()
		_ready_label.name = "EarnedReadHint"
		_ready_label.add_theme_font_size_override("font_size", 16)
		_ready_label.modulate = Color(1.0, 0.9, 0.4)
		_ready_label.position = Vector2(24.0, 120.0)
		hud.add_child(_ready_label)
	_ready_label.visible = _pulse_ready_local
	_ready_label.text = "PULSE READY  [read the crowd]"


# --- helpers ---------------------------------------------------------------
func _all_actors() -> Array:
	var out: Array = []
	out.append_array(get_tree().get_nodes_in_group("player"))
	out.append_array(get_tree().get_nodes_in_group("npc"))
	return out


func _player_of_peer(peer: int) -> Node2D:
	for player in get_tree().get_nodes_in_group("player"):
		if int(player.get("controlling_peer_id")) == peer:
			return player
	return null


func _exposure_of(player: Node) -> float:
	var exp := player.get_node_or_null("ExposureComponent")
	return float(exp.get("exposure")) if exp != null else 100.0
