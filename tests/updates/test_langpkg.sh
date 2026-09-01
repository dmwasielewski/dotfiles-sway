#!/bin/bash
# npm/pip packages inside containers must be a source like any other.
#
# The module had four sources — Flatpak, containers, OS, user-local — and none
# of them updated a single npm or pip package. `do_containers` runs
# `distrobox upgrade` / toolbox `dnf`, i.e. the DISTRO package manager inside the
# container; claude, codex, codewhale and markdownlint-cli2 are installed on top
# of it with `npm install -g`, and shell-gpt / faster-whisper with
# `pip3 install --user`. The tools used every day were updated by nobody and
# drifted until someone noticed by hand (BACKLOG 12, found 2026-08-14).
#
# Hermetic: containers and their package managers are all stubbed.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"; mkdir -p "$stub"

# One distrobox container and one toolbox container, discovered the usual way.
cat > "$stub/distrobox" <<'STUB'
#!/bin/bash
if [[ "$1" == "list" ]]; then
    echo "ID           | NAME     | STATUS  | IMAGE"
    echo "0123456789ab | demobox  | Up      | ubuntu:26.04"
    exit 0
fi
if [[ "$1" == "enter" ]]; then
    export FAKE_CONTAINER="$3"
    shift 4                       # enter --name <n> --
    exec "$@"
fi
exit 0
STUB
cat > "$stub/toolbox" <<'STUB'
#!/bin/bash
if [[ "$1" == "list" ]]; then
    echo "CONTAINER ID  CONTAINER NAME  CREATED  STATUS  IMAGE NAME"
    echo "0123456789ab  demotbx         1 day    running fedora:44"
    exit 0
fi
if [[ "$1" == "run" ]]; then
    export FAKE_CONTAINER="$3"
    shift 3                       # run --container <n>
    exec "$@"
fi
exit 0
STUB
printf '#!/bin/bash\nexit 1\n' > "$stub/podman"
printf '#!/bin/bash\nexit 1\n' > "$stub/flatpak"
printf '#!/bin/bash\nexit 1\n' > "$stub/rpm-ostree"

# npm reports one outdated global package and exits 1 — which is npm's NORMAL
# exit code when something is outdated, not a failure. Treating it as one is the
# obvious way to get this wrong.
cat > "$stub/npm" <<'STUB'
#!/bin/bash
[[ "$1 $2" == "-g root" ]] && { echo "/shared/npm"; exit 0; }
if [[ "$1 $2" == "-g outdated" ]]; then
    # The Fedora toolbox reports an empty set for the very same shared prefix
    # (it sees $HOME through /home -> /var/home, so npm treats the tree as
    # linked and skips it). Observed on the real system 2026-09-01.
    [[ "$FAKE_CONTAINER" == "demotbx" ]] && { echo "{}"; exit 0; }
    echo '{"@openai/codex":{"current":"1.0.0","wanted":"1.2.0","latest":"1.2.0"}}'
    exit 1
fi
exit 0
STUB
# pip has one outdated user package.
cat > "$stub/pip3" <<'STUB'
#!/bin/bash
if [[ "$*" == *"--outdated"* ]]; then
    echo '[{"name":"shell-gpt","version":"1.4.0","latest_version":"1.5.1"}]'
    exit 0
fi
exit 0
STUB
# python3 is what reports pip's user site; give each container its own, so a
# genuinely separate install still produces a row of its own.
cat > "$stub/python3" <<STUB
#!/bin/bash
if [[ "\$*" == *"getusersitepackages"* ]]; then
    echo "/site/\${FAKE_CONTAINER:-unknown}"
    exit 0
fi
exec /usr/bin/python3 "\$@"
STUB
chmod +x "$stub"/*

cache="$tmp/cache"; mkdir -p "$cache"
run_rows() { PATH="$stub:$PATH" XDG_CACHE_HOME="$cache" bash -c '
    source "$1/scripts/lib-updates.sh"; langpkg_update_rows' _ "$DIR"; }

rows="$(run_rows)"
assert_contains "$rows" "@openai/codex" "an outdated npm global package is reported"
assert_contains "$rows" "1.0.0" "the installed npm version is reported"
assert_contains "$rows" "1.2.0" "the available npm version is reported"
assert_contains "$rows" "shell-gpt" "an outdated pip user package is reported"
assert_contains "$rows" "demobox" "the row names the distrobox container it came from"
assert_contains "$rows" "demotbx" "the toolbox container is queried too"

# The shared npm prefix must be reported ONCE, and by the container that can
# actually see it — an empty answer about a directory another container says
# has an outdated package is wrong, not clean.
npm_rows="$(printf '%s\n' "$rows" | grep -c "npm" || true)"
assert_eq "$npm_rows" "1" "a shared npm prefix is reported once, not once per container"
assert_contains "$rows" "demobox	npm" "the container that can see the packages is the one named"

# ── nothing outdated must be silent ──────────────────────────────────────
printf '#!/bin/bash\n[[ "$1 $2" == "-g outdated" ]] && { echo "{}"; exit 0; }\nexit 0\n' > "$stub/npm"
printf '#!/bin/bash\n[[ "$*" == *"--outdated"* ]] && { echo "[]"; exit 0; }\nexit 0\n' > "$stub/pip3"
chmod +x "$stub/npm" "$stub/pip3"
printf '#!/bin/bash\n[[ "$1 $2" == "-g root" ]] && { echo /shared/npm; exit 0; }\n[[ "$1 $2" == "-g outdated" ]] && { echo "{}"; exit 0; }\nexit 0\n' > "$stub/npm"
chmod +x "$stub/npm"
rows2="$(run_rows)"
[[ -z "$rows2" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: nothing reported when every package is current"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: reported rows with nothing outdated (got [$rows2])"; }

# ── a query that could not run must not read as "up to date" ─────────────
# The rule this whole module exists for: silence from a check that failed is not
# the same as a clean result. An offline npm prints an error and no valid JSON.
printf '#!/bin/bash\necho "npm ERR! network" >&2\nexit 1\n' > "$stub/npm"
chmod +x "$stub/npm"
run_rows >/dev/null 2>&1; rc=$?
assert_rc "$rc" "1" "langpkg_update_rows signals failure when a query could not run"

# ── a container without npm/pip is not a failure ─────────────────────────
rm -f "$stub/npm" "$stub/pip3"
run_rows >/dev/null 2>&1; rc2=$?
assert_rc "$rc2" "0" "a container with no npm/pip is skipped, not reported as broken"

# ── end to end: the badge must show the section ──────────────────────────
cat > "$stub/npm" <<'STUB'
#!/bin/bash
[[ "$1 $2" == "-g root" ]] && { echo "/shared/npm"; exit 0; }
if [[ "$1 $2" == "-g outdated" ]]; then
    # The Fedora toolbox reports an empty set for the very same shared prefix
    # (it sees $HOME through /home -> /var/home, so npm treats the tree as
    # linked and skips it). Observed on the real system 2026-09-01.
    [[ "$FAKE_CONTAINER" == "demotbx" ]] && { echo "{}"; exit 0; }
    echo '{"@openai/codex":{"current":"1.0.0","wanted":"1.2.0","latest":"1.2.0"}}'
    exit 1
fi
exit 0
STUB
chmod +x "$stub/npm"
cache2="$tmp/cache2"; mkdir -p "$cache2"
PATH="$stub:$PATH" XDG_CACHE_HOME="$cache2" bash "$DIR/scripts/updates-waybar.sh" --compute >/dev/null 2>&1
badge="$(cat "$cache2/waybar-updates.json" 2>/dev/null)"
assert_contains "$badge" "@openai/codex" "the tooltip lists the outdated language package"
klass="$(printf '%s' "$badge" | sed -n 's/.*"class":"\([^"]*\)".*/\1/p')"
[[ "$klass" != "uptodate" ]] \
    && { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: an outdated npm package makes the badge ask for attention"; } \
    || { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: badge stayed 'uptodate' with an outdated npm package"; }

assert_summary
