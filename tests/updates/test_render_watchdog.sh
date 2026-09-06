#!/bin/bash
# A correct badge the user cannot see is still a wrong badge.
#
# Regression (2026-09-06): the update indicator sat RED for 38 minutes after the
# system was fully up to date. The cache said "uptodate", running the module by
# hand printed "uptodate", and the clock in the same bar was ticking — Waybar was
# alive and had simply stopped re-running this one module's exec. Restarting
# Waybar fixed it instantly, which is what located the fault. A signal that
# changes nothing on screen is the exact failure this module keeps circling back
# to: the state is right and the user sees something else.
#
# The exec now stamps a file every time Waybar runs it, so "did the repaint
# happen" is a measurable fact rather than an assumption.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"; mkdir -p "$stub"
printf '#!/bin/bash\nexit 0\n' > "$stub/pgrep"          # a bar is running
printf '#!/bin/bash\necho "swaymsg $*" >> "%s/actions"\n' "$tmp" > "$stub/swaymsg"
chmod +x "$stub"/*

sed -n '/^ensure_waybar_repainted() {/,/^}/p' "$DIR/scripts/updates-waybar.sh" > "$tmp/wd.sh"
[[ -s "$tmp/wd.sh" ]] || { echo "  FAIL: could not extract ensure_waybar_repainted"; exit 1; }

LASTREAD_FILE="$tmp/lastread"
RENDER_LOG="$tmp/state/stalls.log"
export WAYBAR_REPAINT_GRACE=1
# shellcheck source=/dev/null
source "$tmp/wd.sh"

# ── Waybar repaints: nothing should happen ────────────────────────────────
( sleep 0.3; date +%s > "$LASTREAD_FILE" ) &
PATH="$stub:$PATH" ensure_waybar_repainted uptodate critical
wait
[[ ! -f "$tmp/actions" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: a bar that repaints is left alone"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: reloaded sway even though the exec had re-run"; }
[[ ! -f "$RENDER_LOG" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: nothing logged when the repaint happened"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: logged a stall that did not happen"; }

# ── Waybar goes quiet: recover and leave evidence ─────────────────────────
echo "1000" > "$LASTREAD_FILE"          # a stamp from long before the signal
PATH="$stub:$PATH" ensure_waybar_repainted uptodate critical
grep -q "swaymsg reload" "$tmp/actions" 2>/dev/null \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: a bar that never re-ran the exec is reloaded"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: left the user looking at a stale colour"; }
if [[ -f "$RENDER_LOG" ]]; then
    ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: the stall is recorded, not silently repaired"
    assert_contains "$(cat "$RENDER_LOG")" "critical→uptodate" "the log names the change that was missed"
else
    ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: recovered silently, leaving no evidence for next time"
fi

# ── No bar at all is not a fault ──────────────────────────────────────────
rm -f "$tmp/actions"
printf '#!/bin/bash\nexit 1\n' > "$stub/pgrep"; chmod +x "$stub/pgrep"
PATH="$stub:$PATH" ensure_waybar_repainted uptodate critical
[[ ! -f "$tmp/actions" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: with no bar running there is nothing to repaint"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: reloaded sway with no bar running"; }

assert_summary
