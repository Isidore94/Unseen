#!/usr/bin/env bash
# Headless GDScript validator for UNSEEN — catches the real compile errors a text/syntax
# check misses (type inference, class_name/enum resolution, method-not-found), which is
# exactly what we can't see without a real Godot.
#
#   Usage:  GODOT=/path/to/godot tools/validate.sh        (or just tools/validate.sh if
#           `godot` is on PATH — the SessionStart hook puts it there on web sessions)
#   Exit:   0 = all scripts compile, 1 = one or more real errors (printed)
#
# It runs `godot --headless --check-only` on every script. That check sees one file at a
# time, so it can't resolve AUTOLOAD singletons (e.g. NetworkManager) — those show up as
# "Identifier not found: <Autoload>" and are NOT real errors, so we read the autoload names
# from project.godot and filter exactly those lines out.
set -uo pipefail

GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
	echo "validate.sh: Godot not found (set GODOT=/path/to/godot)." >&2
	exit 2
fi

# Autoload identifiers are valid globals at runtime but not during an isolated --check-only.
autoloads="$(awk '/^\[autoload\]/{f=1;next} /^\[/{f=0} f && /=/{split($0,a,"=");gsub(/ /,"",a[1]);if(a[1]!="")print a[1]}' project.godot)"
ignore_re="Identifier not found: ($(echo "$autoloads" | paste -sd'|' -))"

fail=0
while IFS= read -r f; do
	out="$("$GODOT" --headless --check-only --script "$f" 2>&1)"
	# Decide pass/fail on ROOT error lines only (Parse/Compile Error:), filtering the
	# autoload false positives. The generic "Failed to load script ... Compilation failed"
	# summary lines are just downstream noise and don't decide the verdict.
	real="$(echo "$out" | grep -iE "Parse Error:|Compile Error:" | grep -vE "$ignore_re")"
	if [ -n "$real" ]; then
		echo "❌ $f"
		echo "$real" | sed 's/^/   /' | head -5
		fail=1
	fi
done < <(find scripts components tools -name '*.gd' 2>/dev/null | sort)

if [ "$fail" -eq 0 ]; then
	echo "✅ VALIDATE_OK — all GDScript compiles"
fi
exit "$fail"
