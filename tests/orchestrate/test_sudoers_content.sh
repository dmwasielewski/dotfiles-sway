#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$DIR/scripts/lib-orchestrate.sh"
out="$(provisioning_sudoers_content damian)"
# BACKLOG #16 option c (2026-11-08): passwordless for this one user, for the
# provisioning window only — a command list kept going stale and the VM, which
# grants NOPASSWD: ALL, could never see it.
assert_contains "$out" "damian ALL=(ALL) NOPASSWD: ALL" "passwordless for the provisioning user"
[[ "$out" != *"%wheel"* && "$out" != *"ALL ALL="* ]] && echo "  ok: scoped to one user, not a group" || { echo "  FAIL: grant is wider than one user"; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
assert_contains "$out" "removed in P3" "says it is temporary"
assert_contains "$out" "sudo rm /etc/sudoers.d/10-dotfiles-provisioning" "tells a finder how to remove it"
assert_eq "$(grep -vc '^#' <<< "$out")" "1" "exactly one rule"

# A malformed drop-in in /etc/sudoers.d can break sudo for the whole system, and
# once it has, sudo can no longer be used to remove it. So the syntax check must
# happen on the temp file, BEFORE anything is installed — the code used to
# install first and validate afterwards, which makes the check decorative.
tmpd="$(mktemp -d)"; trap 'rm -rf "$tmpd"' EXIT
cat > "$tmpd/sudo" <<'STUB'
#!/bin/bash
echo "sudo $*" >> "$ORDER_LOG"
[[ "${1:-}" == "visudo" ]] && exit 0
exit 0
STUB
cat > "$tmpd/visudo" <<'STUB'
#!/bin/bash
echo "visudo $*" >> "$ORDER_LOG"
exit 0
STUB
chmod +x "$tmpd/sudo" "$tmpd/visudo"
export ORDER_LOG="$tmpd/order"; : > "$ORDER_LOG"
PATH="$tmpd:$PATH" ORCH_SUDOERS="$tmpd/target" write_provisioning_sudoers >/dev/null 2>&1
first="$(head -1 "$ORDER_LOG" | awk '{print $1, $2}')"
assert_contains "$first" "visudo" "validates before installing anything"

# And an invalid file must abort instead of being installed.
cat > "$tmpd/visudo" <<'STUB'
#!/bin/bash
echo "visudo $*" >> "$ORDER_LOG"
exit 1
STUB
chmod +x "$tmpd/visudo"
: > "$ORDER_LOG"
PATH="$tmpd:$PATH" ORCH_SUDOERS="$tmpd/target" write_provisioning_sudoers >/dev/null 2>&1 && rc=0 || rc=$?
assert_eq "$rc" "1" "returns non-zero when the generated file is invalid"
grep -q "install" "$ORDER_LOG" && { echo "  FAIL: installed an invalid sudoers file"; ASSERT_FAIL=$((ASSERT_FAIL+1)); } || echo "  ok: refused to install an invalid sudoers file"


# Removal must be proven: rm that silently fails would leave the blanket grant.
cat > "$tmpd/sudo" <<'STUB'
#!/bin/bash
[[ "$1" == rm ]] && exit 0          # pretends to remove...
[[ "$1" == test ]] && exit 0        # ...but the file is still there
exit 0
STUB
chmod +x "$tmpd/sudo"
PATH="$tmpd:$PATH" remove_provisioning_sudoers >/dev/null 2>&1 && rc=0 || rc=$?
assert_eq "$rc" "1" "remove reports failure when the drop-in is still present"
cat > "$tmpd/sudo" <<'STUB'
#!/bin/bash
[[ "$1" == test ]] && exit 1        # gone
exit 0
STUB
PATH="$tmpd:$PATH" remove_provisioning_sudoers >/dev/null 2>&1 && rc=0 || rc=$?
assert_eq "$rc" "0" "remove succeeds once the drop-in is gone"
assert_summary
