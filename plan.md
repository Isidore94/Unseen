# UNSEEN — Gameplay and Technical Roadmap

> Codebase audit: 2026-07-11  
> Goal: make the hunt/evade decision the heart of every 3–5 minute round, support 2–5 round sessions, and build a fair foundation for four-player ranked play, gadgets, cosmetics, rooftops, and sewers.

## 1. Audit summary

The prototype already contains most of the pieces needed for a strong game: server-authoritative movement and kills, a one-hunter/one-prey ring, a crowd disguise, exposure, respawns, seven tools, perks, danger feedback, map cover, four maps, scoring, cosmetics plumbing, Steam lobbies, and several experimental anti-stall systems. The project also imports cleanly in Godot 4.7.1, and both the menu and the local AI harness start headlessly without script errors.

The next step should not be “add more features.” It should be to make one clear four-player ruleset consistently fun, measurable, and technically easy to tune. At present, several systems compete with or bypass the hunt/evade loop:

- `KillComponent.request_kill()` and `host_poison()` treat **any player** as a valid clean kill. In a 3–4 player match, a player can therefore kill and score from someone who is not their assigned prey. The target ring becomes guidance rather than the game rule.
- The map currently selects core rules. Compact activates a marks-first duel while Citadel activates immediate PvP. This makes it impossible to tell whether a balance change helped because both the arena and the rules change together.
- `online_match.gd` is over 4,100 lines and owns match flow, spawning, contracts, scoring, danger, perks, gadgets, layers, cosmetics, HUD wiring, replication, and experiments. Changes to one system can easily break another.
- Balance data is not a database or content layer. Roughly 400 exported values and hard-coded tool/perk tables are distributed through scripts and scenes. Comments have already drifted from live perk names and behavior.
- Exposure is doing several jobs at once, but its consequences are concentrated at a 100-point cliff. The game often moves from weak feedback to a precise arrow and face reveal instead of creating readable escalating risk.
- Poison is silent, delayed, exposure-free, and valid against every player. Disguise can fully suppress the hunter's arrow. Permanent access-point claims can deny traversal for an entire round. These are power-without-enough-counterplay cases.
- Score bonuses can dwarf the 100-point base kill. Poison, revenge, focus, drop, streak, blend, and exposure bonuses can stack into several times the value of a normal kill. This obscures the goal and can snowball.
- Counter-stuns award kill-level points on an eight-second cooldown. The prey can potentially farm their hunter instead of using the stun to escape.
- The rooftop and sewer implementation is currently an abstract layer flag. Characters keep using surface position and collision geometry. The sewer is blind, grants perfect prey direction, and forbids kills; the rooftop is a visibility state rather than a real route network.
- Player and NPC nodes are structurally and packet-wise distinguishable. That is acceptable for trusted tests, but not for competitive/ranked play in a game whose core rule is hidden identity.
- Up to 110 NPCs use individual navigation/avoidance and each publishes position/velocity at 20 Hz. That is a likely host CPU and upload ceiling before ranked-quality networking or more elaborate maps are added.
- There are no automated gameplay-rule tests, match simulation tests, replay records, or balance telemetry. Tuning currently depends on feel and changelog notes alone.

## 2. Product direction to lock first

### Primary mode: Hunt Cycle

Build and tune one default mode before preserving variants:

- **Players:** four is the design target. Three is fully supported. Two is a duel/testing variant, not the balance target.
- **Round:** four minutes by default, tunable from three to five.
- **Lives:** continuous respawns with a short, protected return to the crowd. No spectator downtime during the round.
- **Contract:** every living player has exactly one assigned prey and exactly one hunter.
- **Valid attack outcomes:**
  - strike assigned prey → assassination;
  - strike your hunter → defensive counter-stun;
  - strike an unrelated player → failed interference, no death and no score;
  - strike a civilian → visible whiff, short recovery, and exposure.
- **Win:** most contract points at time. Clean approach and contextual skill add small, capped bonuses.
- **Respawn:** 2.5–3 seconds, out of all live players' view, near believable crowd cover, and not close to the killer.
- **Session:** immediate rematch with loadout/map vote; a best-of-three prompt after each round and a “keep playing” flow after three.

Do not key rules off map IDs. Introduce a `GameRules` resource selected independently from a `MapDefinition`. Compact, Citadel, Rome, and future maps must be testable under the same Hunt Cycle rules. A marks-first duel can remain as a named experimental ruleset after the core mode is proven.

### The intended 20-second decision loop

Every short slice of play should ask the player to choose among three pressures:

1. **Hunt:** take a fast route, gain prey information, close distance, and risk becoming readable to your own hunter.
2. **Blend:** move like the crowd, break line of sight, lower immediate heat, and give the prey more time to reposition.
3. **Counter:** react to evidence that your hunter is close, spend a defensive tool or attempt a stun, and temporarily surrender initiative on your prey.

If the best answer is “always sprint,” “always hide under a roof,” “always wait for the arrow,” or “farm counter-stuns,” the loop is not balanced yet.

## 3. P0 — Correct the core rules before further content

### 3.1 Enforce the contract on the host

Move kill validity out of scene groups and into an authoritative `TargetGraph`/`ContractService` query:

```text
resolve_attack(attacker_actor_id, victim_actor_id)
  victim == prey_of(attacker)    -> KILL
  victim == hunter_of(attacker)  -> COUNTER_STUN
  victim is NPC                  -> MARK_KILL or CIVILIAN_WHIFF
  otherwise                      -> INTERFERENCE_WHIFF
```

Required changes:

- Remove `target.is_in_group("player")` as a blanket clean-kill condition from blade and poison paths.
- Validate sender, actor ownership, life state, grace, range, line of sight if required, map layer, cooldown, and exact contract relation in one host-owned resolver.
- Make poison call the same resolver instead of carrying a second version of target validity.
- Make offline mode use the same resolver or clearly label it a non-balance tutorial harness. Three drifting kill paths are too risky.
- Use opaque actor IDs in requests, not client-provided `NodePath` values. The host resolves the ID to a live actor and validates it.
- Add tests for every attacker/victim relationship at two, three, and four players.

Acceptance criteria:

- A player can never kill or poison an unrelated human.
- A player never receives private information identifying their hunter from the outcome request; the host returns only the public result animation/cue.
- Every tool-based kill and blade kill produces the same validity result under the same conditions.

### 3.2 Replace full-ring churn with local reassignment

Recomputing the stable-seat ring whenever someone dies can change several contracts and then change them again 2.5 seconds later. Use a local splice:

- On `A kills B`, A inherits B's prey C after the kill.
- B respawns into one existing edge, turning `D → E` into `D → B → E`.
- Prefer an edge that avoids B's killer and last two opponents, so the same pair is not immediately repeated.
- Only A, B, and the selected insertion hunter should receive a new target. Everyone else keeps the player they were reading.
- Record a target-assignment generation number. Late RPCs for an old generation are ignored.

This preserves the one-hunter/one-prey invariant while making opponent knowledge valuable and reducing HUD churn.

### 3.3 Simplify and cap scoring

Use a score players can understand without a spreadsheet:

| Event | Proposed points | Rule |
|---|---:|---|
| Assigned prey killed | 100 | Only primary scoring event |
| Clean approach | 0–40 | Based on exposure before the unavoidable kill spike |
| Under-pressure kill | 15 | Hunter genuinely nearby with line of sight/recent evidence |
| Route/style action | 10 | One tag maximum: drop, blend, poison, etc. |
| Counter-stun | 0 | Defensive escape tool, not a farming objective |
| Civilian whiff | 0 | Exposure + recovery is enough punishment |
| Unrelated-player interference | 0 | Failed strike + short recovery |

Cap the total bonus for one kill at 50. Remove score multipliers for streaks; show streaks as presentation or award a small end-of-round medal. A player should always prefer an assigned prey kill over farming a style condition.

For ties: assigned kills, then fewest deaths, then clean-kill total. Do not let hidden average-exposure math decide a result players cannot read.

### 3.4 Make respawns safe but not advantageous

- Keep density weighting, but use path distance and line of sight rather than only straight-line distance.
- Hard-exclude every live player's current camera rectangle plus a margin.
- Do not deliberately spawn close to the new prey; that creates unearned contact. Prefer a neutral distance band that produces a 10–20 second approach.
- Break grace on any offensive action or offensive tool, not just a landed kill.
- Prevent target/intel arrows from updating until the respawn fade completes.
- Run the spawn picker against authored test fixtures and measure deaths within 8 seconds of respawn.

## 4. Rebuild exposure as the hunt/evade control system

Keep one player-facing 0–100 meter, but give it four consequences instead of one cliff:

| Exposure | State | Hunter information | Prey meaning |
|---:|---|---|---|
| 0–24 | Blended | No automatic direction | Safest; behavior is the only tell |
| 25–49 | Noticed | Infrequent four-way pulse | Speed created weak, delayed risk |
| 50–74 | Tracked | More frequent four/eight-way pulse | Hunter can route toward the area |
| 75–99 | Hunted | Fast eight-way pulse and stronger local tells | Escape requires a real route/tool |
| 100 | Compromised | Precise off-screen bearing for a short window | Immediate danger, but still no on-screen outline |

Rules:

- The arrow always disappears when the prey is on screen. Never identify the exact on-screen figure.
- Remove global face reveals from normal exposure. A portrait of the exact body skips too much of the crowd-reading game, especially after respawn. Reserve exact face intel for a deliberately earned, short-lived contract reward if playtests prove it is needed.
- Separate **movement heat** from **action notoriety** internally even if the HUD combines them. Movement should rise quickly and recover in roughly 8–15 seconds of civilian behavior. Kills/tools should create a hunter-facing pulse/tell that lasts roughly 15–30 seconds rather than a mostly invisible +25 that takes about a minute to decay.
- Replace flat `+25 except poison` with per-tool risk authored in `ToolDefinition`. Risk can be exposure, sound radius, a visible tell, root time, delayed payoff, or some combination.
- Exposure reduction should come primarily from behaving like the crowd and breaking sight, not from standing inside one of five static blend circles. Convert blend spots into believable world interactions—bench, stall, fountain, procession—or remove them from the core mode.
- Crowd density provides visual cover, not a huge numeric erase. The current `-40/s` blend modifier can delete the meter almost instantly and makes known circles camping objectives.
- Keep overhang anti-loitering, but make its feedback local and gradual. A whole roof turning globally red at exactly 100 is a second hard cliff; use a short sound/visual pulse visible to nearby hunters instead.

### Danger feedback

The current heartbeat knows the hunter's distance through geometry. Keep a defensive cue, but make it evidence-based:

- “Uneasy” when the hunter is near **and** has line of sight, recently produced a tell, or recently crossed the prey's view.
- “Immediate danger” only within counter-stun range or after a failed hunter strike.
- Add a 0.5–1.0 second delay and short persistence so players cannot use the heartbeat as a wall-penetrating detector.
- Vigilant-style perks may alter presentation or cooldown, but must not silently expand omniscient detection radius.

## 5. Gadgets and abilities

### Gadget design contract

Every tool definition must answer five questions in data:

1. What hunt/evade problem does it solve?
2. What vulnerability buys its power?
3. What can the opponent observe?
4. What is the opponent's counterplay?
5. Can it kill only the assigned prey?

Start each life with one utility and one signature gadget. Prefer fixed charges per life over universal regeneration. Thirty-second charge regeneration in a four-minute round encourages waiting for a second use and makes resource state hard to read. If regeneration remains, earn it through a risky map interaction instead of time alone.

### Existing-tool changes

| Tool | Keep | Change/counterplay |
|---|---|---|
| Smoke | Loud escape/space-control tool | Owner cannot attack inside it; opponents are slowed/dazed rather than frozen for most of the cloud; clear public throw cue; arrows lose precision but are not deleted |
| Disguise | Nerve-test identity swap | Sprint/attack breaks it; arrow drops one precision tier rather than turning off; nearby application tell; 8–12 second duration |
| Morph | Turn nearby civilians into look-alikes | Make the copy burst authoritative and deterministic; visible ripple tells observers that a morph happened, not which body cast it |
| Decoy | Make a civilian perform a player-like tell | Give the decoy a believable authored action/path; one attentive counter-read should distinguish it after several seconds, not instantly |
| Poison | Delayed assigned-prey kill | Assigned prey only; close application; 8–12 second delay; nonzero risk through exposure/contact animation; prey gets an ambiguous symptom and can cleanse at a public, exposed point or kill the poisoner before detonation |
| Firecracker | Disengage or force a reaction | Require line of sight; reduce full white-out and hard stun; strong sound/flash exposes the caster; cover/facing away reduces effect |
| Clones | High-skill route confusion | Burst into independent predetermined routes; no every-frame clone driving RPC/state; copies expire on collision/attack and cannot block entrances |

### Perks

Pause expansion of perks until the no-perk core is fun. Current perks are hidden numerical advantages to recovery, hunter warning, cooldowns, or NPC-kill lockout, and one perk is useful only in the map-specific marks mode. That will create mandatory picks in ranked.

When perks return:

- Make each a visible sidegrade with a benefit and cost, not a pure multiplier.
- Avoid modifying the core exposure recovery rate, kill validity, or omniscient hunter warning.
- Prefer new decisions: one quicker sewer interaction but a louder grate; one extra decoy but no smoke; a shorter counter-stun recovery but a smaller counter range.
- Version and hash the allowed ranked loadout list. Casual can use a broader experimental pool.

## 6. Real rooftop and sewer level design

The current `LayerComponent` changes visibility and kill rules while leaving the actor on the surface map. Replace this with authored traversal spaces.

### Required level model

Create a `MapDefinition` resource containing:

- map ID, supported player counts, surface bounds, crowd budget, and spawn regions;
- separate navigation regions for `SURFACE`, `ROOFTOP`, and `SEWER`;
- traversal nodes with entry position, exit position, destination layer, channel time, sound/tell radius, directionality, and cooldown;
- visibility links (for example, rooftop can see a plaza below, but not through roofs);
- authored density zones, landmarks, risky open lanes, and objective/utility sockets;
- route-analysis metadata used by validation tools: travel time, alternate-path count, sightline length, and choke width.

The server owns layer transitions and occupancy. Clients receive only anonymous actor transforms and the visibility they are allowed to render.

### Sewer role

The sewer should be a risky rotation route, not a safe information bunker:

- Build one short loop or two cross-links connecting specific districts.
- Entry/exit uses a 0.6–1.0 second grate animation with an audible local tell.
- No civilian cover underground, limited vision, and distinct footstep audio.
- Remove perfect prey direction while underground. At most provide infrequent four-way surface bearings.
- Do not make the entire sewer a no-kill zone. Either allow close-range fights underground or limit safe tunnel occupancy with a short forced-exit timer and vulnerable exits.
- If using the “something lurks in the darkness” rule, apply it per tunnel segment, not the whole sewer. A blocked entrant gets information, but the occupant also creates an audible cue so camping has counterplay.
- Every entrance needs at least two surface escape decisions nearby; never put the only exit inside a guaranteed kill pocket.

### Rooftop role

Rooftops trade crowd safety for information and route control:

- Use connected roof strips, not the full surface street network while invisible.
- Provide two or more stairs/ladders and selected one-way drops.
- A rooftop player can see only authored streets/courtyards below and has no civilian disguise while exposed on a roof.
- Climbing and dropping create readable local tells. A drop attack has a brief commitment window and modest style credit, not a large score bonus.
- Rooftop peers can see and threaten one another; no guaranteed observation platform.
- Permanent ownership claims should be removed. Temporary control can be bought with a tool and must be breakable from the other side.

### First vertical-slice map

Do not retrofit every map simultaneously. Build one “Vertical Citadel” test map:

- three recognizable surface districts around one central landmark;
- two high-density routes and one exposed fast lane between each adjacent district;
- a two-branch sewer connecting opposite districts;
- two partial rooftop networks with one-way drops into high-risk plazas;
- six total transitions, all with at least one counter-route;
- no teleporter pads in the first test—the vertical routes already provide repositioning.

Test the map under the same Hunt Cycle rules as flat Citadel. Keep flat Citadel as the control map.

## 7. Technical architecture changes

### 7.1 Split the match monolith

Keep `OnlineMatch` as composition/root wiring only. Extract in this order:

| Service | Owns |
|---|---|
| `MatchDirector` | State machine: loading → countdown → active → results/rematch |
| `TargetGraph` | Hunter/prey edges, generations, local splice, validity queries |
| `CombatResolver` | Blade/poison/tool attack validation and outcome events |
| `SpawnDirector` | Spawn candidates, LOS/path/density scoring, grace |
| `ScoreService` | Kill ledger, capped bonuses, standings, tie-breaks |
| `IntelDirector` | Exposure tiers, arrow pulses, danger evidence, private delivery |
| `ToolAuthority` | Tool requests, definitions, charges, effects, counters |
| `LayerService` | Traversal requests, occupancy, layer visibility |
| `ActorReplication` | Anonymous actor snapshots and private owner mapping |
| `MatchPresentation` | HUD, death splash, scoreboard, audio/visual event reactions |

Each service should have one authoritative state model and signals for presentation. No service should mutate HUD nodes directly.

### 7.2 Make balance and content data-driven

There is no need for SQL or an online database at this stage. Use Godot resources in a new `data/` tree:

```text
data/
  rules/hunt_cycle.tres
  maps/citadel.tres
  tools/smoke.tres
  tools/poison.tres
  perks/...
  cosmetics/catalogue/...
```

Add typed resources:

- `GameRules`: duration, player range, respawn/grace, score values, exposure thresholds, enabled systems.
- `ToolDefinition`: stable ID, charges, cooldown, target mode, tell type/radius, risk cost, effect parameters, icon.
- `PerkDefinition`: stable ID, benefit, drawback, ranked legality.
- `MapDefinition`: scene, supported players, crowd density, layers, transitions, spawn/density regions.
- `CosmeticItem`: move live catalogue entries from hard-coded `make()` calls to `.tres` files as real content arrives.

RPCs send stable IDs and compact runtime values, never resource objects. At match start, the host sends a rules/content version hash so mismatched clients cannot join ranked games.

### 7.3 Formal state machines

Replace scattered booleans/dictionaries with explicit states:

- match: `LOADING`, `COUNTDOWN`, `ACTIVE`, `RESULTS`;
- player life: `ALIVE`, `DYING`, `RESPAWNING`, `GRACE`;
- contract: `ACTIVE`, `PREY_DEAD`, `REASSIGNING`;
- tool slot: `READY`, `ACTIVE`, `COOLDOWN`, `EMPTY`;
- traversal: `GROUND`, `CHANNELING`, `ROOFTOP`, `SEWER`.

Transitions should be host-only and logged as match events. This removes cases where `_dead_by_peer`, node death state, respawn timers, phase strings, and UI can disagree.

### 7.4 Identity-safe replication

Ranked play requires more than wiping `controlling_peer_id`:

- Put players and NPCs under one `Actors` parent and instance one shared actor shell.
- Give every actor an opaque, per-match public actor ID. Do not broadcast peer IDs with spawn data.
- Send the local player's actor-ID mapping privately to that owner.
- Send prey actor IDs privately and only while that contract generation is active.
- Batch players and NPCs in the same snapshot format and cadence so packet structure does not identify humans.
- Keep kill, exposure, tool, target, score, and traversal truth on the server.
- For real ranked mode, use a neutral/dedicated server. A player-hosted authoritative host can inspect hidden mappings and manipulate results.

Trusted friend lobbies may ship earlier with the current host model, but label them casual.

### 7.5 Crowd CPU and bandwidth

- Replace one `MultiplayerSynchronizer` per NPC at 20 Hz with batched actor snapshots at 8–12 Hz plus interpolation.
- Do not lower the update rate only for NPCs; that becomes an identity tell. All non-owned actors use the same public snapshot packet.
- Replace repeated full-crowd radius scans with a spatial hash/grid updated several times per second. Use it for density, blend, smoke, spawn, and panic queries.
- Run full navigation/avoidance only near relevant players and in visible districts. Far NPCs can follow precomputed district/waypoint routes at a lower decision rate while their public motion remains smooth.
- Pool temporary effects and NPC actor shells where practical instead of repeatedly creating/freeing them.
- Measure host frame time and upload at 35, 55, 85, and 110 crowd sizes with four clients before raising content limits.

## 8. Cosmetics and progression foundation

The shared `CharacterVisual`, loadout payload, inventory ownership gate, and crowd-safe buckets are good foundations. Complete them in this order:

1. **Persistence:** save owned IDs, equipped loadout, palettes, profile, settings, and schema version to `user://profile_v1.json`. Use atomic write/rename and migration tests. No backend is needed for prototype accounts.
2. **Data catalogue:** move cosmetics to resources/manifests; validate unique stable IDs, valid art paths, correct slot, and safety bucket in an editor tool.
3. **Fairness validator:** every in-match body/outfit/head/weapon combination must have sufficient exact look-alikes in that viewer's crowd, including matching silhouette, scale, walk cycle, and animation timing.
4. **Real content:** prioritize body skins, kill animations, win poses, emotes, banners, badges, titles, tool VFX skins, and HUD themes. Overlay hats/weapons should wait until their animation/silhouette parity is proven.
5. **Unlock track:** reward playtime, challenges, and ranked seasons with cosmetic currency/items only. Never attach gameplay stats to cosmetics.
6. **Backend later:** platform inventory/cloud validation is needed before paid items, trading, or cross-device ownership. Do not build a custom commerce database during the fun-test phase.

Emotes must cancel on movement/attack and may create a small behavioral tell; that turns expression into an intentional risk without making paid content stronger.

## 9. Testing, telemetry, and balance process

### Automated checks

Add a headless test scene or a lightweight GDScript test runner for:

- target graph invariants for 2/3/4 players across kill, disconnect, respawn, and reconnect;
- attack outcome matrix for prey, hunter, unrelated player, mark, and civilian;
- score caps and tie-breaks;
- exposure tier transitions and decay;
- tool charge/cooldown/reset behavior and assigned-prey validation;
- spawn exclusion, LOS, and fallback safety;
- cosmetic payload round-trips and catalogue validation;
- save migration and malformed profile recovery;
- map connectivity on every navigation layer and transition graph.

Keep the existing Godot headless import/startup checks in a local script and CI.

### Match event ledger

Record a compact server-side event stream for every playtest:

```text
match_started, target_assigned, exposure_changed(reason), intel_pulsed,
attack_attempted/outcome, tool_used/outcome, layer_entered/exited,
player_killed, player_respawned, score_awarded, match_ended
```

Use anonymous session IDs. Export JSON/CSV after a local match. The same ledger can later power replays, cheat review, and spectator tools.

### Initial fun targets

These are tuning targets, not permanent rules:

- first assigned-prey contact: 15–30 seconds;
- average life: 35–65 seconds;
- valid assigned kills per player in four minutes: 2–5;
- respawn deaths within 8 seconds: under 5%;
- time at exposure 100: under 10% of alive time, but reached at least once by most aggressive players;
- civilian whiffs: possible but uncommon, roughly 0–2 per player per round;
- counter-stun success: useful escape, under one success per life on average;
- at least 70% of equipped gadget charges used; no gadget above 55% pick rate for several test blocks;
- score from base contract kills: at least 70% of the total score;
- target changes caused by someone else's death: at most one per event for an uninvolved player.

After each playtest block, change one system family only—combat, exposure/intel, gadgets, spawning, or map—and compare the ledger. Do not run multiple experimental flags by default; select a named experiment preset so results are reproducible.

## 10. Ranked-readiness plan

Ranked depth should come from readable decisions, map knowledge, route prediction, resource timing, target identification, and adapting to the hunter/prey graph—not from hidden perk math or a large content grind.

Do not expose a ranked queue until all of these are true:

- one locked Hunt Cycle ruleset and ranked-legal loadout pool;
- assigned-prey-only combat with automated invariant tests;
- anonymous actor replication and no obvious player/NPC packet or scene-tree distinction;
- neutral/dedicated authority, reconnect handling, abandon rules, and result signing;
- stable performance at four players plus the full crowd budget;
- match event ledger/replay sufficient to investigate impossible actions;
- input remapping, controller parity, colorblind-safe cues, and fixed competitive camera bounds;
- at least several hundred internal/friend-lobby rounds showing no dominant gadget or route.

Use placement-based rating with uncertainty (four-player result order), with contract score only as a limited tie-break. Do not directly feed every style point into rating; exploitable performance metrics distort competitive play. Publish visible divisions/seasons while keeping uncertainty and matchmaking range internal.

## 11. Dependency-ordered delivery roadmap

### Milestone A — Stable core baseline

- Create `GameRules` and decouple rules from maps.
- Enforce assigned-prey-only combat for blade and poison.
- Extract/test `TargetGraph` and use local reassignment.
- Simplify scoring and remove counter-stun points.
- Add match ledger and core invariant tests.

**Exit test:** ten consecutive four-player simulated/manual rounds complete without an invalid kill, broken ring, duplicate score, or stuck respawn. Players can explain why the winner won.

### Milestone B — Hunt/evade fun test

- Implement exposure tiers and evidence-based danger.
- Remove normal face reveals and static blend-circle meter deletion.
- Tune one no-perk, two-basic-gadget ruleset on flat Citadel.
- Improve respawn LOS/path safety.
- Run repeated 2–5 round sessions and collect the fun targets above.

**Exit test:** players voluntarily choose both aggressive pushes and defensive re-blends, and ask for a rematch after a short set.

### Milestone C — Gadget depth

- Introduce `ToolDefinition` resources and `ToolAuthority`.
- Rework smoke, disguise, decoy, and poison first.
- Add morph/firecracker/clones one at a time only after counterplay tests.
- Reintroduce sidegrade perks last.

**Exit test:** each gadget has a visible tell, a demonstrated counter, and no large pick-rate/win-rate outlier.

### Milestone D — Vertical Citadel

- Build real surface/roof/sewer navigation and traversal graph.
- Add server-owned transition state, tells, and occupancy.
- Produce the single vertical-slice map and compare it against flat Citadel.
- Add map connectivity/sightline/route metrics.

**Exit test:** rooftops and sewers create prediction and escape decisions without becoming mandatory routes or safe zones.

### Milestone E — Architecture and online scale

- Finish service extraction from `online_match.gd`.
- Unify actor structure and anonymous snapshot replication.
- Batch/LOD crowd simulation and measure four-client load.
- Add reconnect and match-state snapshot support.

**Exit test:** stable four-player online sessions at the target crowd budget, with no client-readable human identity field and no host frame spikes that affect combat.

### Milestone F — Retention and cosmetics

- Add profile persistence and catalogue validation.
- Ship a small polished cosmetic set across body, animation, emote, and profile slots.
- Add post-round medals, challenge progress, map/loadout vote, and fast rematch flow.
- Track session length and repeat-round behavior.

**Exit test:** a player can enjoy two rounds, understand improvement over five rounds, and earn/show something without any gameplay advantage.

### Milestone G — Ranked alpha

- Add neutral server authority, result signing, rating, seasons, abandon/reconnect rules, and replay review.
- Lock and version the competitive rules/loadout/map pool.
- Run a closed ranked alpha before public progression or monetization.

## 12. What not to build yet

- More classes or a large perk tree before the base assassin loop passes Milestone B.
- A shop, battle pass, premium currency, or custom account backend before persistence and cosmetic fairness validation.
- Multiple full vertical maps before one roof/sewer slice proves its role.
- Eight-player support; the current design target is four, and identity-safe replication/crowd cost should be solved there first.
- More experimental HUD intel layered on top of arrows, faceplates, heartbeat, minimap, behavioral flags, and earned reads. Choose one coherent intel model.
- Ranked matchmaking on player-hosted authority.

## 13. Recommended first implementation slice

The highest-value first slice is deliberately small:

1. Add `GameRules` with a four-minute Hunt Cycle preset and make both Compact and Citadel load it.
2. Add a tested `TargetGraph` service.
3. Route blade and poison through one `CombatResolver`; allow only prey kill, hunter stun, unrelated-player whiff, and civilian whiff.
4. Change score to 100 base + at most 50 bonus; counter-stun scores zero.
5. Add a JSON match ledger for assignments, attack results, deaths, respawns, and score.
6. Run 20 four-player rounds on flat Citadel before changing exposure or adding content.

That slice directly restores the premise: **going aggressive helps you kill your prey, but every aggressive action gives your hunter a better chance to kill you.** Everything else in this roadmap should strengthen that sentence.
