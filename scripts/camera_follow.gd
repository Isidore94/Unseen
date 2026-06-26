extends Camera2D
class_name CameraFollow

# A viewport-owned camera that follows one actor. Keeping cameras outside the
# Player scene lets local co-op render the same world from two private views.

## Actor this camera follows.
@export var target_path: NodePath

## How quickly the camera catches up to the target.
@export var smoothing_speed: float = 8.0

var _target: Node2D = null


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = smoothing_speed
	make_current()
	_acquire_target()
	if _target != null:
		global_position = _target.global_position


func _process(_delta: float) -> void:
	_acquire_target()
	if _target != null and is_instance_valid(_target):
		global_position = _target.global_position


func _acquire_target() -> void:
	if _target != null and is_instance_valid(_target):
		return
	if target_path == NodePath(""):
		return
	_target = get_node_or_null(target_path) as Node2D
