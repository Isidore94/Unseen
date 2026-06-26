extends Node
class_name ContractManager

# Contract - UNSEEN, Phase 3/4.
#
# Single-player behavior is still supported: spawn every map mark, then make the
# hunter killable. Local co-op sets a per-player valid target group, gives each
# player a subset of marks, and points the final target at the other Player.

## The scene to spawn marks from. Marks use npc.tscn so they remain identical to
## civilians.
@export var mark_scene: PackedScene

## A HUD Label to show this contract's progress.
@export var status_label_path: NodePath

## Group this contract's owner can kill. Single-player keeps "killable"; local
## co-op uses "killable_for_1" / "killable_for_2".
@export var valid_target_group_name: String = "killable"

## Optional final target for this contract. If empty, the old hunter-bot target is
## used for single-player compatibility.
@export var final_target_path: NodePath

## 0 means use every map mark location. Local co-op usually gives each player one
## exposed mark so the PvP hunt starts quickly.
@export var marks_to_spawn: int = 0

## Offset into the map's mark list. P1 can take mark 0 while P2 takes mark 1.
@export var mark_location_offset: int = 0

## Text prefix shown on this contract's HUD label.
@export var status_prefix: String = "CONTRACT"

## Emitted when the whole contract (all marks + target) is done.
signal contract_completed

var _status_label: Label = null
var _marks: Array[Npc] = []
var _remaining_marks: int = 0
var _phase: String = "marks"  # "marks" -> "target" -> "done"


func _ready() -> void:
	add_to_group("contract")
	call_deferred("_setup")


func _setup() -> void:
	_status_label = get_node_or_null(status_label_path) as Label

	# Wait for the crowd to finish spawning (it spawns after a physics frame) so we
	# can secretly pick our mark from real, existing civilians.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var candidates: Array = []
	for node in get_tree().get_nodes_in_group("npc"):
		var npc := node as Npc
		if npc == null or npc.is_dead():
			continue
		if npc.is_in_group("mark"):
			continue  # already someone else's mark — choose a different civilian
		candidates.append(npc)
	candidates.shuffle()

	var wanted: int = marks_to_spawn if marks_to_spawn > 0 else 1
	wanted = mini(wanted, candidates.size())
	for i in wanted:
		_designate_mark(candidates[i])

	if _remaining_marks <= 0:
		_begin_target_phase()
	else:
		_update_status()


# A RANDOM civilian secretly becomes your mark. It keeps wandering and looks
# identical to everyone else — but for now we ring it with a highlight so you can
# learn the loop (find -> ID -> aim & commit) before pure crowd-reading.
#
# PLAYTEST LIMITATION: the ring is drawn in the shared game world, so in split
# screen the OTHER player can also see your mark lit up. That's fine while we tune
# feel; the private-view fix (per-viewport canvas cull mask) is the same tech the
# future cosmetics system needs, so we'll add it there.
func _designate_mark(npc: Npc) -> void:
	npc.add_to_group(valid_target_group_name)
	npc.add_to_group("mark")
	npc.died.connect(_on_mark_killed)
	_marks.append(npc)
	_remaining_marks += 1
	_highlight_mark(npc)


func _highlight_mark(npc: Npc) -> void:
	var visual := npc.get_node_or_null("CharacterVisual")
	if visual != null and visual.has_method("set_highlight"):
		visual.call("set_highlight", true)


# === objective query (for the mini-map) ====================================
func get_phase() -> String:
	return _phase

# The thing the player is currently hunting: a live mark (PvE) or the final
# target / opponent (PvP). The mini-map reads this to place its objective dot.
func get_objective() -> Node2D:
	if _phase == "marks":
		for mark in _marks:
			if is_instance_valid(mark) and not mark.is_dead():
				return mark
		return null
	return _final_target() as Node2D


func _on_mark_killed() -> void:
	_remaining_marks -= 1
	if _remaining_marks <= 0 and _phase == "marks":
		_begin_target_phase()
	_update_status()


func _begin_target_phase() -> void:
	_phase = "target"
	var target := _final_target()
	if target != null:
		target.add_to_group(valid_target_group_name)
		var death_callback := Callable(self, "_on_target_killed")
		if target.has_signal("died") and not target.is_connected("died", death_callback):
			target.connect("died", death_callback)
	_update_status()


func _final_target() -> Node:
	if final_target_path != NodePath(""):
		return get_node_or_null(final_target_path)
	return get_tree().get_first_node_in_group("hunter")


func _on_target_killed() -> void:
	if _phase == "done":
		return
	_phase = "done"
	_update_status()
	contract_completed.emit()


func _update_status() -> void:
	if _status_label == null:
		return
	match _phase:
		"marks":
			_status_label.text = "%s - eliminate your marks: %d remaining" % [status_prefix, _remaining_marks]
		"target":
			_status_label.text = "%s - marks done. Hunt and kill your target." % status_prefix
		"done":
			_status_label.text = "%s COMPLETE." % status_prefix
