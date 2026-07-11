extends Node
# ARROW INTEL BANDS TEST (see dev_tests/README.md).
# Proves the hunt arrow's SEQUENTIAL escalation, driven by the target's exposure:
#   <25 (Blended)  -> no arrow at all
#   25-49 (Noticed) -> TRANSLUCENT 4-way pulse (noticed_pulse_alpha)
#   50+ (Exposed)  -> SOLID precise bearing (alpha 1.0)
# ...so the faint arrow BECOMES the solid arrow — never two stacked cues at one threshold.


var _failures: Array[String] = []


func _check(label: String, ok: bool) -> void:
	print("  %s: %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures.append(label)


func _ready() -> void:
	# A current camera at the origin, and a target FAR off-screen to the right — so the
	# arrow's off-screen gate passes and the bearing is a clean "RIGHT".
	var camera := Camera2D.new()
	add_child(camera)
	camera.make_current()
	var target := Node2D.new()
	add_child(target)
	target.global_position = Vector2(50000.0, 0.0)
	var target_exposure := ExposureComponent.new()
	target_exposure.name = "ExposureComponent"
	target.add_child(target_exposure)

	var arrow := ExposureArrow.new()
	add_child(arrow)
	arrow.flashing_mode = true
	arrow.track_target(target)

	# BLENDED: no arrow at all.
	target_exposure.exposure = 10.0
	arrow._process_flashing(0.016)
	_check("blended (<25): no arrow", arrow._alpha == 0.0)

	# NOTICED: the pulse fires promptly after entering the band, TRANSLUCENT and 4-way.
	target_exposure.exposure = 30.0
	arrow._process_flashing(0.016)
	_check("noticed (25-49): pulse is translucent",
		absf(arrow._alpha - arrow.noticed_pulse_alpha) < 0.001)
	_check("noticed pulse alpha is genuinely translucent (<1)", arrow.noticed_pulse_alpha < 1.0)
	_check("noticed pulse snaps to a cardinal", arrow._arrow_dir == Vector2.RIGHT)

	# NOTICED, between pulses: the arrow goes dark (it's a pulse, not a beacon).
	arrow._process_flashing(arrow.flash_duration + 0.05)
	_check("noticed: dark between pulses", arrow._alpha == 0.0)

	# EXPOSED: the same arrow turns SOLID and precise.
	target_exposure.exposure = 60.0
	arrow._process_flashing(0.016)
	_check("exposed (50+): arrow is SOLID", arrow._alpha == 1.0)

	# Cooling back into the noticed band drops it back to the faint pulse (no stale solid).
	target_exposure.exposure = 30.0
	arrow._process_flashing(0.016)
	_check("cooling to noticed: no stale solid arrow", arrow._alpha < 1.0)

	if _failures.is_empty():
		print("ALL PASS (arrow bands)")
	else:
		print("FAILURES: %d" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
