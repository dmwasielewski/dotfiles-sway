#!/bin/bash
# A check that could not answer must try again soon, not in three hours.
#
# The badge caches for 3h. Until now a FAILED check kept its "could not check"
# for that whole window: a laptop resumed before NetworkManager had connected, a
# repo having a bad day, or an rpm-ostree transaction held by something else all
# cost three hours of a stale answer. Damian chose backoff over a resume hook
# (2026-09-10) precisely because it fixes the class rather than one trigger.
#
# Two things must hold: a round that did not get a straight answer schedules a
# retry with a growing delay, and a successful round clears it completely.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"; mkdir -p "$stub"
cache="$tmp/cache"; mkdir -p "$cache"

printf '#!/bin/bash\nexit 0\n' > "$stub/flatpak"
printf '#!/bin/bash\nexit 0\n' > "$stub/distrobox"
printf '#!/bin/bash\nexit 0\n' > "$stub/toolbox"
printf '#!/bin/bash\nexit 0\n' > "$stub/podman"
# An rpm-ostree that cannot answer — the shape of an unreachable repo.
cat > "$stub/rpm-ostree" <<'STUB'
#!/bin/bash
[[ "$1" == "status" ]] && { echo '{"deployments":[{"booted":true,"staged":false}]}'; exit 0; }
echo "error: Could not connect to server" >&2
exit 1
STUB
chmod +x "$stub"/*

run() { PATH="$stub:$PATH" XDG_CACHE_HOME="$cache" \
        bash "$DIR/scripts/updates-waybar.sh" --compute >/dev/null 2>&1; }
retry_delay() {   # seconds from now until the scheduled retry
    local at; at="$(sed -n '2p' "$cache/waybar-updates.retry" 2>/dev/null)"
    [[ "$at" =~ ^[0-9]+$ ]] || { echo -1; return; }
    echo $(( at - $(date +%s) ))
}

run
d1="$(retry_delay)"
[[ "$d1" -gt 0 && "$d1" -le 70 ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: first failure retries within about a minute (${d1}s)"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: first retry not scheduled soon (got ${d1}s)"; }
[[ "$d1" -lt 10800 ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: sooner than the 3h cache life it replaces"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: no better than waiting for the cache to expire"; }

run
d2="$(retry_delay)"
[[ "$d2" -gt "$d1" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: the delay grows while it keeps failing (${d1}s → ${d2}s)"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: no backoff — hammers a broken source (${d1}s → ${d2}s)"; }

# ── a good round must clear it, or the backoff outlives its cause ─────────
cat > "$stub/rpm-ostree" <<'STUB'
#!/bin/bash
[[ "$1" == "status" ]] && { echo '{"deployments":[{"booted":true,"staged":false}]}'; exit 0; }
echo "No upgrade available."
exit 0
STUB
chmod +x "$stub/rpm-ostree"
run
[[ ! -f "$cache/waybar-updates.retry" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: a successful check clears the retry schedule"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: retry state survived a successful check"; }

assert_summary
