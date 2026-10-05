#!/bin/bash
# Regressions: first boot must not show a login wizard; GUI library overrides
# must not leak to the native client; exec must preserve the controlled PID.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_HOME="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME"' EXIT
HOME="$TEST_HOME" bash "$ROOT/scripts/onedrive-gui.sh" --autostart
[[ ! -d "$TEST_HOME/.local/opt" ]]
mkdir -p "$TEST_HOME/.local/opt/onedrive-client/current/lib"
cat > "$TEST_HOME/.local/opt/onedrive-client/current/onedrive" <<'CLIENT'
#!/bin/bash
printf '%s\n' "$LD_LIBRARY_PATH" "${LD_PRELOAD:-unset}" "$1" "$$"
CLIENT
chmod +x "$TEST_HOME/.local/opt/onedrive-client/current/onedrive"
python3 - "$TEST_HOME" "$ROOT/scripts/onedrive-wrapper.sh" <<'PY'
import os, subprocess, sys
home, wrapper = sys.argv[1:]
env = dict(os.environ, HOME=home, LD_LIBRARY_PATH='/fake-appimage/lib')
p = subprocess.Popen(['bash', wrapper, 'folder with spaces'], env=env, stdout=subprocess.PIPE, text=True)
out, _ = p.communicate()
assert p.returncode == 0
assert out.splitlines() == [home+'/.local/opt/onedrive-client/current/lib', 'unset', 'folder with spaces', str(p.pid)], out
PY
printf '%s\n' 'PASS: autostart guard, isolated client libraries, argument preservation, native PID'
