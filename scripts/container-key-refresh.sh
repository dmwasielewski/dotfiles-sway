#!/bin/bash
# container-key-refresh.sh — repair an rpm signature failure caused by a vendor
# rotating its package-signing SUBKEY. Runs as root INSIDE a dnf-based container;
# updates-menu.sh pipes it in with `sudo -n bash -s -- <failed.rpm>...` only after
# an upgrade failed its OpenPGP check.
#
# Why it exists (2026-11-08): Warp added a new signing subkey to its existing
# certificate and revoked the old one. The container held the old copy of the
# certificate, so dnf rejected every new Warp package ("Import of the key didn't
# help, wrong key?") until the certificate was refreshed by hand.
#
# Trust rule — the whole point of this script:
#   Only a certificate whose PRIMARY fingerprint is already in the container's rpm
#   keyring is ever refreshed, and it is fetched by that full fingerprint. A key
#   server cannot forge a new subkey binding without the vendor's private primary
#   key, and gpg checks that binding when it parses the download. A new or changed
#   primary key is never trusted automatically: that needs a human.
#
# Every change is proven first in a throwaway rpm root (old certificate + the
# download must verify the failed package) before the live keyring is touched.
# gpgcheck is never disabled.
#
# Exit: 0 = every failed package now verifies; 1 = could not fix (reason printed);
#       3 = not a missing-key failure, nothing to refresh.
set -uo pipefail

# Key servers that serve a certificate by full fingerprint. {FPR} is replaced.
# Not written as ${KEY_SOURCES:-…}: the first "}" of "{FPR}" would end that
# expansion and silently corrupt both URLs (it did, caught 2026-11-08).
DEFAULT_KEY_SOURCES='https://keys.openpgp.org/vks/v1/by-fingerprint/{FPR} https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x{FPR}'
KEY_SOURCES="${KEY_SOURCES:-$DEFAULT_KEY_SOURCES}"
REPO_DIR="${REPO_DIR:-/etc/yum.repos.d}"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
say() { printf '  key-refresh: %s\n' "$*"; }

# Key ID that rpm reports as missing for one package (lowercase hex, 16 chars).
# Needs -v: plain `rpmkeys -K` only says "SIGNATURES NOT OK". rpm 6 prints
# "key ID <16 hex>: NOKEY" for v4 signatures; a full "key fingerprint: <hex>"
# form is reduced to its last 16 hex digits, which is the key ID.
missing_key_id() {
    rpmkeys -Kv "$1" 2>&1 |
        sed -n 's/.*key \(ID\|fingerprint\):* \([0-9a-fA-F]\{16,\}\): NOKEY.*/\2/p' |
        head -1 | tr 'A-F' 'a-f' | grep -oE '.{16}$'
}

# Primary fingerprints already trusted by this container's rpm keyring.
trusted_fprs() { rpmkeys --list 2>/dev/null | awk '{print tolower($1)}' | grep -E '^[0-9a-f]{40}$'; }

# $1 = cert file, $2 = expected primary fpr, $3 = wanted signing key ID.
# Succeeds only if gpg parses the file as exactly that primary key and it carries
# a non-revoked, signing-capable subkey (or primary) with that key ID.
cert_has_signing_key() {
    local home="$work/gnupg"; mkdir -p "$home"; chmod 700 "$home"
    gpg --homedir "$home" --batch --with-colons --show-keys "$1" 2>/dev/null | awk -F: \
        -v want="$2" -v id="$3" '
        $1=="pub" {npub++; cur="pub"; valid=$2; caps=$12; next}
        $1=="sub" {cur="sub"; valid=$2; caps=$12; next}
        $1=="fpr" {
            f=tolower($10)
            if (cur=="pub") primary=f
            if (substr(f, 25) == id && valid != "r" && tolower(caps) ~ /s/) ok=1
            cur=""
        }
        END { exit !(npub==1 && primary==want && ok) }'
}

# Prove the download fixes the package in a throwaway rpm root.
proven_in_isolation() {   # $1 fpr  $2 cert  $3 rpm
    local root="$work/root-$RANDOM"; mkdir -p "$root"
    rpmkeys --export "$1" > "$work/current.asc" 2>/dev/null &&
        rpmkeys --root "$root" --import "$work/current.asc" >/dev/null 2>&1 &&
        rpmkeys --root "$root" --import "$2" >/dev/null 2>&1 &&
        rpmkeys --root "$root" -K "$3" 2>&1 | grep -q 'signatures OK'
}

# Keep local gpgkey= files in step, so dnf's own re-import cannot fall back to a
# stale copy again (that is exactly what failed on 2026-11-08).
update_repo_key_files() {   # $1 fpr
    local file path
    while IFS= read -r path; do
        [[ -f "$path" ]] || continue
        cert_has_primary "$path" "$1" || continue
        cp -p "$path" "$path.bak-$(date +%Y%m%d)"
        rpmkeys --export "$1" > "$path.new" && mv "$path.new" "$path" && say "updated $path"
    done < <(for file in "$REPO_DIR"/*.repo; do
                 [[ -f "$file" ]] || continue
                 sed -n 's/^[[:space:]]*gpgkey[[:space:]]*=//p' "$file" | tr -s ' ,' '\n' | sed -n 's|^file://||p'
             done | sort -u)
}
# True only for a file holding exactly ONE certificate, with that primary. A
# bundle of several vendor keys is left alone rather than replaced by one cert.
# Reads all of gpg's output (no early exit): under pipefail an early awk exit
# lets gpg's SIGPIPE decide the result.
cert_has_primary() {   # $1 file  $2 fpr
    local home="$work/gnupg"; mkdir -p "$home"; chmod 700 "$home"
    gpg --homedir "$home" --batch --with-colons --show-keys "$1" 2>/dev/null |
        awk -F: -v want="$2" '
            $1=="pub" {npub++; cur="pub"; next}
            $1=="sub" {cur="sub"; next}
            $1=="fpr" && cur=="pub" {primary=tolower($10); cur=""}
            END {exit !(npub==1 && primary==want)}'
}

fix_one() {   # $1 = failed rpm path
    local rpm="$1" id fpr src url n=0
    [[ -f "$rpm" ]] || { say "package file is gone: $rpm"; return 1; }
    id="$(missing_key_id "$rpm")"
    [[ -n "$id" ]] || { say "$(basename "$rpm"): not a missing-key failure"; return 3; }
    while IFS= read -r fpr; do
        for src in $KEY_SOURCES; do
            url="${src//\{FPR\}/${fpr^^}}"; n=$((n+1))
            curl -fsSL --max-time 30 -o "$work/cand-$n.asc" "$url" 2>/dev/null || continue
            cert_has_signing_key "$work/cand-$n.asc" "$fpr" "$id" || continue
            if ! proven_in_isolation "$fpr" "$work/cand-$n.asc" "$rpm"; then
                say "download from ${url%%/vks*} did not verify the package in isolation — not imported"
                continue
            fi
            rpmkeys --import "$work/cand-$n.asc" >/dev/null 2>&1 || { say "rpmkeys --import failed"; return 1; }
            rpmkeys -K "$rpm" 2>&1 | grep -q 'signatures OK' || { say "still not verified after import"; return 1; }
            say "refreshed trusted key ${fpr^^} (new signing subkey ${id^^}) from ${url%%\?*}"
            update_repo_key_files "$fpr"
            return 0
        done
    done < <(trusted_fprs)
    say "signing key ${id^^} belongs to no certificate this container already trusts"
    say "(or no key server could be reached). Not trusting a NEW primary key automatically."
    return 1
}

[[ $# -gt 0 ]] || { say "usage: container-key-refresh.sh <failed.rpm>..."; exit 1; }
rc=0 any_missing=0
for rpm in "$@"; do
    fix_one "$rpm"; r=$?
    [[ $r -eq 3 ]] && continue
    any_missing=1; [[ $r -eq 0 ]] || rc=1
done
[[ $any_missing -eq 1 ]] || exit 3
exit "$rc"
