extends Control
class_name DangerOverlay

# DangerOverlay — UNSEEN. The "your hunter is closing in" feedback (AC Rearmed-style pursuer warning).
#
# A red screen-edge VIGNETTE plus a HEARTBEAT sound that both escalate as your hunter nears. The level
# (0 = safe, 1 = near, 2 = very near / in view) is decided HOST-side from the distance between you and
# your assigned hunter, and sent only to you — so it NEVER reveals WHICH on-screen figure your hunter
# is (hidden identity is preserved). This node just renders the level it's told.

## Colour of the danger glow.
@export var danger_color: Color = Color(0.9, 0.12, 0.12)
## Peak alpha of the edge glow (at the brightest beat of the highest level).
@export var max_edge_alpha: float = 0.55
## How far (px) the glow reaches in from each screen edge.
@export var vignette_band_px: float = 150.0
## Seconds between heartbeats at level 1 (near) and level 2 (very near). Faster = scarier.
@export var heartbeat_interval_near: float = 0.95
@export var heartbeat_interval_close: float = 0.5
const HEARTBEAT_STREAM := "res://assets/audio/heartbeat.wav"

var _level: int = 0
var _pulse: float = 0.0       ## 0..1 brightness of the current beat (decays between beats)
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
	_pulse = maxf(0.0, _pulse - delta * 3.0)  # the beat flash fades each frame
	if _level > 0:
		_beat_timer -= delta
		if _beat_timer <= 0.0:
			_beat_timer = heartbeat_interval_close if _level >= 2 else heartbeat_interval_near
			_pulse = 1.0
			if _audio != null and _audio.stream != null:
				_audio.play()
	queue_redraw()


func _draw() -> void:
	if _level <= 0 and _pulse <= 0.01:
		return
	var steady := 0.16 if _level >= 2 else (0.08 if _level == 1 else 0.0)
	var a := clampf(steady + _pulse * 0.6, 0.0, 1.0) * max_edge_alpha
	if a <= 0.01:
		return
	var size := get_rect().size
	var bands := 8
	var step := vignette_band_px / float(bands)
	# Stack translucent strips in from each edge — brightest at the edge, fading inward (a glow).
	for i in range(bands):
		var inset := step * float(i)
		var w := step + 1.0
		var col := Color(danger_color.r, danger_color.g, danger_color.b, a * (1.0 - float(i) / float(bands)))
		draw_rect(Rect2(0.0, inset, size.x, w), col)                    # top
		draw_rect(Rect2(0.0, size.y - inset - w, size.x, w), col)       # bottom
		draw_rect(Rect2(inset, 0.0, w, size.y), col)                    # left
		draw_rect(Rect2(size.x - inset - w, 0.0, w, size.y), col)       # right
