# UNSEEN — PHASE 7 → MAIN  (integration plan, step 1 of 3)

> **Branch:** `phase-7-online-integration` · **Tip:** `9b464c0` (v0.7.1)
> **Integration order:** **Phase 7 → main (this file)** → Phase 8 → main → Phase 9 → main.
> This is the FIRST integration — do it, verify it, land it, *then* Phase 8, then Phase 9.

---

## 0. What Phase 7 (online) is, and who does this

`main` already has the Phase 7 features built/tested on the OFFLINE split-screen path (it's at the
v0.7.0 tip, `c0e2196`). **This branch ports all of them onto the ONLINE, server-authoritative match** —
which is the real playtest surface (each player on a separate machine = a true hidden view). Six commits:

```
269bf1d  Docs: make buildplan.md canonical, online-MP-first; retire old plan
786779f  Phase 7 online: port layers/visibility, claim, items, reveals to the match
9064b10  Phase 7 online: verify integration — fix smoke kill-lockout + claim cooldown
b280b4a  Phase 7 online: up-to-4-player — target ring, last-standing, points, rematch (v0.7.1)
620c23e  Offline: single-player only (retire split-screen co-op)
9b464c0  Add tools/validate.sh — headless Godot compile-checker
```

**You are the VS Code Claude** on Aaron's Windows machine **with Godot 4.7 installed** — so you can do the
two things prior authors couldn't: run `tools/validate.sh` (compile gate) and launch the game to test
online (runtime gate). Aaron is a brand-new coder (`CLAUDE.md`): explain in plain language, give exact
Godot-editor steps, and **wait for his confirmation** before advancing main.

---

## 1. Prerequisite

`main` should be at the Phase 7 **v0.7.0** base (Phase 6 online + Phase 7 offline already landed):

```bash
git fetch origin
git checkout main && git pull
git merge-base --is-ancestor c0e2196 main && echo "OK: at/after the v0.7.0 base" || echo "CHECK with Aaron"
```
This is step 1, so there's no earlier phase to gate on — just confirm main is the expected base. Nothing to
re-sync inbound either (this is the base) — but read §1.5: you are the START of a stacked chain.

---

## 1.5 Forward-propagation of fixes (READ — this is where the chain begins)

The three phase branches are **stacked**: Phase 8 was cut from this Phase 7 branch, and Phase 9 from Phase 8.
That means **every later branch contains a FROZEN copy of the Phase 7 code as it is right now.** Any fix you
make to Phase 7 during this integration will NOT exist in the Phase 8 or Phase 9 branches until it's
deliberately carried forward. If you skip that, the later phases silently re-introduce the bug.

**So for every fix you make here:**
1. **Land it on `main`** as part of this integration.
2. **It must reach the later branches.** Each later phase's plan (`PHASE_8_TO_MAIN.md` §1.5,
   `PHASE_9_TO_MAIN.md` §1.5) starts by running `git merge main` to absorb your fix — but that merge only
   reaches code those phases left **unchanged**. Where a later phase **rewrote or extended** the same code,
   the merge won't fix it. The prime example: **`online_match.gd`** — you may fix it here, and Phase 9 added
   the per-viewer crowd + experiment loader to that same file, so Phase 9 must re-apply the fix by hand.
3. **Tell Aaron exactly what you fixed** (file + symptom) before you finish this phase, and write it in
   `CHANGELOG.md`. That list is the checklist the Phase 8 and Phase 9 passes work through — without it, a
   fix made here can quietly vanish two phases later.

In short: **a Phase 7 fix is not "done" when it's on main — it's done when Phase 8 and Phase 9 have it too.**

---

## 2. Golden rules

1. **`tools/validate.sh` passes before you advance main.** (It arrives in this very branch — once merged
   onto the scratch branch you can run it. It's the compile gate the earlier authors couldn't run.)
2. **Server-authoritative is law** (`buildplan.md` §0 / `CLAUDE.md` §5): the host owns every outcome
   (layer, claim, kill, reveal, score); clients send intent only; **no data revealing who is human** is
   ever sent except the deliberate reveals (and those go to the one earning client, not broadcast).
3. **Test ONLINE, two instances** — host one, connect a second as a `127.0.0.1` client. One screen cannot
   prove the hidden-identity invariants.
4. **Keep `main` releasable** — verify on a scratch branch, advance main only when green.

---

## 3. Integrate onto a scratch branch

```bash
git checkout main && git pull
git checkout -b integrate/phase-7
git merge origin/phase-7-online-integration     # should fast-forward (or a clean merge commit)
tools/validate.sh                                # COMPILE GATE → expect exit 0
```
If `validate.sh` reports a real error, fix it here and tell Aaron — don't advance main with it red.

---

## 4. Runtime gates (online — this is the big test surface)

Host + a `127.0.0.1` client (test with 2, and if possible 3–4 instances). Verify each, on BOTH machines:

1. **Lobby + spawn** — both players spawn; no two start adjacent; each gets 2 spaced NPC marks.
2. **Layers & per-viewer visibility (§7.2):** a ROOFTOP player is hidden from the ground but can see the
   ground; a SEWER player sees no one (dark overlay) but keeps the 100%-uptime hunt arrow; kills only land
   on your own layer, never from the sewer. **Confirm each machine hides the right characters** — that's
   the hidden view.
3. **Claim + global cooldown (§7.3):** using an access point is free; **claiming** it costs ~20% committed
   exposure and locks it to you for the match; the 15s global cooldown blocks unclaimed pass-through during
   a chase. HUD shows claimed/cooldown/available consistently on both machines.
4. **Items (§7.6):** smoke makes you invisible to others and **disables your kill** while up (verify a
   smoked CLIENT genuinely cannot land a kill — that was an authority fix in `9064b10`); cloak hides the
   hunt arrow but not your exposure arrows.
5. **Reveals + faceplates (§7.4):** the first to finish their contract gets the RED target faceplate;
   hitting 100% exposure shows your BLUE faceplate to others **only alongside the arrow** — confirm reveals
   are targeted (the earning client only), never broadcast.
6. **Last-standing + points (§7.5):** a death ELIMINATES (spectate), it doesn't end the match; the match
   ends at ≤1 alive or time-up; **winner = most points** (ties → lowest average exposure), not necessarily
   the survivor; the scoreboard reads correctly.
7. **Rematch:** once everyone still connected votes, the host reloads a fresh round (new ring, marks,
   scores) for all.
8. **Offline mode:** the menu's **Single-player (offline)** runs one human vs a bot hunter (split-screen
   co-op is gone).

Get Aaron's confirmation that the online match is correct and matches the Phase 7 design before advancing.

---

## 5. Advance `main` + tag

```bash
git checkout main
git merge integrate/phase-7
tools/validate.sh
git tag phase-7-complete            # v0.7.1 milestone (also tag v0.7.1 if not already)
git push origin main --tags
```

**Next:** Phase 8 (`PHASE_8_TO_MAIN.md` on `claude/phase-8-monetization-oqu6sd`) — the cosmetic foundation.

---

## 6. Rollback

Nothing touches `main` until §5. To abort: `git checkout main` (untouched, releasable), then
`git branch -D integrate/phase-7`. Report the failing gate, the `validate.sh` output, and any
Output/Debugger errors so the branch can be fixed before retrying. **Slow and verified beats fast and broken.**
