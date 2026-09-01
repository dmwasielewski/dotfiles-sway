#!/bin/bash
# lib-updates.sh — shared update-detection logic for Waybar indicator and menu.
# Single source of truth so the indicator count and the menu list always agree.
# No hardcoded names: containers, apps and OS state are all discovered at runtime.
#
# Source this file; do not execute it directly.

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
CONTAINER_STALE_DAYS="${CONTAINER_STALE_DAYS:-7}"

# ── Timestamp helpers (our record of when we last ran an update) ──────────
upd_ts_file()   { printf '%s/update-last-%s' "$CACHE_DIR" "$1"; }
upd_record()    { mkdir -p "$CACHE_DIR"; date +%s > "$(upd_ts_file "$1")"; }
upd_age_days()  {                      # echoes integer days, -1 if never
    local f; f="$(upd_ts_file "$1")"
    [[ -f "$f" ]] || { echo -1; return; }
    echo $(( ( $(date +%s) - $(cat "$f") ) / 86400 ))
}
upd_age_label() {                      # human-readable label
    local d; d="$(upd_age_days "$1")"
    if   [[ "$d" -lt 0 ]]; then echo "never"
    elif [[ "$d" -eq 0 ]]; then echo "today"
    else echo "${d}d ago"; fi
}

# ── Flatpak ───────────────────────────────────────────────────────────────
# flatpak_count            → integer number of user apps with updates
# flatpak_update_rows      → lines "appid<TAB>current<TAB>available"
# flatpak_last_label       → when flatpak was last updated by us
# Flatpak apps live across one or more installations (user, system, or custom
# ones in /etc/flatpak/installations.d/). Discover them dynamically rather than
# assuming scopes, then query each — flatpak reports all apps in an
# installation in a single call, so we don't loop over individual apps.
flatpak_installations() {              # installation names that actually hold apps
    command -v flatpak >/dev/null 2>&1 || return 0
    flatpak list --columns=installation 2>/dev/null | sort -u
}
_flatpak_scope_arg() {                 # map installation name → flatpak scope flag
    case "$1" in
        user)   echo "--user" ;;
        system) echo "--system" ;;
        *)      echo "--installation=$1" ;;
    esac
}
# Echoes the number of apps with updates, and RETURNS NON-ZERO when at least one
# installation could not be queried. That distinction is the whole point: the old
# version piped a failing `remote-ls` into `grep -c .`, so an unreachable Flathub
# produced the same 0 as a genuinely up-to-date system and the indicator went
# quiet while updates piled up. A count is only meaningful together with whether
# it could be obtained, so callers must check the status, not just the number.
flatpak_count() {
    command -v flatpak >/dev/null 2>&1 || { echo 0; return 0; }
    local total=0 inst scope out rc=0
    while IFS= read -r inst; do
        [[ -z "$inst" ]] && continue
        scope="$(_flatpak_scope_arg "$inst")"
        # Capture first: `flatpak remote-ls` exits non-zero when it cannot reach a
        # remote (verified against the real binary) and 0 on success, so its exit
        # status is the signal — piping straight into grep threw that away.
        if out="$(flatpak remote-ls $scope --updates 2>/dev/null)"; then
            total=$(( total + $(printf '%s' "$out" | grep -c . || true) ))
        else
            rc=1
        fi
    done < <(flatpak_installations)
    echo "$total"
    return "$rc"
}
flatpak_update_rows() {                # echoes "appid<TAB>current<TAB>available"
    command -v flatpak >/dev/null 2>&1 || return 0
    local inst scope updates cur appid avail
    while IFS= read -r inst; do
        [[ -z "$inst" ]] && continue
        scope="$(_flatpak_scope_arg "$inst")"
        updates="$(flatpak remote-ls $scope --updates --columns=application,version 2>/dev/null)" || continue
        [[ -z "$updates" ]] && continue
        while IFS=$'\t' read -r appid avail; do
            [[ -z "$appid" ]] && continue
            cur="$(flatpak info $scope "$appid" 2>/dev/null | awk -F': ' '/^[[:space:]]*Version:/ {print $2; exit}')"
            [[ -z "$cur" ]] && cur="—"
            # Flathub often republishes the SAME version with a new commit
            # (rebuild for an updated runtime/security fix). The version string
            # is unchanged, so label it clearly instead of showing "X → X".
            [[ -n "$avail" && "$cur" == "$avail" ]] && avail="$avail (rebuild)"
            printf '%s\t%s\t%s\n' "$appid" "$cur" "$avail"
        done <<< "$updates"
    done < <(flatpak_installations)
}
# Real last-updated date from flatpak's own history (native source).
flatpak_last_label() {
    command -v flatpak >/dev/null 2>&1 || { echo "unknown"; return; }
    local t
    t="$(flatpak history --columns=time,change 2>/dev/null \
         | awk -F'\t' '/update|deploy/ {last=$1} END{print last}')"
    [[ -z "$t" ]] && { echo "unknown"; return; }
    date -d "$t" +%Y-%m-%d 2>/dev/null || printf '%s' "$t"
}

# ── rpm-ostree (Fedora OS) ────────────────────────────────────────────────
# The check is slow and network-flaky, so callers run os_check_raw ONCE and
# pass the captured text to the os_parse_* helpers (no repeated subshell calls).
os_check_raw()  { rpm-ostree upgrade --check 2>&1 || true; }   # call once, capture
# staged_from_json: echo 1 if any deployment is staged (downloaded, pending the
# next reboot), else 0. Reads `rpm-ostree status --json` on stdin so it is unit-
# testable without rpm-ostree. The "staged" boolean is the authoritative signal —
# the old check grepped the human-readable status for the literal "(staged)",
# which current rpm-ostree no longer prints, so a real pending-reboot update was
# never detected (it showed amber instead of red "reboot to apply"). Same field
# and "staged and not booted" rule already used by setup-nordvpn.sh.
staged_from_json() {
    python3 -c $'import json,sys\ntry: d=json.load(sys.stdin)\nexcept Exception: print(0); sys.exit(0)\nprint(1 if any(x.get("staged") and not x.get("booted") for x in d.get("deployments",[])) else 0)' 2>/dev/null || echo 0
}
os_staged()     { rpm-ostree status --json 2>/dev/null | staged_from_json; }

# ── "Last known good" cache (professional stale-fallback pattern) ──────────
# When a repo is unreachable the live check fails; rather than lie "up to
# date", we keep the last SUCCESSFUL check and show its date. Like apt/dnf
# serving cached metadata when offline.
OS_CACHE_FILE="$CACHE_DIR/os-check.cache"
OS_CACHE_TS_FILE="$CACHE_DIR/os-check.ts"

# Refresh the cache from a live check (3 retries for transient repo hiccups).
# Echoes freshness: "fresh" (just checked OK) | "stale" (using old cache) | "none".
os_refresh_cache() {
    local out try
    for try in 1 2 3; do
        out="$(os_check_raw)"
        if [[ "$(os_parse_state "$out")" != "unknown" ]]; then
            mkdir -p "$CACHE_DIR"
            printf '%s' "$out" > "$OS_CACHE_FILE"
            date +%s > "$OS_CACHE_TS_FILE"
            echo "fresh"; return
        fi
        sleep 1
    done
    [[ -f "$OS_CACHE_FILE" ]] && echo "stale" || echo "none"
}
os_cached_raw() { cat "$OS_CACHE_FILE" 2>/dev/null; }
os_cache_date() {                      # date label of the last successful check
    [[ -f "$OS_CACHE_TS_FILE" ]] || { echo "never"; return; }
    date -d "@$(cat "$OS_CACHE_TS_FILE")" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown"
}

# ── Last OS upgrade ATTEMPT ───────────────────────────────────────────────
# An update that failed to install renders identically to one nobody has run
# yet: both are just "OS: N packages" in the tooltip. On 2026-09-01 that cost a
# session — a layered package's %post wrote under /var, which is read-only
# inside rpm-ostree's scriptlet sandbox, so `rpm-ostree upgrade` aborted every
# time and took the base update with it (the transaction is atomic). The menu
# logged the failure and nothing carried it any further, so the badge sat amber
# for as long as the package stayed broken and the user reported the indicator
# as lying. It was not: it had no way to say "already tried, cannot install".
#
# The marker is written by whoever runs the upgrade and read by the badge, so
# the two never disagree — the same single-source-of-truth rule as the rest of
# this file. Nothing about any particular package is recorded here beyond the
# error text the upgrade itself printed.
OS_FAIL_FILE="$CACHE_DIR/os-upgrade-fail"
os_fail_record() {                     # $1 = error text from the failed upgrade
    mkdir -p "$CACHE_DIR"
    { date +%s; printf '%s\n' "${1:-}"; } > "$OS_FAIL_FILE"
}
os_fail_clear()  { rm -f "$OS_FAIL_FILE"; }
os_failed()      { [[ -f "$OS_FAIL_FILE" ]] && echo 1 || echo 0; }
os_fail_date()   {
    local ts; ts="$(sed -n '1p' "$OS_FAIL_FILE" 2>/dev/null)"
    [[ -n "$ts" ]] || { echo "unknown"; return; }
    date -d "@$ts" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown"
}
os_fail_reason() { sed -n '2p' "$OS_FAIL_FILE" 2>/dev/null; }

os_parse_pending() {                   # $1 = raw check text
    printf '%s' "$1" | grep -q "AvailableUpdate:" && echo 1 || echo 0
}
# os_parse_state: "pending" | "current" | "unknown"
# "unknown" means the check could not complete (e.g. a repo was unreachable),
# so we must NOT claim the system is up to date.
os_parse_state() {                     # $1 = raw check text
    if   printf '%s' "$1" | grep -q "AvailableUpdate:";                    then echo "pending"
    elif printf '%s' "$1" | grep -qiE "no upgrade available|no updates available|no available updates"; then echo "current"
    elif printf '%s' "$1" | grep -qiE "error:|could not connect|cannot update repo"; then echo "unknown"
    # Default to "unknown", never "current": unrecognised output (new rpm-ostree
    # wording, auth/proxy failure, localised text) must not read as up to date.
    # "unknown" degrades gracefully via the last-known-good OS cache.
    else echo "unknown"; fi
}
os_parse_version() {                   # $1 = raw check text
    printf '%s\n' "$1" | awk -F": " '/^[[:space:]]*Version:/ {print $2; exit}'
}
os_parse_pkgcount() {                  # $1 = raw check text
    printf '%s\n' "$1" | grep -oP '^\s*Diff:\s*\K[0-9]+' | head -1 || true
}
os_parse_sec() {                       # $1 = severity, $2 = raw check text
    local line
    line="$(printf '%s\n' "$2" | awk -F": " '/SecAdvisories:/ {print $2}' | head -1)"
    local n; n="$(printf '%s' "$line" | grep -oiP "[0-9]+(?=[[:space:]]+$1)" | head -1)"
    echo "${n:-0}"
}
# Total security advisories (all severities summed) = the "Important" bucket.
os_parse_sec_total() {                 # $1 = raw check text
    local i m l u
    i="$(os_parse_sec important "$1")"; m="$(os_parse_sec moderate "$1")"
    l="$(os_parse_sec low "$1")";       u="$(os_parse_sec unknown "$1")"
    echo $(( i + m + l + u ))
}
os_current_version() {
    rpm-ostree status --json 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['deployments'][0].get('version',''))" 2>/dev/null
}
os_last_label() {
    local ts
    ts="$(rpm-ostree status --json 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['deployments'][0].get('timestamp',0))" 2>/dev/null)"
    [[ -z "$ts" || "$ts" == "0" ]] && { echo "unknown"; return; }
    date -d "@$ts" +%Y-%m-%d 2>/dev/null || echo "unknown"
}

# ── Containers (distrobox + toolbox, discovered dynamically) ──────────────
# discover_distrobox    → container names, one per line
# discover_toolbox      → container names, one per line
# container_is_stale <name> → 0 (stale/never) or 1 (fresh) as exit code
discover_distrobox() {
    command -v distrobox >/dev/null 2>&1 || return 0
    distrobox list --no-color 2>/dev/null \
        | awk -F'|' '/^[0-9a-f]{12}/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($2 != "") print $2}'
}
discover_toolbox() {
    command -v toolbox >/dev/null 2>&1 || return 0
    toolbox list --containers 2>/dev/null | awk 'NR>1 && NF>=2 {print $2}'
}
# Effective "last touched" epoch: our update timestamp if present, else the
# podman container creation time (a freshly created container is not stale).
container_epoch() {                    # echoes epoch seconds, 0 if unknown
    local name="$1" f ts
    f="$(upd_ts_file "container-$name")"
    [[ -f "$f" ]] && { cat "$f"; return; }
    # Go template .Unix avoids the unparseable "+0100 BST" string from date -d
    ts="$(podman inspect "$name" --format '{{.Created.Unix}}' 2>/dev/null)"
    [[ "$ts" =~ ^[0-9]+$ ]] && { echo "$ts"; return; }
    echo 0
}
container_age_label() {                # human label from effective epoch
    local e; e="$(container_epoch "$1")"
    [[ "$e" -eq 0 ]] && { echo "unknown"; return; }
    local d=$(( ( $(date +%s) - e ) / 86400 ))
    if   [[ "$d" -le 0 ]]; then echo "today"
    else echo "${d}d ago"; fi
}
container_is_stale() {                 # exit 0 = stale (needs attention)
    local e; e="$(container_epoch "$1")"
    [[ "$e" -eq 0 ]] && return 0
    local d=$(( ( $(date +%s) - e ) / 86400 ))
    [[ "$d" -ge "$CONTAINER_STALE_DAYS" ]]
}

# ── User-local apps (GitHub-release tools without a package or self updater) ─
# Most tools are covered elsewhere: packaged ones by rpm-ostree/dnf/apt, Flatpaks
# by flatpak, and some (e.g. zed) self-update. What is left are GitHub-release
# binaries that are in no distro repo AND have no self-updater (e.g. yazi). Each
# such tool self-registers a manifest when its setup script installs it, so this
# logic stays generic — it discovers whatever manifests exist, with no tool names
# hardcoded. Manifest is key=value: name, repo (owner/name), installed_version,
# updater (path relative to the dotfiles repo).
USERLOCAL_MANIFEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles-updates"
USERLOCAL_TAG_CACHE="$CACHE_DIR/userlocal-tags"   # repo→tag, last-known-good for offline

userlocal_manifests() {                # paths of manifest files, one per tool
    [[ -d "$USERLOCAL_MANIFEST_DIR" ]] || return 0
    find "$USERLOCAL_MANIFEST_DIR" -maxdepth 1 -type f 2>/dev/null | sort
}
_ul_field() { grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2-; }   # $1=manifest $2=key

# Latest release tag for a repo, cached as last-known-good with a 3h TTL so the
# menu/indicator don't hammer the GitHub API on every redraw. Echoes the tag, or
# the cached value when GitHub is unreachable, or "" if never seen — so we never
# falsely claim "up to date" while offline.
userlocal_latest_tag() {               # $1=repo
    local repo="$1" cache_f json tag age
    cache_f="$USERLOCAL_TAG_CACHE/$(printf '%s' "$repo" | tr '/' '_')"
    if [[ -f "$cache_f" ]]; then
        age=$(( $(date +%s) - $(stat -c %Y "$cache_f" 2>/dev/null || echo 0) ))
        [[ "$age" -lt 10800 ]] && { cat "$cache_f"; return; }
    fi
    # Capture before parsing — piping curl into grep -m1 trips SIGPIPE under pipefail.
    json="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)"
    tag="$(printf '%s' "$json" | grep -m1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')"
    if [[ -n "$tag" ]]; then
        mkdir -p "$USERLOCAL_TAG_CACHE"; printf '%s' "$tag" > "$cache_f"
        printf '%s' "$tag"; return
    fi
    cat "$cache_f" 2>/dev/null          # offline → last known (even past the TTL)
}

# Is $2 a strictly newer version than $1? (a leading "v" is ignored)
_ul_newer() {
    local a="${1#v}" b="${2#v}"
    [[ "$a" != "$b" && "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -1)" == "$b" ]]
}

# Latest version from a manifest's own probe command, for tools that publish
# versions somewhere other than GitHub releases. The ChatGPT desktop app is the
# first: it is installed user-local from OpenAI's RPM repository, so `repo=` has
# nothing to point at and without this branch its manifest was silently skipped
# and a new release would have been reported by nothing at all.
#
# The probe is a script IN THIS REPO plus arguments (e.g.
# "scripts/setup-chatgpt.sh --print-latest-version"); the first word is resolved
# against $DOTFILES and anything that does not land on an executable file inside
# it is refused, so a manifest can never turn into an arbitrary command. Cached
# on the same 3h last-known-good terms as the GitHub lookup — this runs from the
# badge's refresh, and a probe that reaches the network must not run on every
# redraw.
userlocal_probe_version() {            # $1 = probe command line
    local probe="$1" cache_f script out age
    cache_f="$USERLOCAL_TAG_CACHE/probe_$(printf '%s' "$probe" | tr -c 'A-Za-z0-9' '_')"
    if [[ -f "$cache_f" ]]; then
        age=$(( $(date +%s) - $(stat -c %Y "$cache_f" 2>/dev/null || echo 0) ))
        [[ "$age" -lt 10800 ]] && { cat "$cache_f"; return; }
    fi
    # shellcheck disable=SC2086
    set -- $probe                      # deliberate word splitting: probe is a command line
    script="${DOTFILES:-$HOME/dotfiles-sway}/$1"
    [[ "$1" != /* && -x "$script" ]] || return 0
    shift
    out="$(timeout 30 "$script" "$@" 2>/dev/null | head -1)" || return 0
    [[ -n "$out" ]] || return 0
    mkdir -p "$USERLOCAL_TAG_CACHE"; printf '%s' "$out" > "$cache_f"
    printf '%s' "$out"
}

# Outdated user-local tools as "name<TAB>installed<TAB>latest".
userlocal_update_rows() {
    local m name repo probe inst latest
    while IFS= read -r m; do
        [[ -z "$m" ]] && continue
        name="$(_ul_field "$m" name)"; repo="$(_ul_field "$m" repo)"
        probe="$(_ul_field "$m" version_probe)"
        inst="$(_ul_field "$m" installed_version)"
        [[ -z "$inst" ]] && continue
        if   [[ -n "$repo" ]];  then latest="$(userlocal_latest_tag "$repo")"
        elif [[ -n "$probe" ]]; then latest="$(userlocal_probe_version "$probe")"
        else continue; fi
        [[ -z "$latest" ]] && continue           # unknown/offline → don't flag
        _ul_newer "$inst" "$latest" && printf '%s\t%s\t%s\n' "${name:-$repo}" "$inst" "${latest#v}"
    done < <(userlocal_manifests)
}
userlocal_count() { userlocal_update_rows | grep -c . || true; }

# Absolute path of a manifest's updater script, resolved against the dotfiles repo.
userlocal_updater_path() {             # $1=manifest path
    local rel; rel="$(_ul_field "$1" updater)"
    [[ -z "$rel" ]] && return 1
    printf '%s/%s' "${DOTFILES:-$HOME/dotfiles-sway}" "$rel"
}
