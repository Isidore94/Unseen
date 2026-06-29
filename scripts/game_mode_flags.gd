extends Node

# GameModeFlags — UNSEEN. Master switches for the RESPAWN-based game mode (RESPAWN_MODE_PLAN.md).
# Registered as an AUTOLOAD, so every machine reads it as the global `GameModeFlags`.
#
# WHAT THIS IS, in plain terms:
# The new mode is an INVERTED version of the base game: instead of one life + elimination, players
# RESPAWN continuously for a 5-minute round, and every death resets you to a base state. This file
# is the single on/off switch for that mode (and its parts), mirroring how ExperimentFlags gates the
# Phase 9 experiments.
#
# HOW IT WORKS ONLINE (important):
# The match is server-authoritative, so only the HOST's copy of these flags governs gameplay. Flip a
# flag on the machine that HOSTS the match. With every flag at its classic default, the game runs
# EXACTLY as the elimination build did (the "delete test").

## Master switch. ON (the ACTIVE default) = PvP-first continuous RESPAWNS: from the first second every
## player is hunting an assigned target and is hunted (AC Brotherhood/Rearmed style, no marks gate);
## on death you reset to base and drop back into the crowd with a re-assigned contract; the round ends
## only on the clock. OFF = the classic ELIMINATION loop (marks-first, one life, spectate on death,
## match ends at last-standing) — kept as the A/B baseline; flip OFF to compare.
@export var respawn_mode_enabled: bool = true

## The per-life PvE upgrade ladder — kill OPTIONAL NPC marks to earn arrow precision / extra tools, all
## of which wipes on death. NOT YET IMPLEMENTED — reserved for the next increment (Stages 5–6).
@export var pve_ladder_enabled: bool = false

## The crowd-density-weighted respawn spawn picker (favours respawning already blended into a crowd,
## excludes spots near live players / your killer). OFF = respawn at an authored map spawn point instead.
@export var density_spawn_enabled: bool = true
