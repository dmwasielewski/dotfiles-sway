#!/bin/bash
# "Could not check" must never be reported as "up to date".
#
# Regression (2026-08-18): the Waybar indicator sat neutral/grey for days while
# 11 Flatpak updates, a yazi update and a 27-package OS update were waiting.
# Root cause: every detector collapsed a FAILED query into zero. `flatpak_count`
# ran `flatpak remote-ls --updates 2>/dev/null | grep -c .`, so an unreachable
# Flathub produced 0 and the tooltip printed "Flatpak: up to date"; the OS branch
# printed "not yet checked (repo unreachable)" but added nothing to the badge.
# With containers freshly updated, the total was 0 and the badge said uptodate —
# a confident "nothing to do" produced by checking nothing at all.
#
# Hermetic: every external command is stubbed, so there is no network and no
# dependency on what is actually installed.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"; mkdir -p "$stub"

# flatpak: `list` works (so an installation is discovered), every remote query
# fails the way it does with no network — nothing on stdout, non-zero exit.
# Verified against the real binary: `flatpak remote-ls` exits 1 when it cannot
# reach a remote, and 0 on success.
cat > "$stub/flatpak" <<'STUB'
#!/bin/bash
[[ "$1" == "list" ]] && { echo "user"; exit 0; }
echo "error: Unable to load summary from remote flathub" >&2
exit 1
STUB
# No containers, so container staleness cannot mask the result under test.
printf '#!/bin/bash\nexit 0\n' > "$stub/distrobox"
printf '#!/bin/bash\nexit 0\n' > "$stub/toolbox"
printf '#!/bin/bash\nexit 0\n' > "$stub/podman"
printf '#!/bin/bash\necho "error: Could not connect to server" >&2\nexit 1\n' > "$stub/rpm-ostree"
printf '#!/bin/bash\nexit 6\n' > "$stub/curl"
chmod +x "$stub"/*

# ── unit: flatpak_count must signal that it could not check ───────────────
(
    PATH="$stub:$PATH"
    # shellcheck source=scripts/lib-updates.sh
    source "$DIR/scripts/lib-updates.sh"
    fp="$(flatpak_count)" && rc=0 || rc=$?
    echo "$fp|$rc" > "$tmp/unit"
)
IFS='|' read -r fp_out fp_rc < "$tmp/unit"
assert_eq "$fp_rc" "1" "flatpak_count reports failure when a remote cannot be queried"
assert_eq "$fp_out" "0" "flatpak_count still echoes a number so numeric callers keep working"

# ── end to end: the badge must not claim everything is fine ──────────────
cache="$tmp/cache"; mkdir -p "$cache"
PATH="$stub:$PATH" XDG_CACHE_HOME="$cache" bash "$DIR/scripts/updates-waybar.sh" --compute >/dev/null 2>&1
badge="$(cat "$cache/waybar-updates.json" 2>/dev/null)"

klass="$(printf '%s' "$badge" | sed -n 's/.*"class":"\([^"]*\)".*/\1/p')"
[[ "$klass" != "uptodate" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: badge is not 'uptodate' when nothing could be checked"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: badge says 'uptodate' after checking nothing"; }

[[ "$badge" != *"Flatpak: up to date"* ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: tooltip does not claim Flatpak is up to date"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: tooltip claims 'Flatpak: up to date' after a failed query"; }

assert_contains "$badge" "could not check" "tooltip says plainly that the check failed"

assert_summary
