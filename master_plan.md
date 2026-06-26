# UNSEEN — GAME MECHANICS
### Master design reference for all gameplay systems

> **Purpose:** This file is the single source of truth for *what the game is and how it plays* — every mechanic, rule, and design decision we've settled on. It pairs with `UNSEEN_BUILD_PLAN.md` (which covers *how and when to build*). When implementing any system, read the relevant section here for intent, then check the build plan for sequencing. Where a value is "tunable," it must be an `@export` variable, not a hardcoded number.

---

## 1. THE CORE FANTASY

You are an assassin hidden in a living crowd. You are indistinguishable from dozens of AI civilians. You move through an open map completing a contract — kill assigned marks, then hunt a real human target — while another human hunts you. The tension comes from the fact that **acting draws attention**: every objective forces you out of safety, and the player who manages exposure best while completing their contract fastest and cleanest wins.

Genre lineage: the crowd-blend loop of *Hidden in Plain Sight*, the hunt-and-be-hunted fantasy of *Assassin's Creed Brotherhood* multiplayer, the format of *Murderous Pursuits* — but online, on open maps, with map-control resources and a PvE-into-PvP objective structure none of them had.

---

## 2. THE PLAYER

- Top-down 2D character, **visually identical to every NPC and every other player**. Sameness is the whole game — no player is ever visually marked to opponents.
- Controlled with twin-stick-style movement (analog stick or WASD). Controller-first design.
- Two movement modes:
  - **Blend-walk** (default): slow, calm movement that matches NPC walking speed exactly. Keeps exposure low. This is how you disappear — and it's your *default* state, so you're blended unless you choose otherwise.
  - **Run** (hold): faster than any NPC. Covers ground but spikes exposure — running is the single most exposing thing you can do, so it's a deliberate held action, not the default. (Control scheme: walk is default, hold the run button to sprint.)
- Has: an **exposure** value, a limited **tools** resource, a **contract** (objective list), and an assigned **target**.

---

## 3. EXPOSURE — THE CORE TENSION SYSTEM

Exposure is the heartbeat of the game. A 0–100 value representing how much you stand out.

**Exposure has TWO parts (v0.6 design decision):**
- **Movement exposure — RECOVERABLE.** Running and erratic movement build it; **blend-walking and standing still bring it back down.** This is the heat of moving fast, and you cool it off by moving like a civilian. So a sprint is not a life sentence — calm down and it fades.
- **Committed exposure — PERMANENT.** Kills and tools add to a *floor* your total can **never** fall below for the rest of the round, no matter how much you walk. This is what makes using a tool or taking a kill a hard, lasting decision that locks you into less flexibility.

Your total exposure = movement + committed (clamped 0–100). You can always recover from running; you can never walk off a kill or a spent tool.

**What raises exposure (tunable rates):**
- Running — the largest and fastest source (movement part).
- Erratic/sharp movement, sudden direction changes (movement part).
- Performing a kill — a permanent spike to the committed floor (see §6).
- Using tools/abilities (e.g. securing a passage emits a tell) — a permanent commitment.
- Being alone in open, low-crowd space.

**What lowers exposure:**
- Blend-walking at crowd speed → bleeds the movement part down (the main recovery).
- Standing still → bleeds the movement part down slowly.
- **Nothing lowers the committed floor** — walking recovers your running heat but never your kill/tool commitments.
- Being in a dense NPC cluster → great *cover* (blocks sightlines, hides you among bodies — §4/§5), but it is **not** an exposure discount. Hiding protects you from being *found*, not from the exposure you've already spent.

**What exposure does:**
- Drives how quickly hunters can detect and "lock" you (see §5). Low exposure = effectively invisible in the crowd. High exposure = a beacon.
- It is **not** a literal visibility toggle — it's a probability/speed modifier on being identified. A skilled player keeps it low by *acting sparingly*.

**The intended exposure arc (core pacing model):** because exposure only accumulates, the round naturally goes from quiet to loud. The arc is: **everyone starts hidden in the crowd → exposure accumulates across the round → by the endgame everyone is exposed to varying degrees**, converging on a tense, everyone-visible PvP climax like the AC Brotherhood / Rearmed endgame. This means:
- The arrow threshold should effectively **tighten over the round** (threshold falls, and/or a rising exposure floor) to actively push toward confrontation and prevent stalls. The early game rewards stealth; the late game forces the hunt.
- By the time players are hunting *each other* (the PvP phase), most will already be exposed — **unless they were very careful**, which is the reward for discipline. A flawless player can arrive at the PvP phase still hard to find; everyone else is paying for the actions that got them there.
- This arc is why the arrow threshold is a *curve to design*, not a knife-edge to balance — see Known Balance Risks (§15).

**Design rule:** Exposure must always be readable to the player (HUD meter, green→yellow→red) but never directly shown to opponents. Reading *behavior* — not a UI element — is how a hunter identifies a target.

### 3.1 The Exposure Arrow (high-exposure consequence)
When a player's exposure crosses a high threshold (tunable), other players begin to see a **directional arrow** on screen pointing toward that over-exposed assassin. This is the mechanism by which hunters locate prey on large open maps — it makes high exposure a consequence others can *act on*, directly reinforcing Pillar #2 (acting is exposing).

- The arrow points toward the exposed player's general direction, not an exact dot — it guides, it doesn't gift the kill.
- **Crucially, the arrow disappears the moment the exposed assassin is actually on the hunter's screen.** This is the elegant part: the ping gets you to the area, then it vanishes and says *"now find them in the crowd yourself."* The final identification is still a skill check — you must pick the player out of the civilians by reading behavior. The arrow never tells you *which figure* is the target, only roughly where to look.
- Higher exposure could widen who sees the arrow / sharpen its direction (tunable escalation), so a reckless, high-exposure player becomes findable by more hunters at once.
- This pairs with the detection system in §5: the arrow gets a hunter to the neighborhood; exposure-driven detection determines whether they can then lock you.

**Color-coded arrows (multi-player readability):** in lobbies with several players, each assassin's arrow is **color-coded** so hunters can differentiate threats at a distance ("the green assassin is over-exposed to the north; the orange one is east").
- **Guardrail — this must NOT break Pillar #1 (sameness is sacred).** The *arrow* carries the color; the *character it points to remains visually identical to every civilian and every other player.* The color tells you which assassin and roughly where — never which on-screen figure is them. When that player comes on-screen the arrow (and its color) vanishes, dropping you back into a pure read-the-crowd identification with no color assistance.
- **Open question (decide in playtest):** does color map to player identity (each player owns a fixed color all match), to *relationship* (e.g. one color for your assigned target, another for your hunter), or both? Relationship-based coloring may read more intuitively in a free-for-all contract web; test it.

---

## 4. THE CROWD (NPCs)

The crowd is the disguise, the cover, and the core technical challenge.

- 20–30+ NPC civilians per map, identical in appearance to players.
- **Natural wandering:** path to random points, pause, vary speed and timing slightly, cluster at points of interest (markets, fountains, performances). They must NOT look robotic or grid-aligned — believability is everything (this is what sank AC Rearmed).
- NPC movement speed = player **blend-walk** speed. This is the linchpin: a blend-walking player is mechanically identical to a civilian; a running player is obviously not.
- **No physical collision between actors and the crowd.** Players and NPCs pass *through* each other; only world geometry (walls) blocks movement. This is a deliberate design choice from AC Brotherhood/Rearmed multiplayer: the work of blending falls on the **player** (move like a civilian), not on the NPCs (physically behave like solid humans). Walking *through* a dense crowd is part of how you disappear, and it removes the friction/tell of snagging on a body. Reads are behavioral, never physical.
- **Crowd density zones:** areas designed to clump civilians (markets, plazas). Density is the best **cover** — it blocks sightlines and buries you among bodies so hunters can't pick you out (§5). It does **not** lower your exposure (nothing does, §3); it protects you from being *found*, not from spending exposure. Empty streets are where you stand out.
- NPCs are "innocents" — killing the wrong one (a civilian, not your mark) should carry a penalty (see §6), echoing the witness/penalty systems of the genre.

---

## 5. HUNTERS & DETECTION

Every player is simultaneously a hunter (of their target) and prey (of whoever is hunting them). In single-player/prototype phases, **bot hunters** stand in for humans.

**Detection model (tunable):**
- A hunter scans the crowd. The chance/speed of identifying a specific figure as their target scales with:
  - That target's current **exposure**.
  - **Proximity** and **line of sight**.
- On accumulating enough "suspicion," the hunter gets a **lock** and can pursue/attempt a kill.
- Behavioral tells matter: a figure that runs, moves erratically, or beelines toward objectives reads as a player, not a civilian. Good hunters read behavior; good prey deny them tells.

**Counterplay built in:** the prey can shed a lock by re-blending — dropping into a dense crowd, blend-walking, breaking line of sight. Nothing about being spotted is an automatic death; it starts a chase the prey can survive.

---

## 6. THE KILL

- **Assassination:** when within range of a *valid* target (your assigned mark or your assigned player target) and you trigger `action_primary`, a brief kill sequence plays (both actors briefly locked, short timer, success).
- **Kill consequence — exposure spike:** performing a kill spikes the killer's exposure for ~2–3s (tunable). You are momentarily obvious. This is the central risk/reward of acting — the moment you strike is the moment you're most vulnerable to *your* hunter.
- **Wrong-target penalty:** killing a civilian or a non-target player is punished (large exposure spike, score penalty, and/or temporary stun). You must be sure before you strike — this preserves the social-deduction tension and prevents spray-killing.
- **Server-authoritative:** kill validity is always confirmed by the authority (designed this way from day one for the online port). Clients never self-confirm a kill.

### 6.1 Death, elimination, and modes (no respawns)
- **No respawns.** A killed player is out for the round. This keeps kills meaningful and preserves the AC-Rearmed-style PvP climax (see §7/§12).
- **Casual mode:** elimination doesn't matter much — rounds are short, you re-queue. Death is low-stakes. (Decide in playtest what a dead player does meanwhile: spectate, quick post-death filler, or immediate re-queue — casual must not become dead time.)
- **Ranked mode:** you are scored on **performance, not just survival** — how well you played, how low your average exposure was, kill cleanliness, speed/placement, objectives completed. A run you died early in still earns a meaningful score, so elimination never feels like "you lose, go watch." **The ranked ladder is built on this scoring spine** (see §10) — it's a core long-term system, not an afterthought.

---

## 7. THE CONTRACT (OBJECTIVE STRUCTURE)

This PvE-into-PvP structure is our key answer to the genre's fatal flaw (fun for 10 hours, then shallow). It forces engagement and adds a skill layer.

1. **PvE phase — marks:** each player must reach **1–2 NPC "marks"** at specific, intentionally **exposed** locations on the map and eliminate them. Going for a mark forces you out of safe crowd cover — this is deliberate risk.
2. **PvP phase — the target:** after completing your marks, you're assigned a **real player target** to hunt — while you are simultaneously someone else's target.
3. **Win condition:** complete your full contract (marks + target) cleanest and fastest. Scoring rewards low average exposure and fast, clean kills (see §10).

The objective locations being risky creates the core loop rhythm: **dart out to do something dangerous, then slip back into the crowd through a route only you know.**

### 7.1 Speed reward — earned target pings (the aggression incentive)
This is the mechanic that makes an *aggressive* playstyle viable alongside a cautious one, resolving the central tension between "low exposure is king" and Pillar #5 (punish turtling).

- A player who **finishes their NPC marks first** (or among the first) earns **pings on their PvP target** — directional/locational intel on whom they're hunting, **without having to expose themselves to get it.**
- A slower player gets no free intel and must rely on the standard **arrow** system to find their target — which only triggers once that target is over-exposed, and often means wandering exposed themselves to locate them.
- **The strategic axis this creates:** going fast means exposing yourself a bit during the rush, but you're rewarded with a clean read on your target and initiative in the PvP phase. Going slow and careful keeps exposure low, but you surrender information and may get found anyway once forced into the open. **Both are viable; which is correct depends on the lobby and your read of it.** This is the core risk/reward decision of the macro game.

### 7.2 How you kill the mark matters (micro-decision per kill)
Killing an NPC mark is *mechanically easy* — the difficulty is the journey there and staying aware of other assassins en route. The interesting choice is **how** you do it:
- Use a **stealth tool** to take the mark quietly → lower exposure, but spends a limited resource.
- **Walk up and knife** it → free and fast, but a bigger exposure spike.
Every mark is therefore a small risk/budget decision, not a checklist tick.

---

## 8. MAP CONTROL & MAP KNOWLEDGE

The map is the skill ceiling. Veterans know things newcomers don't. This is where depth and replayability live, and where the level designer's work is as important as the code.

### 8.1 Secret passages
- Hidden routes connecting map areas, visually subtle (a dark gap, an unmarked door).
- **No resource cost** — pure map knowledge. Knowing they exist and where they lead *is* the advantage.
- Used for escapes (vanish from a hunter who's lost line of sight) and for reaching objectives unseen.
- Can be one-way (drop-downs/shortcuts) or two-way.

### 8.1a Single-occupancy underground / sub-level rule ("something lurks in the darkness")
Only **one player at a time** may occupy a given underground passage or non-ground-level space (tunnels, sub-levels, hidden rooms).
- If a second player tries to enter an occupied passage, entry is denied and they receive the message **"Something lurks in the darkness."**
- **Why it's good counterplay:** it prevents passages from becoming crowded safe-zones, and it leaks *information without identity* — the second player now knows *someone* is down there (a hunter? their prey? a rival?), but not who. That drives emergent decisions: wait them out, guard the exit, or move on.
- **Open design question (decide in playtest):** is the player *inside* the passage notified that someone tried to enter?
  - *Option A — lurker is warned:* symmetric tension; the hider knows they've been "knocked on" and may bolt.
  - *Option B — lurker is unaware:* asymmetric; the entrant gains private intel the occupant doesn't have.
  Default to **Option B** (entrant gets private info) for the first prototype — intel asymmetry rewards map awareness — and test whether warning the lurker (Option A) is more fun.
- Must obey Pillar #4: the occupant isn't *safe* — the exits can be watched, and the single-occupancy rule means a hunter can deny them the passage entirely by sitting in it first.

### 8.2 Trapdoors
- A node you enter to teleport to a linked exit — a fast escape or repositioning tool.
- **Tell on use:** using a trapdoor briefly breaks blend / emits a subtle local cue. A hunter who *sees* you use one now knows you're a player and roughly where you went. Using it is powerful but not free of risk.
- Can also be used offensively — lure a target over/through map features.

### 8.3 Crowd-density zones
- Designed clusters (markets, plazas, performances) where civilians gather. Best cover, fastest exposure bleed. Smart players route through density; the map rewards knowing where the crowds are.

### 8.4 Choke points, one-way shortcuts, sound tells
- Narrow streets vs open plazas create natural risk gradients.
- One-way drops create directional flow and escape options.
- Some map features emit sound when used (creaky floor, knocked cart) that pings nearby players — turning the map into a field of potential tells.

### 8.5 Teleports (fast repositioning with an exposure cost)
Fixed teleport pads placed around the map let players reposition quickly — designed for the moment **two players spot each other and someone wants to break the standoff** by relocating instead of committing to a fight.

- **Cost:** using a teleport **raises exposure** (tunable) — obeying Pillar #2. A reckless, already-exposed player who teleports just relights themselves elsewhere (likely triggering an arrow at the destination), so escape is never clean for the people who most want it.
- **The low-exposure reward — earned free teleport:** if you've been **cautious** (kept exposure low, killed your NPC marks cleanly), the exposure bump from a teleport stays **below the arrow threshold** — effectively a *free* reposition. This makes the exposure economy *pay out*: careful play banks a repositioning/escape option as a positive reward, not just the absence of punishment. Reckless play forfeits it. This is the key design value of the mechanic — it gives players a reason to play clean beyond avoidance.
- **Self-balancing logic:** the players who most need to flee (aggressive, high-exposure hunters) pay the most to teleport and get flagged on arrival; the careful players who teleport free are the ones who least need to escape. The reward lands where it doesn't break the hunt.
- **Guardrails (so it's a tool, not a panic button — Pillar #4):**
  - **Fixed pads**, not teleport-from-anywhere — you must reach a pad, which costs time and positioning.
  - **Cast time that scales with exposure (tunable):** activating a teleport roots you for a channel time that grows with your current exposure. A clean (low-exposure) player teleports almost instantly; a reckless (high-exposure) player is rooted for the full duration (~15s ceiling) exactly when hunters are converging on their arrow. You can't simply sprint to a pad and vanish — the more you needed the escape, the longer you're a sitting duck to reach it.
  - **Cooldown** per player (tunable) so it can't be spammed mid-chase.
  - **Interruptible:** taking damage / being attacked mid-channel cancels the teleport (this also distinguishes it from the Bomber's *uninterruptible* charge so the two stationary-commit mechanics don't feel redundant).
  - Destinations are **known/fixed pads**, so a hunter can learn them and stake out exits — a teleport escape can be predicted and countered.
  - Optionally: a brief tell at the **destination pad** on arrival (a shimmer/sound) so teleporting isn't a silent vanish.

**Design rule for all map mechanics — every advantage has a counter.** A secured passage can be broken; a trapdoor used in sight betrays you; a hiding spot can be checked. If a feature grants guaranteed, counter-less safety, it's wrong and must be softened. This is the rule that keeps the game fun past 200 hours instead of solved in 10.

---

## 9. THE TOOLS RESOURCE (MAP-CONTROL ECONOMY)

A **limited, consumable** resource that powers map control. The economy is built to *reward action, not turtling*.

- Each player has a small fixed number of **tools** per round (tunable, e.g. 3), and/or can pick more up at risky map locations (grabbing them exposes you).
- **It is consumable, not a regenerating mana pool.** Deliberately so — a regenerating pool would reward passive camping/waiting, which is poison in a hunt game. Once tools are spent, they're gone (until you risk grabbing more).
- **Primary use — secure a passage/trapdoor:** spend 1 tool to make a passage/door usable only by you, for a **short, tunable duration**. Securing **emits a subtle tell** to nearby actors (counterplay).
- **Counter to securing:** a hunter who witnessed the secure can spend their *own* tool to **break the lock** — turning your defensive play into a resource duel rather than an "I win" button. (No guaranteed, counter-less safety — see §8 rule.)
- **Optional offensive uses** (design space to expand): traps, temporary blocks, distractions. Each must obey the "rewards engagement" principle.

**Tradeoff that keeps players aggressive:** in a future scoring/economy tie-in, spending tools on defense should cost progress toward winning, so the cautious player who locks everything down falls *behind*. We reward productive risk, the inverse of what made *Murderous Pursuits* feel timid.

---

## 9A. CLASSES / KITS (ASYMMETRIC ASSASSIN ARCHETYPES)

> **CRITICAL SEQUENCING — DO NOT BUILD UNTIL AFTER THE PHASE 4 FUN TEST.** Asymmetric classes are the single hardest thing to balance in competitive multiplayer and they multiply testing/tuning work per class. Prototype the *entire* game with ONE shared kit first (the base assassin: blend-walk + melee kill). Prove the core loop is fun with two humans + bots. Only then layer classes on as the depth/replayability system. Building four asymmetric kits before the base loop is proven is building on sand.

**The shared balancing currency:** every class is balanced on **commitment vs. vulnerability** — more kill power must be bought with a larger window of exposure, a delay, a tell, or a positional constraint. Every kit must obey **Pillar #2 (acting is exposing)** and **Pillar #4 (every advantage has a counter)**. If a kit can kill with no exploitable window, it's broken by definition.

Planned starting classes (all tunable, all subject to playtest revision):

### Bomber
- **Ability:** plant/charge a mini explosive to kill a target from a distance.
- **Cost / counter:** requires **20–30s standing still** to arm/detonate — an enormous stationary commitment that makes the Bomber a sitting duck during the charge. Self-balancing: the payoff (ranged kill) is paid for by the longest vulnerability window in the game. Standing still also reads as suspicious to nearby hunters and likely raises exposure during the charge.
- **Hard counter:** catch them mid-charge; the long window is the entire balance.

### Poisoner
- **Ability:** attach a poison to a target in melee range; the target goes down ~2 minutes later (tunable delay).
- **Cost / counter:** **applying poison raises the Poisoner's exposure immediately** — the deniability is gone. They light up the moment they act, and at some point in the 2-minute window they'll likely cross the arrow threshold and become huntable *before* their kill even lands. So the Poisoner isn't sidestepping the core risk/reward — it's a *different shape* of it: exposed now, payoff later, vulnerable in between. Still must close to melee like the base assassin (no ranged safety).
- **Design note:** because exposure-on-application is the counter, tune the exposure cost so the Poisoner is genuinely findable during the delay. The kit should feel like "I've committed and now I have to survive until it lands," not "free deniable kill."

### Crossbow
- **Ability:** fire a bolt to kill from medium range. **One bolt per round, maximum** — a single precious, committed shot, not a sniping playstyle.
- **Cost / counter:** needs **line of sight and a committed aim**; range is **short-to-medium only** (you must still work into the crowd — it does not skip the "get close" premise); the **bolt is a visible, loud tell** (others can see it fly and trace its origin); and firing **spikes exposure hard**. The one-shot limit means a miss is catastrophic — you've spent your kit and lit yourself up.
- **Hard counter:** break line of sight; the shot reveals the shooter's position to everyone nearby, and they have nothing left after it.

### Trapper
- **Ability:** place booby traps on map features — trapdoors, passages, choke points.
- **Cost / counter:** indirect/area-denial rather than direct killing — naturally weaker at securing a specific target, stronger at controlling space. Traps should be **detectable/disarmable** (a tell, a counter-tool, or a skill check) so they're not invisible instant-death. Plays directly off the existing map-control systems (§8/§9).
- **Hard counter:** spot and disarm; traps telegraph; limited trap count.

**Cross-class rules to enforce:**
- Class is chosen pre-round (or per-loadout); all classes remain visually identical to crowd and each other — **a class is never visible to opponents** (Pillar #1). You can't tell a Bomber from a civilian by looking.
- Every class still has the base blend/exposure/kill loop; the kit *adds* one signature option, it doesn't replace the fundamentals.
- Balance target: no class should have a kill method without a clear, learnable window the prey can exploit. The fun is in reading *which* kit is hunting you from *how* the threat manifests.

---

## 10. SCORING & WIN CONDITION

- Round ends when a player completes their full contract, or via other end states (all targets resolved / timer).
- Score rewards:
  - **Low average exposure** across the round (you played like a ghost).
  - **Fast kills** (efficiency).
  - **Clean kills** (no civilian/wrong-target penalties).
- Penalties: wrong-target kills, prolonged high exposure, getting killed.
- The intent: the winner is the most *invisible and efficient* assassin, not the twitchiest — keeping the skill on the social/stealth mind game.

---

## 11. MATCH STRUCTURE

- Small player counts (target ~4–8 humans per match) plus the NPC crowd. Small counts keep lobbies fillable and suit the format.
- Free-for-all contract web (everyone hunts someone, everyone is hunted) is the default mode, mirroring AC Brotherhood/Murderous Pursuits.
- Round-based, relatively short matches that produce clip-able moments (a perfect crowd-blend kill, a last-second trapdoor escape) — important for organic/viral growth.

---

## 12. PRESENTATION & FAIRNESS (why 2D top-down)

- **True 2D top-down** is the chosen perspective for **competitive fairness and readability**: identical sightlines for everyone, no camera-angle advantage, no height/parallax exploits, flawless performance on weak hardware, and a bigger player pool across platforms.
- The camera does **not** give players controllable advantage. (If we ever move to 2.5D, lock the camera at a fixed isometric angle to preserve fairness — but 2D is the default and the competitively superior choice.)
- Logic is kept separate from visuals so the art layer can be upgraded (2D → 2.5D) later without touching gameplay.

---

## 13. PLATFORM & INPUT INTENT

- **Controller-first** from day one (analog movement, single-button actions) — this improves the design even for mouse/keyboard and is required for the console/mobile roadmap.
- Abstract input actions only; every action bound to gamepad AND keyboard. No hardcoded keys anywhere.
- Roadmap: PC (Steam) first → console → mobile (mobile only if touch controls can serve the precision the kill/blend loop needs).

---

## 15. KNOWN BALANCE RISKS & OPEN QUESTIONS

A living list of things to watch when playtesting starts. Most can only be resolved by real play (Phase 4 fun test onward). Don't pre-solve these on paper — track them.

**Resolved in design (verify in playtest):**
- *Poisoner deniability* → fixed by exposure-on-application (§9A). Verify the poisoner is actually findable during the delay.
- *Crossbow as sniper* → fixed by one-bolt-max + short/medium range + loud tell (§9A). Verify range doesn't skip the "get close" premise.
- *Aggression vs. caution* → resolved by speed-reward target pings (§7.1). Verify both playstyles stay viable and neither dominates.
- *Elimination = dead time* → resolved by no-respawn + ranked performance scoring (§6.1, §10). Verify casual death doesn't feel like punishment with nothing to do.
- *Teleport as panic button* → fixed by exposure-scaled cast time + interruptible + fixed pads + cooldown (§8.5).

**Still open / watch closely:**
- **The arrow threshold is the most important number in the game.** Several systems are defined relative to it (free teleport, exposure arc, finding anyone at all). Treat it as a *curve over the round* (§3.1, §3 arc), likely tightening toward the endgame. Expect heavy tuning.
- **Trapper may be underpowered.** Three kits get a direct kill; the Trapper gets area denial that smart players route around. Watch whether it feels bad to play; may need cheaper/plentiful traps, active baiting/herding, or a more reliable payoff.
- **Wrong-target penalty vs. passivity.** If the penalty (§6) is too harsh against a perfect-disguise crowd, the safe play is to never commit and rounds go passive (the casual-scale failure that hurt SpyParty). Calibrate so being *mostly* sure is still worth a swing.
- **Low-exposure stacking.** Cautious play is rewarded by detection avoidance *and* free/fast teleports *and* (if careful enough) arriving at PvP still hidden. Confirm there's a real cost to turtling and that the §7.1 speed reward is a strong enough pull the other way. This is the central balance tension of the whole design — hold it consciously.
- **NPC mark tension comes only from location + awareness.** The kill is easy by design (§7.2); make sure map design actually places marks in exposed spots, or the PvE phase goes limp.
- **Dead-player experience** (casual): spectate vs. filler vs. instant re-queue — undecided (§6.1).
- **Arrow color mapping:** identity-based vs. relationship-based (target/hunter) — undecided (§3.1).
- **Single-occupancy passage:** is the occupant warned someone tried to enter? Default no; test yes (§8.1a).

---

## 16. THE DESIGN PILLARS (the non-negotiables)

If a future feature conflicts with one of these, the feature is wrong:

1. **Sameness is sacred.** Players and NPCs are visually identical; you are read by behavior, never by a marker.
2. **Acting is exposing.** Every meaningful action (objectives, kills, securing) costs safety. Tension comes from being forced to act.
3. **The map is the skill.** Knowledge of passages, density, and routes separates good players from new ones. Depth lives here.
4. **Every advantage has a counter.** No guaranteed, counter-less safety. This is the anti-staleness rule.
5. **Reward engagement, punish turtling.** Resources and scoring push players toward productive risk, not camping.
6. **Readability is fairness.** 2D top-down, identical sightlines, no camera or hardware edge. The mind game is the only skill that should decide matches.
7. **Power is bought with vulnerability.** Every class ability and special action trades kill power for a window, delay, tell, or constraint the prey can exploit. No counter-less kill method exists.

---

*Mechanics reference v0.4 — June 2026. Pairs with UNSEEN_BUILD_PLAN.md.*
*v0.2: exposure arrow (§3.1), single-occupancy passages (§8.1a), asymmetric classes (§9A).*
*v0.3: color-coded arrows + sameness guardrail (§3.1), teleport pads + free-teleport reward (§8.5).*
*v0.4: intended exposure arc / pacing model (§3), death + casual/ranked rules, no respawns (§6.1), speed-reward target pings (§7.1), how-you-kill micro-decision (§7.2), Poisoner & Crossbow rebalanced (§9A), exposure-scaled teleport cast time (§8.5), Known Balance Risks (§15).*
