#!/bin/bash
# require_sudo_session must not demand an interactive sudo when sudo already
# needs no password.
#
# Regression (2026-08-18, found by the disposable-VM run): packages.sh called
# require_sudo_session, which ran a bare `sudo -v`. Over ssh with no TTY that
# printed "a terminal is required to read the password" and phase P1 died —
# on a guest where `sudo -n true` worked perfectly. `sudo -v` does not mean
# "check whether I may run things", it means "authenticate the user", and sudo
# demands a password for it even when the sudoers rules are NOPASSWD: ALL.
# Confirmed on the guest: `sudo -n true` succeeded while `sudo -n -v` was
# refused, with `(ALL) NOPASSWD: ALL` present in `sudo -l`.
#
# An unattended install has no terminal by definition, so the one path that
# must never need one was the one that did.
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"; mkdir -p "$stub"

# Reproduces the guest exactly: running a command without a password works,
# validating the user does not.
cat > "$stub/sudo" <<'STUB'
#!/bin/bash
echo "sudo $*" >> "$SUDO_LOG"
for a in "$@"; do [[ "$a" == "-v" ]] && { echo "sudo: a password is required" >&2; exit 1; }; done
exit 0
STUB
chmod +x "$stub/sudo"

export STATE_FILE="$tmp/state"; : > "$STATE_FILE"
export SUDO_LOG="$tmp/sudo.log"; : > "$SUDO_LOG"

(
    PATH="$stub:$PATH"
    # shellcheck source=scripts/lib-install.sh
    source "$DIR/scripts/lib-install.sh"
    require_sudo_session >/dev/null 2>&1 && echo 0 > "$tmp/rc" || echo $? > "$tmp/rc"
)
rc="$(cat "$tmp/rc")"

assert_eq "$rc" "0" "succeeds when sudo already needs no password"
grep -q -- "-v" "$SUDO_LOG" \
    && { ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: called 'sudo -v' even though passwordless sudo works"; } \
    || { ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: does not call 'sudo -v' when it is not needed"; }

assert_summary
