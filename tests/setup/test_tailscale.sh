#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"
export HOME="$TMP/home" DOTFILES="$ROOT" TEST_LOG="$TMP/commands" TEST_OPERATOR="" TEST_READY=0 TEST_GRAPHICAL=0
export XDG_CONFIG_HOME="$TMP/home/.config"
export DOTFILES_LOG_FILE="$TMP/install.log"
cat > "$TMP/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >> "$TEST_LOG"
if [[ "$*" == *'is-active --quiet graphical-session.target'* ]]; then
    [[ "$TEST_GRAPHICAL" == 1 ]]; exit
fi
if [[ "$*" == *'is-enabled --quiet tailscaled'* || "$*" == *'is-active --quiet tailscaled'* ]]; then
    [[ "$TEST_READY" == 1 ]]; exit
fi
exit 0
EOF
cat > "$TMP/bin/tailscale" <<'EOF'
#!/usr/bin/env bash
echo "tailscale $*" >> "$TEST_LOG"
case "$*" in
    'debug prefs') printf '{"OperatorUser":"%s"}\n' "$TEST_OPERATOR" ;;
    'status --json') echo '{"BackendState":"NeedsLogin"}' ;;
esac
EOF
cat > "$TMP/bin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo $*" >> "$TEST_LOG"
[[ "${TEST_DENY:-0}" == 0 ]] || exit 1
[[ "$1" != -n ]] || shift
exec "$@"
EOF
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
bash "$ROOT/scripts/setup-tailscale.sh" > "$TMP/out"
grep -q 'sudo -n systemctl enable --now tailscaled' "$TEST_LOG"
grep -q "sudo -n tailscale set --operator=$USER" "$TEST_LOG"
grep -q 'TAILSCALE_LOGIN=pending' "$HOME/.dotfiles-install-state"
test -L "$HOME/.config/systemd/user/tailscale-systray.service"
if grep -q 'systemctl --user start' "$TEST_LOG"; then exit 1; fi
echo 'PASS: fresh headless P2 installs autostart without launching GUI or login'
export TEST_READY=1 TEST_OPERATOR="$USER" TEST_GRAPHICAL=1
: > "$TEST_LOG"
bash "$ROOT/scripts/setup-tailscale.sh" > "$TMP/out"
if grep -q '^sudo' "$TEST_LOG"; then exit 1; fi
grep -q 'systemctl --user start tailscale-systray.service' "$TEST_LOG"
echo 'PASS: configured rerun needs no root and starts the graphical tray'
export TEST_READY=0 TEST_DENY=1
if bash "$ROOT/scripts/setup-tailscale.sh" > "$TMP/out"; then
    echo 'FAIL: sudo failure was swallowed'; exit 1
fi
grep -q 'TAILSCALE_SERVICE=failed' "$HOME/.dotfiles-install-state"
echo 'PASS: daemon setup failure stops P2 and records failed state'

export TEST_READY=1 TEST_DENY=0
mkdir -p "$XDG_CONFIG_HOME/dotfiles"
printf 'true\n' > "$XDG_CONFIG_HOME/dotfiles/tailscale-accept-routes"
: > "$TEST_LOG"
bash "$ROOT/scripts/setup-tailscale.sh" > "$TMP/out"
grep -q '^tailscale set --accept-routes=true$' "$TEST_LOG"
echo 'PASS: private subnet-route opt-in restored'
printf 'yes\n' > "$XDG_CONFIG_HOME/dotfiles/tailscale-accept-routes"
: > "$TEST_LOG"
if bash "$ROOT/scripts/setup-tailscale.sh" > "$TMP/out" 2>&1; then exit 1; fi
if grep -q 'set --accept-routes=' "$TEST_LOG"; then exit 1; fi
echo 'PASS: invalid private subnet-route policy rejected without changing routes'
