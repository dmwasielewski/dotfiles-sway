#!/bin/bash
# Setup damian toolbox container — Fedora 43 dev environment
# Run this after first reboot: bash ~/dotfiles-sway/scripts/setup-damian-container.sh

set -e

CONTAINER="damian"

echo "==> Creating toolbox container..."
if toolbox list | grep -q "$CONTAINER"; then
    echo "==> Toolbox '$CONTAINER' already exists — skipping."
else
    toolbox create --image registry.fedoraproject.org/fedora-toolbox:43 "$CONTAINER"
fi

echo "==> Installing packages in $CONTAINER..."
toolbox run --container "$CONTAINER" sudo dnf install -y nodejs npm gh

echo "==> Configuring npm prefix (user-space)..."
toolbox run --container "$CONTAINER" bash -c '
    mkdir -p ~/.npm-global
    npm config set prefix ~/.npm-global
    grep -q "npm-global" ~/.bashrc || echo "export PATH=\$PATH:~/.npm-global/bin" >> ~/.bashrc
'

echo "==> Installing Claude Code..."
toolbox run --container "$CONTAINER" bash -c '
    source ~/.bashrc
    PATH=$PATH:~/.npm-global/bin npm install -g @anthropic-ai/claude-code
'

echo ""
echo "=========================================="
echo " damian container ready!"
echo " Enter container: toolbox enter damian"
echo " Run Claude Code: claude"
echo "=========================================="
echo ""
echo "==> ANTHROPIC_API_KEY setup..."
echo "Add your key to ~/.bashrc inside the container:"
echo '  echo '"'"'export ANTHROPIC_API_KEY="your-key-here"'"'"' >> ~/.bashrc'
echo "Get your key at: https://console.anthropic.com/settings/keys"
