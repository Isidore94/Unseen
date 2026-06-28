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

const MAP_SCENE := preload("res://maps/test_map_01.tscn")
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
var _hud: CanvasLayer = null
var _faceplates: FaceplateRow = null
var _arrow: ExposureArrow = null
var _mini: MiniMap = null
## The item readout + the component it watches, kept as members so _process can tick the
## live "(ON Ns)" smoke/cloak countdown every frame (offline this machine owns the timers).
var _item: ItemComponent = null
var _item_label: Label = null


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

	# --- the HUD (built once for the single player) ---
	_hud = HUD_SCRIPT.new() as CanvasLayer
	_hud.name = "HUD"
	add_child(_hud)
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

	# Phase 9 experiments + their on-screen feedback also run offline now (they used to be online-only,
	# which is why crowd-reaction did nothing here). Each experiment self-gates on its ExperimentFlags.
	_spawn_experiments()
	_build_experiment_toast()

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


# The experiment status/toast GUI, bottom-centre of the HUD.
func _build_experiment_toast() -> void:
	if _hud == null:
		return
	var toast := ExperimentToast.new()
	toast.name = "ExperimentToast"
	var vp := get_viewport().get_visible_rect().size
	toast.position = Vector2(vp.x * 0.5 - 180.0, vp.y - 150.0)
	_hud.add_child(toast)


# Builds the on-screen HUD: exposure bar, contract label, the arrow that points at the hunter,
# the mini-map, a "suspect locked" cue, the item readout, the sewer overlay, and the faceplate
# row. Returns the contract label so the ContractManager can write its progress there.
func _build_hud(map: TestMap01) -> Label:
	var screen_width: float = get_viewport().get_visible_rect().size.x

	# Top-left key legend (same component the online HUD uses). It auto-sizes to ~210px tall,
	# so the live readouts below start at y = 224.
	var controls := ControlsHint.new()
	controls.name = "ControlsHint"
	controls.position = Vector2(40.0, 12.0)
	_hud.add_child(controls)

	var exposure_bar := ProgressBar.new()
	exposure_bar.name = "ExposureBar"
	exposure_bar.min_value = 0.0
	exposure_bar.max_value = 100.0
	exposure_bar.show_percentage = false
	exposure_bar.position = Vector2(40.0, 224.0)
	exposure_bar.custom_minimum_size = Vector2(320.0, 24.0)
	exposure_bar.size = Vector2(320.0, 24.0)
	_hud.add_child(exposure_bar)
	_hud.call("watch_exposure", _player.exposure_component)

	var contract_label := Label.new()
	contract_label.name = "ContractLabel"
	contract_label.position = Vector2(40.0, 262.0)
	contract_label.add_theme_font_size_override("font_size", 18)
	contract_label.text = "CONTRACT"
	_hud.add_child(contract_label)

	# The arrow points at the bot hunter: exposure-gated until your marks are done, then it
	# flips to the flashing hunt style (wired in _wire_reveals via marks_completed).
	var arrow := ExposureArrow.new()
	arrow.name = "ExposureArrow"
	arrow.track_target(_hunter)
	_hud.add_child(arrow)

	# Sewer overlay (buildplan §7.2d): darken the WORLD (behind the HUD) + 100% arrow uptime.
	var overlay := ColorRect.new()
	overlay.name = "SewerOverlay"
	overlay.color = Color(0.02, 0.03, 0.04, 0.82)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(overlay)
	_hud.move_child(overlay, 0)
	var layer_comp := _player.get_node_or_null("LayerComponent") as LayerComponent
	if layer_comp != null:
		layer_comp.layer_changed.connect(func(new_layer: int) -> void:
			var in_sewer: bool = new_layer == LayerComponent.Layer.SEWER
			arrow.set_sewer_mode(in_sewer)
			overlay.visible = in_sewer)

	# Mini-map, top-right. We re-point it at the contract once that exists (see _build_match),
	# so it can draw the live mark dot and then the hunt ping from the contract's phase.
	_mini = MINI_MAP_SCRIPT.new() as MiniMap
	_mini.name = "MiniMap"
	_hud.add_child(_mini)
	_mini.setup(map, _player, null)
	_mini.position = Vector2(screen_width - _mini.map_size_px.x - 24.0, 24.0)

	# "Suspect locked" cue.
	var lock_label := Label.new()
	lock_label.name = "LockLabel"
	lock_label.position = Vector2(40.0, 298.0)
	lock_label.add_theme_font_size_override("font_size", 18)
	_hud.add_child(lock_label)
	var kill_component := _player.get_node_or_null("KillComponent") as KillComponent
	if kill_component != null:
		kill_component.lock_changed.connect(
			func(is_locked: bool) -> void: lock_label.text = "SUSPECT LOCKED" if is_locked else "")

	# Item charges readout. Kept on members so _process can tick the live "(ON Ns)" countdown.
	_item_label = Label.new()
	_item_label.name = "ItemLabel"
	_item_label.position = Vector2(40.0, 330.0)
	_item_label.add_theme_font_size_override("font_size", 16)
	_hud.add_child(_item_label)
	_item = _player.get_node_or_null("ItemComponent") as ItemComponent
	if _item != null:
		# Edges (charge spent / effect ended) refresh immediately; _process handles the
		# smooth per-second countdown in between.
		_item.item_activated.connect(func(_which: int, _duration: float) -> void: _refresh_item_label())
		_item.item_expired.connect(func(_which: int) -> void: _refresh_item_label())
	_refresh_item_label()

	# Faceplate row (red target / blue exposed), top-centre.
	var faces := FaceplateRow.new()
	faces.name = "FaceplateRow"
	faces.position = Vector2(screen_width * 0.5 - 130.0, 16.0)
	faces.custom_minimum_size = Vector2(260.0, 60.0)
	_hud.add_child(faces)
	_faceplates = faces
	_arrow = arrow

	return contract_label


# Per-frame: keep the item readout's "(ON Ns)" smoke/cloak countdown ticking. Offline this
# machine owns the item timers, so we just read them straight off the component each frame.
func _process(_delta: float) -> void:
	if _item != null and (_item.smoke_active() or _item.cloak_active()):
		_refresh_item_label()


# Draw the item charges line, with a live seconds countdown while an effect is ON. For SMOKE
# that countdown is how long until you can attack / be seen again.
func _refresh_item_label() -> void:
	if _item_label == null or _item == null:
		return
	var smoke_on: String = " (ON %ds)" % int(ceil(_item.smoke_seconds_left())) if _item.smoke_active() else ""
	var cloak_on: String = " (ON %ds)" % int(ceil(_item.cloak_seconds_left())) if _item.cloak_active() else ""
	_item_label.text = "SMOKE x%d%s   CLOAK x%d%s" % [
		_item.charges_left(ItemComponent.Item.SMOKE), smoke_on,
		_item.charges_left(ItemComponent.Item.CLOAK), cloak_on]


# Reveals (buildplan §7.4): finishing your marks reveals the hunter's look (red plate) and flips
# the arrow to the hunt flash; the hunter hitting 100% exposure reveals its look (blue plate).
func _wire_reveals(contract: ContractManager) -> void:
	contract.marks_completed.connect(func() -> void:
		if _arrow != null:
			_arrow.set_flashing(true)
		if _faceplates != null:
			_faceplates.set_target_face(_appearance_of(_hunter)))

	if _hunter != null and _hunter.exposure_component != null:
		var revealed := {"done": false}
		_hunter.exposure_component.exposure_changed.connect(func(value: float) -> void:
			if value >= 100.0 and not revealed["done"]:
				revealed["done"] = true
				if _faceplates != null:
					_faceplates.add_exposed_face(_appearance_of(_hunter)))


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
