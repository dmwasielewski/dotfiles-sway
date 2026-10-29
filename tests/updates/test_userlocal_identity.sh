#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export XDG_CACHE_HOME="$tmp/cache" XDG_DATA_HOME="$tmp/data" XDG_STATE_HOME="$tmp/state" DOTFILES="$tmp/repo"
mkdir -p "$DOTFILES/scripts" "$XDG_DATA_HOME/dotfiles-updates"
export ACTION_LOG="$tmp/actions"
cat > "$DOTFILES/scripts/demo.sh" <<'STUB'
#!/bin/bash
read -r ignored || true
echo updated >> "$ACTION_LOG"
STUB
cat > "$XDG_DATA_HOME/dotfiles-updates/stirling-pdf" <<'MANIFEST'
name=Stirling PDF
installed_version=1
updater=scripts/demo.sh
MANIFEST
# Source definitions without starting the interactive menu or background worker.
source <(sed '/^trap refresh_waybar EXIT/d; /^# ── Main loop/,$d' "$DIR/scripts/updates-menu.sh" | sed "s|^SCRIPT_DIR=.*|SCRIPT_DIR='$DIR/scripts'|")
refresh_userlocal() { :; }
UL_ROWS=$'Stirling PDF\t1\t2\nStirling PDF\t1\t2'
out="$(do_userlocal </dev/null)"; rc=$?
assert_rc "$rc" 0 'display name differing from filename can update'
assert_eq "$(cat "$ACTION_LOG" 2>/dev/null)" $'updated\nupdated' 'stdin-consuming updater cannot eat later rows'
# Missing scripts and failures remain visible, and later apps still run.
UL_ROWS=$'Missing app\t1\t2\nStirling PDF\t1\t2'
out="$(do_userlocal </dev/null)"; rc=$?
assert_rc "$rc" 1 'missing manifest reports failure'
assert_contains "$(cat "$LOG")" 'FAIL user-local Missing app' 'missing updater persists in log'
assert_contains "$out" 'Stirling PDF' 'later app is still attempted'
# Refuse an updater that escapes the repository.
printf 'updater=../../outside.sh\n' > "$tmp/unsafe"
resolved="$(userlocal_updater_path "$tmp/unsafe")"; rc=$?
assert_rc "$rc" 1 'updater paths outside repository are refused'
cp "$XDG_DATA_HOME/dotfiles-updates/stirling-pdf" "$XDG_DATA_HOME/dotfiles-updates/duplicate"
resolved="$(userlocal_manifest_for_name 'Stirling PDF')"; rc=$?
assert_rc "$rc" 1 'duplicate display labels fail safely'
rm "$XDG_DATA_HOME/dotfiles-updates/duplicate"
printf '#!/bin/bash\nexit 1\n' > "$DOTFILES/scripts/demo.sh"
UL_ROWS=$'Stirling PDF\t1\t2'
out="$(do_userlocal </dev/null)"; rc=$?
assert_rc "$rc" 1 'updater execution failure is propagated'
assert_contains "$(cat "$LOG")" 'FAIL user-local Stirling PDF' 'execution failure persists in log'
assert_summary
