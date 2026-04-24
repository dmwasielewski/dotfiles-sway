#!/bin/bash
# verify.sh — post-install verification checklist
# Run at any time to see what's installed, what's missing, and how to fix it.
# Works from inside the 'damian' toolbox or directly on the host.

set -euo pipefail

STATE_FILE="$HOME/.dotfiles-install-state"

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

pass()    { echo -e "  ${GREEN}✓${NC}  $1"; ((PASS++)); }
fail()    { echo -e "  ${RED}✗${NC}  $1"; ((FAIL++)); FAILURES+=("$1"); FIXES+=("${2:-}"); }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; ((WARN++)); }
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

check_symlink "sway/config"          "$HOME/.config/sway/config"
check_symlink "waybar/config"        "$HOME/.config/waybar/config"
check_symlink "waybar/style.css"     "$HOME/.config/waybar/style.css"
check_symlink "foot/foot.ini"        "$HOME/.config/foot/foot.ini"
check_symlink "mako/config"          "$HOME/.config/mako/config"
check_symlink ".bashrc"              "$HOME/.bashrc"
check_symlink "claude/settings.json" "$HOME/.claude/settings.json"
check_symlink "claude-ai.desktop"    "$HOME/.local/share/applications/claude-ai.desktop"
check_symlink "chatgpt.desktop"      "$HOME/.local/share/applications/chatgpt.desktop"
check_symlink "whatsapp.desktop"     "$HOME/.local/share/applications/whatsapp.desktop"

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
)

for entry in "${HOST_PKGS[@]}"; do
    pkg="${entry%%:*}"
    desc="${entry##*:}"
    if rpm_installed "$pkg"; then
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
        fail "$label  MISSING" "flatpak install -y flathub $id"
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
    check_toolbox_tool "git"    "git"

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
        'grep -q ANTHROPIC_API_KEY ~/.bashrc 2>/dev/null' 2>/dev/null; then
        pass "ANTHROPIC_API_KEY set in ~/.bashrc"
    else
        warn "ANTHROPIC_API_KEY not found in ~/.bashrc — required to use Claude Code"
    fi

else
    fail "Toolbox 'damian'  NOT FOUND" "bash ~/dotfiles-sway/scripts/setup-damian-container.sh"
fi

# ── 6. Distrobox 'security' ───────────────────────────────────────────────
section "6. Distrobox 'security' (pentesting)"

if host distrobox list 2>/dev/null | grep -q "security"; then
    pass "Distrobox 'security' exists"

    check_security_tool() {
        if host distrobox run --name security -- which "$1" &>/dev/null 2>&1; then
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

    if host distrobox run --name security -- test -d /opt/SecLists &>/dev/null 2>&1; then
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
for vmname in win11 winserver kali; do
    VMSTATE=$(host virsh --connect qemu:///system domstate "$vmname" 2>/dev/null || echo "not found")
    if [[ "$VMSTATE" == "not found" ]]; then
        if [[ "$vmname" == "win11" ]]; then
            fail "VM '$vmname'  NOT FOUND" "Create manually — see CLAUDE.md KVM section"
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
echo    "     • ANTHROPIC_API_KEY set in ~/.bashrc (inside damian container)"
echo    "     • claude login  (OAuth via browser)"
echo    "     • gh auth login  (GitHub CLI)"
echo    "     • MCP: Gmail, Calendar, Drive, Slack — log in at claude.ai → Integrations"
echo    "     • Bluetooth — pair via bluetoothctl"
echo    "     • NordVPN — install from nordvpn.com/linux"
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
