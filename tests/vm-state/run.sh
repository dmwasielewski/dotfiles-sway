#!/bin/bash
# Tests for libvirt/libvirt-guests-fallback.sh with a stub virsh.
# Nothing touches libvirt or a real VM.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
source ../updates/assert.sh
assert_absent() { # $1 haystack $2 needle $3 msg
    if [[ "$1" != *"$2"* ]]; then ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: ${3:-}"
    else ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: ${3:-} ([$1] contains [$2])"; fi
}
SCRIPT="$(cd ../.. && pwd)/libvirt/libvirt-guests-fallback.sh"

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/bin"
# Stub virsh: state per domain in $STATE/<dom>; every call is logged.
cat > "$root/bin/virsh" <<'STUB'
#!/bin/bash
shift 2                                   # drop "-c URI"
cmd="$1"; dom="${2:-}"
echo "$cmd $dom" >> "$STATE/calls"
case "$cmd" in
    list)       for f in "$STATE"/dom-*; do [[ "$(cat "$f")" == running ]] && basename "$f" | sed 's/^dom-//'; done ;;
    domstate)   cat "$STATE/dom-$dom" ;;
    shutdown)   [[ -e "$STATE/obeys-$dom" ]] && echo "shut off" > "$STATE/dom-$dom" ;;
    destroy)    echo "shut off" > "$STATE/dom-$dom" ;;
    domjobabort) : ;;
esac
STUB
chmod +x "$root/bin/virsh"
export PATH="$root/bin:$PATH" FALLBACK_POLL=0.1

setup() { export STATE="$root/$1"; rm -rf "$STATE"; mkdir -p "$STATE"; : > "$STATE/calls"; }

echo "== success: does nothing =="
setup a; echo running > "$STATE/dom-win"
SERVICE_RESULT=success bash "$SCRIPT"; assert_rc $? 0 "exit 0"
assert_eq "$(cat "$STATE/calls")" "" "virsh never called"

echo "== timeout: guest obeys ACPI shutdown =="
setup b; echo running > "$STATE/dom-win"; touch "$STATE/obeys-win"
out="$(SERVICE_RESULT=timeout FALLBACK_SHUTDOWN_WAIT=2 bash "$SCRIPT")"
assert_contains "$(cat "$STATE/calls")" "domjobabort win" "save job aborted"
assert_contains "$(cat "$STATE/calls")" "shutdown win" "clean shutdown requested"
assert_absent "$(cat "$STATE/calls")" "destroy win" "no forced power-off when it obeys"
assert_contains "$out" "shut down cleanly" "logged as clean"

echo "== timeout: guest ignores shutdown → destroyed after the wait =="
setup c; echo running > "$STATE/dom-win"
out="$(SERVICE_RESULT=timeout FALLBACK_SHUTDOWN_WAIT=1 bash "$SCRIPT")"
assert_contains "$(cat "$STATE/calls")" "destroy win" "forced power-off as last resort"
assert_eq "$(cat "$STATE/dom-win")" "shut off" "guest no longer running"
assert_contains "$out" "powering it off" "logged as forced"

echo "== failure with no running guests =="
setup d; echo "shut off" > "$STATE/dom-win"
out="$(SERVICE_RESULT=exit-code bash "$SCRIPT")"; assert_rc $? 0 "exit 0"
assert_contains "$out" "no running guests" "nothing to do"

assert_summary
