extends CanvasLayer
class_name Hud

# HUD - UNSEEN. Per-player exposure meter.
#
# The HUD only shows the owning player their own exposure. In local co-op, each
# SubViewport gets a separate HUD instance pointed at its own Player.

## Which ExposureComponent should this bar watch? Scene-authored HUDs can wire
## this in the Inspector; runtime HUDs can call watch_exposure().
@export var exposure_component_path: NodePath

@onready var exposure_bar: ProgressBar = $ExposureBar

var _fill_style: StyleBoxFlat
var _watched_exposure_component: ExposureComponent = null


func _ready() -> void:
	_fill_style = StyleBoxFlat.new()
	_fill_style.set_corner_radius_all(4)
	exposure_bar.add_theme_stylebox_override("fill", _fill_style)

	if exposure_component_path != NodePath(""):
		var exposure_component := get_node_or_null(exposure_component_path) as ExposureComponent
		if exposure_component != null:
			watch_exposure(exposure_component)
			return

	_on_exposure_changed(0.0)


func watch_exposure(exposure_component: ExposureComponent) -> void:
	if _watched_exposure_component != null:
		var old_callback := Callable(self, "_on_exposure_changed")
		if _watched_exposure_component.exposure_changed.is_connected(old_callback):
			_watched_exposure_component.exposure_changed.disconnect(old_callback)

	_watched_exposure_component = exposure_component
	var callback := Callable(self, "_on_exposure_changed")
	if not exposure_component.exposure_changed.is_connected(callback):
		exposure_component.exposure_changed.connect(callback)
	_on_exposure_changed(exposure_component.exposure)


func _on_exposure_changed(new_value: float) -> void:
	exposure_bar.value = new_value
	if _fill_style != null:
		_fill_style.bg_color = _color_for_exposure(new_value)


func _color_for_exposure(value: float) -> Color:
	var amount: float = value / 100.0
	var green: Color = Color(0.2, 0.8, 0.2)
	var yellow: Color = Color(0.9, 0.85, 0.2)
	var red: Color = Color(0.9, 0.2, 0.2)
	if amount < 0.5:
		return green.lerp(yellow, amount / 0.5)
	return yellow.lerp(red, (amount - 0.5) / 0.5)
