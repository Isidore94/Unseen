extends Node
class_name LayerComponent

# Layer — which "plane" a character occupies: the GROUND, up on a ROOFTOP, or down in
# a SEWER. The layer rewrites the rules of SEEING and KILLING (buildplan.md §7.2):
#   GROUND  — the normal world, and the only place kills happen.
#   ROOFTOP — hidden from the ground; a vantage to watch from, then drop down to strike.
#   SEWER   — blind (the surface is obscured) but you get a perfect arrow on your prey.
#
# This component is the SINGLE owner of the value (Principle #3). It is authority-agnostic:
# offline the player drives it directly; online the host drives it and replicates an int
# which the player mirrors into the LayerComponent. NPCs have NO LayerComponent — anything
# without one is treated as GROUND (see KillComponent._layer_of).

## The three planes. Kept in this order everywhere (CharacterVisual mirrors the ints).
enum Layer { GROUND, ROOFTOP, SEWER }

## Past-tense signal so the HUD / visuals react without polling (Principle #5).
signal layer_changed(new_layer: int)

## The plane this character is on right now. Everyone starts on the ground.
var current_layer: int = Layer.GROUND

# The shared body we tint to show the layer. Looked up once when the scene is live.
@onready var _visual: Node = get_parent().get_node_or_null("CharacterVisual")


func _ready() -> void:
	_apply_visual()


# Move to a new layer. ONE place changes the value, updates the look, and announces it.
func set_layer(layer: int) -> void:
	if layer == current_layer:
		return
	current_layer = layer
	_apply_visual()
	layer_changed.emit(current_layer)


func is_ground() -> bool:
	return current_layer == Layer.GROUND

func is_rooftop() -> bool:
	return current_layer == Layer.ROOFTOP

func is_sewer() -> bool:
	return current_layer == Layer.SEWER


# Tint the shared body so the layer reads at a glance.
#
# NOTE (buildplan §7.2, step 1): this is the "simple tint" placeholder — BOTH split-screen
# viewers currently see the tint. True per-viewer hiding (a ground player can't see a
# rooftop/sewer player AT ALL) is the per-viewport culling pass that comes next; doing the
# tint first lets us de-risk and play-test the LAYER LOGIC before the harder rendering work.
func _apply_visual() -> void:
	if _visual != null and _visual.has_method("set_layer_visual"):
		_visual.call("set_layer_visual", current_layer)
