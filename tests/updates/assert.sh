#!/bin/bash
# Minimal assertion helpers for plain-bash tests. Source this; call assertions;
# end the test file with `assert_summary`.
ASSERT_PASS=0
ASSERT_FAIL=0
assert_eq() { # $1 actual $2 expected $3 msg
    if [[ "$1" == "$2" ]]; then ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: ${3:-}"
    else ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: ${3:-} (got [$1] want [$2])"; fi
}
assert_contains() { # $1 haystack $2 needle $3 msg
    if [[ "$1" == *"$2"* ]]; then ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: ${3:-}"
    else ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: ${3:-} ([$1] lacks [$2])"; fi
}
assert_rc() { # $1 actual_rc $2 expected_rc $3 msg
    if [[ "$1" == "$2" ]]; then ASSERT_PASS=$((ASSERT_PASS+1)); echo "  ok: ${3:-}"
    else ASSERT_FAIL=$((ASSERT_FAIL+1)); echo "  FAIL: ${3:-} (rc $1 != $2)"; fi
}
assert_summary() {
    echo "  -- $ASSERT_PASS passed, $ASSERT_FAIL failed"
    [[ "$ASSERT_FAIL" -eq 0 ]]
}
