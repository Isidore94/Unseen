# UNSEEN — PHASE 8 → MAIN  (integration plan, step 2 of 3)

> **Branch:** `claude/phase-8-monetization-oqu6sd` · **Tip:** `ae1a248` (v0.8.0)
> **Integration order:** Phase 7 → main → **Phase 8 → main (this file)** → Phase 9 → main.
> Do **NOT** start until Phase 7 is on `main` and verified (see §1).

---

## 0. What Phase 8 is, and who does this

**Phase 8 = the cosmetic & identity FOUNDATION (plumbing only — no shop, no currency, no progression).**
Eight commits on top of the Phase 7 tip (`9b464c0`):

```
7600f5b Phase 8.0  COSMETIC_SYSTEM_SPEC.md (the brief)
4e15257 Phase 8.1  cosmetic data layer — CosmeticItem, Loadout, registry
02ec0c9 Phase 8.2  composable 4-layer rig + apply_loadout + animation hooks
26a4988 Phase 8.3  NPC crowd on the shared rig with randomized loadouts
cf804fb Phase 8.4  replicate cosmetic loadouts over the network (ids only)
ea64e91 Phase 8.5  wire animation hooks + kill_card stub to real events
50e5ab7 Phase 8.6  account inventory (ownership-gated equip) + PlayerProfile
ae1a248 Phase 8    changelog + version bump to v0.8.0
```

Success test (`COSMETIC_SYSTEM_SPEC.md`): adding a hat later = one art file + one data row; adding the
shop later = UI on top of an inventory that already exists. **Visually this should look almost the same
as Phase 7** — overlays (outfit/head/weapon) are art-less placeholders that stay hidden. That sameness is
success, not a regression.

**You are the VS Code Claude** on Aaron's machine **with Godot 4.7** — so you run `tools/validate.sh`
(compile gate) and launch the game (runtime gate). Aaron is a brand-new coder (`CLAUDE.md`): explain in
plain language, give exact editor steps, and **wait for his confirmation** before advancing main.

---

## 1. Prerequisite — Phase 7 must already be on `main`

```bash
git fetch origin
git checkout main && git pull
git merge-base --is-ancestor 9b464c0 main && echo "OK: Phase 7 tip is on main" || echo "STOP: do Phase 7 first"
```
If STOP, integrate Phase 7 first (`PHASE_7_TO_MAIN.md` on the `phase-7-online-integration` branch).

---

## 1.5 Re-sync this branch with `main` FIRST (absorb Phase 7 fixes)  ·  **do not skip**

These branches are **stacked**: this Phase 8 branch contains a FROZEN copy of the Phase 7 code as it was
when this branch was cut. Any fix made to Phase 7 during *its* integration now lives on `main` but is
**NOT** in this branch yet. Pull it in and resolve before you test, so what you test is what will land:

```bash
git checkout claude/phase-8-monetization-oqu6sd
git merge main          # absorb every Phase 7 fix that reached main
tools/validate.sh       # re-verify after the merge
git push origin claude/phase-8-monetization-oqu6sd
```
Resolve any conflict by **keeping the fix** from `main`. Conflicts are possible in files Phase 8 also
edited — e.g. `npc.gd` and `kill_component.gd` (Phase 8 added cosmetic hooks to them). See §1.6.

## 1.6 Forward-propagation of fixes (the contract that keeps stacked branches correct)

A `git merge main` carries a fix into code this phase left **unchanged** — but it does **not** fix code this
phase **rewrote or newly added**. So after the merge, for every earlier-phase fix:

1. **Keep the fix** when resolving conflicts (don't let this branch's older version win).
2. **Consciously re-check this phase's own code for the SAME bug** and re-apply it by hand where the merge
   couldn't reach (anything Phase 8 rewrote/added).
3. **Record it in `CHANGELOG.md`** so the chain is traceable.

**And hand it forward:** any fix that ends up on `main` here must still reach **Phase 9** — that branch
does the same `git merge main` re-sync before it's tested (its `PHASE_9_TO_MAIN.md` §1.5). When you finish
this phase, tell Aaron explicitly what was fixed so the Phase 9 pass knows to look for it.

---

## 2. Golden rules

1. **`tools/validate.sh` passes before you advance main** (the compile gate the cloud author can't run).
2. **No visual/gameplay regression.** Phase 8 is plumbing — the match must play exactly as Phase 7 did.
3. **Server-authoritative + hidden identity** (`buildplan.md` §0): looks travel as a compact loadout
   payload (ids only), replicated once on join — never textures, never per-frame, never anything that
   reveals who is human.
4. **Test online, two instances** (host + a `127.0.0.1` client).
5. **Keep `main` releasable** — verify on a scratch branch, advance main only when green.

---

## 3. Integrate onto a scratch branch

```bash
git checkout main && git pull
git checkout -b integrate/phase-8
git merge origin/claude/phase-8-monetization-oqu6sd    # ff or a clean merge commit — both fine
tools/validate.sh                                       # COMPILE GATE → expect exit 0
```
Confirm `project.godot` registers the autoloads **`CosmeticRegistry`** and **`CosmeticInventory`**, and the
project opens with no load errors.

---

## 4. Runtime gate (online)

Host one instance + a `127.0.0.1` client. Confirm:
- Players and NPCs all draw on the **one `CharacterVisual` rig**; the crowd still looks varied; no errors
  in the Output/Debugger panel.
- A full match plays exactly as before — marks, kills, layers (rooftop/sewer), claim, items (smoke/cloak),
  reveals/faceplates, last-standing, scoreboard, **rematch** all still work.
- **No shop, no currency** anywhere — that's correct; this is only the foundation.

**Watch for:** any "script failed to load" / missing-class error (a commit landed out of order — re-check
the merge), or the crowd looking wrong (the rig didn't apply a loadout). Get Aaron's confirmation it plays
identically to Phase 7 before advancing main.

---

## 5. Advance `main` + tag

```bash
git checkout main
git merge integrate/phase-8
tools/validate.sh
git tag phase-8-complete            # v0.8.0 milestone
git push origin main --tags
```
Update `CHANGELOG.md` only if something changed during integration. You may delete the `PHASE_*_TO_MAIN.md`
plan files from main once all three phases are in.

**Next:** Phase 9 (`PHASE_9_TO_MAIN.md` on `claude/post-integration-checklist-ig0la4`) — the §0.3 per-viewer
appearance pillar + the endgame experiments.

---

## 6. Rollback

Nothing touches `main` until §5. To abort: `git checkout main` (untouched), then
`git branch -D integrate/phase-8`. Report the failing step, the `validate.sh` output, and any
Output/Debugger errors so the branch can be fixed before retrying.
