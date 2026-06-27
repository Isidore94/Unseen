# UNSEEN — PHASE 9 → MAIN  (integration plan, step 3 of 3)

> **Branch:** `claude/post-integration-checklist-ig0la4` · **Tip:** `7077a48`
> **Integration order (the whole roadmap):** Phase 7 → main → Phase 8 → main → **Phase 9 → main (this file)**.
> Do **NOT** start this until Phase 7 *and* Phase 8 are both on `main` and verified (see §1).

---

## 0. What "Phase 9" is, and who does this

**Phase 9 = everything on this branch beyond the Phase 8 tip (`ae1a248`)** — three commits:

- `d4cabd0` — **§0.3 per-viewer appearance** (the hidden-identity pillar): on each screen the crowd is
  rebuilt from copies of the OTHER players' looks + filler, with your own look excluded. Adds the
  `placeholder_distinct_bodies` test aid (ON) so it's visible before real cosmetic art.
  *(Its commit message says "Phase 8: per-viewer…" — it is Phase 9 work; this plan is canonical.)*
- `48a9746` — **endgame & commitment EXPERIMENTS** (`PHASE_9_EXPERIMENTS.md`): `ExperimentFlags` autoload,
  a folder-scan loader, `behavior_history` infra, six experiments under `scripts/experiments/`, neutral
  core hooks. **All flags OFF by default.**
- `7077a48` — docs.

**You are the VS Code Claude** on Aaron's Windows machine **with Godot 4.7** — so you can do the two
things the cloud author could not: run `tools/validate.sh` (compile gate) and launch the game to test
online (runtime gate). Aaron is a brand-new coder (`CLAUDE.md`): explain in plain language, give exact
editor steps, and **wait for his confirmation between stages.**

---

## 1. Prerequisite — Phase 7 AND Phase 8 must already be on `main`

```bash
git fetch origin
git checkout main && git pull
git merge-base --is-ancestor ae1a248 main && echo "OK: Phase 8 tip is on main" || echo "STOP: do Phase 8 first"
```
If that prints STOP, integrate Phase 8 first (`PHASE_8_TO_MAIN.md` on the `claude/phase-8-monetization-oqu6sd`
branch). Do not proceed.

---

## 1.5 Re-sync this branch with `main` FIRST (absorb Phase 7/8 fixes)  ·  **do not skip**

These branches are **stacked**: this Phase 9 branch contains a FROZEN copy of the Phase 7 and Phase 8 code
as it was when this branch was cut. Any fix made to Phase 7 or Phase 8 during *their* integration now lives
on `main` but is **NOT** in this branch yet. Pull it in and resolve before you test, so what you test is
what will actually land:

```bash
git checkout claude/post-integration-checklist-ig0la4
git merge main          # absorb every Phase 7/8 fix that reached main
tools/validate.sh       # re-verify after the merge
git push origin claude/post-integration-checklist-ig0la4
```
Resolve any conflict by **keeping the fix** from `main`. Expect conflicts in files this phase also edited —
most likely **`online_match.gd`** (Phase 7 created it; Phase 9 adds the per-viewer crowd + experiment
loader to it) and `npc.gd` / `kill_component.gd` (Phase 9 added hooks). See §1.6 before resolving.

## 1.6 Forward-propagation of fixes (the contract that keeps stacked branches correct)

A `git merge main` carries a fix into code this phase left **unchanged** — but it does **not** fix code this
phase **rewrote or newly added**. So after the merge, for every earlier-phase fix:

1. **Keep the fix** when resolving conflicts (don't let this branch's older version win).
2. **Consciously re-check this phase's own code for the SAME bug.** Example: if Phase 7 fixed a logic error
   in `online_match.gd`, the per-viewer/experiment code Phase 9 added to that same file may repeat the
   pattern — the merge won't catch that. Search for it and re-apply by hand.
3. **Record it in `CHANGELOG.md`** so the chain is traceable.

This is the last phase, so there's nothing downstream to hand off to — but if you fix anything *here*,
tell Aaron, since it may need to be reflected on `main` directly.

---

## 2. Golden rules

1. **`tools/validate.sh` passes before you advance main** (compile gate the author couldn't run).
2. **Experiments ship OFF.** With every `ExperimentFlags` bool `false` (default), the game must play
   exactly as it did at the Phase 8 tip — the *delete test* (`PHASE_9_EXPERIMENTS.md` §1.4).
3. **Server-authoritative + hidden identity** (`buildplan.md` §0): host owns outcomes; no data revealing
   who is human is sent except the deliberate reveals.
4. **Test online, two instances** (host + a `127.0.0.1` client). One screen can't prove §0.3.
5. **Keep `main` releasable** — verify on a scratch branch, advance main only when green.
6. **Never commit an experiment flag set to `true`.** Flip them on only in a local, uncommitted playtest.

---

## 3. Integrate onto a scratch branch (main stays untouched)

```bash
git checkout main && git pull
git checkout -b integrate/phase-9
git merge origin/claude/post-integration-checklist-ig0la4   # ff or a clean merge commit — both fine
tools/validate.sh                                           # COMPILE GATE → expect exit 0
```
Confirm the autoloads `ExperimentFlags` + the `earned_read_pulse` input action are present in
`project.godot`, and the project opens with no load errors.

> If the merge conflicts (only likely on `PHASE_*_TO_MAIN.md` doc files if a prior phase's doc was merged),
> keep both — they're just plans — and continue. If `validate.sh` fails, fix it here and tell Aaron.

---

## 4. Runtime gate A — the §0.3 per-viewer pillar (most important)

Host + at least one client (more is clearer). `placeholder_distinct_bodies` is ON, so each player has a
distinct body sheet.
- On the **host** screen, note your own body (say *guard*). The crowd must contain **no other guards** —
  only copies of the other players' looks + filler.
- On the **client** screen, the crowd is **full of guards** (copies of the host), the real host hidden
  among them.
- Each player is the only one of their own look on their own screen. **If you ever see your OWN look out
  in your crowd, that's a failure** — stop and report it.

## 5. Runtime gate B — experiments are INERT (delete test)

With all flags `false`, host + client a full match. It must behave **identically to the Phase 8 tip**:
same crowd, kills, reveals, scoring, rematch. In the running scene tree, confirm an `Experiments` node
exists under the match with one child per file in `scripts/experiments/`, and the same nodes exist at the
same paths on the client (needed for the cue RPCs).

**Get Aaron's confirmation that gates A and B both pass before advancing main.**

---

## 6. Advance `main` + tag

```bash
git checkout main
git merge integrate/phase-9        # bring the verified result onto main
tools/validate.sh                  # final compile gate on main
git tag phase-9-complete
git push origin main --tags
```
Leave the experiment flags **OFF** in the committed `experiment_flags.gd`. Update `CHANGELOG.md` if
anything changed during integration. You may delete the `PHASE_*_TO_MAIN.md` plan files from main now —
they've done their job.

---

## 7. Playtest the experiments (after main is green; flips are NOT committed)

One experiment at a time, A/B against vanilla, judged on: *did humans commit to kills, or turtle harder?*
Flip one bool to `true` in `scripts/experiment_flags.gd` (the **host's** copy governs), host, play, set it
back. Checkpoints (full detail in `PHASE_9_EXPERIMENTS.md` §2):
- **9B crowd_thinning** — crowd full till halftime, then NPCs walk off, ending with a handful; marks never removed.
- **9A whiff_recovery** — whiff *with an opponent watching* → ~2s disarm; whiff *alone* → exposure cost only.
  **Set `wall_collision_mask` to your map's wall layer first.**
- **9D mutual_proximity** — both players done + each other's target → symmetric warming meter, no direction.
  Confirm the **host player** sees it too.
- **9E crowd_reaction** — kill in a crowd → NPCs scatter, leaving a hole pointing back; confirm it shows on the client.
- **9C earned_read** — ≤25 exposure for 30s → "PULSE READY" → press **Q** → soft zones over recent runners/killers.
- **9F behavioral_flag** — a target who just sprinted flashes a screen-edge cue to their hunter (+ "SPOTTED"
  back); a clean blend-walker barely flags. Overlaps the §3.1 arrow — don't judge both at once.

**Pillar check before keeping any** (`PHASE_9_EXPERIMENTS.md` §3.4) and record kept tunables in `CHANGELOG.md`.

---

## 8. Caveats to fix during integration (the author flagged these — needs real Godot)

1. **Runtime `@rpc` registration (the big one).** Experiments are attached to nodes via runtime
   `set_script`; the owner-only cue RPCs in 9C/9D/9F assume `@rpc` registers that way. **Host-own cues are
   delivered directly, so the host always sees its own** — but if a *remote client* never receives a cue
   (9C pulse / 9D meter / 9F flag+spotted), `@rpc` didn't register: convert those three to instanced `.tscn`
   scenes in the tree instead of runtime `set_script`.
2. **9A `wall_collision_mask`** — set to the real wall layer or the witness LOS check is wrong.
3. **9A root mode** stubbed (disarm only; needs a player movement-lock hook). Default off.
4. **Cue visuals** (9D meter / 9F marker / 9C zones) are placeholders to restyle once feel is decided.
5. **Exported builds** — the `DirAccess` loader is reliable from the editor (where you playtest); if an
   exported build loads no experiments, switch the loader to an explicit list or instanced scenes.

---

## 9. Rollback

Nothing touches `main` until §6. To abort: `git checkout main` (untouched, releasable), then
`git branch -D integrate/phase-9`. Report which gate failed, the `validate.sh` output, and any
Output/Debugger errors so the next session can fix the branch. **Slow and verified beats fast and broken.**
