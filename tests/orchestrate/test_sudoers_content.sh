#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
source "$DIR/scripts/lib-orchestrate.sh"
out="$(provisioning_sudoers_content damian)"
assert_contains "$out" "damian ALL=(ALL) NOPASSWD:" "names the user"
assert_contains "$out" "/usr/bin/rpm-ostree" "allows rpm-ostree"
assert_contains "$out" "/usr/bin/systemctl"  "allows systemctl"
assert_contains "$out" "/usr/sbin/usermod"   "allows usermod"
assert_contains "$out" "/usr/bin/loginctl"   "allows loginctl (enable-linger)"
# must NOT be a blanket ALL command grant
[[ "$out" != *"NOPASSWD: ALL"* ]] && echo "  ok: not a blanket grant" || { echo "  FAIL: blanket"; ASSERT_FAIL=$((ASSERT_FAIL+1)); }

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

assert_summary
