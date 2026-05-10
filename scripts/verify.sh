#!/bin/bash
# verify.sh — post-install verification checklist
# Run at any time to see what's installed, what's missing, and how to fix it.
# Works from inside the 'damian' toolbox or directly on the host.

set -euo pipefail

STATE_FILE="$HOME/.dotfiles-install-state"
LOG_FILE="${DOTFILES_LOG_FILE:-$HOME/.dotfiles-install.log}"
DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0
declare -a FAILURES=()
declare -a FIXES=()

pass()    { echo -e "  ${GREEN}✓${NC}  $1"; ((PASS+=1)); }
fail()    { echo -e "  ${RED}✗${NC}  $1"; ((FAIL+=1)); FAILURES+=("$1"); FIXES+=("${2:-}"); }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; ((WARN+=1)); }
section() { echo -e "\n${BOLD}${BLUE}━━━ $1 ━━━${NC}"; }

# Detect if running inside a toolbox container
IN_TOOLBOX=false
[[ -f /run/.toolboxenv ]] && IN_TOOLBOX=true

host() {
    if $IN_TOOLBOX; then
        flatpak-spawn --host "$@" 2>/dev/null
    else
        "$@" 2>/dev/null
    fi
}

rpm_installed()    { host rpm -q "$1" &>/dev/null; }
flatpak_installed(){ host flatpak list --app 2>/dev/null | grep -q "$1"; }
symlink_ok()       { [[ -L "$1" ]] && [[ -e "$1" ]]; }

# ─────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   dotfiles-sway — install verification   ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════╝${NC}"
echo -e "  $(date '+%Y-%m-%d %H:%M')"

# ── Install state from state file ────────────────────────────────────────
if [[ -f "$STATE_FILE" ]]; then
    section "Install state (from $STATE_FILE)"
    while IFS='=' read -r key val; do
        case "$val" in
            done)    echo -e "  ${GREEN}✓${NC}  $key" ;;
            failed)  echo -e "  ${RED}✗${NC}  $key" ;;
            pending) echo -e "  ${YELLOW}…${NC}  $key (pending)" ;;
            skipped) echo -e "  ${YELLOW}⚠${NC}  $key (skipped)" ;;
        esac
    done < "$STATE_FILE"
else
    section "Install state"
    echo -e "  ${YELLOW}⚠${NC}  No state file found ($STATE_FILE)"
    echo -e "      Run bootstrap.sh to start installation."
fi

section "Install log"
if [[ -f "$LOG_FILE" ]]; then
    LOG_SIZE=$(du -h "$LOG_FILE" 2>/dev/null | awk '{print $1}')
    LOG_MTIME=$(date -r "$LOG_FILE" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
    pass "Install log exists ($LOG_FILE, $LOG_SIZE, updated $LOG_MTIME)"
else
    warn "Install log not found ($LOG_FILE) — it will be created by bootstrap.sh or setup scripts"
fi

# ── 1. Config symlinks ───────────────────────────────────────────────────
section "1. Config symlinks"

check_symlink() {
    local label="$1" target="$2"
    if symlink_ok "$target"; then
        pass "$label"
    else
        fail "$label missing ($target)" "bash ~/dotfiles-sway/setup.sh"
    fi
}

check_symlink "sway/config"                    "$HOME/.config/sway/config"
check_symlink "sway/config.d/90-swayidle.conf" "$HOME/.config/sway/config.d/90-swayidle.conf"
check_symlink "waybar/config"        "$HOME/.config/waybar/config"
check_symlink "waybar/style.css"     "$HOME/.config/waybar/style.css"
check_symlink "foot/foot.ini"        "$HOME/.config/foot/foot.ini"
check_symlink "mako/config"          "$HOME/.config/mako/config"
check_symlink ".bashrc"              "$HOME/.bashrc"
check_symlink "claude/settings.json" "$HOME/.claude/settings.json"
check_symlink "claude-ai.desktop"    "$HOME/.local/share/applications/claude-ai.desktop"
check_symlink "chatgpt.desktop"      "$HOME/.local/share/applications/chatgpt.desktop"
check_symlink "whatsapp.desktop"     "$HOME/.local/share/applications/whatsapp.desktop"
check_symlink "nvim Chris Titus Tech config" "$HOME/.config/nvim"

# ── 2. System packages (rpm-ostree) ──────────────────────────────────────
section "2. System packages (rpm-ostree)"

HOST_PKGS=(
    "mako:notification daemon"
    "clipman:clipboard manager"
    "distrobox:Ubuntu container support"
    "unzip:required by setup.sh"
    "qemu-kvm:KVM virtualisation"
    "libvirt:virtualisation daemon"
    "virt-manager:VM GUI"
    "virt-viewer:VM display viewer"
    "virt-install:VM CLI creation"
    "bridge-utils:VM networking"
    "libva-utils:VA-API hardware acceleration"
    "gitleaks:secret scanner"
    "ripgrep:Neovim search dependency"
    "fd-find:Neovim file finder dependency"
    "fzf:Neovim fuzzy finder dependency"
    "wl-clipboard:Neovim Wayland clipboard integration"
    "python3-virtualenv:Neovim Python tooling dependency"
    "ShellCheck:Neovim shell linting dependency"
    "libwebp-tools:Neovim Markdown image paste conversion"
    "nodejs:Neovim Node-based tooling"
    "npm:Neovim Node package tooling"
    "make:Neovim build/tooling dependency"
)

for entry in "${HOST_PKGS[@]}"; do
    pkg="${entry%%:*}"
    desc="${entry##*:}"
    if [[ "$pkg" == "nodejs" ]] && host which node &>/dev/null 2>&1; then
        pass "$pkg  ($desc)"
    elif [[ "$pkg" == "npm" ]] && host which npm &>/dev/null 2>&1; then
        pass "$pkg  ($desc)"
    elif rpm_installed "$pkg"; then
        pass "$pkg  ($desc)"
    else
        fail "$pkg  MISSING ($desc)" "bash ~/dotfiles-sway/packages.sh && systemctl reboot"
    fi
done

if host lspci 2>/dev/null | grep -qi "Intel.*Graphics"; then
    if rpm_installed "intel-media-driver"; then
        pass "intel-media-driver  (Intel GPU)"
    else
        fail "intel-media-driver  MISSING (Intel GPU detected)" \
             "rpm-ostree install intel-media-driver && systemctl reboot"
    fi
fi

# ── 3. Flatpak apps ───────────────────────────────────────────────────────
section "3. Flatpak apps"

if host flatpak remotes 2>/dev/null | grep -q '^flathub'; then
    pass "Flathub remote"
else
    fail "Flathub remote missing" "flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo"
fi

declare -A FLATPAKS=(
    ["com.vivaldi.Vivaldi"]="Vivaldi (default browser)"
    ["com.visualstudio.code"]="VSCode"
    ["md.obsidian.Obsidian"]="Obsidian"
    ["com.bitwarden.desktop"]="Bitwarden"
    ["com.spotify.Client"]="Spotify"
    ["com.obsproject.Studio"]="OBS Studio"
    ["io.mpv.Mpv"]="mpv"
    ["org.jdownloader.JDownloader"]="JDownloader"
    ["com.vixalien.sticky"]="Sticky"
)

for id in "${!FLATPAKS[@]}"; do
    label="${FLATPAKS[$id]}"
    if flatpak_installed "$id"; then
        pass "$label  ($id)"
    else
        fail "$label  MISSING" "flatpak install -y --user flathub $id"
    fi
done

# ── 4. Fonts ──────────────────────────────────────────────────────────────
section "4. Fonts"

if ls "$HOME/.local/share/fonts/JetBrainsMono/"*.ttf &>/dev/null 2>&1; then
    pass "JetBrainsMono Nerd Font"
else
    fail "JetBrainsMono Nerd Font  MISSING" "bash ~/dotfiles-sway/setup.sh"
fi

if ls "$HOME/.local/share/fonts/FontAwesome/"*.otf &>/dev/null 2>&1 || \
   ls "$HOME/.local/share/fonts/FontAwesome/"*.ttf &>/dev/null 2>&1; then
    pass "Font Awesome"
else
    warn "Font Awesome — check ~/.local/share/fonts/FontAwesome/"
fi

# ── 5. Toolbox 'damian' ───────────────────────────────────────────────────
section "5. Toolbox 'damian' (dev environment)"

if host toolbox list 2>/dev/null | grep -qw "damian"; then
    pass "Toolbox 'damian' exists"

    check_toolbox_tool() {
        local tool="$1" label="${2:-$1}"
        if host toolbox run --container damian which "$tool" &>/dev/null 2>&1; then
            pass "$label"
        else
            fail "$label  MISSING in toolbox" "bash ~/dotfiles-sway/scripts/setup-damian-container.sh"
        fi
    }

    check_toolbox_tool "node"   "node (Node.js)"
    check_toolbox_tool "npm"    "npm"
    check_toolbox_tool "gh"     "gh (GitHub CLI)"
    check_toolbox_tool "claude" "claude (Claude Code)"
    check_toolbox_tool "codex"  "codex (OpenAI Codex CLI)"
    check_toolbox_tool "deepseek" "deepseek (DeepSeek TUI)"
    check_toolbox_tool "sgpt"   "sgpt (ShellGPT)"
    check_toolbox_tool "git"    "git"

    if host toolbox run --container damian bash -c \
        'expected="$(readlink -f "$HOME/dotfiles-sway/scripts/deepseek-wrapper.sh")" && test "$(readlink -f ~/.local/bin/deepseek 2>/dev/null)" = "$expected" && test "$(readlink -f ~/.local/bin/deepseek-tui 2>/dev/null)" = "$expected" && test "$(readlink -f ~/.npm-global/bin/deepseek 2>/dev/null)" = "$expected" && test "$(readlink -f ~/.npm-global/bin/deepseek-tui 2>/dev/null)" = "$expected"' &>/dev/null 2>&1; then
        pass "DeepSeek TUI low-motion wrapper installed"
    else
        warn "DeepSeek TUI low-motion wrapper missing — rerun bash ~/dotfiles-sway/scripts/setup-damian-container.sh"
    fi

    if host toolbox run --container damian bash -c \
        'PATH="$HOME/.npm-global/bin:$PATH" command -v markdownlint-cli2' &>/dev/null 2>&1; then
        pass "markdownlint-cli2 (Neovim Markdown linting)"
    else
        fail "markdownlint-cli2  MISSING in toolbox/global npm prefix" \
             "bash ~/dotfiles-sway/scripts/setup-damian-container.sh"
    fi

    # Plugins — check settings.json
    for plugin in superpowers code-simplifier context7; do
        if host toolbox run --container damian bash -c \
            "grep -q '$plugin' ~/.claude/settings.json 2>/dev/null" 2>/dev/null; then
            pass "Claude plugin: $plugin"
        else
            fail "Claude plugin: $plugin  MISSING" \
                 "toolbox enter damian → claude plugin install ${plugin}@claude-plugins-official --yes"
        fi
    done

    # API key
    if host toolbox run --container damian bash -c \
        '[[ -n "${ANTHROPIC_API_KEY:-}" ]] || grep -q ANTHROPIC_API_KEY ~/.bashrc.d/ai-keys.bash 2>/dev/null || grep -q ANTHROPIC_API_KEY ~/.bashrc 2>/dev/null' 2>/dev/null; then
        pass "ANTHROPIC_API_KEY available"
    else
        warn "ANTHROPIC_API_KEY not found — put it in ~/.bashrc.d/ai-keys.bash for Claude Code"
    fi

    if host toolbox run --container damian bash -c \
        'test -s ~/.config/shell_gpt/.sgptrc && ! grep -q "^OPENAI_API_KEY=missing-shellgpt-api-key$" ~/.config/shell_gpt/.sgptrc || [[ -n "${OPENAI_API_KEY:-}" ]] || [[ -n "${SHELLGPT_API_KEY:-}" ]] || [[ -n "${GEMINI_API_KEY:-}" ]] || test -s ~/.config/voice-type/gemini-api-key' 2>/dev/null; then
        pass "ShellGPT API config present"
    else
        warn "ShellGPT API config placeholder — provide ~/.config/voice-type/gemini-api-key, GEMINI_API_KEY, OPENAI_API_KEY/SHELLGPT_API_KEY, or a private env file before running setup-damian-container.sh"
    fi

    if host toolbox run --container damian bash -c \
        'grep -q "^DEFAULT_MODEL=gemini/" ~/.config/shell_gpt/.sgptrc 2>/dev/null && { [[ -n "${GEMINI_API_KEY:-}" ]] || test -s ~/.config/voice-type/gemini-api-key || grep -q GEMINI_API_KEY ~/.bashrc.d/shellgpt-gemini.bash 2>/dev/null; }' 2>/dev/null; then
        pass "ShellGPT Gemini config shares voice typing key source"
    fi

    if host toolbox run --container damian bash -c \
        'grep -q "^DEFAULT_MODEL=gemini/gemini-3.1-flash-lite-preview$" ~/.config/shell_gpt/.sgptrc 2>/dev/null && grep -q "SGPT_FALLBACK_MODEL" ~/.local/bin/sgpt 2>/dev/null && grep -q "gemini/gemini-2.5-flash" ~/.local/bin/sgpt 2>/dev/null' 2>/dev/null; then
        pass "ShellGPT executable fallback configured"
    else
        warn "ShellGPT executable fallback not configured — rerun bash ~/dotfiles-sway/scripts/setup-damian-container.sh"
    fi

else
    fail "Toolbox 'damian'  NOT FOUND" "bash ~/dotfiles-sway/scripts/setup-damian-container.sh"
fi

# ── 5a. NordVPN ──────────────────────────────────────────────────────────
section "5a. NordVPN"

if host which nordvpn &>/dev/null 2>&1; then
    pass "NordVPN CLI"
else
    fail "NordVPN CLI  MISSING" "bash ~/dotfiles-sway/scripts/setup-nordvpn.sh"
fi

if host systemctl list-unit-files nordvpnd.service 2>/dev/null | grep -q '^nordvpnd\.service'; then
    if host systemctl is-enabled --quiet nordvpnd && host systemctl is-active --quiet nordvpnd; then
        pass "NordVPN background service (enabled and running)"
    else
        fail "NordVPN background service  NOT RUNNING" \
             "sudo systemctl enable --now nordvpnd"
    fi
else
    warn "NordVPN background service unit not found yet — reboot after rpm-ostree install may still be required"
fi

if [[ -x "$HOME/.local/bin/nordvpn-waybar" ]]; then
    pass "NordVPN Waybar status helper"
else
    fail "NordVPN Waybar status helper  MISSING" "bash ~/dotfiles-sway/setup.sh"
fi

if host id -nG 2>/dev/null | grep -qw nordvpn; then
    pass "User in nordvpn group"
else
    warn "User not in nordvpn group yet — re-run bash ~/dotfiles-sway/scripts/setup-nordvpn.sh and log out/in"
fi

# ── 5b. AdGuard for Linux ────────────────────────────────────────────────
section "5b. AdGuard for Linux"

if host which adguard-cli &>/dev/null 2>&1 || host test -x /opt/adguard-cli/adguard-cli; then
    pass "AdGuard CLI"
else
    fail "AdGuard CLI  MISSING" "bash ~/dotfiles-sway/scripts/setup-adguard.sh"
fi

if host which iptables &>/dev/null 2>&1; then
    pass "iptables present for AdGuard auto mode"
else
    fail "iptables  MISSING (required by AdGuard auto mode)" "bash ~/dotfiles-sway/packages.sh && systemctl reboot"
fi

if host systemctl list-unit-files adguard-*.service 2>/dev/null | grep -q '^adguard-'; then
    if host systemctl is-active --quiet adguard-ctrl; then
        pass "AdGuard background service running"
    else
        warn "AdGuard service installed but not running yet — complete adguard-cli activate && adguard-cli configure && adguard-cli start"
    fi
else
    warn "AdGuard service unit not found yet — complete bash ~/dotfiles-sway/scripts/setup-adguard.sh"
fi

# ── 5c. Neovim ───────────────────────────────────────────────────────────
section "5c. Neovim"

if [[ -x "$HOME/.local/bin/nvim" ]]; then
    NVIM_LINE=$("$HOME/.local/bin/nvim" --version | head -n1)
    if echo "$NVIM_LINE" | grep -q "v0.12.1"; then
        pass "Neovim user-local latest pinned binary ($NVIM_LINE)"
    else
        warn "Neovim user-local binary found, but expected v0.12.1: $NVIM_LINE"
    fi
else
    fail "Neovim user-local binary missing (~/.local/bin/nvim)" \
         "bash ~/dotfiles-sway/scripts/setup-neovim-config.sh"
fi

if [[ -f "$HOME/dotfiles-sway/nvim/christitustech/titus-kickstart/init.lua" ]]; then
    pass "Chris Titus Tech Neovim submodule present"
else
    fail "Chris Titus Tech Neovim submodule missing" \
         "git -C ~/dotfiles-sway submodule update --init --recursive"
fi

if [[ -L "$HOME/.config/nvim" ]] && \
   [[ "$(readlink "$HOME/.config/nvim")" == "$HOME/dotfiles-sway/nvim/christitustech/titus-kickstart" ]]; then
    pass "~/.config/nvim points to Chris Titus Tech titus-kickstart"
else
    fail "~/.config/nvim does not point to Chris Titus Tech config" \
         "bash ~/dotfiles-sway/scripts/setup-neovim-config.sh"
fi

for tool in rg fd fzf wl-copy python3 shellcheck cwebp node npm make; do
    if host which "$tool" &>/dev/null 2>&1; then
        pass "Neovim dependency: $tool"
    else
        fail "Neovim dependency missing: $tool" \
             "bash ~/dotfiles-sway/packages.sh && systemctl reboot"
    fi
done

if host git -C "$DOTFILES" config --get core.hooksPath 2>/dev/null | grep -qx ".githooks" &&
   host test -x "$DOTFILES/.githooks/pre-push"; then
    pass "Git pre-push secret scan hook configured"
else
    warn "Git pre-push secret scan hook not configured — run: git -C ~/dotfiles-sway config core.hooksPath .githooks"
fi

# ── 5c. Voice typing ─────────────────────────────────────────────────────
section "5c. Voice typing"

if host which wtype &>/dev/null 2>&1; then
    pass "wtype (Wayland text injection)"
else
    fail "wtype  MISSING" "bash ~/dotfiles-sway/packages.sh && systemctl reboot"
fi

if host which arecord &>/dev/null 2>&1; then
    pass "arecord (audio recording)"
else
    fail "arecord  MISSING (alsa-utils)" "bash ~/dotfiles-sway/packages.sh && systemctl reboot"
fi

if host toolbox list 2>/dev/null | grep -qw "damian"; then
    if host toolbox run --container damian python3 -c "import faster_whisper" &>/dev/null 2>&1; then
        pass "faster-whisper AI model (Whisper small) in damian toolbox"
    else
        fail "faster-whisper  MISSING in damian toolbox" \
             "bash ~/dotfiles-sway/scripts/setup-damian-container.sh"
    fi
fi

if [[ -f ~/dotfiles-sway/scripts/voice-type-start.sh ]] && \
   [[ -f ~/dotfiles-sway/scripts/voice-type-stop.sh ]]; then
    pass "voice-type scripts present"
else
    fail "voice-type scripts  MISSING" "cd ~/dotfiles-sway && git pull"
fi

# ── 6. Distrobox 'security' ───────────────────────────────────────────────
section "6. Distrobox 'security' (pentesting)"

if host podman container exists security 2>/dev/null; then
    pass "Distrobox 'security' exists"

    SECURITY_VERSION=$(host distrobox enter --name security -- bash -lc \
        '. /etc/os-release && printf "%s" "$VERSION_ID"' 2>/dev/null || echo "unknown")
    if [[ "$SECURITY_VERSION" == "26.04" ]]; then
        pass "Ubuntu 26.04 in security container"
    else
        fail "security container is Ubuntu $SECURITY_VERSION, expected 26.04" \
             "distrobox stop security --yes && distrobox rm security --force && bash ~/dotfiles-sway/scripts/setup-security-container.sh"
    fi

    check_security_tool() {
        if host distrobox enter --name security -- which "$1" &>/dev/null 2>&1; then
            pass "$1"
        else
            fail "$1  MISSING in security container" \
                 "bash ~/dotfiles-sway/scripts/setup-security-container.sh"
        fi
    }

    check_security_tool "nmap"
    check_security_tool "gobuster"
    check_security_tool "hydra"
    check_security_tool "msfconsole"
    check_security_tool "sqlmap"
    check_security_tool "evil-winrm"
    check_security_tool "enum4linux-ng"
    check_security_tool "ffuf"
    check_security_tool "wireshark"
    check_security_tool "cmake"

    if host distrobox enter --name security -- python3 -c "import impacket, pwn, unicorn" &>/dev/null 2>&1; then
        pass "Python security libraries (impacket, pwntools, unicorn)"
    else
        fail "Python security libraries  MISSING in security container" \
             "bash ~/dotfiles-sway/scripts/setup-security-container.sh"
    fi

    if host distrobox enter --name security -- test -d /opt/SecLists &>/dev/null 2>&1; then
        pass "SecLists (/opt/SecLists)"
    else
        fail "SecLists  MISSING" "bash ~/dotfiles-sway/scripts/setup-security-container.sh"
    fi
else
    fail "Distrobox 'security'  NOT FOUND" "bash ~/dotfiles-sway/scripts/setup-security-container.sh"
fi

# ── 7. KVM / virtualisation ───────────────────────────────────────────────
section "7. KVM / virtualisation"

if host systemctl is-active libvirtd &>/dev/null 2>&1; then
    pass "libvirtd is running"
else
    fail "libvirtd not running" "bash ~/dotfiles-sway/scripts/setup-kvm.sh"
fi

if host systemctl is-enabled libvirtd &>/dev/null 2>&1; then
    pass "libvirtd enabled on boot"
else
    fail "libvirtd not enabled on boot" "sudo systemctl enable libvirtd"
fi

if host ls /dev/kvm &>/dev/null 2>&1; then
    pass "/dev/kvm available (KVM works)"
else
    fail "/dev/kvm NOT available" "Check BIOS — enable AMD-V / Intel VT-x"
fi

if host virsh --connect qemu:///system net-list --all 2>/dev/null | grep -q "default"; then
    NETSTATE=$(host virsh --connect qemu:///system net-list 2>/dev/null | \
        awk '/default/ {print $2}' || echo "unknown")
    if [[ "$NETSTATE" == "active" ]]; then
        pass "NAT network 'default' active"
    else
        warn "NAT network 'default' exists but not active — run: virsh --connect qemu:///system net-start default"
    fi
else
    fail "NAT network 'default'  MISSING" "bash ~/dotfiles-sway/scripts/setup-kvm.sh"
fi

if host groups 2>/dev/null | grep -q libvirt; then
    pass "User in libvirt group"
else
    fail "User NOT in libvirt group" "sudo usermod -aG libvirt \$USER  (then log out and back in)"
fi

section "7a. Virtual machines"
for vmname in win11 winserver kali fedora-sway-test; do
    VMSTATE=$(host virsh --connect qemu:///system domstate "$vmname" 2>/dev/null || echo "not found")
    if [[ "$VMSTATE" == "not found" ]]; then
        if [[ "$vmname" == "win11" ]]; then
            fail "VM '$vmname'  NOT FOUND" "Create manually — see CLAUDE.md KVM section"
        elif [[ "$vmname" == "fedora-sway-test" ]]; then
            warn "VM '$vmname'  not created yet (validation VM)"
        else
            warn "VM '$vmname'  not created yet (planned)"
        fi
    else
        pass "VM '$vmname'  state: $VMSTATE"
    fi
done

# ── 8. Hardware ───────────────────────────────────────────────────────────
section "8. Hardware"

if host vainfo &>/dev/null 2>&1; then
    pass "VA-API working (hardware acceleration)"
else
    warn "VA-API unavailable — check: flatpak-spawn --host vainfo"
fi

if host ls /dev/dri/renderD128 &>/dev/null 2>&1; then
    pass "/dev/dri/renderD128 (GPU render node)"
else
    warn "/dev/dri/renderD128 not found"
fi

# ── 9. Manual steps reminder ──────────────────────────────────────────────
section "9. Manual steps (require human interaction)"

echo -e "  ${YELLOW}⚠${NC}  Cannot be automated — verify manually:"
echo    "     • ANTHROPIC_API_KEY set in ~/.bashrc.d/ai-keys.bash"
echo    "     • claude login  (OAuth via browser)"
echo    "     • codex login  (OpenAI/ChatGPT account)"
echo    "     • gh auth login  (GitHub CLI)"
echo    "     • MCP: Gmail, Calendar, Drive, Slack — log in at claude.ai → Integrations"
echo    "     • Bluetooth — pair via bluetoothctl"
echo    "     • NordVPN — run nordvpn login, or use nordvpn login --token <token> if browser callback fails"
echo    "       Daily use: nordvpn connect | nordvpn status | nordvpn disconnect"
echo    "     • AdGuard for Linux — adguard-cli activate && adguard-cli configure && adguard-cli start"
echo    "       Daily use: adguard-cli status | adguard-cli start | adguard-cli stop"
echo    "     • Vivaldi — log in, restore bookmarks/extensions"

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} VERIFICATION RESULT${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}✓${NC} Passed:   ${BOLD}$PASS${NC}"
echo -e "  ${RED}✗${NC} Failed:   ${BOLD}$FAIL${NC}"
echo -e "  ${YELLOW}⚠${NC} Warnings: ${BOLD}$WARN${NC}"

if [[ $FAIL -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}${BOLD}  All checks passed — system installed correctly!${NC}"
else
    echo ""
    echo -e "${RED}${BOLD}  $FAIL item(s) missing. Fix commands:${NC}"
    echo ""

    declare -a SEEN_FIXES=()
    for i in "${!FAILURES[@]}"; do
        fix="${FIXES[$i]:-}"
        label="${FAILURES[$i]}"
        if [[ -n "$fix" ]]; then
            already=false
            for seen in "${SEEN_FIXES[@]:-}"; do
                [[ "$seen" == "$fix" ]] && already=true && break
            done
            if ! $already; then
                SEEN_FIXES+=("$fix")
                echo -e "  ${RED}✗${NC} $label"
                echo -e "    ${CYAN}→${NC} $fix"
                echo ""
            fi
        else
            echo -e "  ${RED}✗${NC} $label"
        fi
    done
fi

echo ""
