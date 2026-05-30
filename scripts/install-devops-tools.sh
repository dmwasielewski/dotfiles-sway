#!/bin/bash
# install-devops-tools.sh — OS-agnostic DevOps CLI stack, installed home-local.
#
# Runs INSIDE a dev container (needs go, pipx, curl, tar — provided by the
# language-toolchain step). Every tool lands in the shared $HOME
# (~/.local/bin or ~/go/bin), so a single install is visible from both dev
# containers and the host. Idempotent (skips already-present tools) and
# versionless by design — latest version is discovered at runtime, never
# hardcoded.
#
# Tools: kubectl · helm · kind · k9s · opentofu (tofu) · ansible · yq
# The container engine (podman/docker) is installed per-OS by the caller.
set -uo pipefail

BIN="$HOME/.local/bin"
mkdir -p "$BIN" "$HOME/go/bin"
export PATH="$BIN:$HOME/go/bin:$PATH"

# Resolve the latest release tag of a GitHub repo without hardcoding versions.
gh_latest_tag() {
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
        | grep -oP '"tag_name":\s*"\K[^"]+'
}

ok()   { printf '  ✓ %s\n' "$1"; }
skip() { printf '  • %s already present — skipping\n' "$1"; }

# ── kubectl (dynamic stable version) ──────────────────────────────────────
if command -v kubectl >/dev/null 2>&1; then skip kubectl; else
    ver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    curl -fsSL -o "$BIN/kubectl" "https://dl.k8s.io/release/${ver}/bin/linux/amd64/kubectl"
    chmod +x "$BIN/kubectl"; ok "kubectl ${ver}"
fi

# ── helm (official installer, home-local, no sudo) ────────────────────────
if command -v helm >/dev/null 2>&1; then skip helm; else
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
        | HELM_INSTALL_DIR="$BIN" USE_SUDO=false bash >/dev/null && ok helm
fi

# ── kind + yq (Go toolchain → ~/go/bin) ───────────────────────────────────
if command -v kind >/dev/null 2>&1; then skip kind; else
    go install sigs.k8s.io/kind@latest && ok kind
fi
if command -v yq >/dev/null 2>&1; then skip yq; else
    go install github.com/mikefarah/yq/v4@latest && ok yq
fi

# ── k9s (latest release tarball) ──────────────────────────────────────────
if command -v k9s >/dev/null 2>&1; then skip k9s; else
    tag="$(gh_latest_tag derailed/k9s)"
    curl -fsSL "https://github.com/derailed/k9s/releases/download/${tag}/k9s_Linux_amd64.tar.gz" \
        | tar -xz -C "$BIN" k9s && chmod +x "$BIN/k9s" && ok "k9s ${tag}"
fi

# ── opentofu (latest release tarball → tofu) ──────────────────────────────
if command -v tofu >/dev/null 2>&1; then skip opentofu; else
    tag="$(gh_latest_tag opentofu/opentofu)"; ver="${tag#v}"
    curl -fsSL "https://github.com/opentofu/opentofu/releases/download/${tag}/tofu_${ver}_linux_amd64.tar.gz" \
        | tar -xz -C "$BIN" tofu && chmod +x "$BIN/tofu" && ok "opentofu ${tag}"
fi

# ── ansible (pipx → ~/.local/bin) ─────────────────────────────────────────
if command -v ansible >/dev/null 2>&1; then skip ansible; else
    pipx install --include-deps ansible >/dev/null 2>&1 && ok ansible
fi

echo "DevOps userland stack ready in $BIN and $HOME/go/bin"
