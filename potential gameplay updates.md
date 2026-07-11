# UNSEEN — Potential Gameplay Updates

> Implementation handoff for Fable/Codex/another AI agent.  
> Created: 2026-07-11  
> Status: proposed gameplay experiments. Build behind flags and preserve the current modes for A/B testing.

## 1. Purpose

The current hunt loop is readable but too direct:

1. Follow the continuously updating target arrow.
2. Walk toward the target.
3. Everyone's shortest routes converge near the center.
4. Find the target on screen and assassinate them.
5. Avoid the player following their arrow toward you.

This document proposes systems that make the exterior districts, corners, future rooftops, and future sewers strategically valuable without replacing the PvP hunt with mandatory errands.

The central design goal is:

> Taking an exterior route should improve your ability to hunt or escape, but obtaining that advantage must cost time, create a readable tell, or add exposure.

## 2. Locked design decisions

These decisions come directly from the current project direction and should not be silently redesigned during implementation:

- Game mode and map remain intentionally coupled for balance.
- Citadel is the main 3–4 player immediate Hunt Cycle map.
- Compact should become a faster 1v1 mode rather than requiring two slow NPC kills.
- Rounds should remain roughly 3–5 minutes.
- The serious exposure state begins at **50 exposure**, not only at 100.
- At 50+, the harsh tracking/reveal consequences are active. Values above 50 make them more frequent, accurate, or persistent rather than unlocking a separate punishment only at 100.
- Active items and abilities add **+25 committed exposure**, including poison.
- Committed exposure decays much more slowly than running or overhang heat. Initial target: approximately `0.25 exposure/second`, so +25 takes about 100 seconds to clear.
- Running, erratic movement, and overhang loitering use recoverable movement heat and should clear much faster when the player behaves calmly.
- A player can assassinate only their assigned prey.
- Striking the player hunting you resolves as a counter-stun where that mode supports it.
- Optional objectives must not gate the ability to assassinate another player.
- Optional objectives should primarily grant information, utility, or route access—not damage or large score rewards.

## 3. Important diagnosis: corner pickups alone will not solve center convergence

Placing an objective in the opposite corner can make the problem worse because the shortest diagonal path still crosses the center.

The complete solution needs three coordinated changes:

1. **Tracking becomes snapshot-based below 50 exposure.** The arrow stops behaving like live GPS.
2. **Personal exterior opportunities provide optional advantage.** Different players receive different route incentives rather than one shared control point.
3. **Perimeter routes become competitive.** The center remains fastest but dangerous; the surface edge, rooftops, and sewers offer slower/safer or specialized alternatives.

Do not judge the exterior-objective experiment solely by whether players touch a corner prop. Judge it by whether player movement and kills spread across the map.

## 4. Feature flags

Add host-authoritative experiment flags before implementing behavior. The current baseline must remain playable.

Suggested additions to `scripts/game_mode_flags.gd`:

```gdscript
## Below-50 hunt arrows update only on timed snapshots instead of tracking every frame.
@export var snapshot_hunt_arrow_enabled: bool = true

## Personal exterior information objectives for Citadel and Compact.
@export var peripheral_leads_enabled: bool = true

## Optional utility-only resupply caches on exterior sockets.
@export var utility_caches_enabled: bool = false

## Scheduled NPC markets/processions that move cover toward exterior districts.
@export var outer_crowd_events_enabled: bool = false

## Compact uses immediate PvP + Leads instead of mandatory NPC marks.
@export var compact_intel_duel_enabled: bool = true

## Experimental asymmetric 1v1 role-swapping mode. Do not enable with Intel Duel.
@export var cat_and_mouse_duel_enabled: bool = false
```

Only the host's flags determine outcomes. Clients render state sent by the host.

## 5. Priority 1 — Snapshot hunt arrows

### 5.1 Design

Below 50 exposure, target tracking should provide periodic information rather than an every-frame direction vector.

Suggested map-specific first pass:

| Map/mode | Target exposure | Tracking behavior |
|---|---:|---|
| Citadel Hunt Cycle | 0–24 | No automatic pulse, or a very slow district pulse if tests stall |
| Citadel Hunt Cycle | 25–49 | Four-way snapshot every 7–9 seconds |
| Citadel Hunt Cycle | 50–100 | Frequent/live high-consequence tracking; precision and frequency scale upward |
| Compact Intel Duel | 0–49 | Four-way snapshot approximately every 7 seconds to prevent a two-player stall |
| Compact Intel Duel | 50–100 | Frequent/live high-consequence tracking |

A snapshot records the direction or district where the prey was **when the pulse happened**. The arrow must not rotate continuously as the prey moves between pulses.

The arrow still disappears when the prey is on screen. It never outlines or directly marks the exact on-screen body.

### 5.2 Current code integration

Relevant current file:

- `scripts/exposure_arrow.gd`

The current flashing hunt arrow calls its target-direction calculation repeatedly. Add snapshot state rather than rewriting the drawing code:

```gdscript
var _snapshot_direction: Vector2 = Vector2.ZERO
var _snapshot_valid: bool = false
var _snapshot_seconds_left: float = 0.0
var _snapshot_refresh_left: float = 0.0
var _tracked_exposure: float = 0.0
```

Suggested public API:

```gdscript
func configure_snapshot_tracking(
        enabled: bool,
        refresh_seconds: float,
        visible_seconds: float,
        hot_threshold: float = 50.0) -> void

func set_tracked_exposure(value: float) -> void

func grant_trace(precision_tier: int, duration_seconds: float) -> void
```

Behavior:

- When the target is under 50 and snapshot tracking is enabled, capture direction only when the refresh timer reaches zero.
- Keep the captured direction fixed for the pulse duration.
- Do not call the live target-bearing calculation again until the next snapshot.
- When the target reaches 50, switch to the map-mode's full exposed tracking behavior.
- When a Lead grants Trace, temporarily increase snapshot precision/frequency without outlining the target.
- Disguise or false-trail effects can modify sub-50 snapshots, but must not suppress the serious 50+ consequences.

### 5.3 Networking rule

The immediate prototype can use the replicated target position already present on the hunter's client because the client currently renders the remote target body anyway. The ranked-safe version should eventually have the host send private direction/district snapshots.

Do not expand public RPC data to include prey identity or peer ID.

### 5.4 Acceptance tests

- A prey walking around the hunter between pulses does not rotate the hunter's arrow.
- A new snapshot updates to the prey's new direction.
- The arrow disappears once the target is on screen.
- Crossing 50 exposure activates the configured serious tracking behavior immediately.
- Dropping below 50 returns to snapshot behavior without leaving stale live tracking active.
- Compact and Citadel can use different intervals without hard-coded `if map == ...` checks inside `ExposureArrow`.

## 6. Priority 2 — Peripheral Lead Network

### 6.1 Player-facing concept

Peripheral Leads are optional, private information objectives placed around the exterior districts.

Examples:

- Browse contraband at a market stall.
- Pray for a coded message at a shrine.
- Inspect a notice board.
- Intercept a message at a pigeon coop.
- Contact a sewer informant.
- Survey the district from a rooftop lookout.

NPCs should occasionally use the same props and animations. Watching someone interact is evidence, not automatic proof they are a player.

### 6.2 Citadel first-pass rules

- Round duration remains 240 seconds.
- Define eight exterior sockets: two per outer district.
- First Lead offer appears about 15 seconds after the round starts.
- Each player privately receives two alternatives:
  - one in the clockwise-adjacent exterior district;
  - one in the counterclockwise-adjacent exterior district.
- Never assign the player's current/spawn district.
- Do not assign a diagonal opposite corner until a competitive exterior sewer/roof route exists.
- Selecting/starting one socket cancels the alternative.
- Desired route distance: approximately 10–17 seconds at blend-walk speed, excluding the channel.
- Interaction radius: start around 72–85 px.
- Hold `interact` for 2.75 seconds while stationary.
- Moving more than roughly 20 px from the channel origin cancels it.
- Velocity over roughly 20 px/s cancels it.
- Attacking, using a gadget, becoming stunned, dying, leaving the layer, or leaving the radius cancels it.
- The channel disables attacking.
- Completion produces a localized tell with approximately 450–550 px range.
- Completion adds **+25 committed exposure** because receiving the Trace is itself an active information ability.
- Completion grants one `Trace`:
  - snapshot of the prey's current district/direction;
  - one arrow-precision tier improvement;
  - approximately 10 seconds of improved snapshot tracking;
  - never an exact on-screen outline.
- The prey receives a delayed warning after approximately one second:
  - example: `Your trail was queried from the West Market.`
- If the prey is already at 50+ exposure, the Lead reports `Trail already hot` and is not consumed.
- Maximum two completed Leads per player per round.
- The second offer appears no sooner than 45 seconds after the first completion and must use a different district.
- Leads award zero score.
- A Lead is lost/reset on death; no world item is dropped.

### 6.3 Why the reciprocal warning matters

Free private information is pure power. The warning converts it into interaction:

- The hunter learns the prey's district.
- The prey learns the district from which their hunter acted.
- The prey can rotate away, set an ambush, pursue their own target, or deliberately remain nearby as bait.

This keeps both sides making decisions.

### 6.4 Proposed files

Do not add the entire system directly to `online_match.gd`.

Create:

```text
scripts/opportunities/opportunity_socket.gd
scripts/opportunities/peripheral_lead_director.gd
scripts/opportunities/opportunity_visual.gd
```

Suggested responsibilities:

#### `OpportunitySocket`

- Stable socket ID.
- World position.
- District ID.
- Interaction radius.
- Opportunity kind/theme.
- Public visual/channel state.
- No score, contract, or private assignment logic.

#### `PeripheralLeadDirector`

- Host-owned assignment and channel truth.
- Player-to-socket offers.
- Channel progress/cancellation.
- Exposure cost.
- Trace delivery.
- Prey warning delivery.
- Per-player completion cap and cooldown.
- Client-private offer payloads.

#### `OpportunityVisual`

- Draws the subtle prop marker or placeholder.
- Plays interaction animation/local tell.
- Does not decide completion or rewards.

### 6.5 Suggested signals

```gdscript
signal lead_offered(peer_id: int, socket_ids: Array[int])
signal channel_started(peer_id: int, socket_id: int)
signal channel_cancelled(peer_id: int, socket_id: int, reason: StringName)
signal lead_completed(peer_id: int, socket_id: int)
signal trace_granted(peer_id: int, target_peer_id: int, duration_seconds: float)
```

Use past-tense names for resolved events. Keep private peer/target mappings on the host.

### 6.6 Host channel state

Suggested host dictionary:

```gdscript
## peer_id -> {socket_id, progress, start_position, generation}
var _active_channels: Dictionary = {}
```

Suggested update shape:

```gdscript
func _host_tick_channels(delta: float) -> void:
    for peer_id in _active_channels.keys():
        var channel: Dictionary = _active_channels[peer_id]
        var player := _player_for_peer(peer_id)
        var socket := _socket_for_id(int(channel["socket_id"]))

        var cancel_reason := _channel_cancel_reason(player, socket, channel)
        if cancel_reason != &"":
            _cancel_channel(peer_id, cancel_reason)
            continue

        channel["progress"] = float(channel["progress"]) + delta
        _active_channels[peer_id] = channel

        if float(channel["progress"]) >= channel_seconds:
            _complete_lead(peer_id, socket)
```

Never trust a client-sent completion percentage. Clients send only start/cancel intent; the host measures time, position, velocity, life state, and eligibility.

### 6.7 Suggested RPC surface

The director may be a stable child of `OnlineMatch` on every machine, or `OnlineMatch` can forward these calls.

```gdscript
@rpc("any_peer", "call_local", "reliable")
func request_start_lead(socket_id: int, offer_generation: int) -> void

@rpc("any_peer", "call_local", "reliable")
func request_cancel_lead(offer_generation: int) -> void

@rpc("authority", "call_local", "reliable")
func receive_lead_offer(socket_ids: Array, offer_generation: int) -> void

@rpc("authority", "call_local", "reliable")
func receive_lead_result(socket_id: int, target_district: int, trace_seconds: float) -> void

@rpc("authority", "call_local", "reliable")
func receive_trail_warning(source_district: int) -> void
```

Every offer has a generation number. Ignore delayed requests for an old/dead offer.

### 6.8 Input integration

Use the existing abstract `interact` input action.

Recommended priority when the local player presses interact:

1. If inside an explicitly offered opportunity socket, start/hold that channel.
2. Otherwise use a rooftop/sewer access point.
3. Otherwise do nothing.

Show a small contextual prompt such as `Hold Interact — Query Lead` only to the assigned player.

Do not display a world beam visible to opponents. The physical prop is public; its private eligibility marker is owner-only.

### 6.9 Socket placement

Short-term prototype:

- The host chooses eight deterministic outer walkable positions and broadcasts their IDs/positions.
- Use the outer 20–25% of map bounds.
- Require reasonable separation.
- Reject positions inside walls, water, the central third, or immediate spawn contact range.
- Prefer locations near NPC errand points and at least two approaches.

Long-term:

- Author socket markers per map in the map scene or `MapDefinition`.
- Each marker includes district, theme, allowed opportunity types, route tags, and approach count.
- Never place a socket at the end of a single-exit kill pocket unless the risk is intentional and the reward reflects it.

### 6.10 Acceptance tests

- Every player receives a private offer; other clients do not receive that player's eligible socket IDs.
- Starting one of two choices closes the other.
- Movement, death, stun, tool use, and attack cancel the channel.
- A client cannot complete remotely or accelerate the timer.
- Completion adds exactly +25 committed exposure once.
- Trace affects only the correct hunter/target relationship.
- The prey warning reports the source district without identifying an on-screen actor.
- No score is awarded.
- A dead/disconnected player cannot leave a locked socket or stale offer.
- No more than the configured maximum can be completed per round.

## 7. Priority 3 — Compact Intel Duel (1v1)

### 7.1 Reason for the change

Compact currently uses two mandatory NPC marks before PvP. The marks create walking, but they delay the part players care about and make the opening feel like a checklist.

In the proposed Intel Duel:

- PvP is live immediately.
- NPCs remain disguises, witnesses, decoy targets, and moving cover.
- Exterior Leads are optional ways to buy temporary information.

### 7.2 First-pass rules

- Map: Compact.
- Round length: 210 seconds.
- PvP valid from second zero.
- First to three valid player kills wins immediately.
- If time expires, highest player-kill total wins; use existing score tie-breaks as needed.
- Respawn delay: approximately three seconds.
- Respawn into crowd cover at neutral distance with current grace rules.
- No mandatory NPC marks.
- No score for NPC kills.
- Below 50 exposure, use a four-way target snapshot about every seven seconds.
- At 12 seconds without a recent player kill, each player receives one two-choice Peripheral Lead offer in adjacent exterior districts.
- Channel duration: 2.5 seconds.
- Completion: +25 committed exposure.
- Reward:
  - opponent's current district snapshot;
  - temporary 8-way or improved snapshot pulse every three seconds;
  - duration approximately 10 seconds.
- Opponent receives the delayed source-district warning.
- After any player kill, Lead offers sleep for 20 seconds.
- New unresolved offer approximately every 40–45 seconds.
- No objective score.

### 7.3 Current code changes

Relevant current file:

- `scripts/online_match.gd`

Current behavior to replace under the new flag:

```gdscript
func _marks_gate_enabled() -> bool:
    return _respawn_mode() and NetworkManager.selected_map == NetworkManager.Map.COMPACT
```

New behavior should be controlled by the Compact map-mode configuration:

```gdscript
func _marks_gate_enabled() -> bool:
    if NetworkManager.selected_map == NetworkManager.Map.COMPACT \
            and GameModeFlags.compact_intel_duel_enabled:
        return false
    return _existing_marks_gate_rule()
```

Avoid leaving this as the final architecture. The map should ultimately reference its rules resource, but the flag is acceptable for the first playtest slice.

Add a kill-goal check after a valid player kill is banked:

```gdscript
if _compact_intel_duel_on() \
        and int(_player_kills_by_peer.get(killer_peer, 0)) >= compact_kill_goal:
    _end_match("kill_goal")
```

### 7.4 What to do with the old marks mode

Do not delete it. Keep it selectable behind the existing behavior/flag for comparison.

If a lighter NPC version is desired later, test one optional informant instead of two kills:

- Privately mark one exterior courier NPC.
- Match their walk or remain near them for two seconds.
- No kill, death animation, blade lockout, or score.
- Completion grants one Trace and +25 committed exposure.
- The informant continues behaving like an ordinary civilian.

### 7.5 Acceptance tests

- Both players can assassinate one another immediately after start grace/countdown.
- No NPC kill is required.
- First to three valid player kills ends the round.
- Invalid/non-target outcomes do not advance the kill goal.
- Lead timers reset/sleep correctly after a kill and respawn.
- A player can ignore Leads and still win by hunting well.
- The mode reliably ends within 3.5 minutes.

## 8. Priority 4 — Utility-only contraband caches

Build only after Peripheral Leads have proven that exterior channels improve map flow.

### 8.1 First-pass rules

- Two exterior cache sockets become available at approximately 50 seconds.
- A second pair becomes available at approximately 135 seconds.
- Use opposite or well-separated districts, but pick from a larger pool so openings do not become solved.
- Active window: approximately 30 seconds.
- A player may use a cache only if an equipped utility gadget is below its normal maximum charge.
- Hold still for approximately three seconds.
- The host validates the channel like a Lead.
- Completion restores one charge to a depleted utility tool.
- Allowed initial tools:
  - smoke;
  - disguise;
  - morph;
  - decoy;
  - firecracker;
  - clones.
- Do not restore poison or a future direct-kill ability.
- Maximum one cache completion per player per round.
- Cache consumption is per player; one player cannot deny it to everyone.
- Opening creates a public sound/tell within roughly 500–550 px.
- Leave a visible opened/residue state for approximately eight seconds.
- The pickup itself does not need +25 committed exposure because it grants no immediate effect and the channel is publicly risky.
- Using the restored item still adds the normal +25 committed exposure.
- Cache awards no score.

### 8.2 `ItemComponent` API

Add a host-only helper rather than directly editing `_charges` from the cache system:

```gdscript
func can_restore_utility_charge() -> bool

func restore_one_utility_charge() -> int:
    # Returns restored slot index, or -1 when nothing was restored.
```

Deterministic selection for the first prototype:

1. Primary slot if eligible and depleted.
2. Secondary slot if eligible and depleted.
3. Otherwise fail without consuming the cache.

Later, a short owner-only selection prompt can choose the slot, but do not block the first implementation on that UI.

### 8.3 Failure guards

- If nearly every player immediately visits a cache after spending smoke, reduce availability or strengthen the tell.
- If cache users die during more than roughly one-third of channel attempts, improve nearby escape geometry or reduce the channel toward 2.75 seconds.
- Never turn caches into lethal resupply or a leader snowball.

## 9. Priority 5 — Rotating outer markets/processions

### 9.1 Purpose

The center currently attracts traffic partly because it has a landmark and reliable crowd cover. Move some cover value outward during the round rather than only placing icons at the edge.

### 9.2 First-pass schedule for Citadel

- At approximately 30, 95, and 160 seconds, prepare an exterior crowd event.
- Announce it visually/audio approximately six seconds before movement begins.
- Choose two opposite or well-separated outer districts, never one single global destination.
- Select 12–16 existing living, unmarked NPCs.
- Send them toward those districts over approximately 10–12 seconds.
- Let them linger for approximately 24–30 seconds.
- Then return them to ordinary errands.
- Never migrate more than approximately 20–25% of the live crowd.
- Keep at least 40–50% of normal central crowd density.
- Put Lead/cache sockets near the destination flow, but not directly inside the safest cluster.
- Crowd events grant visual camouflage only. No numeric exposure reduction or score.

### 9.3 Current NPC integration

Relevant current files:

- `scripts/npc.gd`
- `scripts/test_map_01.gd`

The NPC already supports errands and `walk_off_to()`. Add a temporary event behavior that can resume normal errands:

```gdscript
func attend_event(destination: Vector2, linger_seconds: float) -> void

func cancel_event_and_resume_errands() -> void
```

Suggested state:

```gdscript
var _event_active: bool = false
var _event_destination: Vector2 = Vector2.ZERO
var _event_linger_left: float = 0.0
```

Host owns selection and navigation. Clients only render the already replicated NPC positions.

### 9.4 Performance guard

Do not spawn more NPCs. Repath a capped number of existing NPCs and measure host frame time/network upload before enabling this by default.

If everyone follows one blob, always run two smaller simultaneous gatherings rather than one dominant event.

## 10. Priority 6 — Exterior route network

Exterior objectives work best when the route itself is interesting.

### 10.1 Intended route triangle

- **Center:** shortest and fastest, sparse/open, high identification risk.
- **Surface perimeter:** slower, more corners and crowd cover, contains Leads/caches.
- **Rooftop/sewer:** fast specialist rotation, but entry/exit creates strong tells and neither is a safe place to camp.

### 10.2 Suggested Citadel topology

- West sewer connects NW ↔ SW exterior districts.
- East sewer connects NE ↔ SE exterior districts.
- North rooftop route connects NW ↔ NE.
- South rooftop route connects SW ↔ SE.
- Rooftops include selected one-way drops into risky interior plazas/alleys.
- Avoid diagonal tunnels directly connecting opposite corners through the center; they would become mandatory highways.

### 10.3 Suggested traversal rules

#### Sewer

- Entry channel: approximately 0.8 seconds.
- Exit channel: approximately 0.8 seconds.
- Audible tell within approximately 450 px at both ends.
- Target arrow underground is stale/four-way at best; never perfect prey direction.
- Player kills remain legal underground.
- No NPC crowd cover.
- No committed-exposure recovery underground.
- After approximately six seconds of loitering, add recoverable lurk heat at roughly six points/second.
- Entrances need more than one nearby escape decision.

#### Rooftop

- Entry channel: approximately 0.7 seconds.
- Visible/audible climb tell.
- No NPC crowd cover on the roof.
- Roof geometry is a real connected route, not the entire surface network while invisible.
- Rooftop players can see/threaten other rooftop players.
- One-way drops create commitment and predictable landing areas.
- Remove permanent match-long access claims.
- Use approximately 8–12 second access cooldowns or short breakable locks.

### 10.4 Implementation dependency

Do not assign diagonal cross-map Leads until at least one exterior route network makes avoiding the center a rational travel choice.

## 11. Experimental 1v1 alternative — Cat-and-Mouse Set

Build only if immediate-live Intel Duel still feels like ordinary symmetric deathmatch.

### Rules

- One player is the lethal hunter for 35 seconds.
- The quarry can counter-stun but cannot kill during that phase.
- Hunter kill: two points and immediate role swap after respawn.
- Successful quarry counter-stun: one point and immediate role swap.
- Quarry survives the full phase: one point and role swap.
- First to seven points.
- Expected match length: approximately 3–4 minutes.
- Hunter receives information-focused exterior Leads.
- Quarry receives utility/route-focused exterior opportunities in different districts.

This restores genuine role asymmetry in a player count where the normal two-player target ring necessarily makes both players each other's prey.

Keep it behind `cat_and_mouse_duel_enabled`; do not replace Intel Duel without direct playtest evidence.

## 12. Additional ideas for later experiments

### 12.1 Moving courier

- One or two courier NPCs travel the exterior loop.
- The assigned player must match their walking pace/remain nearby for approximately three seconds.
- Completion grants a utility item or Trace.
- The courier never needs to be killed.
- Best for testing social-stealth interaction while moving rather than stationary channels.

### 12.2 Smuggler gate

- Exterior interaction opens a sewer/roof shortcut for approximately 20 seconds.
- Everyone can use the route, including enemies.
- Activation produces a local bell/grate tell.
- Power is bought with the risk of helping an opponent.

### 12.3 False trail

- Player plants a signal at an exterior socket.
- Their hunter's next **below-50** snapshot points to that socket.
- It cannot override real 50+ exposed tracking.
- Use adds the normal +25 committed exposure.

### 12.4 Two-stage cipher/courier contract

- Personal pickup at one exterior district.
- Optional delivery to the adjacent clockwise/counterclockwise district.
- Never diagonal.
- Pickup channel approximately two seconds.
- Handoff approximately 1.5 seconds.
- Package creates a subtle nearby tell every 7–9 seconds.
- Reward is Trace, utility, or temporary route access—not score.
- Job expires after approximately 45 seconds with no penalty.

This is lower priority because it is the idea most likely to feel like a fetch quest.

### 12.5 Map-specific single-use items

- Limited smoke, decoy, trap, listening device, or false-trail item at exterior props.
- Never grant raw damage or an unavoidable kill.
- Item use adds +25 committed exposure.
- Map-specific pools support the decision to couple modes and maps for balance.

## 13. Systems that should not be added

- Mandatory survival needs like hunger, sleep, or bathroom meters. They create circulation in *The Ship* but would become chores in a 3–5 minute round.
- One globally shared corner objective for all players.
- Large score rewards for optional objectives.
- Exposure cleansing at exterior stations; it would undermine the +25 action economy.
- Permanent upgrades or permanent access ownership.
- Lethal gadget regeneration.
- Channels significantly longer than three seconds in the first prototype.
- Fixed objectives inside single-exit dead ends.
- Exact world-position reveals below 50 exposure.
- World drops from dead Lead carriers; these would pull traffic back toward kill sites and the center.
- More than one new objective family enabled during the first evaluation block.

## 14. UI and presentation requirements

Keep the HUD light. Exterior systems should not add another large panel.

Needed UI:

- Small owner-only edge/district marker for offered Lead choices.
- Context prompt: `Hold Interact — Query Lead`.
- Small circular or horizontal channel progress display.
- Clear cancellation feedback without a modal message.
- Short result log:
  - `TRACE ACQUIRED — target last seen in West Market`;
  - `TRAIL ALREADY HOT`;
  - `YOUR TRAIL WAS QUERIED FROM THE EAST SHRINE`.
- Temporary Trace icon/timer near the existing target/arrow information.
- Cache prompt and restored-slot confirmation.
- Crowd-event announcement using world sound/animation rather than a full-screen banner.

Accessibility:

- Do not rely on color alone; district icons need shape/text.
- Every local audio tell needs a visual counterpart.
- Interaction prompts must support keyboard and controller input actions.

## 15. Telemetry and playtest metrics

Record server-authoritative events for every test round:

```text
lead_offered
lead_channel_started
lead_channel_cancelled(reason)
lead_completed
trace_granted
trail_warning_sent
cache_channel_started/completed
crowd_event_started/ended
player_entered_district
player_entered_center
player_killed(position, district)
```

First-pass targets:

- Median first player contact: 15–25 seconds.
- Median first kill: 25–45 seconds.
- At least 35% of player kills outside the central third.
- Players spend no more than approximately 45–50% of aggregate alive time in the central third.
- Approximately 35–65% of players use at least one Lead.
- If more than 75–80% always use every Lead, the system is mandatory and must be weakened or made riskier.
- If fewer than 25–30% use one, the reward is too weak, the detour is too long, or baseline arrows are too informative.
- A completed Lead should create a total detour of approximately 12–20 seconds including travel and channel.
- Fewer than 10% of rounds end with a player never seeing their prey.
- Track deaths during/within five seconds of a channel.
- Track how long players camp near sockets without having an active offer.
- Track whether leaders use optional objectives disproportionately; a strong leader snowball means the reward is too vertical.
- Track opening-route repetition among experienced players; one solved opener means assignment/socket selection needs more variation.

Use a map heatmap split into center plus outer districts. The purpose of the experiment is movement distribution, so kill counts alone are insufficient.

## 16. Failure interpretation

### Everyone still crosses the center

Possible causes:

- Opposite/diagonal assignments.
- Center route is much faster than perimeter.
- Hunt arrow still updates too frequently.
- Outer streets lack NPC cover or alternate approaches.
- Exterior reward is collected, but the return route still points straight through center.

Fix route topology and tracking before increasing rewards.

### Everyone camps a Lead socket

Possible causes:

- Offers are public or predictable.
- Too few socket locations.
- Socket is a single-exit pocket.
- Reward is strong enough to make interception mandatory.

Use private two-choice offers, larger socket pools, and alternate exits. Do not make channels safe or invisible.

### Nobody uses Leads

Possible causes:

- Existing arrows already provide enough information.
- Travel plus channel exceeds roughly 20 seconds.
- +25 exposure is too expensive relative to Trace duration.
- Warning gives the prey too much benefit.

First tune Trace duration/precision and socket placement. Do not add score.

### Leads become mandatory

Possible causes:

- Baseline tracking is too weak.
- Trace lasts too long.
- Warning is too vague.
- The same optimal Lead exists at match start.

Delay/reduce offers or improve baseline snapshots. Optional means a good player can ignore the system and still win through reads and routing.

### 1v1 stalls without NPC marks

Possible fixes, in order:

1. Shorten Compact snapshot interval.
2. Increase Lead availability slightly.
3. Add a shrinking final-minute pulse interval.
4. Add one optional moving informant.
5. Test Cat-and-Mouse roles.

Do not immediately restore two mandatory NPC kills.

## 17. Dependency-ordered implementation plan

### Slice A — Arrow behavior only

Files:

- `scripts/exposure_arrow.gd`
- `scripts/online_match.gd` integration only
- `scripts/game_mode_flags.gd`

Work:

- Add snapshot tracking.
- Add map-specific configuration values.
- Confirm 50+ transition.
- Test Citadel and Compact without any objectives.

Exit test:

- Arrows no longer behave as live sub-50 GPS.
- Rounds do not stall excessively.

### Slice B — Lead vertical slice

Files:

- new opportunity scripts;
- minimal `online_match.gd` wiring;
- placeholder socket visuals;
- Match HUD prompt/log support.

Work:

- Four temporary Citadel sockets first, then expand to eight.
- One offer and one completion maximum for the first test.
- Host channel validation.
- +25 exposure.
- Trace and reciprocal warning.
- No caches/crowd events yet.

Exit test:

- Two-instance online test passes.
- No invalid completion, duplicate exposure, stale offer, or identity leak.
- Players sometimes choose the Lead and sometimes ignore it.

### Slice C — Full Citadel Lead rotation

- Eight sockets.
- Two-choice adjacent-district assignment.
- Maximum two completions.
- Second-offer cooldown/district exclusion.
- Telemetry and district heatmap.

Exit test:

- At least 35% of kills occur outside the central third in the test block.

### Slice D — Compact Intel Duel

- Disable marks gate only under its feature flag.
- Immediate PvP.
- 210-second timer.
- Three-kill goal.
- Compact snapshot intervals.
- Compact Lead schedule.

Exit test:

- Faster than the marks duel without turning into constant spawn rushing.

### Slice E — One secondary exterior system

Choose only one based on playtest evidence:

- If players need more resources: utility caches.
- If exterior travel is too exposed: rotating markets/processions.
- If the perimeter is still slower/empty: implement real sewer/roof routes.

Do not enable all three simultaneously for the first evaluation.

### Slice F — Data extraction

After the mechanics are fun:

- Move map-mode tuning into typed resources.
- `CitadelHuntCycleRules` owns its Lead schedule, exposure thresholds, tracking intervals, sockets, and crowd events.
- `CompactIntelDuelRules` owns its timer, kill goal, tracking intervals, and Lead schedule.
- Remove direct map comparisons from generic gameplay components.

## 18. Exact first recommended build

For the smallest useful implementation, build only this:

1. Snapshot arrows below 50 exposure.
2. Four placeholder Lead sockets on Citadel's exterior.
3. One private two-choice Lead offer per player at 15 seconds.
4. Adjacent districts only.
5. 2.75-second host-validated stationary channel.
6. +25 committed exposure on completion.
7. Ten-second improved target snapshot.
8. One-second delayed prey warning naming the source district.
9. Zero objective score.
10. One Lead maximum per player for the test.
11. Match event logging and a center-versus-exterior heatmap.

Do not build caches, crowd events, courier delivery, or Cat-and-Mouse until that slice demonstrates better map circulation.

## 19. Genre references and lessons

- [Murderous Pursuits](https://store.steampowered.com/app/638070/Murderous_Pursuits/) combines quarry tracking, exposure, abilities, and detours for higher-value weapons. Borrow optional detours, not direct lethal superiority.
- [SpyParty's developer-authored manual](https://cdn.spyparty.com/wp-content/uploads/2011/03/SpyParty-Manual.pdf) describes missions performed at social props with hard, soft, or behavioral tells. This is the model for contextual opportunity interactions that NPCs also perform.
- [The Ship](https://store.steampowered.com/app/2420/The_Ship_Single_Player/) forces movement through character needs. Mandatory needs are too chore-like here; borrow short vulnerable interactions instead.
- [Deceive Inc. Operations](https://wiki.deceiveinc.com/index.php?title=Operations) use distributed terminals to move players through a map before convergence. UNSEEN should use one quick optional interaction rather than a long mandatory objective chain.
- [Hunt: Showdown's developer survey](https://www.huntshowdown.com/news/developer-insight-devil-s-trail-survey-results) notes that scouting-point placement moved fights toward unintended areas when points clustered on one side. Use multiple balanced/private sockets and validate movement with heatmaps.

## 20. Final design rule

Exterior objectives should improve the hunt rather than compete with it:

> Cut through the center for speed and risk being read, or take the exterior route to buy information while exposing your own action.

If the optimal choice is always to collect the objective, it is mandatory busywork. If the optimal choice is always to ignore it, it is decoration. The desired result is a decision that changes with prey exposure, hunter pressure, gadget state, map knowledge, and the remaining round time.
