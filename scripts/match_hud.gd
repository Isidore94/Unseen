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
var _objective_panel: Panel = null   # the OBJECTIVE box — pops in on change, fades out when stale (contextual)
var _objective_last: String = ""     # so we only pulse when the objective actually changes
var _objective_tween: Tween = null
var _legend_target_swatch: ColorRect = null  # the "your kill targets" colour chip in the legend
var _countdown_label: Label = null            # big centred start-of-round "3/2/1/GO!" overlay
var _round_label: Label = null
var _time_label: Label = null
var _roster_rows: Array = []          # Array of {name:Label, score:Label, dot:ColorRect}
var _log_lines: Array[String] = []
var _log_label: Label = null
var _score_value_label: Label = null   # YOUR running point total (the big focal number)
var _score_kills_label: Label = null   # YOUR kill count, beside the points
var _portrait: TextureRect = null
var _portrait_unknown: Label = null   # the big "?" shown over the portrait while disguised/morphed
var _portrait_box: StyleBoxFlat = null  # the portrait panel's frame, turned RED while you're hunted
var _hunted_label: Label = null         # "YOU ARE BEING HUNTED" warning (hidden until hunted)
var _ability_slots: Dictionary = {}   # key -> {label:Label, sub:Label, dim:bool}
var minimap_slot: Control = null      # the match drops its MiniMap in here
var _reveals: HBoxContainer = null     # holds the TARGET (red) + EXPOSED (blue) reveal portraits
var _target_plate: Control = null
var _exposed_plates: Dictionary = {}   # reveal_id (revealed peer) -> its EXPOSED plate, so it updates
const MAX_LOG := 6
## Seconds the OBJECTIVE box stays fully visible after a change before it fades away.
const OBJECTIVE_HOLD_SECONDS := 4.5


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
	_objectives_panel(Rect2(16, 126, 330, 84))
	_legend_panel(Rect2(16, 222, 330, 126))
	_timer_banner(Rect2(vp.x * 0.5 - 200, 12, 400, 60))
	_roster_panel(Rect2(vp.x - 316, 16, 300, 156))
	_score_panel(Rect2(16, vp.y - 268, 360, 44))  # YOUR kill-score, just above the log box (left side)
	_log_panel(Rect2(16, vp.y - 220, 360, 204))
	_ability_bar(Rect2(vp.x * 0.5 - 300, vp.y - 106, 600, 92))
	_minimap_panel(Rect2(vp.x - 268, vp.y - 268, 252, 252))
	_reveals_row(Vector2(vp.x * 0.5, 82))
	# Big centred start-of-round countdown ("3/2/1/GO!"), hidden until the match feeds it.
	_countdown_label = Label.new()
	_countdown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 120)
	_countdown_label.add_theme_color_override("font_color", GOLD)
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_label.visible = false
	_root.add_child(_countdown_label)


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

# Returns the inner TextureRect (so callers like the ability bar can swap its icon later), or null
# when the icon file is missing (a placeholder box is drawn instead).
func _icon(parent: Control, icon_name: String, pos: Vector2, sz: int) -> TextureRect:
	var path := ICONS + icon_name + ".png"
	if not ResourceLoader.exists(path):
		var box := ColorRect.new(); box.position = pos; box.size = Vector2(sz, sz); box.color = Color(0.25, 0.2, 0.12); parent.add_child(box); return null
	var wrap := Control.new(); wrap.position = pos; wrap.custom_minimum_size = Vector2(sz, sz); wrap.size = Vector2(sz, sz); wrap.clip_contents = true; parent.add_child(wrap)
	var tr := TextureRect.new(); tr.texture = load(path); tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; wrap.add_child(tr)
	return tr


# === regions ===============================================================
func _portrait_panel(rect: Rect2) -> void:
	var p := _panel(rect)
	_portrait_box = p.get_theme_stylebox("panel") as StyleBoxFlat  # we recolour this red when hunted
	var frame := Panel.new(); frame.position = Vector2(8, 8); frame.size = Vector2(72, 72)
	var fb := StyleBoxFlat.new(); fb.bg_color = Color(0.03, 0.03, 0.04); fb.set_border_width_all(2); fb.border_color = GOLD_DIM
	frame.add_theme_stylebox_override("panel", fb); p.add_child(frame)
	_portrait = TextureRect.new(); _portrait.position = Vector2(4, 4); _portrait.size = Vector2(64, 64)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; _portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; frame.add_child(_portrait)
	# A big "?" overlaid on the portrait while disguise/morph is active (shown via set_portrait_unknown).
	_portrait_unknown = Label.new()
	_portrait_unknown.text = "?"
	_portrait_unknown.add_theme_font_size_override("font_size", 46)
	_portrait_unknown.add_theme_color_override("font_color", GOLD)
	_portrait_unknown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_unknown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_unknown.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_unknown.visible = false
	frame.add_child(_portrait_unknown)
	_name_label = _mklabel(p, "PLAYER", Vector2(90, 8), 20, GOLD)
	_title_label = _mklabel(p, "", Vector2(90, 34), 14, TEXT)
	for i in 7:
		var seg := ColorRect.new(); seg.position = Vector2(90 + i * 28, 60); seg.size = Vector2(24, 12); seg.color = Color(0.2, 0.18, 0.15)
		p.add_child(seg); _exposure_segs.append(seg)
	# "YOU ARE BEING HUNTED" warning, shown (with a red frame) once another player is hunting you.
	_hunted_label = _mklabel(p, "YOU ARE BEING HUNTED", Vector2(8, 78), 12, Color(0.95, 0.27, 0.22))
	_hunted_label.visible = false

func _objectives_panel(rect: Rect2) -> void:
	var p := _panel(rect)
	_objective_panel = p
	p.pivot_offset = rect.size * 0.5  # scale-pop from the centre
	p.modulate.a = 0.0                # hidden until the first objective arrives (contextual)
	_mklabel(p, "OBJECTIVE", Vector2(8, 6), 15, GOLD)
	# Wider panel + word-wrap so the full contract line fits instead of clipping at the edge.
	_objective_label = _mklabel(p, "Locating your marks…", Vector2(10, 34), 14, TEXT)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.custom_minimum_size = Vector2(rect.size.x - 24, 0)
	_objective_label.size = Vector2(rect.size.x - 24, rect.size.y - 40)

func _legend_panel(rect: Rect2) -> void:
	var p := _panel(rect)
	_mklabel(p, "LEGEND", Vector2(8, 6), 13, GOLD)
	# Colour chips matching what you actually see in the world: the teal teleporter pads, the ring
	# around YOUR kill targets (recoloured to your colour via set_legend_target_color), and the
	# green sewer entrances.
	var rows := [
		[Color(0.2, 0.8, 0.85), "TELEPORTER"],
		[Color(1.0, 0.84, 0.25), "YOUR KILL TARGETS"],
		[Color(0.30, 0.62, 0.36), "SEWER (cover)"],
	]
	for i in rows.size():
		var y := 32 + i * 30
		var chip := ColorRect.new(); chip.position = Vector2(10, y); chip.size = Vector2(22, 22); chip.color = rows[i][0]; p.add_child(chip)
		_mklabel(p, rows[i][1], Vector2(42, y + 2), 14, TEXT)
		if i == 1:
			_legend_target_swatch = chip

func _timer_banner(rect: Rect2) -> void:
	var p := _panel(rect)
	_round_label = _mklabel(p, "Round 1", Vector2(rect.size.x * 0.5 - 50, 4), 18, GOLD)
	_time_label = _mklabel(p, "--:--", Vector2(rect.size.x * 0.5 - 36, 28), 22, TEXT)

func _roster_panel(rect: Rect2) -> void:
	var p := _panel(rect)
	for i in 4:
		var y := 8 + i * 34
		# The leading number is now data-driven (set per row from the player's stable number), since the
		# board ranks by score — so we store the label instead of baking in a fixed "1/2/3/4".
		var num_lbl := _mklabel(p, str(i + 1), Vector2(8, y), 16, GOLD)
		var dot := ColorRect.new(); dot.position = Vector2(34, y + 3); dot.size = Vector2(16, 16); dot.color = Color(0.4, 0.4, 0.4); p.add_child(dot)
		var nm := _mklabel(p, "—", Vector2(58, y), 15, TEXT)
		var sc := _mklabel(p, "", Vector2(rect.size.x - 40, y), 15, TEXT)
		_roster_rows.append({"num": num_lbl, "name": nm, "score": sc, "dot": dot})

# YOUR kill-score readout (left side, above the log). Scoring is purely kills + kill-quality
# bonuses now, so this is the number the player is actually playing for — given its own focal panel.
func _score_panel(rect: Rect2) -> void:
	var p := _panel(rect)
	_mklabel(p, "SCORE", Vector2(8, 12), 15, GOLD)
	_score_value_label = _mklabel(p, "0", Vector2(82, 6), 26, TEXT)
	_score_kills_label = _mklabel(p, "KILLS 0", Vector2(rect.size.x - 110, 14), 15, GOLD_DIM)

func _log_panel(rect: Rect2) -> void:
	var p := _panel(rect)
	_log_label = _mklabel(p, "", Vector2(8, 8), 13, TEXT)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.custom_minimum_size = Vector2(rect.size.x - 20, 0)
	_log_label.size = Vector2(rect.size.x - 20, rect.size.y - 20)

func _ability_bar(rect: Rect2) -> void:
	var p := _panel(rect)
	# Two TOOL slots (their tool is set per-match via set_ability_tool) + emote. Keyed by id.
	var slots := [["slot0", "TOOL 1", "R", "ui_hide"], ["slot1", "TOOL 2", "T", "ui_flag"], ["emote", "EMOTE", "V", "ui_coin"]]
	for i in slots.size():
		var x := 12 + i * 192
		var slot := Panel.new(); slot.position = Vector2(x, 8); slot.size = Vector2(180, 72)
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.04, 0.04, 0.05); sb.set_border_width_all(2); sb.border_color = GOLD_DIM; sb.set_corner_radius_all(3)
		slot.add_theme_stylebox_override("panel", sb); p.add_child(slot)
		var icon := _icon(slot, slots[i][3], Vector2(8, 16), 40)
		var name_label := _mklabel(slot, slots[i][1], Vector2(56, 12), 14, GOLD)
		var sub := _mklabel(slot, "[%s]" % slots[i][2], Vector2(56, 36), 15, Color(0.95, 0.9, 0.75))
		_ability_slots[slots[i][0]] = {"label": sub, "name": name_label, "icon": icon, "key": slots[i][2], "slot": slot}

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
	if appearance_index < 0:
		# Unknown look (the revealed player is DISGUISED) — show a "?" instead of a sprite.
		var q := Label.new(); q.text = "?"
		q.add_theme_font_size_override("font_size", 40); q.add_theme_color_override("font_color", border)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.set_anchors_preset(Control.PRESET_FULL_RECT); frame.add_child(q)
	else:
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

# Update just the top-left box's name + subtitle (no portrait change). Used online once the roster
# arrives so the box shows YOUR player number ("PLAYER 2" / "YOU") and matches the scoreboard.
func set_player_name(name_text: String, title_text: String = "") -> void:
	if _name_label != null: _name_label.text = name_text
	if _title_label != null: _title_label.text = title_text

func set_portrait(appearance_index: int) -> void:
	if _portrait == null:
		return
	if _portrait_unknown != null:
		_portrait_unknown.visible = false
	_portrait.visible = true
	var sheets = CharacterVisual.SHEET_TEXTURES
	var tex: Texture2D = sheets[wrapi(appearance_index, 0, sheets.size())]
	var frame_px := int(float(tex.get_width()) / float(CharacterVisual.SHEET_COLUMNS))
	var at := AtlasTexture.new(); at.atlas = tex; at.region = Rect2(0, 0, frame_px, frame_px)
	_portrait.texture = at

# Turn the top-left box RED + show "YOU ARE BEING HUNTED" once another player is hunting you.
func set_hunted(on: bool) -> void:
	if _hunted_label != null:
		_hunted_label.visible = on
	if _portrait_box != null:
		_portrait_box.border_color = Color(0.9, 0.2, 0.18) if on else GOLD
		_portrait_box.set_border_width_all(4 if on else 2)


# Show a "?" instead of the portrait — used while your disguise/morph hides who you are.
func set_portrait_unknown() -> void:
	if _portrait_unknown != null:
		_portrait_unknown.visible = true
	if _portrait != null:
		_portrait.visible = false

func set_exposure(fraction: float) -> void:
	var lit := int(round(clampf(fraction, 0.0, 1.0) * _exposure_segs.size()))
	for i in _exposure_segs.size():
		_exposure_segs[i].color = (Color(0.85, 0.35, 0.25) if fraction > 0.66 else (Color(0.85, 0.7, 0.3) if fraction > 0.33 else Color(0.4, 0.7, 0.35))) if i < lit else Color(0.2, 0.18, 0.15)

func set_objective(main_text: String, _optional_text: String = "") -> void:
	if _objective_label: _objective_label.text = main_text
	# CONTEXTUAL: only surface the OBJECTIVE box when the objective actually CHANGES — it pops in,
	# holds a few seconds, then fades away, instead of sitting on screen permanently.
	if main_text != _objective_last:
		_objective_last = main_text
		_pulse_objective()


# Pop the objective box to full visibility, hold, then fade it out — "objective appears as necessary".
func _pulse_objective() -> void:
	if _objective_panel == null:
		return
	if _objective_tween != null and _objective_tween.is_valid():
		_objective_tween.kill()
	_objective_panel.modulate.a = 1.0
	_objective_panel.scale = Vector2(1.05, 1.05)
	_objective_tween = create_tween()
	_objective_tween.tween_property(_objective_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_objective_tween.tween_interval(OBJECTIVE_HOLD_SECONDS)
	_objective_tween.tween_property(_objective_panel, "modulate:a", 0.0, 0.8)

# Show the big centred countdown text ("3"/"GO!"); pass "" to hide it.
func set_countdown(text: String) -> void:
	if _countdown_label == null:
		return
	_countdown_label.text = text
	_countdown_label.visible = text != ""

# Recolour the legend's "your kill targets" chip to match this player's ring/roster colour.
func set_legend_target_color(c: Color) -> void:
	if _legend_target_swatch != null:
		_legend_target_swatch.color = c

func set_timer(round_text: String, time_text: String) -> void:
	if _round_label: _round_label.text = round_text
	if _time_label: _time_label.text = time_text

func set_roster(rows: Array) -> void:  # rows: Array of {name, num, color, score, dead}, ranked highest-first
	for i in _roster_rows.size():
		var r: Dictionary = _roster_rows[i]
		if i < rows.size():
			# An eliminated player is dimmed and tagged, so the live board shows who's "out" at a glance.
			var dead: bool = bool(rows[i].get("dead", false))
			var dim: float = 0.45 if dead else 1.0
			var col: Color = rows[i].get("color", TEXT)
			r.num.text = str(rows[i].get("num", i + 1)); r.num.modulate = Color(1, 1, 1, dim)
			r.name.text = str(rows[i].get("name", "—")) + ("  ✗" if dead else "")
			r.name.modulate = col * Color(1, 1, 1, dim)
			r.dot.color = col * Color(1, 1, 1, dim)
			r.score.text = str(rows[i].get("score", 0)); r.score.modulate = Color(1, 1, 1, dim)
		else:
			r.num.text = str(i + 1); r.num.modulate = Color(1, 1, 1, 0.35)
			r.name.text = "—"; r.name.modulate = TEXT; r.score.text = ""; r.dot.color = Color(0.25, 0.25, 0.25)

# Update YOUR focal kill-score readout (points + kills), fed each roster tick from the match.
func set_kill_score(points: int, kills: int) -> void:
	if _score_value_label != null:
		_score_value_label.text = str(points)
	if _score_kills_label != null:
		_score_kills_label.text = "KILLS %d" % kills

func set_ability(id: String, text: String, available: bool = true) -> void:
	if not _ability_slots.has(id):
		return
	var s: Dictionary = _ability_slots[id]
	s.label.text = text
	(s.slot as Panel).modulate = Color(1, 1, 1, 1.0 if available else 0.45)

# Set a tool slot's NAME + ICON (the match calls this once it knows your equipped tools). The slot's
# key (R / T) is appended to the name so you can still see which key fires it.
func set_ability_tool(id: String, tool_display_name: String, icon_id: String) -> void:
	if not _ability_slots.has(id):
		return
	var s: Dictionary = _ability_slots[id]
	if s.get("name") != null:
		(s["name"] as Label).text = "%s [%s]" % [tool_display_name, s.get("key", "")]
	if s.get("icon") != null:
		var path := ICONS + icon_id + ".png"
		if ResourceLoader.exists(path):
			(s["icon"] as TextureRect).texture = load(path)

# Your target's look (red plate), shown once you've cleared your marks. Replaces any prior one.
func set_target_reveal(appearance_index: int) -> void:
	if _reveals == null:
		return
	if _target_plate != null and is_instance_valid(_target_plate):
		_target_plate.queue_free()
	_target_plate = _make_plate(appearance_index, Color(0.85, 0.25, 0.25), "TARGET")
	_reveals.add_child(_target_plate)
	_reveals.move_child(_target_plate, 0)  # keep the target on the left

# An opponent who hit 100% exposure (blue plate), keyed by `reveal_id` (the revealed player) so the
# SAME player's plate can be UPDATED — e.g. a disguised reveal shows "?" (index < 0) and then flips
# to their real sprite once the disguise wears off.
func add_exposed_reveal(reveal_id: int, appearance_index: int) -> void:
	if _reveals == null:
		return
	if _exposed_plates.has(reveal_id) and is_instance_valid(_exposed_plates[reveal_id]):
		_exposed_plates[reveal_id].queue_free()  # replace this player's existing plate
	var plate := _make_plate(appearance_index, Color(0.3, 0.6, 0.95), "EXPOSED")
	_reveals.add_child(plate)
	_exposed_plates[reveal_id] = plate

func clear_reveals() -> void:
	_target_plate = null
	_exposed_plates.clear()
	if _reveals != null:
		for c in _reveals.get_children():
			c.queue_free()


# Remove just ONE player's EXPOSED plate (used when that player is eliminated, so it doesn't linger).
func remove_exposed_reveal(reveal_id: int) -> void:
	if _exposed_plates.has(reveal_id):
		if is_instance_valid(_exposed_plates[reveal_id]):
			_exposed_plates[reveal_id].queue_free()
		_exposed_plates.erase(reveal_id)


# Experiments (crowd_reaction etc.) call this via the "experiment_toast" group — into the log.
func show_message(text: String) -> void:
	add_log(text)


func add_log(line: String) -> void:
	_log_lines.append(line)
	while _log_lines.size() > MAX_LOG:
		_log_lines.pop_front()
	if _log_label:
		_log_label.text = "\n".join(_log_lines)
