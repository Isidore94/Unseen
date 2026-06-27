# UNSEEN — PHASE 10 → MAIN  (integration plan, step 4 of 4)

> **Branch:** `phase-10-maps` (stacked on `phase-9`)
> **Integration order:** Phase 7 → main → Phase 8 → main → Phase 9 → main → **Phase 10 → main (this file)**.
> Do **NOT** start until Phase 9 is on `main` and verified (see §1).

---

## 0. What Phase 10 is, and who does this

**Phase 10 is the MAP-DESIGN phase.** It's a home for new maps and map tooling, kept separate from the
systems phases so level design can iterate on its own. First content: **Rome** — a small, street-only map.

What's in it (everything on this branch beyond the Phase 9 tip):
- **`maps/rome.tscn`** — same play size as the compact arena (1440×1120) on a denser **19×15** grid: tight
  1-cell lanes between insulae blocks, a central fountain piazza, two small markets. **No rooftops, no
  sewers, no portals** — just roads. Reuses the whole `test_map_01.gd` generator. Layout flood-fill
  verified offline (`scratchpad/gen_rome.py`): 148 open cells, all reachable, all 4 spawn corners open.
- **`test_map_01.gd`** — one additive export, `enable_portals` (default true; Rome sets false). Existing
  maps unchanged.
- **`lobby.gd`** — the old "Compact arena" checkbox is now a 3-way map **OptionButton** (Four Zones /
  Compact / Rome).
- **`network_manager.gd`** — `enum Map { FOUR_ZONE, COMPACT, ROME }` + `selected_map` (survives the
  lobby→match scene change); `_begin_match` carries the map id and derives `small_arena`.
- **`online_match.gd`** — loads the map scene by `selected_map`.

**You are the VS Code Claude** on Aaron's machine **with Godot 4.7** — so you run `tools/validate.sh`
(compile gate) and launch the game (runtime gate). Aaron is a brand-new coder (`CLAUDE.md`): explain in
plain language, give exact editor steps, and **wait for his confirmation** before advancing main.

---

## 1. Prerequisite — Phase 9 must already be on `main`

```bash
git fetch origin
git checkout main && git pull
# Confirm a Phase 9 marker is on main (the per-viewer crowd + experiments):
git merge-base --is-ancestor "$(git rev-parse origin/phase-9)" main 2>/dev/null && echo "OK: Phase 9 is on main" || echo "STOP: do Phase 9 first"
```
If STOP, integrate Phase 9 first (`PHASE_9_TO_MAIN.md` on the `phase-9` branch).

---

## 1.5 Re-sync this branch with `main` FIRST (absorb Phase 7/8/9 fixes)  ·  **do not skip**

This branch is stacked on Phase 9, which is stacked on 8 and 7, so it holds a FROZEN copy of all of them.
Any fix made during earlier integrations now lives on `main` but is NOT in this branch yet. Pull it in:

```bash
git checkout phase-10-maps
git merge main          # absorb every Phase 7/8/9 fix that reached main
tools/validate.sh       # re-verify after the merge
git push origin phase-10-maps
```
Resolve conflicts by **keeping the fix** from `main`. The likely conflict file is **`online_match.gd`**
(Phase 7 created it; Phase 9 added the per-viewer crowd + experiment loader; Phase 10 added the map-scene
switch). See §1.6.

## 1.6 Forward-propagation of fixes

A `git merge main` carries a fix into code Phase 10 left **unchanged** — but not code Phase 10 **rewrote
or added**. So after the merge: **keep the fix** on conflict, **re-check Phase 10's own edits for the same
bug** (especially the `_build_world` map-scene switch in `online_match.gd`), and **log it in `CHANGELOG.md`**.
**And hand it forward:** Phase 11 (`PHASE_11_TO_MAIN.md` on `phase-11-art-pipeline`) stacks on Phase 10 and
does the same `git merge main` re-sync before it's tested — it also touches `project.godot`. When you finish
this phase, tell Aaron what was fixed so the Phase 11 pass knows to look for it.

---

## 2. Golden rules

1. **`tools/validate.sh` passes before you advance main.**
2. **No regression to the existing two maps.** Four-Zone and Compact must still load and play exactly as
   before — Phase 10's generator change is additive (`enable_portals` defaults true).
3. **Server-authoritative**: the host picks the map; every peer loads the *same* one (`selected_map`).
4. **Test online, two instances** — confirm host AND client load the chosen map.
5. **Keep `main` releasable** — verify on a scratch branch, advance main only when green.

---

## 3. Integrate onto a scratch branch

```bash
git checkout main && git pull
git checkout -b integrate/phase-10
git merge origin/phase-10-maps
tools/validate.sh                 # COMPILE GATE → expect exit 0
```

---

## 4. Runtime gates (maps)

Host + a `127.0.0.1` client.
1. **Picker works**: the lobby shows a Map dropdown with **Four Zones / Compact / Rome**; the host's pick
   is what loads on **both** machines.
2. **Rome loads correctly**: a dense grid of tight lanes + a central fountain; **no rooftop stairs, no
   sewer grates, no teleporter pads** anywhere; the crowd fills the streets; the four players spawn in the
   four corners, well apart; the mini-map sketches the layout with no portal markers.
3. **No dead ends**: you can walk from any street to any other (the flood-fill said so — confirm it feels
   right; watch the Output panel for any `TestMap01: … pocket walled off` warning, which would mean a
   layout edit broke connectivity).
4. **No regression**: pick **Four Zones** → rooftops/sewers/teleporters all still work. Pick **Compact** →
   same as before.

Get Aaron's confirmation before advancing main.

---

## 5. Advance `main` + tag

```bash
git checkout main
git merge integrate/phase-10
tools/validate.sh
git tag phase-10-maps-complete
git push origin main --tags
```
You may delete the `PHASE_*_TO_MAIN.md` plan files from main once all phases are in.

---

## 6. Rollback

Nothing touches `main` until §5. To abort: `git checkout main` (untouched), then
`git branch -D integrate/phase-10`. Report the failing gate + `validate.sh` output + any Output errors.
