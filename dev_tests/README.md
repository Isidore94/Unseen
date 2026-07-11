# dev_tests — headless rule tests (plan.md §9)

Permanent, re-runnable tests for the game's **rules** (contract outcomes, target rings,
lockouts). They exist so a change to combat/ring code can be proven safe in seconds without
booting a 2-instance playtest. Dev-only; they ship no gameplay.

## How to run

Each test is a scene (scenes get the full autoload/class environment; bare `-s` scripts don't).
A test prints `PASS`/`FAIL` per check and exits with code 0 (all pass) or 1.

Run everything:

```powershell
powershell -ExecutionPolicy Bypass -File dev_tests\run_all.ps1
```

Run one test:

```powershell
d:\Godot\Godot_v4.7-stable_win64_console.exe --headless --path . res://dev_tests/test_target_ring.tscn
```

> If a test fails with "Could not find type …" after ADDING a new `class_name`, rebuild the
> class cache once: `Godot_v4.7-stable_win64_console.exe --headless --editor --quit` (or just
> open the editor).

## The tests

| Scene | Proves |
|---|---|
| `test_contract_rules.tscn` | plan §3.1/§3.3 attack matrix: prey kill, hunter counter-stun, stranger INTERFERENCE (+5s rattle), civilian whiff (+10s lock), lockout gating/reasons, per-pool exposure + decay ordering |
| `test_target_ring.tscn` | `TargetRing` math: static seat rings (dead-skipping, mutual pairs), rotating rings (fresh prey guaranteed when possible, waiting when not, never a stalled match) |
| `test_arrow_bands.tscn` | the hunt arrow's sequential escalation: no arrow <25, TRANSLUCENT 4-way pulse 25-49, SOLID precise 50+, no stale state when cooling |

## Adding a test

1. Copy an existing pair (`.gd` + `.tscn`), keep the `_check(label, ok)` pattern.
2. Root node runs everything in `_ready()` and ends with `get_tree().quit(0 or 1)`.
3. Add the scene to the table above. `run_all.ps1` picks up any `test_*.tscn` automatically.

Run these before committing anything that touches `kill_component.gd`, `target_ring.gd`,
or the contract/scoring parts of `online_match.gd`.
