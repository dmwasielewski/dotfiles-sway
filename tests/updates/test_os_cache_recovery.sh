#!/bin/bash
# A zero-byte RPM left in rpm-ostree's repo cache must not permanently block
# every Fedora update. Reproduce the real 2026-09-15 failure: the first upgrade
# rejects the empty RPM, cleanup removes repo metadata, and one retry succeeds.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"; mkdir -p "$stub"
cache="$tmp/cache"; mkdir -p "$cache"
state="$tmp/state"; mkdir -p "$state"
repomd="$tmp/repomd"; mkdir -p "$repomd/nordvpn/packages"
empty_rpm="$repomd/nordvpn/packages/nordvpn-5.4.0-1.x86_64.rpm"
: > "$empty_rpm"

cat > "$stub/rpm-ostree" <<'STUB'
#!/bin/bash
if [[ "$1" == "upgrade" && "${2:-}" == "--check" ]]; then
    echo "AvailableUpdate:"
    echo "        Version: 44.99"
    echo "           Diff: 1 upgraded"
    exit 0
fi
if [[ "$1" == "status" ]]; then
    echo '{"deployments":[{"booted":true,"staged":false,"version":"44.0","timestamp":0}]}'
    exit 0
fi
if [[ "$1" == "cleanup" && "${2:-}" == "-m" ]]; then
    echo cleanup >> "$ACTION_LOG"
    find "$RPMOSTREE_REPOMD_DIR" -type f -name '*.rpm' -size 0 -delete
    exit 0
fi
if [[ "$1" == "upgrade" ]]; then
    echo upgrade >> "$ACTION_LOG"
    attempts="$(wc -l < "$ACTION_LOG")"
    if [[ "$attempts" -eq 1 ]]; then
        echo "error: importing RPMs: package nordvpn cannot be verified: $RPMOSTREE_REPOMD_DIR/nordvpn/packages/nordvpn-5.4.0-1.x86_64.rpm could not be verified."
        exit 1
    fi
    echo "Upgrade complete"
    exit 0
fi
exit 0
STUB

# Keep the interactive menu isolated from the desktop and network. No Flatpak,
# container, language-package or user-local work is needed for option 5.
for cmd in flatpak distrobox toolbox podman curl setsid clear; do
    printf '#!/bin/bash\nexit 0\n' > "$stub/$cmd"
done
chmod +x "$stub"/*

action_log="$tmp/actions"
PATH="$stub:$PATH" \
HOME="$tmp/home" \
XDG_CACHE_HOME="$cache" \
XDG_STATE_HOME="$state" \
RPMOSTREE_REPOMD_DIR="$repomd" \
ACTION_LOG="$action_log" \
    bash "$DIR/scripts/updates-menu.sh" <<< $'5\n\nq\n' > "$tmp/output" 2>&1

actions="$(cat "$action_log" 2>/dev/null)"
assert_eq "$actions" $'upgrade\ncleanup\nupgrade' "an empty cached RPM triggers one cleanup and one retry"
assert_contains "$(cat "$tmp/output")" "Empty rpm-ostree cache entry detected" "the recovery is visible to the user"
[[ ! -e "$empty_rpm" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: cleanup removed the empty cached RPM"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: empty cached RPM survived cleanup"; }

# An unrelated empty file — including a filename that is a prefix of the failed
# one — must not reclassify a genuinely invalid non-empty RPM as cache corruption.
# The complete path named by rpm-ostree has to be the empty one.
mkdir -p "$repomd/other/packages"
: > "$repomd/other/packages/package.rpm"
printf 'not empty\n' > "$repomd/other/packages/package.rpm.rpm"
reason="error: package $repomd/other/packages/package.rpm.rpm cannot be verified"
if RPMOSTREE_REPOMD_DIR="$repomd" bash -c '
    source "$1/scripts/lib-updates.sh"
    os_failure_is_empty_cache "$2"
' _ "$DIR" "$reason"; then
    ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: an unrelated empty RPM weakened a real signature failure"
else
    ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: a non-empty invalid package remains blocked"
fi

assert_summary
