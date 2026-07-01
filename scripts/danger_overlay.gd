extends Control
class_name DangerOverlay

# DangerOverlay — UNSEEN. The "your hunter is closing in" feedback (AC Rearmed-style pursuer warning).
#
# A HEARTBEAT sound that escalates as your hunter nears. The level (0 = safe, 1 = near / on-screen,
# 2 = very near) is decided HOST-side from the distance between you and your assigned hunter, and sent
# only to you — so it NEVER reveals WHICH on-screen figure your hunter is (hidden identity is
# preserved). This node just plays the beat for the level it's told.
#
# NOTE: the old red screen-edge VIGNETTE was removed — the heartbeat alone now carries the tension, and
# the glow was cluttering the view. If a visual cue is ever wanted again, restore a _draw() here; the
# host-driven level plumbing is unchanged.

## Seconds between heartbeats at level 1 (near) and level 2 (very near). Faster = scarier.
@export var heartbeat_interval_near: float = 0.95
@export var heartbeat_interval_close: float = 0.5
const HEARTBEAT_STREAM := "res://assets/audio/heartbeat.wav"

var _level: int = 0
var _beat_timer: float = 0.0
var _audio: AudioStreamPlayer = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eat clicks
	_audio = AudioStreamPlayer.new()
	if ResourceLoader.exists(HEARTBEAT_STREAM):
		_audio.stream = load(HEARTBEAT_STREAM)  # silent if the placeholder sound is absent
	add_child(_audio)


# Host-driven danger level (0 safe / 1 near / 2 very near). Idempotent.
func set_level(level: int) -> void:
	_level = clampi(level, 0, 2)
	if _level == 0:
		_beat_timer = 0.0


func _process(delta: float) -> void:
	if _level <= 0:
		return
	_beat_timer -= delta
	if _beat_timer <= 0.0:
		_beat_timer = heartbeat_interval_close if _level >= 2 else heartbeat_interval_near
		if _audio != null and _audio.stream != null:
			_audio.play()
