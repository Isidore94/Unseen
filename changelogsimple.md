# UNSEEN — Devlog (brief)

## Big Art + Crowd Update

**Art (all PixelLab pixel art):**
- 4 end-game **assassin** player skins — Norse (warhammer), Crusader (longsword), Revolution (dual rapiers), Egyptian (dual maces) — each with **walk + attack** animations.
- 11 **Roman commoner** crowd looks, all animated.
- Every map reskinned to a clean, sunny **stylized look** (sand streets, extruded buildings, water edges).

**Crowd:**
- Bigger, livelier crowds, now a **50/50 mix of commoners and assassin look-alikes** (so a player assassin actually blends in).
- Movement variety — some people loiter, some wander, some cross the map.
- Killing now sends nearby NPCs into a **6-second panic scatter**.

**Lobby & identity:**
- New lobby **character select** — pick your assassin (private; opponents never see it).
- **NPC disguise** option — appear as a commoner while your assassin is duplicated as decoys, so you can't be tracked by sprite.
- Rematch returns everyone to the lobby to re-pick.

**Polish & fixes:**
- On-screen **controls legend**, numbered **cooldowns**, smoke now shows you're hidden.
- Experiment status/event **toasts**.
- Fixed: offline crowd bunching at map center, off-center reveal portraits, a startup crash.

## Gadgets & Tools (pick 2)

Bring **two gadgets** into each match, chosen privately in the lobby from a pool of five:
- **Smoke** — drop a cloud that freezes anyone caught inside (a chasing hunter included) so they can't kill for a few seconds.
- **Disguise** — look like a nearby civilian for 30 seconds to break a pursuer's lock (you still see yourself normally).
- **Morph** — turn nearby civilians into copies of YOU for a few seconds, so a hunter can't tell which one is real.
- **Decoy** — spook a civilian into bolting, baiting a hunter into a wrong kill.
- **Poison** — a delayed, silent kill: your target drops moments later with no crowd panic, so you walk away clean.
- New **targeting ring** around you highlights the civilian or player you're aiming at, so it's clear who a gadget or kill will hit.

## New Main Map — Compact Arena

- A tighter, faster main map with **varied buildings** (including L-shapes and a tower), a **central fountain plaza**, and **canals crossed by bridges**, ringed by water.
- Two **sewer corner pockets** to duck into for cover — only one person fits, so if someone's already down there you're told *"Something lurks in the darkness."*
- **Rooftops removed** — the map now reads as clean street-level streets and plazas.

## The Hunt — Arrows, Exposure & Scoring

- **Direction arrows** help you find people on the open map: an **exposure arrow** points at a player only once they're fully exposed, and a **hunt arrow** points roughly toward your target — and vanishes the moment they're on your screen, so the final find is still about reading the crowd.
- **Exposure retuned** so a clean contract (your two marks + two gadgets) stays survivable; only reckless extras (sprinting, wrong kills) push you over the edge.
- **Killing a real player is worth far more** than killing an NPC mark.
- A red **"YOU ARE BEING HUNTED"** warning appears when someone locks onto you.

## HUD & Match Flow

- A new **premium HUD**: your portrait, a segmented exposure bar, your objectives, a map legend, the round timer, and the player roster.
- **Start-of-round 3 / 2 / 1 / GO! countdown** so everyone begins together.
- **Minimap shows both of your marks**, so you can plan a route between them.
- The crowd now **actually walks** (animated) on every screen, and characters no longer slide or moonwalk.
