#!/bin/bash
# setup-chatgpt.sh must never delete a release tree something is running from.
#
# Regression (2026-09-02): the guard was `pgrep -f "^$old/"`, with $old built
# from $HOME — "/home/damian/.local/opt/chatgpt-...". The running process
# reported "/var/home/damian/.local/opt/chatgpt-...", because /home is a symlink
# to /var/home on Fedora Atomic. Same directory, different spelling, so the
# pattern never matched and the script deleted the 1.4 GB tree out from under
# the running app while the user was using it.
#
# The replacement asks /proc which directories are actually being executed from
# and compares resolved paths, so no spelling of the path can fool it.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Lift the helper out of the script rather than running the whole installer.
tmp="$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/prune-guard.XXXXXX")"
trap 'pkill -f "$tmp/bin/sleep" 2>/dev/null; rm -rf "$tmp"' EXIT
sed -n '/^dir_in_use() {/,/^}/p' "$DIR/scripts/setup-chatgpt.sh" > "$tmp/guard.sh"
[[ -s "$tmp/guard.sh" ]] || { echo "  FAIL: could not extract dir_in_use from setup-chatgpt.sh"; exit 1; }
# shellcheck source=/dev/null
source "$tmp/guard.sh"

mkdir -p "$tmp/release/bin" "$tmp/idle"
cp /usr/bin/sleep "$tmp/release/bin/"
"$tmp/release/bin/sleep" 120 &
runner=$!
# Give the kernel a moment to publish /proc/<pid>/exe.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -e "/proc/$runner/exe" ]] && break
    sleep 0.2
done

dir_in_use "$tmp/release" \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: a directory with a running process is reported in use"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: missed a process running from the directory"; }

dir_in_use "$tmp/idle" \
    && { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: reported an unused directory as in use"; } \
    || { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: an unused directory is free to remove"; }

# The heart of the regression: reach the same directory by its other name. On
# this host $HOME is /home/damian while /proc reports /var/home/damian.
alt="$tmp/altlink"
ln -sfn "$tmp/release" "$alt"
dir_in_use "$alt" \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: still in use when named through a symlink (the /home → /var/home case)"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: a different spelling of the same path hides the running process"; }

kill "$runner" 2>/dev/null; wait "$runner" 2>/dev/null
dir_in_use "$tmp/release" \
    && { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: still reported in use after the process exited"; } \
    || { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: free again once nothing is running from it"; }

assert_summary
