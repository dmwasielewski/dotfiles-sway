#!/bin/bash
# An update that FAILED to install must not look like one nobody ran yet.
#
# Regression (2026-09-01): a third-party layered package shipped a %post that
# writes under /var, which is read-only inside rpm-ostree's scriptlet sandbox.
# `set -e` in the scriptlet aborted the whole transaction, so EVERY
# `rpm-ostree upgrade` failed — base updates included. The menu logged
# "FAIL rpm-ostree upgrade" and nothing else kept that fact: the tooltip went on
# saying "OS: 1 packages → new version" indefinitely, which is exactly what it
# says when the user simply has not run the updater. The user reported the
# indicator as broken; it was telling the truth about the wrong thing.
#
# Same class as test_unknown_not_uptodate.sh: a state the module cannot act on
# must be stated, not collapsed into a state that looks routine.
#
# Hermetic: rpm-ostree is stubbed, so no network and no dependency on the host's
# actual deployment.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"; mkdir -p "$stub"

# rpm-ostree: one package pending, nothing staged — the exact shape the host was
# in while the upgrade kept failing.
cat > "$stub/rpm-ostree" <<'STUB'
#!/bin/bash
if [[ "$1" == "upgrade" && "$2" == "--check" ]]; then
    echo "AvailableUpdate:"
    echo "           Diff: 1 upgraded"
    exit 0
fi
if [[ "$1" == "status" ]]; then
    echo '{"deployments":[{"booted":true,"staged":false,"version":"44.0","timestamp":0}]}'
    exit 0
fi
exit 0
STUB
# No flatpak/containers/user-local noise: the OS branch is what is under test.
printf '#!/bin/bash\nexit 0\n' > "$stub/flatpak"
printf '#!/bin/bash\nexit 0\n' > "$stub/distrobox"
printf '#!/bin/bash\nexit 0\n' > "$stub/toolbox"
printf '#!/bin/bash\nexit 0\n' > "$stub/podman"
chmod +x "$stub"/*

cache="$tmp/cache"; mkdir -p "$cache"
REASON="error: Running %post for somepkg: bwrap(/bin/sh): Child process exited with code 1"

# ── the recorded failure must reach the tooltip ───────────────────────────
(
    PATH="$stub:$PATH" XDG_CACHE_HOME="$cache"
    export PATH XDG_CACHE_HOME
    # shellcheck source=scripts/lib-updates.sh
    source "$DIR/scripts/lib-updates.sh"
    os_fail_record "$REASON"
)
PATH="$stub:$PATH" XDG_CACHE_HOME="$cache" bash "$DIR/scripts/updates-waybar.sh" --compute >/dev/null 2>&1
badge="$(cat "$cache/waybar-updates.json" 2>/dev/null)"

assert_contains "$badge" "last attempt FAILED" "tooltip says the update was tried and failed"
assert_contains "$badge" "Child process exited with code 1" "tooltip carries the actual error, not just a flag"

klass="$(printf '%s' "$badge" | sed -n 's/.*"class":"\([^"]*\)".*/\1/p')"
[[ "$klass" != "uptodate" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: badge is not 'uptodate' while an upgrade keeps failing"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: badge says 'uptodate' with a failing upgrade"; }

# ── a stale marker must clear itself once the OS is actually current ──────
cache2="$tmp/cache2"; mkdir -p "$cache2"
cat > "$stub/rpm-ostree" <<'STUB'
#!/bin/bash
if [[ "$1" == "upgrade" && "$2" == "--check" ]]; then
    echo "No upgrade available."
    exit 0
fi
if [[ "$1" == "status" ]]; then
    echo '{"deployments":[{"booted":true,"staged":false,"version":"44.0","timestamp":0}]}'
    exit 0
fi
exit 0
STUB
chmod +x "$stub/rpm-ostree"
(
    PATH="$stub:$PATH" XDG_CACHE_HOME="$cache2"
    export PATH XDG_CACHE_HOME
    source "$DIR/scripts/lib-updates.sh"
    os_fail_record "$REASON"
)
PATH="$stub:$PATH" XDG_CACHE_HOME="$cache2" bash "$DIR/scripts/updates-waybar.sh" --compute >/dev/null 2>&1
badge2="$(cat "$cache2/waybar-updates.json" 2>/dev/null)"
[[ "$badge2" != *"last attempt FAILED"* ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: the failure marker clears once the OS is current again"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: a stale failure keeps showing after the OS went current"; }
[[ ! -f "$cache2/os-upgrade-fail" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: the marker file itself is removed, not just hidden"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: marker file survives an up-to-date OS"; }

assert_summary
