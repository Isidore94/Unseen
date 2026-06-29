extends Node2D
class_name LockReticle

# LockReticle — UNSEEN. The private, controller-friendly target-lock indicator: AC-style corner
# brackets drawn over the character your KillComponent has soft-locked.
#
# HIDDEN-IDENTITY SAFE: it is created LOCALLY for your own player and NEVER replicated, so only YOU
# see your lock. It locks ANY character (you can lock the wrong one) and does NOT mean "this is your
# assigned target" — you still confirm by behaviour. So Pillar #1 (sameness) holds.

## Half the bracket box size (px) and how long each corner stroke is.
@export var half_size_px: float = 26.0
@export var corner_len_px: float = 11.0
@export var line_width: float = 2.5
## Colour when locked but OUT of striking range, vs IN range ("press to assassinate").
@export var color_far: Color = Color(1.0, 1.0, 1.0, 0.75)
@export var color_ready: Color = Color(1.0, 0.28, 0.22, 0.95)

var _target: Node2D = null
var _ready_to_kill: bool = false


func _ready() -> void:
	z_index = 40  # above the characters
	visible = false


# Called each frame by OnlineMatch from the local player's KillComponent lock state.
func track(target: Node2D, ready_to_kill: bool) -> void:
	_target = target
	_ready_to_kill = ready_to_kill
	visible = target != null and is_instance_valid(target)


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		if visible:
			visible = false
		return
	global_position = _target.global_position
	queue_redraw()


func _draw() -> void:
	var c := color_ready if _ready_to_kill else color_far
	var h := half_size_px
	var l := corner_len_px
	# Four corner brackets around the box (an AC-style reticle).
	for corner in [Vector2(-h, -h), Vector2(h, -h), Vector2(-h, h), Vector2(h, h)]:
		var sx := signf(corner.x)
		var sy := signf(corner.y)
		draw_line(corner, corner - Vector2(sx * l, 0.0), c, line_width)
		draw_line(corner, corner - Vector2(0.0, sy * l), c, line_width)
