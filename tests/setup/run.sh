#!/bin/bash
# Run every tests/setup/test_*.sh; exit nonzero if any fails.
set -uo pipefail
cd "$(dirname "$0")"
fail=0
for t in test_*.sh; do
    echo "== $t =="
    if bash "$t"; then :; else fail=1; fi
done
[[ "$fail" -eq 0 ]] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$fail"
