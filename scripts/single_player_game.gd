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

# The CITADEL (AC-Rearmed-style dense city) is our main map now — bigger + denser than Compact,
# the one we're building variety into. Swap back to test_map_02 (Compact) to compare.
const MAP_SCENE := preload("res://maps/test_map_03.tscn")
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

## Camera zoom for the view. >1 tightens it (zoom IN); LOWER pulls back to show MORE. Set to 1.1 for
## a closer, more zoomed-in view. Pure feel — tune freely.
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
## Offline smoke stun of the AI hunter: seconds left, and whether it's currently frozen.
var _hunter_stun_left: float = 0.0
var _hunter_stunned: bool = false
## Offline DISGUISE: seconds left + the player's real body index to restore. MORPH: active overrides.
var _disguise_left: float = 0.0
var _disguise_real_index: int = -1
var _offline_morphs: Array = []  # [{visual, restore, left}]


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
	# Offline we own the tool effects directly: apply each tool when the kit fires it.
	if _item != null and _item.has_signal("tool_activated"):
		_item.tool_activated.connect(_on_offline_tool)

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
		for slot in 2:
			var tool := _item.tool_in_slot(slot)
			var charges := _item.charges_left_slot(slot)
			var cooldown := _item.cooldown_left_slot(slot)
			var active := _item.active_left_slot(slot)
			var key := "slot%d" % slot
			_mhud.set_ability_tool(key, ItemComponent.tool_name(tool), ItemComponent.tool_icon(tool))
			var sub := "x%d" % charges
			if active > 0.0:
				sub = "ON %ds" % int(ceil(active))
			elif cooldown > 0.0:
				sub = "%ds" % int(ceil(cooldown))
			_mhud.set_ability(key, sub, (charges > 0 and cooldown <= 0.0 and active <= 0.0) or active > 0.0)
		_mhud.set_ability("emote", "[V]", true)
	# Offline smoke: freeze the AI hunter while it's standing inside any smoke cloud.
	if _hunter != null and is_instance_valid(_hunter):
		for cloud in get_tree().get_nodes_in_group("smoke_cloud"):
			var sc := cloud as SmokeCloud
			if sc != null and sc.contains(_hunter.global_position):
				# Cap by the cloud's remaining life so the stun never outlasts the animation.
				_hunter_stun_left = maxf(_hunter_stun_left, minf(float(sc.get("stun_seconds")), sc.remaining()))
		if _hunter_stun_left > 0.0:
			_hunter_stun_left = maxf(0.0, _hunter_stun_left - delta)
		_set_hunter_stunned(_hunter_stun_left > 0.0)
	# Offline disguise: count down + restore the player's real body when it ends.
	if _disguise_left > 0.0:
		_disguise_left = maxf(0.0, _disguise_left - delta)
		if _disguise_left == 0.0 and _disguise_real_index >= 0 and _player != null:
			var pv := _player.get_node_or_null("CharacterVisual")
			if pv != null and pv.has_method("set_appearance"):
				pv.call("set_appearance", _disguise_real_index)
			_disguise_real_index = -1
	# Offline morph: count down each NPC override + restore it when done.
	for i in range(_offline_morphs.size() - 1, -1, -1):
		var m: Dictionary = _offline_morphs[i]
		m["left"] = float(m["left"]) - delta
		var mv = m["visual"]
		if mv == null or not is_instance_valid(mv):
			_offline_morphs.remove_at(i)
		elif float(m["left"]) <= 0.0:
			mv.call("set_appearance", int(m["restore"]))
			_offline_morphs.remove_at(i)
	# Top-left portrait shows "?" while your identity is hidden (disguise or morph active).
	if _disguise_left > 0.0 or not _offline_morphs.is_empty():
		_mhud.set_portrait_unknown()
	else:
		_mhud.set_portrait(_player.appearance_index if _player != null else 11)


# Offline: the kit fired a tool — apply its world effect ourselves. (Disguise/morph/decoy/poison
# arrive in later slices; for now they log so the player knows the kit triggered.)
func _on_offline_tool(tool: int, slot: int) -> void:
	var ok := true
	if tool == ItemComponent.Tool.SMOKE:
		_deploy_smoke_offline()
	elif tool == ItemComponent.Tool.DECOY:
		ok = _deploy_decoy_offline()
	elif tool == ItemComponent.Tool.DISGUISE:
		ok = _apply_disguise_offline()
	elif tool == ItemComponent.Tool.MORPH:
		_apply_morph_offline()
	elif tool == ItemComponent.Tool.POISON:
		ok = _apply_poison_offline()
	elif _mhud != null:
		_mhud.add_log("%s isn't wired up yet." % ItemComponent.tool_name(tool).capitalize())
	# A target-needing tool fired with nothing in the ring — refund the charge + say why.
	if not ok:
		if _item != null:
			_item.refund(slot)
		if _mhud != null:
			_mhud.add_log("Aim at someone in your ring first.")


# Offline disguise: become a random commoner for the duration (single screen, so we just swap our
# own body). _process reverts it and shows the "?" portrait while it's up.
func _apply_disguise_offline() -> bool:
	if _player == null or _item == null:
		return false
	var target := _player.interaction_target(false)  # must be aimed at an NPC
	if target == null:
		return false
	var visual := _player.get_node_or_null("CharacterVisual")
	if visual == null or not visual.has_method("set_appearance"):
		return false
	if _disguise_real_index < 0:
		_disguise_real_index = int(visual.call("get_appearance"))
	# Disguise AS the targeted civilian (take their look).
	var tv := target.get_node_or_null("CharacterVisual")
	var idx := int(tv.call("get_appearance")) if (tv != null and tv.has_method("get_appearance")) else _random_commoner_index()
	visual.call("set_appearance", idx)
	_disguise_left = _item.disguise_seconds
	if _mhud != null:
		_mhud.add_log("Disguised as a civilian (%ds)." % int(_item.disguise_seconds))
	return true


# Offline morph: reskin the nearest NPCs to the player's current look for the duration.
func _apply_morph_offline() -> void:
	if _player == null or _item == null:
		return
	var src := _player.get_node_or_null("CharacterVisual")
	if src == null or not src.has_method("get_appearance"):
		return
	var look_index := int(src.call("get_appearance"))
	var scored: Array = []
	for node in get_tree().get_nodes_in_group("npc"):
		var npc := node as Node2D
		if npc == null or (npc.has_method("is_dead") and npc.is_dead()):
			continue
		var dist := npc.global_position.distance_to(_player.global_position)
		if dist <= _item.morph_radius:
			scored.append({"npc": npc, "dist": dist})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])
	for i in mini(_item.morph_npc_count, scored.size()):
		var visual = (scored[i]["npc"] as Node).get_node_or_null("CharacterVisual")
		if visual != null and visual.has_method("set_appearance"):
			_offline_morphs.append({"visual": visual, "restore": int(visual.call("get_appearance")), "left": _item.morph_seconds})
			visual.call("set_appearance", look_index)


func _random_commoner_index() -> int:
	var ids: Array = CosmeticRegistry.COMMONER_BODY_IDS
	if ids.is_empty():
		return 1
	return int(CosmeticRegistry.index_for_body_id(ids[randi() % ids.size()]))


# Spook the NPC in the player's interaction ring into bolting in its current direction.
func _deploy_decoy_offline() -> bool:
	if _player == null or _item == null:
		return false
	var target := _player.interaction_target(false)  # NPC only
	if target == null or not target.has_method("flee_run"):
		return false
	target.call("flee_run", target.velocity, _item.decoy_flee_seconds, 2.0)  # below player run speed
	return true


# Drop a smoke cloud at the player's feet; the _process loop freezes the hunter while it's inside.
func _deploy_smoke_offline() -> void:
	if _player == null or _item == null:
		return
	var cloud := SmokeCloud.new()
	cloud.set("stun_seconds", _item.smoke_stun_seconds)
	var parent: Node = _player.get_parent()
	if parent == null:
		parent = self
	parent.add_child(cloud)
	cloud.setup(_player.global_position, _item.smoke_cloud_radius, _item.smoke_cloud_seconds, -1)
	var visual := _player.get_node_or_null("CharacterVisual")
	if visual != null and visual.has_method("play_strike"):
		visual.call("play_strike")


# Offline poison: a delayed, quiet death on the targeted character (no crowd panic — is_poisoned).
func _apply_poison_offline() -> bool:
	if _player == null or _item == null:
		return false
	var target := _player.interaction_target(true)
	if target == null or not target.has_method("die"):
		return false
	if target.get("is_poisoned") != null:
		target.set("is_poisoned", true)
	var delay: float = _item.poison_delay_seconds
	get_tree().create_timer(maxf(0.05, delay)).timeout.connect(func() -> void:
		if is_instance_valid(target) and target.has_method("die"):
			target.call("die"))
	if _mhud != null:
		_mhud.add_log("Target poisoned — they drop in %ds." % int(delay))
	return true


# Freeze/unfreeze the AI hunter (offline smoke stun). Pausing its physics stops its chase + kill.
func _set_hunter_stunned(on: bool) -> void:
	if _hunter_stunned == on or _hunter == null or not is_instance_valid(_hunter):
		return
	_hunter_stunned = on
	_hunter.set_physics_process(not on)


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
					_mhud.add_exposed_reveal(1, _appearance_of(_hunter)))  # reveal_id 1 = the hunter


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
