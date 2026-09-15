#!/bin/bash
# "Update everything" must attempt the security-critical Fedora deployment
# before spending time on application and container updates. A Fedora failure
# remains non-fatal to the later independent update sources.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"; mkdir -p "$stub"
cache="$tmp/cache"; mkdir -p "$cache"
state="$tmp/state"; mkdir -p "$state"
home="$tmp/home"; mkdir -p "$home"

cat > "$stub/rpm-ostree" <<'STUB'
#!/bin/bash
if [[ "$1" == "upgrade" && "${2:-}" == "--check" ]]; then
    echo "AvailableUpdate:"
    echo "        Version: 44.99"
    echo "           Diff: 1 upgraded"
    exit 0
fi
if [[ "$1" == "status" ]]; then
    if [[ "$OS_MODE" == "staged" ]]; then
        echo '{"deployments":[{"booted":false,"staged":true,"version":"44.99","timestamp":0},{"booted":true,"staged":false,"version":"44.0","timestamp":0}]}'
    else
        echo '{"deployments":[{"booted":true,"staged":false,"version":"44.0","timestamp":0}]}'
    fi
    exit 0
fi
if [[ "$1" == "upgrade" ]]; then
    echo os >> "$ACTION_LOG"
    if [[ "$OS_MODE" == "fail" ]]; then
        echo "error: a non-cache OS failure"
        exit 1
    fi
    echo "Upgrade complete"
    exit 0
fi
exit 0
STUB

cat > "$stub/flatpak" <<'STUB'
#!/bin/bash
case "$1" in
    list)      echo user ;;
    update)    echo flatpak >> "$ACTION_LOG" ;;
    remote-ls|history|ps) ;;
esac
exit 0
STUB

cat > "$stub/systemctl" <<'STUB'
#!/bin/bash
[[ "$1" == "reboot" ]] && echo reboot >> "$ACTION_LOG"
exit 0
STUB

for cmd in distrobox toolbox podman curl setsid clear; do
    printf '#!/bin/bash\nexit 0\n' > "$stub/$cmd"
done
chmod +x "$stub"/*

action_log="$tmp/actions"
PATH="$stub:$PATH" \
HOME="$home" \
XDG_CACHE_HOME="$cache" \
XDG_STATE_HOME="$state" \
OS_MODE="fail" \
ACTION_LOG="$action_log" \
    bash "$DIR/scripts/updates-menu.sh" <<< $'6\n\nq\n' > "$tmp/output" 2>&1

assert_eq "$(cat "$action_log")" $'os\nflatpak' "Update everything runs Fedora before independent application updates"
assert_contains "$(cat "$tmp/output")" "Fedora OS failed" "an OS failure is reported after later sources still run"

# When Fedora stages successfully, the reboot action must remain last: all
# independent updates finish before the user is asked to restart.
: > "$action_log"
cache2="$tmp/cache2"; mkdir -p "$cache2"
state2="$tmp/state2"; mkdir -p "$state2"
PATH="$stub:$PATH" \
HOME="$home" \
XDG_CACHE_HOME="$cache2" \
XDG_STATE_HOME="$state2" \
OS_MODE="staged" \
ACTION_LOG="$action_log" \
    bash "$DIR/scripts/updates-menu.sh" <<< $'6\ny\n\nq\n' > "$tmp/output2" 2>&1

assert_eq "$(cat "$action_log")" $'os\nflatpak\nreboot' "the reboot prompt waits until independent updates finish"

assert_summary
