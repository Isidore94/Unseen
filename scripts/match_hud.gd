extends CanvasLayer
class_name MatchHud

# MatchHud — UNSEEN. The premium themed match HUD (the 8-region layout from the mockup): portrait +
# name + exposure, objectives, map legend, round/timer banner, player roster, system log, ability
# bar, and a slot to host the mini-map. Built in code (dark + gold panels, Cinzel typography, PixelLab
# icons). The match (online or offline) creates ONE of these and feeds it via the public setters —
# the HUD owns presentation only; gameplay/logic stays in the match (Principle #1).

const GOLD := Color(0.80, 0.64, 0.34)
const GOLD_DIM := Color(0.55, 0.45, 0.28)
const PANEL_BG := Color(0.07, 0.06, 0.05, 0.93)
const TEXT := Color(0.90, 0.87, 0.80)
const ICONS := "res://assets/ui/icons/"
const FONT := "res://assets/fonts/Cinzel.ttf"

var _root: Control = null
var _name_label: Label = null
var _title_label: Label = null
var _exposure_segs: Array[ColorRect] = []
var _objective_label: Label = null
var _optional_label: Label = null
var _round_label: Label = null
var _time_label: Label = null
var _roster_rows: Array = []          # Array of {name:Label, score:Label, dot:ColorRect}
var _log_lines: Array[String] = []
var _log_label: Label = null
var _portrait: TextureRect = null
var _ability_slots: Dictionary = {}   # key -> {label:Label, sub:Label, dim:bool}
var minimap_slot: Control = null      # the match drops its MiniMap in here
var _reveals: HBoxContainer = null     # holds the TARGET (red) + EXPOSED (blue) reveal portraits
var _target_plate: Control = null
var _exposed_shown: Array[int] = []
const MAX_LOG := 6


func _ready() -> void:
	layer = 5
	# Experiments call group "experiment_toast" .show_message() — route those into the log instead of
	# the old middle-of-screen toast.
	add_to_group("experiment_toast")
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	var f := load(FONT)
	if f != null:
		theme.default_font = f
	theme.default_font_size = 14
	_root.theme = theme
	add_child(_root)

	var vp := _root.get_viewport_rect().size
	if vp == Vector2.ZERO:
		vp = Vector2(1920, 1080)
	_portrait_panel(Rect2(16, 16, 320, 96))
	_objectives_panel(Rect2(16, 126, 270, 132))
	_legend_panel(Rect2(16, 270, 270, 232))
	_timer_banner(Rect2(vp.x * 0.5 - 200, 12, 400, 60))
	_roster_panel(Rect2(vp.x - 316, 16, 300, 156))
	_log_panel(Rect2(16, vp.y - 220, 360, 204))
	_ability_bar(Rect2(vp.x * 0.5 - 300, vp.y - 106, 600, 92))
	_minimap_panel(Rect2(vp.x - 268, vp.y - 268, 252, 252))
	_reveals_row(Vector2(vp.x * 0.5, 82))


# === styling helpers =======================================================
func _panel(rect: Rect2) -> Panel:
	var p := Panel.new()
	p.position = rect.position; p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_border_width_all(2); sb.border_color = GOLD
	sb.set_corner_radius_all(4); sb.set_content_margin_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.5); sb.shadow_size = 6
	p.add_theme_stylebox_override("panel", sb)
	_root.add_child(p)
	return p

func _mklabel(parent: Control, text: String, pos: Vector2, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text; l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _icon(parent: Control, icon_name: String, pos: Vector2, sz: int) -> void:
	var path := ICONS + icon_name + ".png"
	if not ResourceLoader.exists(path):
		var box := ColorRect.new(); box.position = pos; box.size = Vector2(sz, sz); box.color = Color(0.25, 0.2, 0.12); parent.add_child(box); return
	var wrap := Control.new(); wrap.position = pos; wrap.custom_minimum_size = Vector2(sz, sz); wrap.size = Vector2(sz, sz); wrap.clip_contents = true; parent.add_child(wrap)
	var tr := TextureRect.new(); tr.texture = load(path); tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; wrap.add_child(tr)


# === regions ===============================================================
func _portrait_panel(rect: Rect2) -> void:
	var p := _panel(rect)
	var frame := Panel.new(); frame.position = Vector2(8, 8); frame.size = Vector2(72, 72)
	var fb := StyleBoxFlat.new(); fb.bg_color = Color(0.03, 0.03, 0.04); fb.set_border_width_all(2); fb.border_color = GOLD_DIM
	frame.add_theme_stylebox_override("panel", fb); p.add_child(frame)
	_portrait = TextureRect.new(); _portrait.position = Vector2(4, 4); _portrait.size = Vector2(64, 64)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; frame.add_child(_portrait)
	_name_label = _mklabel(p, "PLAYER", Vector2(90, 8), 20, GOLD)
	_title_label = _mklabel(p, "", Vector2(90, 34), 14, TEXT)
	for i in 7:
		var seg := ColorRect.new(); seg.position = Vector2(90 + i * 28, 60); seg.size = Vector2(24, 12); seg.color = Color(0.2, 0.18, 0.15)
		p.add_child(seg); _exposure_segs.append(seg)

func _objectives_panel(rect: Rect2) -> void:
	var p := _panel(rect)
	_mklabel(p, "OBJECTIVES", Vector2(8, 6), 15, GOLD)
	_objective_label = _mklabel(p, "Locating your marks…", Vector2(10, 34), 14, TEXT)
	_mklabel(p, "OPTIONAL", Vector2(8, 80), 15, GOLD)
	_optional_label = _mklabel(p, "—", Vector2(10, 104), 13, TEXT)

func _legend_panel(rect: Rect2) -> void:
	var p := _panel(rect)
	var rows := [["ui_flag", "YOU"], ["ui_target", "NPC TARGET"], ["ui_intel", "INTEL"],
		["ui_stairs", "STAIRS / PASSAGE"], ["", "HIDDEN PASSAGE"], ["", "BACK ALLEY"]]
	for i in rows.size():
		var y := 8 + i * 36
		if rows[i][0] != "": _icon(p, rows[i][0], Vector2(8, y), 32)
		else:
			var box := ColorRect.new(); box.position = Vector2(8, y); box.size = Vector2(28, 28); box.color = Color(0.25, 0.22, 0.16); p.add_child(box)
		_mklabel(p, rows[i][1], Vector2(48, y + 4), 14, TEXT)

func _timer_banner(rect: Rect2) -> void:
	var p := _panel(rect)
	_round_label = _mklabel(p, "Round 1", Vector2(rect.size.x * 0.5 - 50, 4), 18, GOLD)
	_time_label = _mklabel(p, "--:--", Vector2(rect.size.x * 0.5 - 36, 28), 22, TEXT)

func _roster_panel(rect: Rect2) -> void:
	var p := _panel(rect)
	for i in 4:
		var y := 8 + i * 34
		_mklabel(p, str(i + 1), Vector2(8, y), 16, GOLD)
		var dot := ColorRect.new(); dot.position = Vector2(34, y + 3); dot.size = Vector2(16, 16); dot.color = Color(0.4, 0.4, 0.4); p.add_child(dot)
		var nm := _mklabel(p, "—", Vector2(58, y), 15, TEXT)
		var sc := _mklabel(p, "", Vector2(rect.size.x - 40, y), 15, TEXT)
		_roster_rows.append({"name": nm, "score": sc, "dot": dot})

func _log_panel(rect: Rect2) -> void:
	var p := _panel(rect)
	_log_label = _mklabel(p, "", Vector2(8, 8), 13, TEXT)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.custom_minimum_size = Vector2(rect.size.x - 20, 0)
	_log_label.size = Vector2(rect.size.x - 20, rect.size.y - 20)

func _ability_bar(rect: Rect2) -> void:
	var p := _panel(rect)
	# Real abilities: smoke + cloak (the kit), plus emote. Keyed by id we update via set_ability().
	var slots := [["smoke", "SMOKE", "R"], ["cloak", "CLOAK", "T"], ["emote", "EMOTE", "V"]]
	var icon_for := {"smoke": "ui_hide", "cloak": "ui_disguise", "emote": "ui_coin"}
	for i in slots.size():
		var x := 12 + i * 192
		var slot := Panel.new(); slot.position = Vector2(x, 8); slot.size = Vector2(180, 72)
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.04, 0.04, 0.05); sb.set_border_width_all(2); sb.border_color = GOLD_DIM; sb.set_corner_radius_all(3)
		slot.add_theme_stylebox_override("panel", sb); p.add_child(slot)
		_icon(slot, icon_for.get(slots[i][0], "ui_coin"), Vector2(8, 16), 40)
		_mklabel(slot, slots[i][1], Vector2(56, 12), 14, GOLD)
		var sub := _mklabel(slot, "[%s]" % slots[i][2], Vector2(56, 36), 15, Color(0.95, 0.9, 0.75))
		_ability_slots[slots[i][0]] = {"label": sub, "key": slots[i][2], "slot": slot}

func _minimap_panel(rect: Rect2) -> void:
	var p := _panel(rect)
	minimap_slot = Control.new(); minimap_slot.position = Vector2(8, 8); minimap_slot.size = rect.size - Vector2(20, 20)
	minimap_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(minimap_slot)
	_mklabel(p, "MINIMAP", Vector2(10, 10), 11, GOLD_DIM)

# Reveal portraits row (top-centre, under the timer): your TARGET (red) once your marks are done,
# and any EXPOSED opponent (blue) once they hit 100% exposure.
func _reveals_row(top_centre: Vector2) -> void:
	_reveals = HBoxContainer.new()
	_reveals.add_theme_constant_override("separation", 8)
	_reveals.position = Vector2(top_centre.x - 150, top_centre.y)
	_reveals.size = Vector2(300, 96)
	_reveals.alignment = BoxContainer.ALIGNMENT_CENTER
	_reveals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_reveals)

# A framed portrait of a character (its down-facing frame), with a coloured border + caption.
func _make_plate(appearance_index: int, border: Color, caption: String) -> Control:
	var holder := VBoxContainer.new()
	holder.custom_minimum_size = Vector2(72, 90)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := Panel.new(); frame.custom_minimum_size = Vector2(64, 64)
	var fb := StyleBoxFlat.new(); fb.bg_color = Color(0.03, 0.03, 0.04); fb.set_border_width_all(3); fb.border_color = border
	frame.add_theme_stylebox_override("panel", fb); holder.add_child(frame)
	var tr := TextureRect.new()
	var sheets = CharacterVisual.SHEET_TEXTURES
	var tex: Texture2D = sheets[wrapi(appearance_index, 0, sheets.size())]
	var fpx := int(float(tex.get_width()) / float(CharacterVisual.SHEET_COLUMNS))
	var at := AtlasTexture.new(); at.atlas = tex; at.region = Rect2(0, 0, fpx, fpx)
	tr.texture = at; tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; frame.add_child(tr)
	var lbl := Label.new(); lbl.text = caption; lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", border); lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(lbl)
	return holder


# === public setters (the match feeds these) ================================
func set_player(name_text: String, title_text: String, appearance_index: int) -> void:
	if _name_label: _name_label.text = name_text
	if _title_label: _title_label.text = title_text
	set_portrait(appearance_index)

func set_portrait(appearance_index: int) -> void:
	if _portrait == null:
		return
	var sheets = CharacterVisual.SHEET_TEXTURES
	var tex: Texture2D = sheets[wrapi(appearance_index, 0, sheets.size())]
	var frame_px := int(float(tex.get_width()) / float(CharacterVisual.SHEET_COLUMNS))
	var at := AtlasTexture.new(); at.atlas = tex; at.region = Rect2(0, 0, frame_px, frame_px)
	_portrait.texture = at

func set_exposure(fraction: float) -> void:
	var lit := int(round(clampf(fraction, 0.0, 1.0) * _exposure_segs.size()))
	for i in _exposure_segs.size():
		_exposure_segs[i].color = (Color(0.85, 0.35, 0.25) if fraction > 0.66 else (Color(0.85, 0.7, 0.3) if fraction > 0.33 else Color(0.4, 0.7, 0.35))) if i < lit else Color(0.2, 0.18, 0.15)

func set_objective(main_text: String, optional_text: String = "") -> void:
	if _objective_label: _objective_label.text = main_text
	if _optional_label and optional_text != "": _optional_label.text = optional_text

func set_timer(round_text: String, time_text: String) -> void:
	if _round_label: _round_label.text = round_text
	if _time_label: _time_label.text = time_text

func set_roster(rows: Array) -> void:  # rows: Array of {name, color, score}
	for i in _roster_rows.size():
		var r: Dictionary = _roster_rows[i]
		if i < rows.size():
			r.name.text = str(rows[i].get("name", "—")); r.name.modulate = rows[i].get("color", TEXT)
			r.dot.color = rows[i].get("color", Color(0.4, 0.4, 0.4)); r.score.text = str(rows[i].get("score", 0))
		else:
			r.name.text = "—"; r.score.text = ""; r.dot.color = Color(0.25, 0.25, 0.25)

func set_ability(id: String, text: String, available: bool = true) -> void:
	if not _ability_slots.has(id):
		return
	var s: Dictionary = _ability_slots[id]
	s.label.text = text
	(s.slot as Panel).modulate = Color(1, 1, 1, 1.0 if available else 0.45)

# Your target's look (red plate), shown once you've cleared your marks. Replaces any prior one.
func set_target_reveal(appearance_index: int) -> void:
	if _reveals == null:
		return
	if _target_plate != null and is_instance_valid(_target_plate):
		_target_plate.queue_free()
	_target_plate = _make_plate(appearance_index, Color(0.85, 0.25, 0.25), "TARGET")
	_reveals.add_child(_target_plate)
	_reveals.move_child(_target_plate, 0)  # keep the target on the left

# An opponent who hit 100% exposure (blue plate). Ignored if already shown.
func add_exposed_reveal(appearance_index: int) -> void:
	if _reveals == null or appearance_index in _exposed_shown:
		return
	_exposed_shown.append(appearance_index)
	_reveals.add_child(_make_plate(appearance_index, Color(0.3, 0.6, 0.95), "EXPOSED"))

func clear_reveals() -> void:
	_target_plate = null
	_exposed_shown.clear()
	if _reveals != null:
		for c in _reveals.get_children():
			c.queue_free()


# Experiments (crowd_reaction etc.) call this via the "experiment_toast" group — into the log.
func show_message(text: String) -> void:
	add_log(text)


func add_log(line: String) -> void:
	_log_lines.append(line)
	while _log_lines.size() > MAX_LOG:
		_log_lines.pop_front()
	if _log_label:
		_log_label.text = "\n".join(_log_lines)
