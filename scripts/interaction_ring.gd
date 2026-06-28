extends Node2D
class_name InteractionRing

# A tight ring drawn around the LOCAL player (AC-Rearmed style). It shows the reach within which
# your actions (kill / decoy / poison) land, and highlights the NPC you'd act on right now (the one
# you're facing inside the ring — Player.interaction_target()). Purely a local visual aid; it owns
# no gameplay logic and is never replicated (other players never see your ring).

## Ring + highlight colours.
@export var ring_color: Color = Color(1.0, 0.95, 0.8, 0.32)
@export var target_color: Color = Color(1.0, 0.85, 0.2, 0.9)

var _player: Node2D = null


func _ready() -> void:
	_player = get_parent() as Node2D
	z_index = 40  # above the ground, below the smoke cloud (50)
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _player == null:
		return
	var radius := float(_player.get("interaction_radius"))
	# The ring itself (drawn at our parent's origin = the player's centre).
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, ring_color, 2.0, true)
	# Highlight whoever we'd act on right now.
	var target: Node2D = _player.call("interaction_target")
	if target != null and is_instance_valid(target):
		var local := target.global_position - _player.global_position  # ring sits at player origin, no scale
		draw_arc(local, 18.0, 0.0, TAU, 24, target_color, 2.5, true)
		draw_circle(local, 4.0, target_color)
