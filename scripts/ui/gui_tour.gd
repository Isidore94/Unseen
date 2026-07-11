extends CanvasLayer
class_name GuiTour

# GuiTour — UNSEEN. A click-through GUI tutorial for new players: dims the whole screen,
# SPOTLIGHTS one HUD region at a time (a bright-bordered hole in the dim), and explains it in a
# caption card. Click anywhere (or press any key) to advance; Esc closes it early.
#
# It is a pure OVERLAY: it never pauses the game or touches gameplay state. The steps come from
# whoever opens it (MatchHud.tour_steps() supplies the real on-screen rects), so the tour always
# points at the actual HUD the player is looking at — no separate screenshots to keep in sync.
#
# It is opened on demand: the menu's TUTORIAL button (a single-player bot match) and the in-match
# scoreboard's HOW TO PLAY button. It never auto-opens in real MP — those matches just start.

## Emitted when the tour finishes or is skipped.
signal closed

## The steps to walk through. Each is {"rect": Rect2 (screen coords; a ZERO rect = no spotlight,
## centred text card instead), "title": String, "body": String}. Set BEFORE add_child().
var steps: Array = []

## Dim colour of the non-highlighted screen, and the spotlight's border colour.
@export var dim_color: Color = Color(0.0, 0.0, 0.0, 0.62)
@export var border_color: Color = Color(0.95, 0.8, 0.35)

var _index: int = 0
var _click_shield: Control = null
var _dim_rects: Array[ColorRect] = []      # 4 panels around the spotlight hole
var _border_rects: Array[ColorRect] = []   # 4 thin edges outlining the hole
var _caption: PanelContainer = null
var _step_label: Label = null
var _title_label: Label = null
var _body_label: Label = null


func _ready() -> void:
	layer = 85  # above the HUD (5), scoreboard (40) and start curtain (80); below the flashbang (90)
	# Full-screen invisible shield: STOPs mouse so clicks advance the tour instead of hitting
	# whatever is underneath.
	_click_shield = Control.new()
	_click_shield.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP only the MOUSE. Keyboard/gamepad flow straight through to the live bot match underneath,
	# so the player can WALK AROUND and fight the AI hunter while the tour points things out — only
	# a CLICK advances a step (movement never does).
	_click_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_click_shield)
	# The dim is FOUR rects arranged around the spotlight hole (so the hole itself stays bright).
	for i in 4:
		var dim := ColorRect.new()
		dim.color = dim_color
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
		_dim_rects.append(dim)
	for i in 4:
		var edge := ColorRect.new()
		edge.color = border_color
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(edge)
		_border_rects.append(edge)
	# The caption card (step counter + title + body + footer hint).
	_caption = PanelContainer.new()
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 16)
	_caption.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	pad.add_child(column)
	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", 13)
	_step_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	column.add_child(_step_label)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", border_color)
	column.add_child(_title_label)
	_body_label = Label.new()
	_body_label.add_theme_font_size_override("font_size", 16)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.custom_minimum_size = Vector2(460, 0)
	column.add_child(_body_label)
	var footer := Label.new()
	footer.text = "CLICK to continue   ·   Esc to close   ·   (WASD still moves you)"
	footer.add_theme_font_size_override("font_size", 13)
	footer.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	column.add_child(footer)
	add_child(_caption)
	_show_step()


# Advance ONLY on a mouse click; Esc closes. We deliberately DON'T handle movement keys — they
# fall through to the live match so the player keeps playing while learning. Each event we DO act
# on is marked handled so the click/Esc doesn't also hit gameplay or the scoreboard underneath.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_index += 1
		if _index >= steps.size():
			_close()
		else:
			_show_step()
		get_viewport().set_input_as_handled()


func _close() -> void:
	closed.emit()
	queue_free()


# Lay out the current step: position the four dim panels + border edges around the spotlight
# hole (or dim everything when the step has no rect), and place the caption card near it.
func _show_step() -> void:
	var step: Dictionary = steps[_index]
	var view_size := _click_shield.get_viewport_rect().size
	var hole: Rect2 = step.get("rect", Rect2())
	var has_hole := hole.size.x > 0.0 and hole.size.y > 0.0
	if has_hole:
		hole = hole.grow(6.0)  # a little air around the highlighted panel
	# Four dims: above, below, left-of and right-of the hole (full-screen when no hole).
	if has_hole:
		_dim_rects[0].position = Vector2.ZERO
		_dim_rects[0].size = Vector2(view_size.x, hole.position.y)
		_dim_rects[1].position = Vector2(0, hole.end.y)
		_dim_rects[1].size = Vector2(view_size.x, view_size.y - hole.end.y)
		_dim_rects[2].position = Vector2(0, hole.position.y)
		_dim_rects[2].size = Vector2(hole.position.x, hole.size.y)
		_dim_rects[3].position = Vector2(hole.end.x, hole.position.y)
		_dim_rects[3].size = Vector2(view_size.x - hole.end.x, hole.size.y)
	else:
		_dim_rects[0].position = Vector2.ZERO
		_dim_rects[0].size = view_size
		for i in range(1, 4):
			_dim_rects[i].size = Vector2.ZERO
	# Gold border edges around the hole (hidden when there is none).
	var edge := 3.0
	for border in _border_rects:
		border.visible = has_hole
	if has_hole:
		_border_rects[0].position = hole.position - Vector2(edge, edge)
		_border_rects[0].size = Vector2(hole.size.x + edge * 2.0, edge)
		_border_rects[1].position = Vector2(hole.position.x - edge, hole.end.y)
		_border_rects[1].size = Vector2(hole.size.x + edge * 2.0, edge)
		_border_rects[2].position = Vector2(hole.position.x - edge, hole.position.y)
		_border_rects[2].size = Vector2(edge, hole.size.y)
		_border_rects[3].position = Vector2(hole.end.x, hole.position.y)
		_border_rects[3].size = Vector2(edge, hole.size.y)
	# Caption text.
	_step_label.text = "STEP %d OF %d" % [_index + 1, steps.size()]
	_title_label.text = String(step.get("title", ""))
	_body_label.text = String(step.get("body", ""))
	# Place the caption: centred when there's no hole; otherwise beside the hole, on whichever
	# half of the screen has more room (below it in the top half, above it in the bottom half).
	_caption.reset_size()
	await get_tree().process_frame  # let the card re-measure with the new text before placing it
	var card := _caption.size
	if not has_hole:
		_caption.position = (view_size - card) * 0.5
	else:
		var x := clampf(hole.position.x, 16.0, view_size.x - card.x - 16.0)
		var y: float
		if hole.get_center().y < view_size.y * 0.5:
			y = minf(hole.end.y + 18.0, view_size.y - card.y - 16.0)
		else:
			y = maxf(hole.position.y - card.y - 18.0, 16.0)
		_caption.position = Vector2(x, y)
