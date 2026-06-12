#!/bin/bash
source "$(dirname "$0")/assert.sh"
APPLY="$(dirname "$0")/../../scripts/vault/vault-apply-manifest.sh"
FIX="$(dirname "$0")/fixtures/manifest.toml"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"; mkdir -p "$HOME"
export VAULT_MOUNT="$tmp/vault"; mkdir -p "$VAULT_MOUNT/ai" "$VAULT_MOUNT/vpn"
printf 'sk-ant\n'   > "$VAULT_MOUNT/ai/anthropic.key"
printf 'gem-123\n'  > "$VAULT_MOUNT/ai/gemini.key"
printf 'nord-xyz\n' > "$VAULT_MOUNT/vpn/nordvpn-token"
# capture commands instead of running the real ones
export TMP_CMDLOG="$tmp/cmdlog"
export VAULT_CMD_RUNNER="$tmp/runner.sh"
cat > "$VAULT_CMD_RUNNER" <<'EOF'
#!/bin/bash
echo "$1" >> "$TMP_CMDLOG"
EOF
chmod +x "$VAULT_CMD_RUNNER"

bash "$APPLY" "$FIX"

# env action -> export appended to ~/.bashrc.d/ai-keys.bash
if grep -q "export ANTHROPIC_API_KEY='sk-ant'" "$HOME/.bashrc.d/ai-keys.bash"; then
    echo "  ok: env planted"; ASSERT_PASS=$((ASSERT_PASS+1))
else echo "  FAIL: env missing"; ASSERT_FAIL=$((ASSERT_FAIL+1)); fi
# file action -> copied to dest with mode 600
assert_eq "$(cat "$HOME/.config/voice-type/gemini-api-key")" "gem-123" "file planted"
assert_eq "$(stat -c '%a' "$HOME/.config/voice-type/gemini-api-key")" "600" "file mode 600"
# command action -> value substituted into the template
assert_contains "$(cat "$TMP_CMDLOG")" "nordvpn login --token nord-xyz" "command got value"

# idempotency: running again must not duplicate the env line
bash "$APPLY" "$FIX"
cnt="$(grep -c "export ANTHROPIC_API_KEY=" "$HOME/.bashrc.d/ai-keys.bash")"
assert_eq "$cnt" "1" "env line not duplicated on rerun"
assert_summary
