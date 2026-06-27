extends Control
class_name LocalCoopGame

# Phase 4 local two-player bootstrap.
#
# The world is instanced once inside P1's SubViewport. P2's SubViewport shares the
# same World2D, but owns its own Camera2D and HUD. That gives each player a
# separate view without changing actor visuals or gameplay state.

const MAP_SCENE := preload("res://maps/test_map_01.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const NPC_SCENE := preload("res://scenes/npc.tscn")
const END_SCREEN_SCENE := preload("res://scenes/end_screen.tscn")
const CAMERA_FOLLOW_SCRIPT := preload("res://scripts/camera_follow.gd")
const HUD_SCRIPT := preload("res://scripts/hud.gd")
const LOCAL_MATCH_MANAGER_SCRIPT := preload("res://scripts/local_match_manager.gd")
const MINI_MAP_SCRIPT := preload("res://scripts/mini_map.gd")

## Civilian crowd size for the local fun test.
@export var npc_count: int = 30

## Marks each player must kill before the other player becomes a valid target.
## Two marks (buildplan §7.0, note 9), forced apart + local by the ContractManager.
@export var marks_per_player: int = 2

## Camera zoom for each private view. Higher than 1.0 tightens the view (zoom IN);
## ~1.1 shows roughly three-quarters of the old span — the tighter new four-zone map
## reads better closer in (buildplan.md §7.0, note 1). Pure feel — tune freely.
@export var camera_zoom: Vector2 = Vector2(1.1, 1.1)

var _p1_viewport: SubViewport = null
var _p2_viewport: SubViewport = null
var _world: Node2D = null
var _end_screen: EndScreen = null


func _ready() -> void:
	get_tree().paused = false
	_build_split_view_shell()

	_world = Node2D.new()
	_world.name = "World"
	_p1_viewport.add_child(_world)
	_p2_viewport.world_2d = _p1_viewport.world_2d

	var map := MAP_SCENE.instantiate() as TestMap01
	_world.add_child(map)

	await get_tree().physics_frame
	_build_local_match(map)


func _build_split_view_shell() -> void:
	var views := HBoxContainer.new()
	views.name = "PrivateViews"
	views.set_anchors_preset(Control.PRESET_FULL_RECT)
	views.offset_left = 0.0
	views.offset_top = 0.0
	views.offset_right = 0.0
	views.offset_bottom = 0.0
	add_child(views)

	_p1_viewport = _add_private_view(views, "P1View", "P1Viewport")

	var divider := ColorRect.new()
	divider.name = "PrivacyDivider"
	divider.color = Color(0.01, 0.01, 0.012)
	divider.custom_minimum_size = Vector2(12.0, 0.0)
	views.add_child(divider)

	_p2_viewport = _add_private_view(views, "P2View", "P2Viewport")


func _add_private_view(parent: Control, container_name: String, viewport_name: String) -> SubViewport:
	var container := SubViewportContainer.new()
	container.name = container_name
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(container)

	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.size = Vector2i(954, 1080)
	container.add_child(viewport)
	return viewport


func _build_local_match(map: TestMap01) -> void:
	var spawns := map.get_player_spawns()
	var player_one := _spawn_player(1, _spawn_or_fallback(spawns, 0, Vector2(-900.0, -700.0)), "p1")
	var player_two := _spawn_player(2, _spawn_or_fallback(spawns, 3, Vector2(900.0, 700.0)), "p2")

	_add_follow_camera(_p1_viewport, "P1Camera", player_one)
	_add_follow_camera(_p2_viewport, "P2Camera", player_two)

	var p1_hud_data := _add_player_hud(_p1_viewport, "P1HUD", player_one, player_two, Color(1.0, 0.35, 0.25))
	var p2_hud_data := _add_player_hud(_p2_viewport, "P2HUD", player_two, player_one, Color(0.25, 0.65, 1.0))

	_spawn_crowd()

	var contract_one := _spawn_contract(1, player_two, p1_hud_data["label"] as Label, 0)
	var contract_two := _spawn_contract(2, player_one, p2_hud_data["label"] as Label, 1)

	_add_mini_map(p1_hud_data["hud"] as CanvasLayer, player_one, contract_one, map)
	_add_mini_map(p2_hud_data["hud"] as CanvasLayer, player_two, contract_two, map)
	_add_lock_label(p1_hud_data["hud"] as CanvasLayer, player_one)
	_add_lock_label(p2_hud_data["hud"] as CanvasLayer, player_two)

	# Layer feedback (buildplan §7.2): in the sewer, darken that player's view and give
	# their arrow 100% uptime; the tint on the bodies already shows rooftop vs sewer.
	_wire_layer_feedback(player_one, p1_hud_data["hud"] as CanvasLayer, p1_hud_data["arrow"] as ExposureArrow)
	_wire_layer_feedback(player_two, p2_hud_data["hud"] as CanvasLayer, p2_hud_data["arrow"] as ExposureArrow)

	# Items (buildplan §7.6). Cloak hides the HUNT arrow the opponent has on you, so each
	# player's cloak suppresses the OTHER player's arrow (which is the one tracking them).
	_wire_cloak(player_one, p2_hud_data["arrow"] as ExposureArrow)
	_wire_cloak(player_two, p1_hud_data["arrow"] as ExposureArrow)
	_add_item_hud(p1_hud_data["hud"] as CanvasLayer, player_one)
	_add_item_hud(p2_hud_data["hud"] as CanvasLayer, player_two)

	_end_screen = END_SCREEN_SCENE.instantiate() as EndScreen
	add_child(_end_screen)

	_spawn_match_manager(player_one, player_two, contract_one, contract_two)


func _spawn_player(player_id: int, spawn_position: Vector2, action_prefix: String) -> Player:
	var player := PLAYER_SCENE.instantiate() as Player
	player.name = "Player%d" % player_id
	player.player_id = player_id
	player.move_left_action = "%s_move_left" % action_prefix
	player.move_right_action = "%s_move_right" % action_prefix
	player.move_up_action = "%s_move_up" % action_prefix
	player.move_down_action = "%s_move_down" % action_prefix
	player.run_action = "%s_run" % action_prefix
	player.interact_action = "%s_interact" % action_prefix
	player.drop_down_action = "%s_drop_down" % action_prefix
	player.secondary_action = "%s_action_secondary" % action_prefix

	var embedded_camera := player.get_node_or_null("Camera2D") as Camera2D
	if embedded_camera != null:
		embedded_camera.enabled = false

	var kill_component := player.get_node_or_null("KillComponent") as KillComponent
	if kill_component != null:
		kill_component.action_primary_action = "%s_action_primary" % action_prefix
		kill_component.valid_target_group_name = "killable_for_%d" % player_id

	var item_component := player.get_node_or_null("ItemComponent") as ItemComponent
	if item_component != null:
		item_component.item_primary_action = "%s_item_primary" % action_prefix
		item_component.item_secondary_action = "%s_item_secondary" % action_prefix

	_world.add_child(player)
	player.global_position = spawn_position
	return player


func _add_follow_camera(viewport: SubViewport, camera_name: String, target: Player) -> void:
	var camera := CAMERA_FOLLOW_SCRIPT.new() as Camera2D
	camera.name = camera_name
	camera.set("target_path", target.get_path())
	camera.zoom = camera_zoom
	viewport.add_child(camera)


func _add_player_hud(viewport: SubViewport, hud_name: String, owner: Player, target: Player, arrow_color: Color) -> Dictionary:
	var hud := HUD_SCRIPT.new() as CanvasLayer
	hud.name = hud_name

	var exposure_bar := ProgressBar.new()
	exposure_bar.name = "ExposureBar"
	exposure_bar.min_value = 0.0
	exposure_bar.max_value = 100.0
	exposure_bar.show_percentage = false
	exposure_bar.offset_left = 40.0
	exposure_bar.offset_top = 40.0
	exposure_bar.offset_right = 360.0
	exposure_bar.offset_bottom = 74.0
	hud.add_child(exposure_bar)

	var contract_label := Label.new()
	contract_label.name = "ContractLabel"
	contract_label.offset_left = 40.0
	contract_label.offset_top = 84.0
	contract_label.offset_right = 900.0
	contract_label.offset_bottom = 116.0
	contract_label.text = "P%d CONTRACT" % owner.player_id
	contract_label.add_theme_font_size_override("font_size", 18)
	hud.add_child(contract_label)

	var arrow := ExposureArrow.new()
	arrow.name = "ExposureArrow"
	arrow.arrow_color = arrow_color
	arrow.track_target(target)
	hud.add_child(arrow)

	viewport.add_child(hud)
	hud.call("watch_exposure", owner.exposure_component)

	return {
		"hud": hud,
		"label": contract_label,
		"arrow": arrow,
	}


func _spawn_crowd() -> void:
	var crowd := CrowdManager.new()
	crowd.name = "Crowd"
	crowd.npc_scene = NPC_SCENE
	crowd.npc_count = npc_count
	_world.add_child(crowd)


func _spawn_contract(player_id: int, final_target: Player, status_label: Label, mark_offset: int) -> ContractManager:
	var contract := ContractManager.new()
	contract.name = "ContractP%d" % player_id
	contract.mark_scene = NPC_SCENE
	contract.status_label_path = status_label.get_path()
	contract.valid_target_group_name = "killable_for_%d" % player_id
	contract.final_target_path = final_target.get_path()
	contract.marks_to_spawn = marks_per_player
	contract.mark_location_offset = mark_offset
	contract.status_prefix = "P%d CONTRACT" % player_id
	_world.add_child(contract)
	return contract


func _spawn_match_manager(player_one: Player, player_two: Player, contract_one: ContractManager, contract_two: ContractManager) -> void:
	var match_manager := LOCAL_MATCH_MANAGER_SCRIPT.new() as Node
	match_manager.name = "LocalMatch"
	match_manager.set("player_one_path", player_one.get_path())
	match_manager.set("player_two_path", player_two.get_path())
	match_manager.set("contract_one_path", contract_one.get_path())
	match_manager.set("contract_two_path", contract_two.get_path())
	match_manager.set("end_screen_path", _end_screen.get_path())
	_world.add_child(match_manager)


func _add_mini_map(hud: CanvasLayer, player: Player, contract: ContractManager, map: TestMap01) -> void:
	var mini := MINI_MAP_SCRIPT.new() as MiniMap
	mini.name = "MiniMap"
	hud.add_child(mini)
	mini.setup(map, player, contract)
	# Top-right corner of this player's private view (954 px wide per side).
	mini.position = Vector2(954.0 - mini.map_size_px.x - 20.0, 20.0)


func _add_lock_label(hud: CanvasLayer, player: Player) -> void:
	var label := Label.new()
	label.name = "LockLabel"
	label.position = Vector2(40.0, 130.0)
	label.add_theme_font_size_override("font_size", 18)
	hud.add_child(label)
	var kill_component := player.get_node_or_null("KillComponent") as KillComponent
	if kill_component != null:
		kill_component.lock_changed.connect(
			func(is_locked: bool) -> void: label.text = "SUSPECT LOCKED" if is_locked else ""
		)


# When this player drops into a sewer, darken ONLY their view (a back-of-HUD overlay, so
# their own bars/arrow stay readable) and switch their arrow to 100% uptime. Rooftop/ground
# need no overlay — the body tint already reads the layer.
func _wire_layer_feedback(player: Player, hud: CanvasLayer, arrow: ExposureArrow) -> void:
	var overlay := ColorRect.new()
	overlay.name = "SewerOverlay"
	overlay.color = Color(0.02, 0.03, 0.04, 0.82)
	overlay.size = Vector2(954.0, 1080.0)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(overlay)
	# Push it behind the other HUD nodes so it only dims the WORLD, not your own HUD.
	hud.move_child(overlay, 0)

	var layer_comp := player.get_node_or_null("LayerComponent") as LayerComponent
	if layer_comp != null:
		layer_comp.layer_changed.connect(func(new_layer: int) -> void:
			var in_sewer: bool = new_layer == LayerComponent.Layer.SEWER
			arrow.set_sewer_mode(in_sewer)
			overlay.visible = in_sewer
		)


# When this player raises their CLOAK, hide the opponent's hunt arrow on them; restore
# it when the cloak expires (buildplan §7.6).
func _wire_cloak(player: Player, opponent_arrow: ExposureArrow) -> void:
	var item := player.get_node_or_null("ItemComponent") as ItemComponent
	if item == null:
		return
	item.item_activated.connect(func(which: int, _duration: float) -> void:
		if which == ItemComponent.Item.CLOAK:
			opponent_arrow.set_suppressed(true)
	)
	item.item_expired.connect(func(which: int) -> void:
		if which == ItemComponent.Item.CLOAK:
			opponent_arrow.set_suppressed(false)
	)


# A tiny readout of each player's item charges + which is active, so the kit is legible.
func _add_item_hud(hud: CanvasLayer, player: Player) -> void:
	var label := Label.new()
	label.name = "ItemLabel"
	label.position = Vector2(40.0, 160.0)
	label.add_theme_font_size_override("font_size", 16)
	hud.add_child(label)
	var item := player.get_node_or_null("ItemComponent") as ItemComponent
	if item == null:
		return
	var refresh := func() -> void:
		var smoke := "SMOKE x%d%s" % [item.charges_left(ItemComponent.Item.SMOKE), " (ON)" if item.smoke_active() else ""]
		var cloak := "CLOAK x%d%s" % [item.charges_left(ItemComponent.Item.CLOAK), " (ON)" if item.cloak_active() else ""]
		label.text = "%s   %s" % [smoke, cloak]
	refresh.call()
	item.item_activated.connect(func(_which: int, _duration: float) -> void: refresh.call())
	item.item_expired.connect(func(_which: int) -> void: refresh.call())


func _spawn_or_fallback(spawns: Array[Vector2], index: int, fallback: Vector2) -> Vector2:
	if index >= 0 and index < spawns.size():
		return spawns[index]
	return fallback
