extends Resource
class_name GameRules

# GameRules — UNSEEN (plan.md §7.2 / §13.1). The RULES PROFILE for one map-mode pairing.
#
# WHY THIS EXISTS: the map deliberately selects the mode (Compact = marks-first duel, Citadel =
# immediate Hunt Cycle) — that coupling is a balance tool. But it used to be hard-coded as
# `selected_map == COMPACT` checks scattered through online_match.gd, which made it impossible to
# tune or version one pairing without touching code. Now each map references ONE of these
# resources (data/rules/*.tres) and the match reads every mode rule from it. Balance changes are
# edits to a .tres, comparable across revisions of the SAME pairing (plan.md §2).
#
# Every peer loads the same resource locally from the shared lobby map choice — deterministic,
# no extra network messages (same pattern as _crowd_size_for_map).

## Shown in logs/ledger so playtest records name the ruleset they ran under.
@export var display_name: String = "Hunt Cycle"

# --- contract / pacing -------------------------------------------------------
## When true, each player must clear NPC marks before their hunt opens (Compact's duel).
## Marks persist across respawns — clear them once per match.
@export var requires_marks: bool = false
## How many NPC marks each player is assigned when requires_marks is on.
@export var marks_per_player: int = 2
## Round length in seconds (plan.md: 4 minutes default, tunable 3–5).
@export var round_time_seconds: float = 240.0

# --- exposure economy (plan.md §4 — the hunt/evade control system) -----------
## Exposure at which the hunter gets the infrequent 4-way pulse ("Noticed" band).
@export var noticed_exposure: float = 25.0
## Exposure at which serious tracking switches on ("Exposed"): the hunter's arrow turns SOLID
## and precise, and the hot-cover roof glow arms. The serious state begins HERE — there is no
## separate second cliff at 100 (locked decision, potential gameplay updates.md §2).
@export var exposed_exposure: float = 50.0
## Exposure at which a player's FACE is revealed to everyone (the blue EXPOSED plate). Kept
## ABOVE exposed_exposure ON PURPOSE so intel arrives in SEQUENCE, never stacked at one number:
## faint arrow at noticed_exposure → solid arrow at exposed_exposure → face plate here.
@export var reveal_exposure: float = 75.0
## Committed exposure added by EVERY active tool/ability — including poison (no silent tools).
@export var ability_committed_exposure: float = 25.0
## Committed exposure added by killing an NPC MARK (decays at committed_decay_per_second).
@export var kill_committed_exposure: float = 25.0
## Exposure added by assassinating your PLAYER prey — lands in the SLOWEST-decaying pool
## (player_kill_decay_per_second below), so each kill leaves you more visible to your hunter.
@export var player_kill_committed_exposure: float = 25.0
## How fast committed (tool/NPC-kill) exposure bleeds off, points/second. 0.25 ≈ 100 seconds per
## +25 action: one ability is a lasting warning; two quick ones cross the 50 exposed threshold.
@export var committed_decay_per_second: float = 0.25
## How fast PLAYER-KILL heat bleeds off, points/second — the SLOWEST rate by design. 0.1 ≈ 250s
## per +25 kill: two un-decayed kills sit you at the 50 Exposed threshold (a snowball brake).
@export var player_kill_decay_per_second: float = 0.1

# --- scoring (plan.md §3.3 — a score players can read without a spreadsheet) --
## The one primary scoring event: your assigned prey killed.
@export var prey_kill_points: int = 100
## Hard cap on ALL bonuses stacked onto one kill (clean approach + pressure + style).
@export var kill_bonus_cap: int = 50
## Clean-approach bonus at zero exposure, scaling linearly down to 0 at full exposure.
@export var clean_approach_max_bonus: int = 40
## Bonus for killing your prey while your own hunter is closing in (danger level >= 1).
@export var under_pressure_bonus: int = 15
## One style tag maximum per kill (poison / drop / blend …) at this flat value.
@export var style_tag_bonus: int = 10
## Points for a counter-stun. 0 by design: it's a defensive escape tool, not a farm.
@export var counter_stun_points: int = 0

# --- world systems ------------------------------------------------------------
## Static "stand here to erase your meter" blend circles. OFF for the core modes (plan.md §4:
## exposure relief should come from behaving like the crowd, not from camping known circles).
@export var blend_spots_enabled: bool = false
