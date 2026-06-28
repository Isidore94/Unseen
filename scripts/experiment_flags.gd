extends Node

# ExperimentFlags — UNSEEN, Phase 9 (PHASE_9_EXPERIMENTS.md §1.1). The SINGLE source of truth
# for which experimental endgame/commitment features are live. Registered as an AUTOLOAD, so
# every machine reads it as the global `ExperimentFlags`.
#
# WHAT THIS IS, in plain terms:
# Phase 9 is a batch of *feel* experiments we may keep or delete after playtesting. Each one is
# a self-contained node that does NOTHING until its master switch here is true. With every flag
# false (the default), the base game runs EXACTLY as it did before Phase 9 existed — that's the
# "delete test" (§1.4) the whole phase is built around.
#
# HOW IT WORKS ONLINE (important):
# The match is server-authoritative, so the HOST's copy of these flags is what governs gameplay.
# Each experiment runs its real logic only on the host (gated on its flag), then sends any
# player-facing cue to the right client. Clients render the cues they're sent regardless of their
# own local flags — so you only ever need to flip a flag on the machine that HOSTS the match.
#
# HOW TO USE: flip ONE bool to true (here, or on the autoload in the Inspector) before hosting,
# play a block of rounds, then flip it back. Never run two at once when judging feel (§3.1).

## 9A — WHIFF RECOVERY: killing the wrong target briefly disarms you (a punishable commitment).
@export var whiff_recovery_enabled: bool = true
## 9B — CROWD THINNING: NPCs leave the map as the round ages, forcing an exposed endgame.
@export var crowd_thinning_enabled: bool = false
## 9C — EARNED READ: sustained discipline charges a one-shot "anomaly pulse" over the crowd.
@export var earned_read_enabled: bool = true
## 9D — MUTUAL PROXIMITY: two players who are each other's target both get a hot/cold cue.
@export var mutual_proximity_enabled: bool = false
## 9E — CROWD REACTION: NPCs near a kill flinch/scatter, leaving a directional tell.
@export var crowd_reaction_enabled: bool = true
## 9F — BEHAVIORAL FLAG: a reciprocal, behavior-triggered directional flag that scales with exposure.
@export var behavioral_flag_enabled: bool = true
