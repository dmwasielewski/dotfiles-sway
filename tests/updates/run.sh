#!/bin/bash
# Run every tests/updates/test_*.sh; exit nonzero if any fails.
set -uo pipefail
cd "$(dirname "$0")"
# Keep fixtures and container runtime state completely separate from the host.
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root"/{home,cache,config,data,state,runtime,bin}
chmod 700 "$test_root/runtime"
export HOME="$test_root/home" XDG_CACHE_HOME="$test_root/cache"
export XDG_CONFIG_HOME="$test_root/config" XDG_DATA_HOME="$test_root/data"
export XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime"
# Each test's own stubs take precedence. These guards catch omitted stubs so
# no test can fall through to real container engines, updates or service calls.
for command in podman toolbox distrobox flatpak rpm-ostree systemctl setsid pgrep pkill swaymsg; do
    printf '#!/bin/bash\nexit 0\n' > "$test_root/bin/$command"
done
for command in curl sudo; do
    printf '#!/bin/bash\nexit 1\n' > "$test_root/bin/$command"
done
chmod +x "$test_root/bin"/*
export PATH="$test_root/bin:$PATH"
fail=0
for t in test_*.sh; do
    echo "== $t =="
    if bash "$t"; then :; else fail=1; fi
done
[[ "$fail" -eq 0 ]] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$fail"
