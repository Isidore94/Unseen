extends Node
class_name MatchLedger

# MatchLedger — UNSEEN (plan.md §9 / §13.6). A compact HOST-side event stream for every match,
# written to one JSON file at the end. This is the balance-process backbone: after a playtest
# block you compare ledgers instead of arguing from memory ("were kills actually 2-5 per player?
# did anyone die within 8s of respawning?"). The same records can later power replays and
# cheat review. Host-only — clients never build one, and no ledger data is ever sent to peers.
#
# Events use anonymous per-match player numbers where possible; peer ids appear only because
# friend-lobby ledgers are for local tuning, not public telemetry.

## Where finished ledgers land (user:// = this machine's Godot data dir for the project).
const LEDGER_DIR := "user://ledgers"

var _events: Array = []
var _started_msec: int = 0
var _active: bool = false


# Begin a match record. `context` should carry map/mode/rules info (anything JSON-friendly).
func start(context: Dictionary) -> void:
	_events.clear()
	_started_msec = Time.get_ticks_msec()
	_active = true
	log_event("match_started", context)


# Append one event with a match-relative timestamp (seconds since start, 0.1s precision —
# plenty for pacing analysis, and it keeps the files small and diffable).
func log_event(type: String, data: Dictionary = {}) -> void:
	if not _active:
		return
	_events.append({
		"t": snappedf(float(Time.get_ticks_msec() - _started_msec) / 1000.0, 0.1),
		"e": type,
		"d": data,
	})


# Close the record and write it to user://ledgers/match_<unixtime>.json. Returns the path
# ("" on failure). Safe to call once; later log_event calls are ignored.
func finish(reason: String) -> String:
	if not _active:
		return ""
	log_event("match_ended", {"reason": reason})
	_active = false
	DirAccess.make_dir_recursive_absolute(LEDGER_DIR)
	var path := "%s/match_%d.json" % [LEDGER_DIR, int(Time.get_unix_time_from_system())]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("MatchLedger: could not write %s" % path)
		return ""
	file.store_string(JSON.stringify({"events": _events}, "\t"))
	file.close()
	print("[MatchLedger] wrote %d events -> %s" % [_events.size(), path])
	return path
