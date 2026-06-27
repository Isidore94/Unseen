# UNSEEN — PHASE 8 → MAIN INTEGRATION GUIDE (for the VS Code Claude)

> **Naming note.** This file is called *Phase 9 integration* because Phase 9 (the experiments) is the
> newest work, but what it actually instructs is the **slow, staged integration of the entire Phase 8
> branch into `main`** — and that branch now contains three layers stacked in order: Phase 8 cosmetics
> → the §0.3 per-viewer appearance pillar → the Phase 9 experiments. Treat "integrate Phase 8" as
> "integrate everything on this branch that isn't already on main."

---

## 0. Who this is for, and the one advantage you have

You are the **VS Code Claude**, running on Aaron's Windows machine **with Godot 4.7 installed and the
project openable**. The author of this branch (a cloud session) could **not** run Godot — so nothing on
this branch has been compile-checked or runtime-tested. **That is your job and your advantage.** Every
stage below has a *compile gate* (`tools/validate.sh`) and a *runtime gate* (launch + host/client test)
that the cloud author could not perform. Do not skip them.

Aaron is a **solo, brand-new coder** (see `CLAUDE.md`). Explain what you're doing in plain language as
you go, give him exact Godot-editor steps to confirm each stage, and **wait for his confirmation before
moving to the next stage.** Integration is not a single button — it's a sequence of small, verified steps.

---

## 1. HARD PREREQUISITE — Phase 7 online must be on `main` first

**Do not begin until the Phase 7 online integration branch is fully merged into `main` and verified.**
This branch was built *on top of* the Phase 7 online work, so integrating it before Phase 7 lands would
drag Phase 7 commits in unverified and tangle the history.

Confirm Phase 7 is on main before doing anything else:

```bash
git fetch origin
git checkout main && git pull
# These Phase 7 ONLINE commits must already be reachable from main:
git merge-base --is-ancestor 786779f main && echo "OK: 7-port on main"     # port layers/visibility/claim/items/reveals
git merge-base --is-ancestor 9064b10 main && echo "OK: 7-verify on main"   # smoke/claim authority fixes
git merge-base --is-ancestor b280b4a main && echo "OK: 7-4player on main"  # up-to-4-player, v0.7.1
```

If any line does **not** print OK, stop and tell Aaron Phase 7 isn't fully in yet. Integrating now is unsafe.

---

## 2. What's on this branch (the integration payload)

Branch: **`claude/post-integration-checklist-ig0la4`**. Everything from after the Phase 7 tip up to HEAD
is what you're bringing in. Three layers, in dependency order:

1. **Pre-cosmetic prep**
   - `620c23e` offline = single-player only (split-screen co-op retired)
   - `9b464c0` `tools/validate.sh` — the headless compile-checker you'll lean on at every gate
2. **Phase 8 — cosmetic & identity foundation (plumbing only; no shop/currency)** — `7600f5b … ae1a248`
   - `CharacterVisual` 4-layer rig + `apply_loadout`; `CosmeticItem`/`Loadout`/`CosmeticRegistry`;
     NPC crowd on the shared rig; loadout network replication (ids only); animation hooks + kill_card
     stub; `PlayerProfile`; `CosmeticInventory` (ownership-gated equip). See `COSMETIC_SYSTEM_SPEC.md`.
3. **§0.3 per-viewer appearance pillar** — `d4cabd0`
   - On each screen the crowd is rebuilt from copies of the OTHER players' looks + filler, with your own
     look excluded. Adds `placeholder_distinct_bodies` (a test aid, ON) so it's visible before real art.
4. **Phase 9 — endgame & commitment EXPERIMENTS (all OFF by default)** — `48a9746`
   - `ExperimentFlags` autoload, a folder-scan loader, `behavior_history` infra, six experiments under
     `scripts/experiments/`, plus neutral core hooks. See `PHASE_9_EXPERIMENTS.md`.

**Discover the exact delta against your main (don't trust the list above blindly):**

```bash
git log --oneline --no-merges main..claude/post-integration-checklist-ig0la4
git diff --stat main..claude/post-integration-checklist-ig0la4
```

---

## 3. Golden rules for the whole integration (read once)

1. **`tools/validate.sh` must pass before every commit.** It's the compile gate the author couldn't run:
   ```bash
   tools/validate.sh    # exit 0 = all scripts compile; it filters autoload false-positives itself
   ```
2. **Flags-off means the base game is unchanged.** After Stage 4, with every `ExperimentFlags` bool
   `false` (their default), the game must behave exactly as it did at the end of Stage 3. This is the
   spec's *delete test* (`PHASE_9_EXPERIMENTS.md` §1.4) and your strongest safety net — verify it.
3. **Server-authoritative is law** (`CLAUDE.md` §5 / `buildplan.md` §0). Every behaviour you verify
   online: the host owns the outcome, clients send intent only, and **no data that reveals which
   character is human** is ever sent except the deliberate reveals.
4. **Test online, two instances.** Host one instance, connect a second as a `127.0.0.1` client. One
   screen can't prove the hidden-identity invariants — two can.
5. **Keep `main` releasable at every gate.** Integrate onto a scratch branch, verify, *then* advance main.
6. **Do not commit any experiment flag set to `true`.** Experiments ship OFF; you flip them on only in a
   local, uncommitted playtest session (Stage 5).

---

## 4. The integration mechanism (slow = staged gates, not one big merge)

Because the history is linear on top of Phase 7, a single merge *would* technically work — but "slowly"
means **stop and verify at each layer**. Use cherry-pick groups onto an integration branch so each layer
is its own verified commit range and any failure is isolated.

```bash
git checkout main && git pull
git checkout -b integrate/phase-8        # the scratch branch you'll verify on; main stays untouched
```

Each stage below = cherry-pick that stage's commit range, run the **compile gate**, run the **runtime
gate**, get Aaron's confirmation, then proceed. Only after the LAST stage is green do you advance `main`
(Stage 6).

> Tip: `git cherry-pick A^..B` brings the inclusive range A…B. If a stage is a single commit, just
> `git cherry-pick <hash>`. If a cherry-pick conflicts, stop and resolve with Aaron — don't force it.

---

### STAGE 1 — Tooling + offline prep  (`620c23e`, `9b464c0`)
Bring the compile-checker first so it's available for every later gate, plus the offline single-player change.
- **Integrate:** `git cherry-pick 620c23e 9b464c0`
- **Compile gate:** `tools/validate.sh` → expect exit 0.
- **Runtime gate:** launch the game; open the **Single-player (offline)** mode from the menu — confirm it
  runs (one human + a bot hunter + crowd). The old split-screen co-op should be gone.
- **Rollback if bad:** `git reset --hard HEAD~2`.

### STAGE 2 — Phase 8 cosmetic plumbing  (`7600f5b … ae1a248`)
The whole cosmetic foundation. Visually this should look almost identical to before (overlays are art-less
placeholders that stay hidden) — that's success, not a bug.
- **Integrate:** `git cherry-pick 7600f5b^..ae1a248`
- **Compile gate:** `tools/validate.sh` → exit 0. Confirm the autoloads `CosmeticRegistry` and
  `CosmeticInventory` are registered in `project.godot` and the project opens with no load errors.
- **Runtime gate (online):** host + one client. Confirm: players and NPCs all draw on the one
  `CharacterVisual` rig; the crowd still looks varied; no errors in the Output/Debugger panel; the match
  plays as before (marks, kills, reveals, rematch all still work).
- **Watch for:** any "script failed to load" / missing-class errors — those mean a commit landed out of
  order. Re-check the cherry-pick range.
- **Rollback if bad:** `git reset --hard` back to the Stage 1 tip.

### STAGE 3 — §0.3 per-viewer appearance pillar  (`d4cabd0`)
The crowd is now rebuilt per-viewer so you never see your own look. `placeholder_distinct_bodies` is ON,
so each player gets a distinct body sheet — this is what makes the effect visible before real art.
- **Integrate:** `git cherry-pick d4cabd0`
- **Compile gate:** `tools/validate.sh` → exit 0.
- **Runtime gate (online, the important one):** host + at least one client (more is clearer).
  - On the **host** screen, note your own body (say you're the *guard*). The crowd should contain **no
    other guards** — only copies of the other players' looks + filler.
  - On the **client** screen, the crowd should be **full of guards** (copies of the host), with the real
    host hidden among them.
  - Each player is the only one of "their" look on their own screen. That is the §0.3 invariant — verify
    it by eye on both machines. If you ever see your *own* look out in your crowd, that's a failure.
- **Rollback if bad:** `git reset --hard HEAD~1`.

### STAGE 4 — Phase 9 experiments, integrated INERT  (`48a9746`)
This brings the `ExperimentFlags` autoload, the loader, `behavior_history`, the six experiments, and the
neutral core hooks. **Every flag is OFF**, so this stage must change *nothing* about how the game plays.
- **Integrate:** `git cherry-pick 48a9746`
- **Compile gate:** `tools/validate.sh` → exit 0. Confirm `ExperimentFlags` is registered as an autoload
  and the `earned_read_pulse` input action exists in `project.godot`.
- **Delete-test gate (critical):** with all flags `false`, host + client a full match and confirm it
  behaves **identically to the end of Stage 3** — same crowd, kills, reveals, scoring, rematch. The
  experiment loader builds an `Experiments` node, but every experiment early-returns on its flag.
- **Loader sanity:** in the running scene tree, confirm an `Experiments` node exists under the match with
  one child per file in `scripts/experiments/` (named after each file). On a client, confirm the same
  nodes exist at the same paths (needed for the cue RPCs).
- **Rollback if bad:** `git reset --hard HEAD~1`.

> If any stage's compile gate fails, **fix it on the integration branch and tell Aaron** — the cloud
> author flagged that nothing here was compiled. Likely suspects are listed in §7.

---

## 5. Turning experiments ON for playtest (do NOT commit these flips)

Only after Stage 4 is green and the delete test passed. Per `PHASE_9_EXPERIMENTS.md` §3: **one experiment
at a time, A/B against vanilla**, judged on the one question — *did humans commit to kills, or turtle harder?*

Flip a single bool to `true` in `scripts/experiment_flags.gd` (the **host's** copy governs), host, play a
block, then set it back. Verify each against its checkpoint:

- **9B `crowd_thinning_enabled`** — crowd stays full until the round's halfway mark, then NPCs visibly
  walk to exits and leave, ending with a handful clustered in the dense zones. Marks are never removed.
- **9A `whiff_recovery_enabled`** — knife a civilian *with an opponent in range + line of sight* → you
  can't kill for ~2s; knife one *alone* → just the exposure cost, no window. **Set `wall_collision_mask`
  on the whiff_recovery node to your map's actual wall layer first**, or the witness LOS check is wrong.
- **9D `mutual_proximity_enabled`** — two players, both contracts done, each other's target → both feel a
  warming meter as they close, with no direction and no figure. Confirm the **host player** sees it too
  (the author fixed a host-render bug here — verify it actually shows on the host).
- **9E `crowd_reaction_enabled`** — kill in a crowd → nearby NPCs scatter for ~2.5s, leaving a hole that
  points back at the kill. Confirm it replicates to the client (host owns the motion).
- **9C `earned_read_enabled`** — stay at/under 25 exposure for 30s → "PULSE READY" → press **Q**
  (`earned_read_pulse`) → soft zones light over figures who recently ran/killed (including a player who
  slipped up), while calm civilians stay dark. Confirm a reckless player can never charge it.
- **9F `behavioral_flag_enabled`** — a target who just sprinted flashes a screen-edge cue toward their
  area for their hunter (brighter the higher their exposure; gone once they're on the hunter's screen),
  and the target gets a "SPOTTED" cue back. A clean blend-walker barely flags. Note it overlaps the §3.1
  exposure arrow — judge them separately, not both at once.

**Pillar check before keeping any of these** (`PHASE_9_EXPERIMENTS.md` §3.4): never points at a specific
*figure* (Pillar #1); the disadvantaged player always has a counter / knows they're found (Pillar #4);
rewards engagement over camping (Pillar #5). Record kept tunable values in `CHANGELOG.md`.

---

## 6. Finishing — advance `main` and tag

Only once Stages 1–4 are all green and Aaron has confirmed the inert delta test:

```bash
git checkout main
git merge --ff-only integrate/phase-8     # fast-forward main to the verified tip
tools/validate.sh                          # one last compile gate on main
git tag phase-8-complete                   # the cosmetics + per-viewer milestone
git tag phase-9-experiments                # the experiment scaffold (inert) milestone
git push origin main --tags
```

Update `CHANGELOG.md` if anything changed during integration (a compile fix, a tunable). Leave the
experiment flags **OFF** in the committed `experiment_flags.gd`.

---

## 7. Known caveats the cloud author flagged — fix these during integration

These are the spots most likely to need a real Godot to settle. Address them as you hit them and tell Aaron.

1. **Runtime `@rpc` registration (the big one).** The loader attaches each experiment script to a node at
   runtime via `set_script`. The owner-only cue RPCs in 9C/9D/9F assume `@rpc` annotations register on a
   set-script node. **Host-own cues are delivered directly (no RPC), so the host always sees its own cues**
   — but if a *remote client* never receives a cue (9C pulse, 9D meter, 9F flag/spotted), `@rpc` didn't
   register. Fix: convert those experiments to instanced `.tscn` scenes added in the scene tree instead of
   runtime `set_script`. (The author offered to do this; verify in play before deciding.)
2. **9A `wall_collision_mask`.** Defaults to `1`. Set it to your map's real wall physics layer or the
   witness line-of-sight test is meaningless.
3. **9A root mode.** `mode_root_instead_of_disarm` is stubbed (it prints a warning and falls back to
   disarm) — rooting needs a player movement-lock hook that doesn't exist yet. Default is off; only wire
   it if playtest asks for the harsher feel.
4. **Placeholder cue visuals.** The 9D meter, 9F edge-marker, and 9C zone rings are minimal stand-ins to
   prove the plumbing — expect to restyle them once feel is decided. The author suggests 9F ideally shares
   the existing §3.1 `ExposureArrow` rendering rather than its own marker.
5. **Loader + exported builds.** `DirAccess` folder-scanning is reliable from the editor (where you'll
   playtest). If you ever export a build and experiments don't load, switch the loader to an explicit list
   or instanced scenes — note it, don't block integration on it.

---

## 8. If integration goes wrong — abort cleanly

Nothing here has touched `main` until Stage 6. To abandon at any point:

```bash
git cherry-pick --abort      # if mid-conflict
git checkout main            # main is untouched and releasable
git branch -D integrate/phase-8
```

Then report to Aaron exactly which stage failed, the `validate.sh` output, and any Output/Debugger errors,
so the next session can fix the branch before retrying. **Slow and verified beats fast and broken** — that
is the whole point of this document.
