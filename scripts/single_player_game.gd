extends Control
class_name SinglePlayerGame

# Offline SINGLE-PLAYER harness — UNSEEN.
#
# Online (main menu → lobby → online_match) is the REAL multiplayer surface, played over the
# Steam relay; this offline scene exists only to test the basic feel without a second machine.
# It is deliberately ONE human player vs a bot:
#   - You blend in the crowd, kill your NPC marks, then hunt and kill the bot HUNTER (your
#     contract target) — while that same bot is hunting YOU (master_plan §5: a bot hunter
#     stands in for a human in offline/prototype play).
#   - One full-screen view (the player's own camera) — no split screen, no second player.
#   - Scored by RoundManager: low average exposure + speed + clean kills (master_plan §10).
#
# Everything self-wires through groups: the hunter finds the "player", the contract targets
# the "hunter" group, and RoundManager finds "player" / "contract" / "end_screen". So this
# builder just spawns the pieces and positions the HUD.

# The COMPACT arena is our main map now (smaller, denser, the one we're building variety into).
const MAP_SCENE := preload("res://maps/test_map_02.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const NPC_SCENE := preload("res://scenes/npc.tscn")
const HUNTER_SCENE := preload("res://scenes/hunter.tscn")
const END_SCREEN_SCENE := preload("res://scenes/end_screen.tscn")
const HUD_SCRIPT := preload("res://scripts/hud.gd")
const ROUND_MANAGER_SCRIPT := preload("res://scripts/round_manager.gd")
const MINI_MAP_SCRIPT := preload("res://scripts/mini_map.gd")

## Civilian crowd size for the offline test (lighter than online — one local machine).
@export var npc_count: int = 50

## NPC marks to kill before the bot hunter becomes your valid target (buildplan §7.0, note 9).
@export var marks_to_kill: int = 2

## Camera zoom for the view. >1 tightens it (zoom IN); ~1.1 shows ~¾ of the old span so the
## four-zone map reads better (buildplan §7.0, note 1). Pure feel — tune freely.
@export var camera_zoom: Vector2 = Vector2(1.1, 1.1)

var _player: Player = null
var _hunter: HunterAi = null
var _mhud: MatchHud = null            ## the premium themed HUD
var _contract_label: Label = null     ## hidden label the contract writes to; mirrored into the HUD
var _faceplates: FaceplateRow = null
var _arrow: ExposureArrow = null
var _mini: MiniMap = null
## The item component, kept on a member so _process can tick the live smoke/cloak countdown.
var _item: ItemComponent = null
## Round clock (5 minutes) + rough score, shown in the HUD banner / roster.
var _round_time_left: float = 300.0
var _score: int = 0


func _ready() -> void:
	# Pause survives scene changes; clear it on the way in (e.g. after an end screen → menu).
	get_tree().paused = false

	# Pick this game's 3–5 commoner crowd looks (varies each run) before the crowd spawns.
	CosmeticRegistry.roll_filler_bodies()

	var map := MAP_SCENE.instantiate() as TestMap01
	map.name = "Map"
	add_child(map)

	# Wait one physics frame so the map's navigation is ready before we place actors on it.
	await get_tree().physics_frame
	_build_match(map)


func _build_match(map: TestMap01) -> void:
	# --- the player (full-screen view via its own embedded camera) ---
	# Showcase: offline you play as a premium ASSASSIN skin (index 11 = Norse hammer) so you can
	# see an end-game look walking among the Roman commoner crowd.
	_player = PLAYER_SCENE.instantiate() as Player
	_player.name = "Player"
	_player.appearance_index = 11
	add_child(_player)
	_player.global_position = _first_spawn(map)

	var camera := _player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.enabled = true
		camera.zoom = camera_zoom
		camera.make_current()

	# --- the crowd you hide in ---
	var crowd := CrowdManager.new()
	crowd.name = "Crowd"
	crowd.npc_scene = NPC_SCENE
	crowd.npc_count = npc_count
	add_child(crowd)

	# --- the bot hunter: your contract target AND the thing hunting you ---
	_hunter = HUNTER_SCENE.instantiate() as HunterAi
	_hunter.name = "Hunter"
	add_child(_hunter)
	_hunter.global_position = _hunter_spawn(map)

	# --- the premium themed HUD ---
	_mhud = MatchHud.new()
	_mhud.name = "MatchHud"
	add_child(_mhud)
	var contract_label := _build_hud(map)

	# --- the contract: kill your marks, then the hunter (final target = the "hunter" group) ---
	var contract := ContractManager.new()
	contract.name = "Contract"
	contract.mark_scene = NPC_SCENE
	contract.status_label_path = contract_label.get_path()
	contract.marks_to_spawn = marks_to_kill
	contract.status_prefix = "CONTRACT"
	add_child(contract)
	# Now that the contract exists, let the mini-map read its phase (mark dot → hunt ping).
	if _mini != null:
		_mini.setup(map, _player, contract)

	# --- end screen + scorer (both self-find the player/contract by group) ---
	var end_screen := END_SCREEN_SCENE.instantiate() as EndScreen
	add_child(end_screen)
	var round_manager := ROUND_MANAGER_SCRIPT.new()
	round_manager.name = "RoundManager"
	add_child(round_manager)

	# Phase 9 experiments run offline too; their events route into the HUD log (MatchHud is in the
	# "experiment_toast" group), so there's no more middle-of-screen text.
	_spawn_experiments()

	_wire_reveals(contract)


# Load every experiment script in scripts/experiments/ as a child (mirrors online_match). Each is
# inert unless its ExperimentFlags switch is on, so this is safe to always run.
func _spawn_experiments() -> void:
	var dir := DirAccess.open("res://scripts/experiments")
	if dir == null:
		return
	var holder := Node.new()
	holder.name = "Experiments"
	add_child(holder)
	for file_name in dir.get_files():
		if not file_name.ends_with(".gd"):
			continue
		var script: Script = load("res://scripts/experiments/" + file_name)
		if script == null:
			continue
		var node := Node.new()
		node.name = file_name.get_basename()
		node.set_script(script)
		holder.add_child(node)


# Wires the premium MatchHud to the offline match's live data, and keeps the gameplay overlays
# (hunter arrow + sewer darken + faceplate reveals). Returns a hidden label the ContractManager
# writes to (mirrored into the objectives panel each frame).
func _build_hud(map: TestMap01) -> Label:
	var vp := get_viewport().get_visible_rect().size
	_mhud.set_player("PLAYER 1", "The Shadow", _player.appearance_index)
	_mhud.set_roster([{"name": "PLAYER 1", "color": Color(0.32, 0.7, 1.0), "score": 0}])
	_mhud.set_timer("Round 1", "")
	_mhud.add_log("Welcome to Desert Souk")

	# Exposure → segmented bar.
	var exposure := _player.exposure_component
	if exposure != null:
		exposure.exposure_changed.connect(func(v: float) -> void: _mhud.set_exposure(v / 100.0))
		_mhud.set_exposure(exposure.exposure / 100.0)

	# Hidden label the ContractManager writes to; mirrored into the objectives panel in _process.
	_contract_label = Label.new()
	_contract_label.name = "ContractLabel"
	_contract_label.visible = false
	_mhud.add_child(_contract_label)

	# Hunter arrow on a dedicated top layer so HUD panels never cover the bearing; sewer darken
	# overlay stays behind the panels (added to _mhud below).
	var arrow_layer := CanvasLayer.new()
	arrow_layer.name = "ArrowLayer"
	arrow_layer.layer = 5
	add_child(arrow_layer)
	_arrow = ExposureArrow.new()
	_arrow.name = "ExposureArrow"
	_arrow.track_target(_hunter)
	arrow_layer.add_child(_arrow)
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.04, 0.82)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mhud.add_child(overlay)
	_mhud.move_child(overlay, 0)
	var layer_comp := _player.get_node_or_null("LayerComponent") as LayerComponent
	if layer_comp != null:
		layer_comp.layer_changed.connect(func(new_layer: int) -> void:
			var in_sewer: bool = new_layer == LayerComponent.Layer.SEWER
			_arrow.set_sewer_mode(in_sewer)
			overlay.visible = in_sewer)

	# Mini-map into the HUD's minimap slot, scaled to fit.
	_mini = MINI_MAP_SCRIPT.new() as MiniMap
	_mini.name = "MiniMap"
	var slot := _mhud.minimap_slot
	if slot != null:
		slot.add_child(_mini)
	else:
		_mhud.add_child(_mini)
	_mini.position = Vector2.ZERO
	_mini.setup(map, _player, null)
	if slot != null and _mini.map_size_px.x > 0.0:
		var fit := minf(slot.size.x / _mini.map_size_px.x, slot.size.y / _mini.map_size_px.y)
		_mini.scale = Vector2(fit, fit)

	# Suspect-lock cue → log line.
	var kill_component := _player.get_node_or_null("KillComponent") as KillComponent
	if kill_component != null:
		kill_component.lock_changed.connect(func(is_locked: bool) -> void:
			if is_locked: _mhud.add_log("Suspect locked."))

	_item = _player.get_node_or_null("ItemComponent") as ItemComponent

	# Rough scoring: +1 per valid kill, shown in the roster.
	if kill_component != null and kill_component.has_signal("kill_resolved"):
		kill_component.kill_resolved.connect(func(_killer: Node, _victim: Node, was_valid: bool) -> void:
			if was_valid:
				_score += 1)

	return _contract_label


# Per-frame: mirror the contract text into the objectives panel and refresh the ability readouts
# (smoke/cloak charges + live countdown). This machine owns the item timers offline.
func _process(delta: float) -> void:
	if _mhud == null:
		return
	# Round clock (counts down from 5:00) + rough roster score.
	_round_time_left = maxf(0.0, _round_time_left - delta)
	_mhud.set_timer("Round 1", _format_time(_round_time_left))
	_mhud.set_roster([{"name": "PLAYER 1", "color": Color(0.32, 0.7, 1.0), "score": _score}])
	if _contract_label != null:
		_mhud.set_objective(_contract_label.text)
	if _item != null:
		var smoke_secs: String = " · %ds" % int(ceil(_item.smoke_seconds_left())) if _item.smoke_active() else ""
		var cloak_secs: String = " · %ds" % int(ceil(_item.cloak_seconds_left())) if _item.cloak_active() else ""
		var smoke_n := _item.charges_left(ItemComponent.Item.SMOKE)
		var cloak_n := _item.charges_left(ItemComponent.Item.CLOAK)
		_mhud.set_ability("smoke", "x%d  [R]%s" % [smoke_n, smoke_secs], smoke_n > 0 or _item.smoke_active())
		_mhud.set_ability("cloak", "x%d  [T]%s" % [cloak_n, cloak_secs], cloak_n > 0 or _item.cloak_active())
		_mhud.set_ability("emote", "[V]", true)


# Reveals (buildplan §7.4): finishing your marks reveals the hunter's look (red plate) and flips
# the arrow to the hunt flash; the hunter hitting 100% exposure reveals its look (blue plate).
func _wire_reveals(contract: ContractManager) -> void:
	contract.marks_completed.connect(func() -> void:
		if _arrow != null:
			_arrow.set_flashing(true)
		if _mhud != null:
			_mhud.set_target_reveal(_appearance_of(_hunter))
			_mhud.add_log("Marks down — your target is revealed.")
		)

	if _hunter != null and _hunter.exposure_component != null:
		var revealed := {"done": false}
		_hunter.exposure_component.exposure_changed.connect(func(value: float) -> void:
			if value >= 100.0 and not revealed["done"]:
				revealed["done"] = true
				if _mhud != null:
					_mhud.add_exposed_reveal(_appearance_of(_hunter)))


func _format_time(seconds: float) -> String:
	var s := int(ceil(seconds))
	return "%d:%02d" % [s / 60, s % 60]


func _appearance_of(actor: Node) -> int:
	var visual := actor.get_node_or_null("CharacterVisual")
	if visual != null and visual.has_method("get_appearance"):
		return int(visual.call("get_appearance"))
	return 0


# The player starts at the map's first spawn point (fallback: a corner) so they begin in a
# sensible spot; the hunter starts well away so it has to find you.
func _first_spawn(map: TestMap01) -> Vector2:
	var spawns := map.get_player_spawns()
	if spawns.size() > 0:
		return spawns[0]
	return Vector2(-900.0, -700.0)


func _hunter_spawn(map: TestMap01) -> Vector2:
	var spawns := map.get_player_spawns()
	if spawns.size() > 1:
		return spawns[spawns.size() - 1]  # opposite corner from the player
	return Vector2(900.0, 700.0)
