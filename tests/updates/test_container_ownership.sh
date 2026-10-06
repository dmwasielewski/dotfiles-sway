#!/bin/bash
# A Distrobox from a Toolbox image must never be entered through Toolbox.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/cache"
cat > "$tmp/bin/distrobox" <<'STUB'
#!/bin/bash
[[ "$1" == list ]] && printf 'ID | NAME | STATUS | IMAGE\n0123456789ab | helper | Up | fedora-toolbox:44\n'
exit 0
STUB
cat > "$tmp/bin/toolbox" <<'STUB'
#!/bin/bash
printf 'CONTAINER ID CONTAINER NAME CREATED STATUS IMAGE\n0123456789ab helper today running fedora-toolbox:44\nabcdef012345 dev today running fedora-toolbox:44\n'
STUB
chmod +x "$tmp/bin"/*
export PATH="$tmp/bin:$PATH" XDG_CACHE_HOME="$tmp/cache"
source "$DIR/scripts/lib-updates.sh"
assert_eq "$(discover_toolbox)" dev "Distrobox overlap excluded from Toolbox list"
assert_eq "$(discover_containers)" $'distrobox\thelper\ntoolbox\tdev' "each container has exactly one runtime owner"
container_exec() { printf '%s %s\n' "$1" "$2" > "$tmp/runtime"; }
container_exec_by_name helper true
assert_eq "$(cat "$tmp/runtime")" 'distrobox helper' "package execution uses the owning runtime"
# An empty Distrobox list must not hide actual Toolbox containers.
discover_distrobox() { :; }
assert_eq "$(discover_toolbox)" $'helper\ndev' "no overlaps when Distrobox list is empty"
# Retry a failed session check before declaring language updates impossible.
eval "$(sed -n '/^do_langpkg()/,/^do_os()/p' "$DIR/scripts/updates-menu.sh" | sed '$d')"
LP_OK=0 LP_ROWS='' LOG="$tmp/log"
refresh_langpkg() { echo retry >> "$tmp/retries"; LP_OK=1; LP_ROWS=''; }
output="$(do_langpkg)"; result=$?
assert_rc "$result" 2 "successful retry with no outdated packages is a clean result"
assert_eq "$(cat "$tmp/retries")" retry "failed cached check is retried once"
refresh_langpkg() { LP_OK=0; }
printf 'helper (npm): query failed\n' > "$CACHE_DIR/update-langpkg-errors"
output="$(do_langpkg)"; result=$?
assert_rc "$result" 1 "persistent query failure is not an all-clear"
assert_contains "$output" 'helper (npm)' "failure identifies the container and manager"
assert_summary
