#!/bin/bash
# A user-local tool whose versions do not come from GitHub must still be seen.
#
# userlocal_update_rows only ever knew one version source: `repo=owner/name`,
# resolved through the GitHub releases API. The ChatGPT desktop app is installed
# user-local (see scripts/setup-chatgpt.sh) but publishes its versions in an RPM
# repository, not on GitHub — so under the old code its manifest was skipped and
# a new release would have been reported by nothing at all. That is the failure
# setup-chatgpt.sh's own header warned about when the app was still layered:
# "invisible to the Waybar update indicator forever".
#
# Hermetic: the probe is a stub script, so no network and no dependency on what
# upstream currently publishes.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cache="$tmp/cache"; manifests="$tmp/share/dotfiles-updates"; repo="$tmp/repo"
mkdir -p "$cache" "$manifests" "$repo/scripts"

# A stand-in for the real repo: the probe must be resolved against $DOTFILES.
cat > "$repo/scripts/probe.sh" <<'STUB'
#!/bin/bash
[[ "$1" == "--print-latest-version" ]] && { echo "9.9.9-1"; exit 0; }
exit 1
STUB
chmod +x "$repo/scripts/probe.sh"

cat > "$manifests/demo" <<'MANIFEST'
name=demo
installed_version=1.0.0-1
version_probe=scripts/probe.sh --print-latest-version
updater=scripts/probe.sh
MANIFEST

run_rows() {
    XDG_CACHE_HOME="$cache" XDG_DATA_HOME="$tmp/share" DOTFILES="$repo" bash -c '
        source "$1/scripts/lib-updates.sh"; userlocal_update_rows' _ "$DIR"
}

rows="$(run_rows)"
assert_contains "$rows" "demo" "a manifest with a version_probe is not skipped"
assert_contains "$rows" "9.9.9-1" "the probe's version is what gets reported"

# ── up to date must stay silent ───────────────────────────────────────────
sed -i 's/^installed_version=.*/installed_version=9.9.9-1/' "$manifests/demo"
rm -rf "$cache/userlocal-tags"
rows2="$(run_rows)"
[[ -z "$rows2" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: nothing reported when the installed version is current"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: reported an update while current (got [$rows2])"; }

# ── a probe that cannot answer must not read as "up to date" ──────────────
# Same rule as the OS and Flatpak sources: silence from a check that failed is
# not the same as a clean result, so a failing probe reports nothing rather than
# a false all-clear — and must not crash the badge either.
sed -i 's/^installed_version=.*/installed_version=1.0.0-1/' "$manifests/demo"
rm -rf "$cache/userlocal-tags"
printf '#!/bin/bash\nexit 1\n' > "$repo/scripts/probe.sh"
rows3="$(run_rows)"; rc=$?
# rc 1 is the point: a lookup that could not answer must SAY so. It used to
# `continue` silently, which made a rate-limited GitHub reply indistinguishable
# from "no newer release" — the same failure the OS and Flatpak sources were
# fixed for. The caller turns this into "could not check" in the tooltip.
assert_rc "$rc" "1" "a failing probe signals that it could not check"
[[ -z "$rows3" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: a failing probe reports nothing rather than a wrong version"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: a failing probe produced a row (got [$rows3])"; }

# ── a probe pointing outside the repo must be refused ─────────────────────
cat > "$manifests/demo" <<'MANIFEST'
name=evil
installed_version=1.0.0-1
version_probe=/usr/bin/id
MANIFEST
rm -rf "$cache/userlocal-tags"
rows4="$(run_rows)"
[[ -z "$rows4" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: a probe outside the dotfiles repo is not executed"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: ran a probe from outside the repo (got [$rows4])"; }

# ── and the badge must say it, not quietly render an all-clear ───────────
badge_cache="$tmp/cache-badge"; mkdir -p "$badge_cache"
PATH="$stub:$PATH" XDG_CACHE_HOME="$badge_cache" XDG_DATA_HOME="$tmp/share" DOTFILES="$repo" \
    bash "$DIR/scripts/updates-waybar.sh" --compute >/dev/null 2>&1
badge="$(cat "$badge_cache/waybar-updates.json" 2>/dev/null)"
assert_contains "$badge" "User-local apps: could not check" "the tooltip states plainly that the check failed"
klass="$(printf '%s' "$badge" | sed -n 's/.*"class":"\([^"]*\)".*/\1/p')"
[[ "$klass" != "uptodate" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: badge is not 'uptodate' when a version lookup failed"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: badge says 'uptodate' after failing to check"; }

assert_summary
