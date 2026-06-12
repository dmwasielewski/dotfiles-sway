# Encrypted Secrets Vault Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the tooling for a LUKS2-encrypted USB secrets vault (one file per secret, mount-and-read, single-unlock harvest for install, age-backed backup) for dotfiles-sway.

**Architecture:** The `vault` CLI is split into a **pure data layer** (get/list/env/apply-manifest — operate on a mounted directory, unit-testable with plain files) and a **privileged device layer** (unlock/lock/setup/clone — cryptsetup+mount, integration-tested against a loopback LUKS image, never real hardware during development). Manifest parsing uses python3's stdlib `tomllib` (Fedora base). The real `/dev/sda` is touched only in the final, explicitly-confirmed, user-run task.

**Tech Stack:** Bash, `cryptsetup` (LUKS2, already on the host — system root is LUKS), `age` (layered via packages.sh), python3 `tomllib` (Fedora base), plain-bash test scripts (no external test framework).

**Spec:** `docs/superpowers/specs/2026-06-12-secrets-vault-design.md`

---

## Environment & safety rules (read before any task)

- **Toolbox vs host:** Claude Code runs inside the `damianf` toolbox. Privileged
  ops (`cryptsetup`, `losetup`, `mount`, partitioning) require root and generally
  must run **on the host**: prefix with `flatpak-spawn --host sudo …` or have the
  user run them via `! …`. Data-layer tests need no privileges and run in the toolbox.
- **No real hardware in dev:** Every device-layer test uses a throwaway loopback
  image (`/var/tmp/vault-test.img`), never `/dev/sda`.
- **Destructive ops are gated:** Any command that formats/partitions re-confirms the
  target via `lsblk` and requires an explicit typed confirmation. The real-USB task
  is last and run by the user.
- **Secrets never printed/logged** except by an explicit `vault get`.
- **Commits:** dotfiles-sway is on `main`; the repo's pre-push gitleaks hook runs.
  Tooling is non-secret; never commit any real secret or the loopback image.

## File structure

```
scripts/vault/
├── lib-vault.sh             # shared: config, device resolution (by PARTLABEL), state checks, data-layer get/list
├── vault                    # CLI dispatcher: unlock|lock|status|get|list|env
├── vault-parse-manifest.py  # python3 tomllib → TSV (action<TAB>source<TAB>k=v…)
├── vault-apply-manifest.sh  # read TSV, apply env|file|command actions (used by the orchestrator later)
├── setup-vault-usb.sh       # DESTRUCTIVE: partition+LUKS2+mkfs+scaffold (host, confirmed)
├── clone-vault.sh           # clone vault to a second LUKS USB (host)
├── backup-vault.sh          # tar + age-encrypt → vault.age (for the private repo)
└── vault-precommit-guard.sh # refuse to commit anything but vault.age (for dotfiles-secrets repo)

tests/vault/
├── assert.sh                # tiny assertion helper + counters
├── run.sh                   # run every test_*.sh, aggregate, exit nonzero on failure
├── test_data_layer.sh       # get/list against a temp dir (no privileges)
├── test_manifest_parse.sh   # parse fixture manifest.toml → expected TSV
├── test_manifest_apply.sh   # env|file|command actions into a temp HOME
├── test_env.sh              # `vault env <group>` output
├── test_precommit_guard.sh  # guard accepts vault.age only
└── fixtures/
    └── manifest.toml        # sample manifest for parse/apply tests

tests/vault/integration/      # host-run, privileged (loopback LUKS); not run in CI
├── loopback-setup.sh         # create /var/tmp/vault-test.img as a LUKS2 vault
├── test_unlock_lock.sh       # unlock/lock/status against the loopback image
└── test_clone.sh             # clone loopback vault → second loopback image

docs/superpowers/plans/2026-06-12-secrets-vault.md   # this file
```

---

## Task 0: Verify prerequisites and layer `age`

**Files:**
- Modify: `packages.sh` (add `age`)

- [ ] **Step 1: Confirm cryptsetup is present on the host**

Run: `flatpak-spawn --host cryptsetup --version`
Expected: prints a version (the system root is LUKS, so this should exist). If missing, add `cryptsetup` to `packages.sh` alongside `age` in Step 3.

- [ ] **Step 2: Confirm python3 tomllib is available**

Run: `python3 -c "import tomllib; print('ok')"`
Expected: `ok` (Fedora base python ≥3.11).

- [ ] **Step 3: Add `age` to the host package list**

In `packages.sh`, append `age` to the `PACKAGES` string and add a comment line near the other entries:

```
# age         - file encryption for the vault repo backup (vault.age)
```

Verify `age` exists for the host: `flatpak-spawn --host rpm-ostree install --dry-run age 2>&1 | tail -3` (or check `dnf` metadata in a container). Do not actually layer it here — packages.sh owns that.

- [ ] **Step 4: Commit**

```bash
git add packages.sh
git commit -m "vault: add age to host packages for encrypted repo backups"
```

---

## Task 1: Test harness + lib-vault.sh config and data layer

**Files:**
- Create: `tests/vault/assert.sh`, `tests/vault/run.sh`
- Create: `scripts/vault/lib-vault.sh`
- Test: `tests/vault/test_data_layer.sh`

- [ ] **Step 1: Write the assertion helper**

Create `tests/vault/assert.sh`:

```bash
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
```

- [ ] **Step 2: Write the test runner**

Create `tests/vault/run.sh`:

```bash
#!/bin/bash
# Run every tests/vault/test_*.sh; exit nonzero if any fails.
set -uo pipefail
cd "$(dirname "$0")"
fail=0
for t in test_*.sh; do
    echo "== $t =="
    if bash "$t"; then :; else fail=1; fi
done
[[ "$fail" -eq 0 ]] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$fail"
```

- [ ] **Step 3: Write the failing data-layer test**

Create `tests/vault/test_data_layer.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/assert.sh"
DIR="$(dirname "$0")/.."          # repo root-ish
source "$DIR/scripts/vault/lib-vault.sh"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export VAULT_MOUNT="$tmp"
mkdir -p "$tmp/ai" "$tmp/dev/ssh"
printf 'sk-ant-123\n' > "$tmp/ai/anthropic.key"
printf 'ghp_abc\n'    > "$tmp/dev/github-token"
printf '# readme\n'   > "$tmp/README.md"

# get returns the value (trailing newline stripped)
assert_eq "$(vault_get ai/anthropic.key)" "sk-ant-123" "get reads a secret"
# get on a missing file fails
( vault_get ai/nope.key >/dev/null 2>&1 ); assert_rc "$?" "1" "get missing fails"
# list shows secret paths, not README
out="$(vault_list)"
assert_contains "$out" "ai/anthropic.key" "list includes secret"
assert_contains "$out" "dev/github-token" "list includes token"
[[ "$out" != *"README.md"* ]] && echo "  ok: list excludes README" || { echo "  FAIL: README listed"; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
assert_summary
```

- [ ] **Step 4: Run it to verify it fails**

Run: `bash tests/vault/test_data_layer.sh`
Expected: FAIL — `lib-vault.sh` / `vault_get` not found.

- [ ] **Step 5: Implement lib-vault.sh (config + data layer)**

Create `scripts/vault/lib-vault.sh`:

```bash
#!/bin/bash
# Shared vault library. Config + device resolution + non-privileged data layer.
# Source this; do not execute. No secret value is ever logged here.

VAULT_LABEL="${VAULT_LABEL:-VAULT}"        # filesystem label inside the LUKS volume
VAULT_PARTLABEL="${VAULT_PARTLABEL:-vault}"# GPT partition name set at setup time
VAULT_MAPPER="${VAULT_MAPPER:-vault}"      # device-mapper name when unlocked
VAULT_MOUNT="${VAULT_MOUNT:-$HOME/.vault}" # mountpoint (overridable in tests)

# Resolve the vault's LUKS partition by its GPT PARTLABEL — never a hardcoded
# /dev path. Echoes /dev/<name> or nothing.
vault_device() {
    lsblk -rno NAME,PARTLABEL 2>/dev/null \
        | awk -v l="$VAULT_PARTLABEL" '$2==l {print "/dev/"$1; exit}'
}

vault_is_unlocked() { [[ -e "/dev/mapper/$VAULT_MAPPER" ]] && mountpoint -q "$VAULT_MOUNT"; }

# --- data layer (operates on $VAULT_MOUNT; no privileges) ---
vault_get() { # $1 = path relative to vault root
    local f="$VAULT_MOUNT/$1"
    [[ -f "$f" ]] || { echo "vault: no such secret: $1" >&2; return 1; }
    # strip a single trailing newline, preserve the rest verbatim
    printf '%s' "$(cat "$f")"
}

vault_list() {
    [[ -d "$VAULT_MOUNT" ]] || { echo "vault: not mounted" >&2; return 1; }
    ( cd "$VAULT_MOUNT" && find . -type f \
        ! -name 'README.md' ! -path './install/*' \
        | sed 's|^\./||' | sort )
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash tests/vault/test_data_layer.sh`
Expected: PASS — all assertions ok, `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add tests/vault/assert.sh tests/vault/run.sh tests/vault/test_data_layer.sh scripts/vault/lib-vault.sh
git commit -m "vault: data layer (get/list) + bash test harness"
```

---

## Task 2: `vault env <group>` (load a group on demand)

**Files:**
- Modify: `scripts/vault/lib-vault.sh`
- Test: `tests/vault/test_env.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/vault/test_env.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/assert.sh"
source "$(dirname "$0")/../scripts/vault/lib-vault.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export VAULT_MOUNT="$tmp"
mkdir -p "$tmp/ai"
printf 'sk-ant\n'  > "$tmp/ai/anthropic.key"
printf 'sk-openai\n'> "$tmp/ai/openai.key"

out="$(vault_env ai)"
assert_contains "$out" "export ANTHROPIC_API_KEY='sk-ant'"  "anthropic exported"
assert_contains "$out" "export OPENAI_API_KEY='sk-openai'"  "openai exported"
assert_summary
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/vault/test_env.sh`
Expected: FAIL — `vault_env` not defined.

- [ ] **Step 3: Implement `vault_env`**

Append to `scripts/vault/lib-vault.sh`:

```bash
# Map a secret filename stem to its conventional env var name.
# ai/anthropic.key -> ANTHROPIC_API_KEY ; dev/github-token -> GITHUB_TOKEN
vault_env_varname() { # $1 = stem (filename without dir, without .key)
    local base="${1%.key}"
    base="${base//-/_}"
    case "$base" in
        *_token|*_TOKEN) printf '%s' "$(echo "$base" | tr a-z A-Z)";;
        *)               printf '%s_API_KEY' "$(echo "$base" | tr a-z A-Z)";;
    esac
}

# Print `export NAME='value'` lines for every secret in a group dir. Use as:
#   eval "$(vault env ai)"
vault_env() { # $1 = group (subdirectory)
    local dir="$VAULT_MOUNT/$1"
    [[ -d "$dir" ]] || { echo "vault: no such group: $1" >&2; return 1; }
    local f name val
    for f in "$dir"/*; do
        [[ -f "$f" ]] || continue
        name="$(vault_env_varname "$(basename "$f")")"
        val="$(cat "$f")"
        printf "export %s='%s'\n" "$name" "$val"
    done
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/vault/test_env.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/vault/lib-vault.sh tests/vault/test_env.sh
git commit -m "vault: env <group> emits export lines on demand"
```

---

## Task 3: Manifest parser (python3 tomllib → TSV)

**Files:**
- Create: `scripts/vault/vault-parse-manifest.py`
- Create: `tests/vault/fixtures/manifest.toml`
- Test: `tests/vault/test_manifest_parse.sh`

- [ ] **Step 1: Write the fixture manifest**

Create `tests/vault/fixtures/manifest.toml`:

```toml
[[secret]]
source = "ai/anthropic.key"
action = "env"
name   = "ANTHROPIC_API_KEY"

[[secret]]
source = "ai/gemini.key"
action = "file"
dest   = "~/.config/voice-type/gemini-api-key"
mode   = "0600"

[[secret]]
source = "vpn/nordvpn-token"
action = "command"
command = "nordvpn login --token {value}"
```

- [ ] **Step 2: Write the failing parse test**

Create `tests/vault/test_manifest_parse.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/assert.sh"
PARSE="$(dirname "$0")/../scripts/vault/vault-parse-manifest.py"
out="$(python3 "$PARSE" "$(dirname "$0")/fixtures/manifest.toml")"
# TSV columns: action \t source \t key=val pairs...
assert_contains "$out" $'env\tai/anthropic.key\tname=ANTHROPIC_API_KEY' "env row"
assert_contains "$out" $'file\tai/gemini.key\tdest=~/.config/voice-type/gemini-api-key\tmode=0600' "file row"
assert_contains "$out" $'command\tvpn/nordvpn-token\tcommand=nordvpn login --token {value}' "command row"
assert_summary
```

- [ ] **Step 3: Run it to verify it fails**

Run: `bash tests/vault/test_manifest_parse.sh`
Expected: FAIL — parser script does not exist.

- [ ] **Step 4: Implement the parser**

Create `scripts/vault/vault-parse-manifest.py`:

```python
#!/usr/bin/env python3
"""Parse a vault manifest.toml into TSV lines the shell can consume.

Output per [[secret]]: action<TAB>source<TAB>k=v<TAB>k=v...
Order of trailing k=v pairs is deterministic (sorted by key) so tests are stable.
Values must not contain tabs or newlines (secrets are single-line keys/tokens).
"""
import sys, tomllib

def main(path: str) -> int:
    with open(path, "rb") as fh:
        data = tomllib.load(fh)
    for s in data.get("secret", []):
        action = s.get("action", "")
        source = s.get("source", "")
        rest = {k: v for k, v in s.items() if k not in ("action", "source")}
        cols = [action, source] + [f"{k}={rest[k]}" for k in sorted(rest)]
        for c in cols:
            if "\t" in str(c) or "\n" in str(c):
                print(f"manifest: tab/newline in value: {c!r}", file=sys.stderr)
                return 2
        print("\t".join(str(c) for c in cols))
    return 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: vault-parse-manifest.py manifest.toml", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/vault/test_manifest_parse.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/vault/vault-parse-manifest.py tests/vault/fixtures/manifest.toml tests/vault/test_manifest_parse.sh
git commit -m "vault: manifest.toml parser (python3 tomllib -> TSV)"
```

---

## Task 4: Apply manifest actions (env / file / command)

**Files:**
- Create: `scripts/vault/vault-apply-manifest.sh`
- Test: `tests/vault/test_manifest_apply.sh`

- [ ] **Step 1: Write the failing apply test**

Create `tests/vault/test_manifest_apply.sh`. It points a fake HOME and a fake vault mount at temp dirs and a stub `command` runner, then asserts the env file and copied file appear and the command received the value:

```bash
#!/bin/bash
source "$(dirname "$0")/assert.sh"
APPLY="$(dirname "$0")/../scripts/vault/vault-apply-manifest.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"; mkdir -p "$HOME"
export VAULT_MOUNT="$tmp/vault"; mkdir -p "$VAULT_MOUNT/ai" "$VAULT_MOUNT/vpn"
printf 'sk-ant\n'    > "$VAULT_MOUNT/ai/anthropic.key"
printf 'gem-123\n'   > "$VAULT_MOUNT/ai/gemini.key"
printf 'nord-xyz\n'  > "$VAULT_MOUNT/vpn/nordvpn-token"
# capture commands instead of running the real ones
export VAULT_CMD_RUNNER="$tmp/runner.sh"
cat > "$VAULT_CMD_RUNNER" <<'EOF'
#!/bin/bash
# $1 = template with {value} already substituted; record it
echo "$1" >> "$TMP_CMDLOG"
EOF
chmod +x "$VAULT_CMD_RUNNER"; export TMP_CMDLOG="$tmp/cmdlog"

bash "$APPLY" "$(dirname "$0")/fixtures/manifest.toml"

# env action -> export appended to ~/.bashrc.d/ai-keys.bash
grep -q "export ANTHROPIC_API_KEY='sk-ant'" "$HOME/.bashrc.d/ai-keys.bash" \
  && echo "  ok: env planted" || { echo "  FAIL: env missing"; ASSERT_FAIL=$((ASSERT_FAIL+1)); }
# file action -> copied to dest with mode 600
assert_eq "$(cat "$HOME/.config/voice-type/gemini-api-key")" "gem-123" "file planted"
assert_eq "$(stat -c '%a' "$HOME/.config/voice-type/gemini-api-key")" "600" "file mode 600"
# command action -> value substituted into the template
assert_contains "$(cat "$TMP_CMDLOG")" "nordvpn login --token nord-xyz" "command got value"
assert_summary
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/vault/test_manifest_apply.sh`
Expected: FAIL — apply script missing.

- [ ] **Step 3: Implement the apply script**

Create `scripts/vault/vault-apply-manifest.sh`:

```bash
#!/bin/bash
# Apply a vault manifest: plant secrets into their destinations. Reads secrets
# from $VAULT_MOUNT, writes into $HOME. Never prints secret values.
# Actions: env (append export to ~/.bashrc.d/ai-keys.bash), file (copy to dest,
# chmod), command (run a login command with {value} substituted).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib-vault.sh"

MANIFEST="${1:?usage: vault-apply-manifest.sh manifest.toml}"
ENV_FILE="$HOME/.bashrc.d/ai-keys.bash"
# Test hook: a runner that records the final command instead of executing it.
RUNNER="${VAULT_CMD_RUNNER:-}"

expand_tilde() { printf '%s' "${1/#\~/$HOME}"; }

run_command() { # $1 = command template with literal {value}; $2 = secret value
    local cmd="${1//\{value\}/$2}"
    if [[ -n "$RUNNER" ]]; then "$RUNNER" "$cmd"; return; fi
    # Real path: prefer stdin for token logins that read it; otherwise eval.
    bash -c "$cmd"
}

mkdir -p "$(dirname "$ENV_FILE")"; touch "$ENV_FILE"; chmod 600 "$ENV_FILE"

python3 "$HERE/vault-parse-manifest.py" "$MANIFEST" | while IFS=$'\t' read -r action source rest1 rest2; do
    # collect trailing k=v columns into an assoc array
    declare -A kv=(); for col in "$rest1" "$rest2"; do
        [[ -n "$col" ]] && kv["${col%%=*}"]="${col#*=}"
    done
    value="$(vault_get "$source")" || { echo "vault-apply: missing $source" >&2; continue; }
    case "$action" in
        env)
            name="${kv[name]}"
            # idempotent: drop any prior line for this var, then append
            grep -v "^export ${name}=" "$ENV_FILE" > "$ENV_FILE.tmp" 2>/dev/null || true
            mv "$ENV_FILE.tmp" "$ENV_FILE"
            printf "export %s='%s'\n" "$name" "$value" >> "$ENV_FILE"
            ;;
        file)
            dest="$(expand_tilde "${kv[dest]}")"; mode="${kv[mode]:-0600}"
            mkdir -p "$(dirname "$dest")"
            printf '%s\n' "$value" > "$dest"; chmod "$mode" "$dest"
            ;;
        command)
            run_command "${kv[command]}" "$value"
            ;;
        *) echo "vault-apply: unknown action: $action" >&2 ;;
    esac
    unset kv
done
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/vault/test_manifest_apply.sh`
Expected: PASS — env planted, file planted, mode 600, command got value.

- [ ] **Step 5: Commit**

```bash
git add scripts/vault/vault-apply-manifest.sh tests/vault/test_manifest_apply.sh
git commit -m "vault: apply manifest actions (env/file/command) with test hook"
```

---

## Task 5: `vault` CLI dispatcher (data + device commands)

**Files:**
- Create: `scripts/vault/vault`
- Test: extend `tests/vault/test_data_layer.sh` (CLI path for get/list)

- [ ] **Step 1: Add a failing CLI assertion**

Append to `tests/vault/test_data_layer.sh` before `assert_summary`:

```bash
VAULT="$DIR/scripts/vault/vault"
assert_eq "$(VAULT_MOUNT="$tmp" "$VAULT" get ai/anthropic.key)" "sk-ant-123" "cli get"
assert_contains "$(VAULT_MOUNT="$tmp" "$VAULT" list)" "dev/github-token" "cli list"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/vault/test_data_layer.sh`
Expected: FAIL — `vault` dispatcher missing.

- [ ] **Step 3: Implement the dispatcher**

Create `scripts/vault/vault` (executable). Device commands shell out to the
privileged helpers; data commands call the library directly:

```bash
#!/bin/bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib-vault.sh"

usage() { cat >&2 <<EOF
vault <command>
  unlock           cryptsetup open + mount the vault (asks passphrase)
  lock             unmount + cryptsetup close
  status           show locked/unlocked + mountpoint
  get <path>       print one secret (e.g. ai/anthropic.key)
  list             list secret paths (names only)
  env <group>      print export lines for a group: eval "\$(vault env ai)"
EOF
}

require_unlocked() { vault_is_unlocked || { echo "vault: locked — run 'vault unlock'" >&2; exit 1; }; }

cmd="${1:-}"; shift || true
case "$cmd" in
    unlock)
        dev="$(vault_device)"; [[ -n "$dev" ]] || { echo "vault: device not found (PARTLABEL=$VAULT_PARTLABEL)" >&2; exit 1; }
        sudo cryptsetup open "$dev" "$VAULT_MAPPER"
        mkdir -p "$VAULT_MOUNT"; chmod 700 "$VAULT_MOUNT"
        sudo mount "/dev/mapper/$VAULT_MAPPER" "$VAULT_MOUNT"
        sudo chown "$USER:$USER" "$VAULT_MOUNT"
        echo "vault: unlocked at $VAULT_MOUNT" ;;
    lock)
        mountpoint -q "$VAULT_MOUNT" && sudo umount "$VAULT_MOUNT"
        [[ -e "/dev/mapper/$VAULT_MAPPER" ]] && sudo cryptsetup close "$VAULT_MAPPER"
        echo "vault: locked" ;;
    status)
        if vault_is_unlocked; then echo "unlocked at $VAULT_MOUNT"; else echo "locked"; fi ;;
    get)  require_unlocked; vault_get "${1:?path}";;
    list) require_unlocked; vault_list ;;
    env)  require_unlocked; vault_env "${1:?group}";;
    ""|-h|--help) usage ;;
    *) echo "vault: unknown command: $cmd" >&2; usage; exit 2 ;;
esac
```

Note: data-layer tests set `VAULT_MOUNT` to a temp dir, so `get`/`list`/`env`
work without `unlock` in tests (the dir is "mounted"). `require_unlocked` only
trips when neither a real mount nor a test `VAULT_MOUNT` dir is present — adjust
`vault_is_unlocked` if a test needs the guard bypassed (tests point VAULT_MOUNT
at an existing dir, and get/list/env check the dir directly).

- [ ] **Step 4: Make the guard test-friendly**

To keep `get/list/env` usable in tests without a real device, change the case
branches to skip `require_unlocked` when `$VAULT_MOUNT` is already a populated
directory. Replace the three data branches with:

```bash
    get)  [[ -d "$VAULT_MOUNT" ]] || require_unlocked; vault_get "${1:?path}";;
    list) [[ -d "$VAULT_MOUNT" ]] || require_unlocked; vault_list ;;
    env)  [[ -d "$VAULT_MOUNT" ]] || require_unlocked; vault_env "${1:?group}";;
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `chmod +x scripts/vault/vault && bash tests/vault/test_data_layer.sh`
Expected: PASS — including the two new CLI assertions.

- [ ] **Step 6: Commit**

```bash
git add scripts/vault/vault tests/vault/test_data_layer.sh
git commit -m "vault: CLI dispatcher (unlock/lock/status/get/list/env)"
```

---

## Task 6: Backup — age encrypt + pre-commit guard

**Files:**
- Create: `scripts/vault/backup-vault.sh`, `scripts/vault/vault-precommit-guard.sh`
- Test: `tests/vault/test_precommit_guard.sh`

- [ ] **Step 1: Write the failing guard test**

Create `tests/vault/test_precommit_guard.sh`:

```bash
#!/bin/bash
source "$(dirname "$0")/assert.sh"
GUARD="$(dirname "$0")/../scripts/vault/vault-precommit-guard.sh"
# guard reads staged file list on stdin; exits 0 only if every path is vault.age
echo "vault.age" | bash "$GUARD"; assert_rc "$?" "0" "accepts vault.age only"
printf 'vault.age\nai/anthropic.key\n' | bash "$GUARD"; assert_rc "$?" "1" "rejects a plaintext secret"
printf 'README.md\n' | bash "$GUARD"; assert_rc "$?" "1" "rejects anything else"
assert_summary
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/vault/test_precommit_guard.sh`
Expected: FAIL — guard missing.

- [ ] **Step 3: Implement the guard**

Create `scripts/vault/vault-precommit-guard.sh`:

```bash
#!/bin/bash
# Pre-commit guard for the PRIVATE dotfiles-secrets repo: the only path allowed
# in a commit is vault.age. Reads staged paths on stdin (one per line). Install
# in that repo as .git/hooks/pre-commit:  git diff --cached --name-only | this
set -uo pipefail
bad=0
while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if [[ "$path" != "vault.age" ]]; then
        echo "REFUSED: only vault.age may be committed (got: $path)" >&2
        bad=1
    fi
done
exit "$bad"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/vault/test_precommit_guard.sh`
Expected: PASS.

- [ ] **Step 5: Implement backup-vault.sh**

Create `scripts/vault/backup-vault.sh`:

```bash
#!/bin/bash
# Encrypt the unlocked vault into a single age file for the private repo backup.
# Plaintext NEVER leaves the machine: we tar the mount and pipe straight into age.
# Usage: backup-vault.sh [output.age]   (default: ./vault.age)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib-vault.sh"
out="${1:-vault.age}"

vault_is_unlocked || { echo "vault: unlock first (vault unlock)" >&2; exit 1; }
command -v age >/dev/null || { echo "age not installed (packages.sh adds it)" >&2; exit 1; }

# age with a passphrase (symmetric). tar -C the mount so paths are relative.
tar -C "$VAULT_MOUNT" -cf - . | age -p -o "$out"
echo "vault: encrypted backup written to $out (ciphertext only)"
echo "Restore: age -d $out | tar -C <mounted-vault> -xf -"
```

- [ ] **Step 6: Commit**

```bash
git add scripts/vault/backup-vault.sh scripts/vault/vault-precommit-guard.sh tests/vault/test_precommit_guard.sh
git commit -m "vault: age-encrypted repo backup + pre-commit plaintext guard"
```

---

## Task 7: USB setup script (DESTRUCTIVE — develop against loopback)

**Files:**
- Create: `scripts/vault/setup-vault-usb.sh`
- Create: `tests/vault/integration/loopback-setup.sh`, `tests/vault/integration/test_unlock_lock.sh`

These run **on the host** (privileged). They use a loopback image, never `/dev/sda`.

- [ ] **Step 1: Write the setup script**

Create `scripts/vault/setup-vault-usb.sh`:

```bash
#!/bin/bash
# DESTRUCTIVE: turn a block device into a LUKS2 vault. Re-confirms the target and
# requires typing the device path to proceed. Run on the host with root.
# Usage: sudo setup-vault-usb.sh /dev/sdX
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib-vault.sh"
dev="${1:?usage: setup-vault-usb.sh /dev/sdX}"

[[ -b "$dev" ]] || { echo "not a block device: $dev" >&2; exit 1; }
echo "About to ERASE and re-create as a LUKS2 vault:"
lsblk -o NAME,SIZE,TYPE,RM,TRAN,MOUNTPOINT,MODEL "$dev"
echo "Type the device path EXACTLY to confirm destruction:"
read -r confirm
[[ "$confirm" == "$dev" ]] || { echo "aborted"; exit 1; }

# single GPT partition named for label-based discovery
sgdisk --zap-all "$dev"
sgdisk -n 1:0:0 -c 1:"$VAULT_PARTLABEL" "$dev"
partprobe "$dev"
part="$(lsblk -rno NAME,PARTLABEL "$dev" | awk -v l="$VAULT_PARTLABEL" '$2==l{print "/dev/"$1; exit}')"
[[ -n "$part" ]] || { echo "partition not found after create" >&2; exit 1; }

cryptsetup luksFormat --type luks2 "$part"
cryptsetup open "$part" "$VAULT_MAPPER"
mkfs.ext4 -L "$VAULT_LABEL" "/dev/mapper/$VAULT_MAPPER"

mnt="$(mktemp -d)"; mount "/dev/mapper/$VAULT_MAPPER" "$mnt"
# scaffold the layout + README
mkdir -p "$mnt"/{ai,dev/ssh,vpn,accounts,install}
"$HERE/scaffold-readme.sh" > "$mnt/README.md" 2>/dev/null || true
chmod -R go-rwx "$mnt"
umount "$mnt"; rmdir "$mnt"
cryptsetup close "$VAULT_MAPPER"
echo "vault: LUKS2 vault ready on $dev (PARTLABEL=$VAULT_PARTLABEL, FS label=$VAULT_LABEL)"
```

(The README scaffold can be inlined; a separate `scaffold-readme.sh` is optional. If you inline it, drop the `||true` line and `cat` a heredoc into `$mnt/README.md`.)

- [ ] **Step 2: Write the loopback integration harness**

Create `tests/vault/integration/loopback-setup.sh`:

```bash
#!/bin/bash
# Host-run. Build a loopback-backed LUKS2 vault to exercise the device layer
# WITHOUT real hardware. Requires root. Passphrase for tests: "testpass".
set -euo pipefail
IMG="${IMG:-/var/tmp/vault-test.img}"
MAP="vault"  # matches VAULT_MAPPER default
rm -f "$IMG"; truncate -s 64M "$IMG"
echo -n testpass | cryptsetup luksFormat --type luks2 "$IMG" -
echo -n testpass | cryptsetup open "$IMG" "$MAP" -
mkfs.ext4 -q -L VAULT "/dev/mapper/$MAP"
mnt="$(mktemp -d)"; mount "/dev/mapper/$MAP" "$mnt"
mkdir -p "$mnt/ai"; echo "sk-ant" > "$mnt/ai/anthropic.key"
umount "$mnt"; rmdir "$mnt"; cryptsetup close "$MAP"
echo "loopback vault image at $IMG (passphrase: testpass)"
```

- [ ] **Step 3: Write the unlock/lock integration test**

Create `tests/vault/integration/test_unlock_lock.sh`:

```bash
#!/bin/bash
# Host-run, root. Verifies open+mount+read+close against the loopback image.
set -euo pipefail
IMG="${IMG:-/var/tmp/vault-test.img}"; MAP="vault"; MNT="$(mktemp -d)"
echo -n testpass | cryptsetup open "$IMG" "$MAP" -
mount "/dev/mapper/$MAP" "$MNT"
val="$(cat "$MNT/ai/anthropic.key")"
umount "$MNT"; cryptsetup close "$MAP"; rmdir "$MNT"
[[ "$val" == "sk-ant" ]] && echo "PASS: read secret from loopback vault" || { echo "FAIL"; exit 1; }
```

- [ ] **Step 4: Run the loopback integration on the host**

Run (user, host):
```bash
sudo bash tests/vault/integration/loopback-setup.sh
sudo bash tests/vault/integration/test_unlock_lock.sh
```
Expected: `PASS: read secret from loopback vault`. Clean up: `rm -f /var/tmp/vault-test.img`.

- [ ] **Step 5: Commit**

```bash
git add scripts/vault/setup-vault-usb.sh tests/vault/integration/
git commit -m "vault: USB setup script + loopback integration tests (no real hardware)"
```

---

## Task 8: Clone script + README scaffold + docs wiring

**Files:**
- Create: `scripts/vault/clone-vault.sh`
- Modify: `README.md`, `CLAUDE.md` (document the vault), `BACKLOG.md` (mark vault sub-project)

- [ ] **Step 1: Implement clone-vault.sh**

Create `scripts/vault/clone-vault.sh`:

```bash
#!/bin/bash
# Clone an unlocked vault onto a second freshly-set-up LUKS USB (offline backup).
# Both must be unlocked+mounted first (vault unlock on source; setup+open dest).
# Usage: clone-vault.sh <src-mount> <dest-mount>
set -euo pipefail
src="${1:?src mount}"; dest="${2:?dest mount}"
mountpoint -q "$src"  || { echo "src not mounted: $src" >&2; exit 1; }
mountpoint -q "$dest" || { echo "dest not mounted: $dest" >&2; exit 1; }
rsync -aH --delete "$src"/ "$dest"/
echo "vault: cloned $src -> $dest"
```

- [ ] **Step 2: Document in README.md and CLAUDE.md**

Add a "Secrets vault" section to `README.md` (how to unlock/use/back up) and a
matching entry in `CLAUDE.md`'s repo-structure and layers sections. Keep it in
English. Mention: `vault unlock|get|list|env|lock`, the manifest, and the B2 backup.

- [ ] **Step 3: Mark the sub-project in BACKLOG.md**

Under the install-pipeline section, add: vault is the dependency for the
orchestrator (item 1); link the spec and this plan.

- [ ] **Step 4: Run the full data-layer test suite once more**

Run: `bash tests/vault/run.sh`
Expected: `ALL TESTS PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/vault/clone-vault.sh README.md CLAUDE.md BACKLOG.md
git commit -m "vault: clone script + docs (README/CLAUDE) + backlog link"
```

---

## Task 9: GO LIVE on the real USB (user-run, last, irreversible)

**This task is performed by the user on the host. Do not run it from the toolbox.**
Pre-req: all prior tasks merged; loopback integration passed.

- [ ] **Step 1: Re-confirm the device**

Run: `lsblk -o NAME,SIZE,TYPE,RM,TRAN,MOUNTPOINT,MODEL`
Confirm the USB is the removable `usb` device (at design time: `sda`, 28.9G,
"TransMemory") and **not** `nvme0n1`. If anything differs, STOP.

- [ ] **Step 2: Confirm nothing on the USB is needed**

The setup ERASES it. Verify its current contents are expendable.

- [ ] **Step 3: Create the vault on the real device**

Run (user): `sudo bash scripts/vault/setup-vault-usb.sh /dev/sdX`
Type the device path when prompted; set a strong LUKS passphrase.

- [ ] **Step 4: Unlock and populate**

```bash
scripts/vault/vault unlock
$EDITOR ~/.vault/ai/anthropic.key   # paste each key, one file per secret
# ... fill in the rest per README.md ...
scripts/vault/vault list
```

- [ ] **Step 5: First backup (both legs of B2)**

```bash
scripts/vault/backup-vault.sh ~/vault.age      # age ciphertext for the private repo
# create the private repo dotfiles-secrets, install the pre-commit guard, push vault.age
# clone to a 2nd LUKS USB: setup-vault-usb.sh on it, unlock, then:
scripts/vault/clone-vault.sh ~/.vault /run/media/$USER/VAULT2
scripts/vault/vault lock
```

- [ ] **Step 6: Verify end-to-end**

```bash
scripts/vault/vault unlock && scripts/vault/vault get ai/anthropic.key && scripts/vault/vault lock
```
Expected: prints the key, then locks. Vault is live.

---

## Self-review notes

- **Spec coverage:** mechanism/LUKS (Tasks 7,9), one-file-per-secret layout
  (Tasks 1,7), data-layer get/list/env (Tasks 1,2,5), manifest (Tasks 3,4), install
  consumption apply (Task 4; orchestrator wires it later), backup B2 = clone + age
  (Tasks 6,8,9), pre-commit guard (Task 6), security modes/labels (Tasks 1,7),
  device discovery by PARTLABEL not hardcoded path (Task 1). Manual-limits and
  orchestrator are explicitly out of scope per the spec.
- **Deferred to implementation (from spec "to verify"):** cryptsetup presence
  (Task 0 Step 1), age availability/layering (Task 0), exact destinations in the
  real manifest (finalised when the orchestrator consumes it — this plan ships a
  tested fixture + apply engine, not the production manifest).
- **Type/name consistency:** `VAULT_MOUNT`, `VAULT_MAPPER`, `VAULT_PARTLABEL`,
  `VAULT_LABEL`, `vault_get`, `vault_list`, `vault_env`, `vault_device`,
  `vault_is_unlocked` are used identically across tasks.
```
