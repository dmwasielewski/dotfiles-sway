# Design: Encrypted secrets vault on USB

**Date:** 2026-06-12
**Status:** Approved (design); implementation plan pending
**Repo:** dotfiles-sway (tooling is non-secret and lives here; secrets never do)

## Goal

A permanent, encrypted, extensible **secrets vault** on a USB drive that holds all
of the user's API keys and tokens (AI services, GitHub, VPN, SSH, …). It serves
two roles:

1. **General-purpose vault** — day-to-day source of truth for keys/tokens, usable
   by any application or shell, edited and extended over time.
2. **Install source** — the install orchestrator (separate sub-project) reads from
   it once to provision a fresh machine unattended.

The vault is the foundation; the orchestrator is a downstream consumer. This spec
covers the **vault only**. The orchestrator gets its own spec.

## Decisions (with rationale)

- **Encryption: LUKS2 whole-partition on the USB.** Unlock once with a passphrase;
  the volume mounts like a normal disk and the secrets inside are plain files.
  Chosen over per-file `age`/`pass` because the user's primary model is
  "plug in and read like a disk" (live editing, any app reads a file path, no
  encrypt/decrypt cycle per change). Linux-only is acceptable (Fedora Sway).
- **Layout: one file per secret.** Editing or adding a key = open/create one
  clearly-named file. No hunting inside a combined file; no code change to add a key.
- **Day-to-day access: mount-and-read, plus a thin `vault` helper.** Secrets are
  not loaded into the environment unless explicitly requested (avoids leaking all
  keys into every process). Auto-load-into-shell (U3) was rejected for this reason.
- **Install consumption: unlock once, harvest everything, persist to disk.** The
  USB is read a single time at the start of install; needed secrets are planted in
  their destinations and post-reboot secrets are copied to a protected on-disk
  staging dir. The USB is not needed across the install's reboots.
- **Backup: B2 — cloned LUKS USB + an `age`-encrypted bundle in a private repo.**
  The bundle is encrypted locally **before** anything leaves the machine; the repo
  only ever stores ciphertext. (A raw LUKS image is not repo-friendly, so the repo
  backup is a small `age` file, not a device image.)
- **Prefer non-expiring credentials (API keys / PATs) over OAuth session tokens.**
  This removes the need to copy and refresh expiring tokens; OAuth session-file
  pre-seeding is therefore out of scope.

## Components

All tooling is non-secret shell code and lives in the public `dotfiles-sway` repo
(e.g. under `scripts/vault/`). The **secrets themselves never go in any repo.**

### 1. USB device and LUKS volume

- Target device confirmed at design time: `/dev/sda` (28.9 GB, removable, USB,
  model "TransMemory"). The system disk is `nvme0n1` (untouched). The device must
  be re-confirmed by `lsblk` immediately before any destructive command.
- Layout: single partition → LUKS2 → ext4, filesystem label `VAULT`.
- Setup script `setup-vault-usb.sh` performs (only after explicit confirmation and
  run by the user with host root): partition, `cryptsetup luksFormat`, `luksOpen`,
  `mkfs.ext4 -L VAULT`, mount, scaffold the directory layout + `README.md`.
- Mountpoint is mode `0700`; secret files are created mode `0600`.

### 2. Directory layout (inside the encrypted volume)

```
VAULT/
├── README.md               # what each secret is, where it lands, how to add one
├── ai/                     # AI service API keys (non-expiring preferred)
│   ├── anthropic.key
│   ├── openai.key
│   ├── gemini.key
│   ├── deepseek.key
│   ├── qwen.key
│   ├── perplexity.key
│   └── kimi.key
├── dev/
│   ├── github-token
│   └── ssh/
│       ├── id_ed25519
│       └── id_ed25519.pub
├── vpn/
│   └── nordvpn-token
├── accounts/
│   └── accounts.env        # KEY=VALUE app/account passwords (reference only)
└── install/
    └── manifest.toml       # maps install-consumed secrets to destinations
```

Each secret file holds a single value (trailing newline tolerated). Adding a new
secret = create a file; if the installer should plant it, add one manifest entry.

### 3. `manifest.toml` (install mapping — config, not logic)

Describes which secrets the installer consumes and where they go, so adding a new
install-consumed secret needs no code change. Each entry declares the source file
(relative to the vault root) and a destination action. Example shape:

```toml
[[secret]]
source = "ai/anthropic.key"
action = "env"                       # write export into ~/.bashrc.d/ai-keys.bash
name   = "ANTHROPIC_API_KEY"

[[secret]]
source = "ai/gemini.key"
action = "file"                      # copy verbatim to a path
dest   = "~/.config/voice-type/gemini-api-key"
mode   = "0600"

[[secret]]
source = "dev/ssh/id_ed25519"
action = "file"
dest   = "~/.ssh/id_ed25519"
mode   = "0600"

[[secret]]
source = "vpn/nordvpn-token"
action = "command"                   # used by a login command, not stored
command = "nordvpn login --token {value}"

[[secret]]
source = "dev/github-token"
action = "command"
command = "gh auth login --with-token"   # value piped on stdin
```

Supported `action` values: `env` (append an export to a shell rc file), `file`
(copy to a path with a mode), `command` (feed the value to a login command). The
exact set is finalised during implementation; the manifest is the single source of
truth for the mapping.

### 4. `vault` helper CLI

A small script on `PATH` wrapping cryptsetup/mount and reads:

- `vault unlock` — `cryptsetup luksOpen` + mount (prompts for passphrase once).
- `vault lock` — unmount + `cryptsetup luksClose`.
- `vault status` — locked/unlocked, mountpoint.
- `vault get <path>` — print one secret (e.g. `vault get ai/anthropic`).
- `vault env <group>` — export a chosen group into the **current** shell on demand
  (e.g. `eval "$(vault env ai)"`), never automatically.
- `vault list` — list available secret paths (names only, never values).

Values are never echoed to logs.

### 5. Install consumption flow

The orchestrator (separate spec) calls into the vault as follows:

1. `vault unlock` — one passphrase.
2. Read every secret marked in `manifest.toml`; apply its action (plant file,
   append env export, or run the login command).
3. Copy any secret needed **after** the rpm-ostree reboot into a protected staging
   dir `~/.local/state/dotfiles-secrets/` (`0700` dir, `0600` files), so phase 2
   resumes without the USB.
4. Continue the phased install; the USB may be removed after this step.
5. On successful completion, wipe the staging dir; only the legitimate final homes
   (rc files, `~/.ssh`, app configs) remain.

### 6. Backup (B2)

- `clone-vault.sh` — make a faithful encrypted clone onto a second LUKS USB (offline
  copy kept in a safe place).
- `backup-vault.sh` — `tar` the secrets tree → `age`-encrypt **locally** →
  `vault.age` → commit/push to the **private** repo `dotfiles-secrets`. The repo
  never receives plaintext: a `.gitignore` plus a pre-commit guard refuse to commit
  anything except `vault.age`. Restore: clone the private repo, `age -d vault.age |
  tar x` into a freshly set-up LUKS USB.

### 7. Security model

- LUKS2 with a strong passphrase; the passphrase is the only routine human input.
- Mountpoint `0700`, secret files `0600`.
- On-disk install staging is wiped after the install completes.
- The private-repo backup is `age`-encrypted before leaving the machine; plaintext
  is never committed (gitignore + pre-commit guard).
- Secret values are never written to logs or printed except by an explicit
  `vault get`.
- Re-confirm `/dev/sda` via `lsblk` immediately before any destructive operation.

### 8. Manual limits (out of scope for automation)

GUI account logins (Bitwarden master password, Spotify, Thunderbird/OAuth) and
Bluetooth pairing remain manual. Their passwords may be stored under
`accounts/accounts.env` for convenience, but the user enters them by hand.

## Out of scope (this spec)

- The install **orchestrator** (phase engine, reboot handoff, verify profiles) —
  separate spec; this vault is its dependency.
- Cross-platform (non-Linux) reading of the vault.
- OAuth session-token pre-seeding (superseded by preferring non-expiring keys).

## To verify during implementation

- Whether `cryptsetup` and `age` are present in the Fedora Sway Atomic base image,
  or must be layered via `packages.sh`.
- The exact destinations and login-command invocations for each install-consumed
  secret (finalise `manifest.toml` against the current setup scripts).
