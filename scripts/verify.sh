#!/bin/bash
# verify.sh — post-install verification checklist
# Run at any time to see what's installed, what's missing, and how to fix it.
# Works from inside the selected toolbox or directly on the host.

set -euo pipefail

STATE_FILE="$HOME/.dotfiles-install-state"
LOG_FILE="${DOTFILES_LOG_FILE:-$HOME/.dotfiles-install.log}"
DOTFILES="${DOTFILES:-$HOME/dotfiles-sway}"
TOOLBOX_CONTAINER="${TOOLBOX_CONTAINER:-damianf}"
UBUNTU_DEV_CONTAINER="${UBUNTU_DEV_CONTAINER:-damianu}"
DISTROBOX_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/distrobox"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
PENDING=0
PENDINGS=()
PENDING_FIXES=()
FAIL=0
WARN=0
declare -a FAILURES=()
declare -a FIXES=()

pass()    { echo -e "  ${GREEN}✓${NC}  $1"; ((PASS+=1)); }
fail()    { echo -e "  ${RED}✗${NC}  $1"; ((FAIL+=1)); FAILURES+=("$1"); FIXES+=("${2:-}"); }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; ((WARN+=1)); }
# A third verdict, distinct from pass/fail. Some things the install genuinely
# cannot finish by itself: a group membership needs a fresh login, a VPN needs
# the user's credentials. Reporting those as failures makes a correct unattended
# install report failure forever — the orchestrator's phase 2 ends in
# `verify.sh --profile post-reboot`, so whatever this calls a failure, the whole
# install calls a failure. "Waiting for you" is not "broken".
pending() { echo -e "  ${CYAN}◔${NC}  $1"; ((PENDING+=1)); PENDINGS+=("$1"); PENDING_FIXES+=("${2:-}"); }
section() { echo -e "\n${BOLD}${BLUE}━━━ $1 ━━━${NC}"; }

PROFILE="full"
for arg in "$@"; do
    case "$arg" in
        --profile=*) PROFILE="${arg#*=}" ;;
        --profile)   PROFILE="__next__" ;;
        *) [[ "$PROFILE" == "__next__" ]] && PROFILE="$arg" ;;
    esac
done
case "$PROFILE" in phase1|post-reboot|full) ;; *) echo "unknown profile: $PROFILE" >&2; exit 2 ;; esac

# Which section groups run in each profile.
profile_includes() { # $1 profile, $2 section
    case "$1" in
        phase1)      [[ "$2" == base ]] ;;
        post-reboot) [[ "$2" == base || "$2" == kvm || "$2" == containers ]] ;;
        full)        return 0 ;;
        *)           return 1 ;;
    esac
}

# Allow sourcing (tests) to load functions without executing the checks.
(return 0 2>/dev/null) && return 0

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

mkdir -p "$DISTROBOX_CACHE_DIR"

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
check_symlink "whispering-open.desktop" "$HOME/.local/share/applications/whispering-open.desktop"
check_symlink "nvim Chris Titus Tech config" "$HOME/.config/nvim"
check_symlink "power-menu"                 "$HOME/.local/bin/power-menu"
check_symlink "deepseek"                   "$HOME/.local/bin/deepseek"
check_symlink "deepseek-tui"               "$HOME/.local/bin/deepseek-tui"
check_symlink "adguard-waybar"             "$HOME/.local/bin/adguard-waybar"
check_symlink "nordvpn-waybar"             "$HOME/.local/bin/nordvpn-waybar"
check_symlink "nordvpn-whitelist-domain"   "$HOME/.local/bin/nordvpn-whitelist-domain"
check_symlink "updates-waybar"             "$HOME/.local/bin/updates-waybar"
check_symlink "updates-do"                 "$HOME/.local/bin/updates-do"
check_symlink "updates-menu"               "$HOME/.local/bin/updates-menu"
check_symlink "damianf entry shortcut"     "$HOME/.local/bin/damianf"
check_symlink "damianu entry shortcut"     "$HOME/.local/bin/damianu"
check_symlink "bat cross-distro wrapper"   "$HOME/.local/bin/bat"
check_symlink "fd cross-distro wrapper"    "$HOME/.local/bin/fd"
check_symlink "rg system wrapper"          "$HOME/.local/bin/rg"
check_symlink "environment.d/locale.conf"  "$HOME/.config/environment.d/locale.conf"

# ── 1b. Whispering Open ───────────────────────────────────────────────────
section "1b. Whispering Open"

if [[ -x "$HOME/.local/bin/whispering-open" ]]; then
    pass "Whispering Open launcher binary"
else
    warn "Whispering Open not installed yet — run: bash ~/dotfiles-sway/scripts/setup-whispering-open.sh"
fi

if [[ -f "$HOME/.local/opt/whispering-open/current-binary" ]]; then
    pass "Whispering Open install metadata"
else
    warn "Whispering Open install metadata missing — GitHub release may not have been downloaded yet"
fi


# ── 1a. Locale & 24h time format ───────────────────────────────────────────
section "1a. Locale & 24h time format"

if grep -q "import-environment LC_TIME" "$HOME/.config/sway/config" 2>/dev/null; then
    pass "sway config imports LC_TIME"
else
    fail "sway config missing LC_TIME import" "echo 'exec_always systemctl --user import-environment LC_TIME' >> ~/.config/sway/config"
fi

# Thunderbird's flatpak ID is variant-dependent (Flathub rebased the plain
# org.mozilla.Thunderbird to org.mozilla.thunderbird_esr), so discover whatever is
# installed instead of hardcoding it. Reused for the presence check further down.
# `|| true` is load-bearing: verify.sh runs under `set -euo pipefail`, and a grep
# that matches nothing exits 1, which pipefail propagates out of the command
# substitution and set -e turns into a silent abort of the WHOLE script. Since
# Flathub rebased the plain ID onto _esr, `grep -vi esr` matches nothing on this
# machine, so verify.sh stopped right here — after ~10% of its checks — and still
# looked like it had finished. Not finding an optional app is not an error.
TB_ID="$(host flatpak list --app --columns=application 2>/dev/null | grep -iE '^org\.mozilla\.thunderbird' | grep -vi esr | head -n1 || true)"
[[ -z "$TB_ID" ]] && TB_ID="$(host flatpak list --app --columns=application 2>/dev/null | grep -iE '^org\.mozilla\.thunderbird' | head -n1 || true)"

if [[ -n "$TB_ID" ]] && host flatpak override --user --show "$TB_ID" 2>/dev/null | grep -q "LC_TIME"; then
    pass "Thunderbird flatpak override LC_TIME  ($TB_ID)"
else
    warn "Thunderbird flatpak override LC_TIME not set"
fi

if [[ -f "$HOME/.config/environment.d/locale.conf" ]] && grep -q "LC_TIME=en_GB.UTF-8" "$HOME/.config/environment.d/locale.conf" 2>/dev/null; then
    pass "LC_TIME=en_GB.UTF-8 in environment.d/locale.conf"
else
    fail "LC_TIME not set in environment.d/locale.conf" "mkdir -p ~/.config/environment.d && echo LC_TIME=en_GB.UTF-8 > ~/.config/environment.d/locale.conf"
fi

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
    ["com.visualstudio.code"]="VSCode"
    ["md.obsidian.Obsidian"]="Obsidian"
    ["org.libreoffice.LibreOffice"]="LibreOffice"
    ["com.bitwarden.desktop"]="Bitwarden"
    ["com.spotify.Client"]="Spotify"
    ["com.obsproject.Studio"]="OBS Studio"
    ["io.mpv.Mpv"]="mpv"
    ["org.jdownloader.JDownloader"]="JDownloader"
    ["com.vixalien.sticky"]="Sticky"
    ["org.kde.kdenlive"]="Kdenlive"
    ["com.simplenote.Simplenote"]="Simplenote"
)

for id in "${!FLATPAKS[@]}"; do
    label="${FLATPAKS[$id]}"
    if flatpak_installed "$id"; then
        pass "$label  ($id)"
    else
        fail "$label  MISSING" "flatpak install -y --user flathub $id"
    fi
done

# Thunderbird checked separately — its ID is variant-dependent (discovered above).
if [[ -n "$TB_ID" ]]; then
    pass "Thunderbird  ($TB_ID)"
else
    fail "Thunderbird  MISSING" "flatpak install -y --user flathub org.mozilla.thunderbird_esr"
fi

# ── 4. Fonts ──────────────────────────────────────────────────────────────
section "4. Fonts"

if ls "$HOME/.local/share/fonts/JetBrainsMono/"*.ttf &>/dev/null 2>&1; then
    pass "JetBrainsMono Nerd Font"
else
    fail "JetBrainsMono Nerd Font  MISSING" "bash ~/dotfiles-sway/setup.sh"
fi

if find "$HOME/.local/share/fonts/FontAwesome" -type f \( -name '*.otf' -o -name '*.ttf' \) 2>/dev/null | grep -q .; then
    pass "Font Awesome"
else
    warn "Font Awesome — check ~/.local/share/fonts/FontAwesome/"
fi

if profile_includes "$PROFILE" containers; then
# ── 5. Toolbox ────────────────────────────────────────────────────────────
section "5. Toolbox '$TOOLBOX_CONTAINER' (dev environment)"

if host toolbox list 2>/dev/null | grep -qw "$TOOLBOX_CONTAINER"; then
    pass "Toolbox '$TOOLBOX_CONTAINER' exists"

    # Probe ONCE and ask the container for everything it has, instead of running
    # `toolbox run` separately for every tool. Each invocation is another chance
    # for an infrastructure hiccup — a container mid-start, a busy host — to be
    # reported as a missing tool, and one call per tool multiplies that by the
    # number of tools. On 2026-08-19 the VM run reported bat, fd, sgpt and claude
    # missing from a container where they were present, with passes interleaved
    # between the failures; the files predated the check by half an hour. The
    # probe was flaky, not the install.
    TOOLBOX_TOOLS=""
    TOOLBOX_PROBE_OK=0
    if TOOLBOX_TOOLS="$(host toolbox run --container "$TOOLBOX_CONTAINER" bash -lc \
            'for t in "$@"; do command -v "$t" >/dev/null 2>&1 && printf "%s\n" "$t"; done' _ \
            node npm gh claude codex deepseek sgpt git nvim btop duf bat ncdu rg fzf fd \
            2>/dev/null)"; then
        TOOLBOX_PROBE_OK=1
    fi

    check_toolbox_tool() {
        local tool="$1" label="${2:-$1}"
        if [[ "$TOOLBOX_PROBE_OK" -ne 1 ]]; then
            # "I could not ask" is not "it is not there" — the distinction this
            # whole audit is about. Do not turn it into a failure.
            warn "$label — could not query toolbox '$TOOLBOX_CONTAINER'"
        elif grep -qx -- "$tool" <<<"$TOOLBOX_TOOLS"; then
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
    check_toolbox_tool "nvim"   "nvim (Neovim, from dnf)"
    check_toolbox_tool "btop"   "btop (process monitor)"
    check_toolbox_tool "duf"    "duf (disk usage overview)"
    check_toolbox_tool "bat"    "bat (pager with syntax highlighting)"
    check_toolbox_tool "ncdu"   "ncdu (interactive disk usage)"
    check_toolbox_tool "rg"     "rg (ripgrep search)"
    check_toolbox_tool "fzf"    "fzf (fuzzy finder)"
    check_toolbox_tool "fd"     "fd (file finder)"

    if host toolbox run --container "$TOOLBOX_CONTAINER" bash -c \
        'expected="$(readlink -f "$HOME/dotfiles-sway/scripts/deepseek-wrapper.sh")" && test "$(readlink -f ~/.local/bin/deepseek 2>/dev/null)" = "$expected" && test "$(readlink -f ~/.local/bin/deepseek-tui 2>/dev/null)" = "$expected" && test "$(readlink -f ~/.npm-global/bin/deepseek 2>/dev/null)" = "$expected" && test "$(readlink -f ~/.npm-global/bin/deepseek-tui 2>/dev/null)" = "$expected"' &>/dev/null 2>&1; then
        pass "DeepSeek TUI low-motion wrapper installed"
    else
        warn "DeepSeek TUI low-motion wrapper missing — rerun bash ~/dotfiles-sway/scripts/setup-damian-container.sh"
    fi

    if host toolbox run --container "$TOOLBOX_CONTAINER" bash -c \
        'PATH="$HOME/.npm-global/bin:$PATH" command -v markdownlint-cli2' &>/dev/null 2>&1; then
        pass "markdownlint-cli2 (Neovim Markdown linting)"
    else
        fail "markdownlint-cli2  MISSING in toolbox/global npm prefix" \
             "bash ~/dotfiles-sway/scripts/setup-damian-container.sh"
    fi

    # Plugins — check settings.json
    for plugin in superpowers code-simplifier context7; do
        if host toolbox run --container "$TOOLBOX_CONTAINER" bash -c \
            "grep -q '$plugin' ~/.claude/settings.json 2>/dev/null" 2>/dev/null; then
            pass "Claude plugin: $plugin"
        else
            fail "Claude plugin: $plugin  MISSING" \
                 "toolbox enter $TOOLBOX_CONTAINER → claude plugin install ${plugin}@claude-plugins-official --yes"
        fi
    done

    # API key
    if host toolbox run --container "$TOOLBOX_CONTAINER" bash -c \
        '[[ -n "${ANTHROPIC_API_KEY:-}" ]] || grep -q ANTHROPIC_API_KEY ~/.bashrc.d/ai-keys.bash 2>/dev/null || grep -q ANTHROPIC_API_KEY ~/.bashrc 2>/dev/null' 2>/dev/null; then
        pass "ANTHROPIC_API_KEY available"
    else
        warn "ANTHROPIC_API_KEY not found — put it in ~/.bashrc.d/ai-keys.bash for Claude Code"
    fi

    if host toolbox run --container "$TOOLBOX_CONTAINER" bash -c \
        'test -s ~/.config/shell_gpt/.sgptrc && ! grep -q "^OPENAI_API_KEY=missing-shellgpt-api-key$" ~/.config/shell_gpt/.sgptrc || [[ -n "${OPENAI_API_KEY:-}" ]] || [[ -n "${SHELLGPT_API_KEY:-}" ]] || [[ -n "${GEMINI_API_KEY:-}" ]] || test -s ~/.config/voice-type/gemini-api-key' 2>/dev/null; then
        pass "ShellGPT API config present"
    else
        warn "ShellGPT API config placeholder — provide ~/.config/voice-type/gemini-api-key, GEMINI_API_KEY, OPENAI_API_KEY/SHELLGPT_API_KEY, or a private env file before running setup-damian-container.sh"
    fi

    if host toolbox run --container "$TOOLBOX_CONTAINER" bash -c \
        'grep -q "^DEFAULT_MODEL=gemini/" ~/.config/shell_gpt/.sgptrc 2>/dev/null && { [[ -n "${GEMINI_API_KEY:-}" ]] || test -s ~/.config/voice-type/gemini-api-key || grep -q GEMINI_API_KEY ~/.bashrc.d/shellgpt-gemini.bash 2>/dev/null; }' 2>/dev/null; then
        pass "ShellGPT Gemini config shares voice typing key source"
    fi

    if host toolbox run --container "$TOOLBOX_CONTAINER" bash -c \
        'test -x ~/.local/bin/sgpt && grep -q "real_sgpt=" ~/.local/bin/sgpt 2>/dev/null && grep -q "SGPT_FALLBACK_MODEL" ~/.local/bin/sgpt 2>/dev/null && grep -q "gemini/gemini-2.5-flash-lite" ~/.local/bin/sgpt 2>/dev/null' 2>/dev/null; then
        pass "ShellGPT executable fallback configured"
    else
        warn "ShellGPT executable fallback not configured — rerun bash ~/dotfiles-sway/scripts/setup-damian-container.sh"
    fi

else
    fail "Toolbox '$TOOLBOX_CONTAINER'  NOT FOUND" "bash ~/dotfiles-sway/scripts/setup-damian-container.sh"
fi

# ── 5a. Ubuntu dev Distrobox ─────────────────────────────────────────────
section "5a. Distrobox '$UBUNTU_DEV_CONTAINER' (Ubuntu dev CLI parity)"

if host podman container exists "$UBUNTU_DEV_CONTAINER" 2>/dev/null; then
    pass "Distrobox '$UBUNTU_DEV_CONTAINER' exists"

    UBUNTU_DEV_VERSION=$(host distrobox enter --name "$UBUNTU_DEV_CONTAINER" -- bash -lc \
        '. /etc/os-release && printf "%s" "$VERSION_ID"' 2>/dev/null || echo "unknown")
    if [[ "$UBUNTU_DEV_VERSION" == "26.04" ]]; then
        pass "Ubuntu 26.04 in $UBUNTU_DEV_CONTAINER container"
    else
        fail "$UBUNTU_DEV_CONTAINER container is Ubuntu $UBUNTU_DEV_VERSION, expected 26.04" \
             "distrobox stop $UBUNTU_DEV_CONTAINER --yes && distrobox rm $UBUNTU_DEV_CONTAINER --force && bash ~/dotfiles-sway/scripts/setup-ubuntu-dev-container.sh"
    fi

    # One probe for the whole container — see the note on the toolbox check above.
    UBUNTU_TOOLS=""
    UBUNTU_PROBE_OK=0
    if UBUNTU_TOOLS="$(host distrobox enter --name "$UBUNTU_DEV_CONTAINER" -- bash -lc \
            'for t in "$@"; do command -v "$t" >/dev/null 2>&1 && printf "%s\n" "$t"; done' _ \
            node npm gh claude codex deepseek sgpt git nvim btop duf bat ncdu rg fzf fd \
            2>/dev/null)"; then
        UBUNTU_PROBE_OK=1
    fi

    check_ubuntu_dev_tool() {
        local tool="$1" label="${2:-$1}"
        if [[ "$UBUNTU_PROBE_OK" -ne 1 ]]; then
            warn "$label — could not query container '$UBUNTU_DEV_CONTAINER'"
        elif grep -qx -- "$tool" <<<"$UBUNTU_TOOLS"; then
            pass "$label"
        else
            fail "$label  MISSING in $UBUNTU_DEV_CONTAINER container" \
                 "bash ~/dotfiles-sway/scripts/setup-ubuntu-dev-container.sh"
        fi
    }

    check_ubuntu_dev_tool "node"   "node (Node.js)"
    check_ubuntu_dev_tool "npm"    "npm"
    check_ubuntu_dev_tool "gh"     "gh (GitHub CLI)"
    check_ubuntu_dev_tool "claude" "claude (Claude Code)"
    check_ubuntu_dev_tool "codex"  "codex (OpenAI Codex CLI)"
    check_ubuntu_dev_tool "deepseek" "deepseek (DeepSeek TUI)"
    check_ubuntu_dev_tool "sgpt"   "sgpt (ShellGPT)"
    check_ubuntu_dev_tool "git"    "git"
    check_ubuntu_dev_tool "nvim"   "nvim (Neovim, from apt)"
    check_ubuntu_dev_tool "btop"   "btop (process monitor)"
    check_ubuntu_dev_tool "duf"    "duf (disk usage overview)"
    check_ubuntu_dev_tool "bat"    "bat (pager with syntax highlighting)"
    check_ubuntu_dev_tool "ncdu"   "ncdu (interactive disk usage)"
    check_ubuntu_dev_tool "rg"     "rg (ripgrep search)"
    check_ubuntu_dev_tool "fzf"    "fzf (fuzzy finder)"
    check_ubuntu_dev_tool "fd"     "fd (file finder)"

    if host distrobox enter --name "$UBUNTU_DEV_CONTAINER" -- bash -lc \
        'expected="$(readlink -f "$HOME/dotfiles-sway/scripts/deepseek-wrapper.sh")" && test "$(readlink -f ~/.local/bin/deepseek 2>/dev/null)" = "$expected" && test "$(readlink -f ~/.local/bin/deepseek-tui 2>/dev/null)" = "$expected" && test "$(readlink -f ~/.npm-global/bin/deepseek 2>/dev/null)" = "$expected" && test "$(readlink -f ~/.npm-global/bin/deepseek-tui 2>/dev/null)" = "$expected"' &>/dev/null 2>&1; then
        pass "DeepSeek TUI low-motion wrapper installed in $UBUNTU_DEV_CONTAINER"
    else
        warn "DeepSeek TUI low-motion wrapper missing in $UBUNTU_DEV_CONTAINER — rerun bash ~/dotfiles-sway/scripts/setup-ubuntu-dev-container.sh"
    fi

    if host distrobox enter --name "$UBUNTU_DEV_CONTAINER" -- bash -lc \
        'PATH="$HOME/.npm-global/bin:$PATH" command -v markdownlint-cli2' &>/dev/null 2>&1; then
        pass "markdownlint-cli2 in $UBUNTU_DEV_CONTAINER"
    else
        fail "markdownlint-cli2  MISSING in $UBUNTU_DEV_CONTAINER/global npm prefix" \
             "bash ~/dotfiles-sway/scripts/setup-ubuntu-dev-container.sh"
    fi

    if host distrobox enter --name "$UBUNTU_DEV_CONTAINER" -- python3 -c "import faster_whisper" &>/dev/null 2>&1; then
        pass "faster-whisper in $UBUNTU_DEV_CONTAINER"
    else
        fail "faster-whisper  MISSING in $UBUNTU_DEV_CONTAINER" \
             "bash ~/dotfiles-sway/scripts/setup-ubuntu-dev-container.sh"
    fi

    if host distrobox enter --name "$UBUNTU_DEV_CONTAINER" -- bash -lc \
        'test -s ~/.config/shell_gpt/.sgptrc && ! grep -q "^OPENAI_API_KEY=missing-shellgpt-api-key$" ~/.config/shell_gpt/.sgptrc || [[ -n "${OPENAI_API_KEY:-}" ]] || [[ -n "${SHELLGPT_API_KEY:-}" ]] || [[ -n "${GEMINI_API_KEY:-}" ]] || test -s ~/.config/voice-type/gemini-api-key' &>/dev/null 2>&1; then
        pass "ShellGPT API config present in $UBUNTU_DEV_CONTAINER"
    else
        warn "ShellGPT API config placeholder in $UBUNTU_DEV_CONTAINER — provide a private key source and rerun bash ~/dotfiles-sway/scripts/setup-ubuntu-dev-container.sh"
    fi
else
    fail "Distrobox '$UBUNTU_DEV_CONTAINER'  NOT FOUND" "bash ~/dotfiles-sway/scripts/setup-ubuntu-dev-container.sh"
fi

# ── 5b. NordVPN ──────────────────────────────────────────────────────────
section "5b. NordVPN"

if host which nordvpn &>/dev/null 2>&1; then
    pass "NordVPN CLI"
else
    fail "NordVPN CLI  MISSING" "bash ~/dotfiles-sway/scripts/setup-nordvpn.sh"
fi

if host systemctl list-unit-files nordvpnd.service 2>/dev/null | grep -q '^nordvpnd\.service'; then
    if host systemctl is-enabled --quiet nordvpnd && host systemctl is-active --quiet nordvpnd; then
        pass "NordVPN background service (enabled and running)"
    elif host systemctl is-enabled --quiet nordvpnd; then
        # Enabled but not up yet — it starts on the next boot. setup-nordvpn.sh
        # has done everything it can; the login that follows is Damian's step,
        # documented as manual in README.
        pending "NordVPN service enabled but not started yet — starts on next boot" \
                "sudo systemctl start nordvpnd, then: nordvpn login"
    else
        fail "NordVPN background service neither running nor enabled" \
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

# ── Repo hygiene ─────────────────────────────────────────────────────────
section "Repo working tree"

# setup.sh runs `chmod +x scripts/*.sh`. Any script recorded in git as 644 is
# therefore flipped to 755 on every install, leaving a permanent mode-only diff —
# and `git pull --ff-only` refuses to run against a dirty tree. The effect is that
# the documented update path stops working after the first setup.sh, silently:
# bootstrap.sh sees local changes and skips the pull. Observed 2026-08-19 in the
# test VM, where it blocked the orchestrator resume outright.
MODE_DRIFT="$(cd "$HOME/dotfiles-sway" 2>/dev/null && git diff --summary 2>/dev/null | grep -c "mode change" || true)"
if [[ "${MODE_DRIFT:-0}" -eq 0 ]]; then
    pass "No file-mode drift between the working tree and git"
else
    fail "$MODE_DRIFT script(s) differ from git by file mode only — this blocks 'git pull --ff-only'" \
         "cd ~/dotfiles-sway && git diff --summary | grep 'mode change'  # then: git update-index --chmod=+x <file>"
fi

# ── 5b. ChatGPT desktop app ──────────────────────────────────────────────
section "5b. ChatGPT desktop (incl. Codex)"

# The app is installed user-local (~/.local/opt), NOT layered onto the OS image.
# See scripts/setup-chatgpt.sh for why: upstream's %post writes under /var, which
# is read-only inside rpm-ostree's scriptlet sandbox, and the failure aborts the
# whole atomic transaction — every OS update with it.
CHATGPT_LAUNCHER="$HOME/.local/bin/chatgpt"
CHATGPT_MANIFEST="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles-updates/chatgpt"

if [[ -x "$CHATGPT_LAUNCHER" ]]; then
    pass "ChatGPT desktop app  ($(readlink -f "$CHATGPT_LAUNCHER" | sed 's:.*/opt/::; s:/usr/lib/.*::'))"
else
    fail "ChatGPT desktop app  MISSING" "bash ~/dotfiles-sway/scripts/setup-chatgpt.sh"
fi

if [[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/applications/chatgpt.desktop" ]]; then
    pass "ChatGPT desktop entry"
else
    fail "ChatGPT desktop entry  MISSING  (the app would not appear in the launcher)" \
         "bash ~/dotfiles-sway/scripts/setup-chatgpt.sh"
fi

# Without the manifest the app is invisible to the update module — it is in no
# distro repo and has no self-updater, so nothing else would ever notice a
# release.
if [[ -f "$CHATGPT_MANIFEST" ]]; then
    pass "ChatGPT update manifest"
else
    fail "ChatGPT update manifest  MISSING  (new releases would never be detected)" \
         "bash ~/dotfiles-sway/scripts/setup-chatgpt.sh"
fi

# A leftover layered copy is not cosmetic: while it is in the deployment, every
# `rpm-ostree upgrade` aborts on its %post and NO OS update can install.
if host rpm -q chatgpt >/dev/null 2>&1; then
    fail "chatgpt is STILL layered onto the OS  (this blocks every OS update)" \
         "sudo rpm-ostree uninstall chatgpt && systemctl reboot"
else
    pass "chatgpt is not layered onto the OS image"
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
    fail "iptables  MISSING (required by AdGuard auto mode)" "sudo rpm-ostree install iptables-nft && systemctl reboot   # iptables-nft ships in the Fedora Sway Atomic base; layer it only if a stripped base lacks it"
fi

if host adguard-cli status >/dev/null 2>&1; then
    pass "AdGuard background service running"
elif host systemctl list-unit-files adguard-*.service 2>/dev/null | grep -q '^adguard-'; then
    if host systemctl is-active --quiet adguard-ctrl; then
        pass "AdGuard background service running"
    else
        warn "AdGuard service installed but not running yet — complete adguard-cli activate && adguard-cli configure && adguard-cli start"
    fi
else
    warn "AdGuard service unit not found — this CLI install may be using the root helper only; verify with adguard-cli status"
fi
fi  # end containers (Toolbox / Ubuntu distrobox / NordVPN / AdGuard)

# ── 5c. Neovim ───────────────────────────────────────────────────────────
section "5c. Neovim"

# Neovim now comes from the package manager (rpm-ostree/dnf/apt), so check for a
# packaged nvim on PATH — and warn if a stale user-local binary lingers, since it
# would shadow the packaged one.
NVIM_ON_PATH="$(command -v nvim || true)"
if [[ -n "$NVIM_ON_PATH" ]]; then
    # A broken nvim (missing shared lib, bad build) would exit non-zero here and,
    # with pipefail + set -e, take the remaining sections of this script with it.
    NVIM_LINE=$("$NVIM_ON_PATH" --version 2>/dev/null | head -n1 || true)
    [[ -n "$NVIM_LINE" ]] || NVIM_LINE="version unreadable"
    pass "Neovim from package manager ($NVIM_ON_PATH — $NVIM_LINE)"
    if echo "$NVIM_LINE" | grep -qvE "v0\.(1[2-9]|[2-9][0-9])"; then
        warn "Neovim < 0.12 — Chris Titus Tech config uses vim.pack (needs 0.12+): $NVIM_LINE"
    fi
else
    fail "Neovim not found on PATH" \
         "install it via the package manager (dnf/apt/rpm-ostree), then: bash ~/dotfiles-sway/scripts/setup-neovim-config.sh"
fi
if [[ -L "$HOME/.local/bin/nvim" || -e "$HOME/.local/bin/nvim" ]]; then
    warn "Stale user-local ~/.local/bin/nvim present — it shadows the packaged nvim; run setup-neovim-config.sh to remove it"
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

if profile_includes "$PROFILE" containers; then
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

if host toolbox list 2>/dev/null | grep -qw "$TOOLBOX_CONTAINER"; then
    if host toolbox run --container "$TOOLBOX_CONTAINER" python3 -c "import faster_whisper" &>/dev/null 2>&1; then
        pass "faster-whisper AI model (Whisper small) in $TOOLBOX_CONTAINER toolbox"
    else
        fail "faster-whisper  MISSING in $TOOLBOX_CONTAINER toolbox" \
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

    # Optional tools the setup installs best-effort (run_step_warn). A miss is a
    # warning, not a failure — this keeps verify consistent with the setup script,
    # which does not mark the container un-ready when these are absent.
    check_security_tool_optional() {
        if host distrobox enter --name security -- which "$1" &>/dev/null 2>&1; then
            pass "$1"
        else
            warn "$1  not installed (optional) — bash ~/dotfiles-sway/scripts/setup-security-container.sh"
        fi
    }

    check_security_tool "nmap"
    check_security_tool "gobuster"
    check_security_tool "hydra"
    check_security_tool "msfconsole"
    check_security_tool "sqlmap"
    check_security_tool "evil-winrm"
    check_security_tool_optional "enum4linux-ng"
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
        warn "SecLists not installed (optional, ~1 GB) — bash ~/dotfiles-sway/scripts/setup-security-container.sh"
    fi
else
    fail "Distrobox 'security'  NOT FOUND" "bash ~/dotfiles-sway/scripts/setup-security-container.sh"
fi
fi  # end containers (Voice typing / security distrobox)

if profile_includes "$PROFILE" kvm; then
# ── 7. KVM / virtualisation ───────────────────────────────────────────────
section "7. KVM / virtualisation"

if host systemctl is-active libvirtd &>/dev/null 2>&1; then
    pass "libvirtd is running"
elif host systemctl is-enabled libvirtd &>/dev/null 2>&1; then
    # Enabled but not started: setup-kvm.sh has done its part and the service
    # comes up on the next boot. Calling that a failure makes a correct install
    # report failure until someone reboots.
    pending "libvirtd enabled but not started yet — starts on next boot" \
            "sudo systemctl start libvirtd  (or just reboot)"
else
    fail "libvirtd neither running nor enabled" "bash ~/dotfiles-sway/scripts/setup-kvm.sh"
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

if host virsh --connect qemu:///system net-list --all 2>/dev/null | grep -q "dotfiles-nat"; then
    NETSTATE=$(host virsh --connect qemu:///system net-list 2>/dev/null | \
        awk '/dotfiles-nat/ {print $2}' || echo "unknown")
    if [[ "$NETSTATE" == "active" ]]; then
        pass "NAT network 'dotfiles-nat' active"
    else
        warn "NAT network 'dotfiles-nat' exists but not active — run: virsh --connect qemu:///system net-start dotfiles-nat"
    fi
elif ! host virsh --connect qemu:///system net-list --all >/dev/null 2>&1; then
    # libvirtd unreachable, so the network's absence was never established.
    # "I could not ask" is not "it is not there" — the same distinction the
    # container probes needed.
    warn "NAT network 'dotfiles-nat' — could not check (libvirtd not reachable)"
else
    fail "NAT network 'dotfiles-nat'  MISSING" "bash ~/dotfiles-sway/scripts/setup-kvm.sh"
fi

if host groups 2>/dev/null | grep -q libvirt; then
    pass "User in libvirt group"
elif host getent group libvirt 2>/dev/null | grep -q "\b$USER\b"; then
    # The install added the user; group membership only reaches a session at
    # login. The install cannot log you out, so this is waiting, not broken.
    pending "User added to libvirt group — takes effect after the next login" \
            "Log out and back in (or reboot)"
else
    fail "User NOT in libvirt group" "sudo usermod -aG libvirt \$USER  (then log out and back in)"
fi

section "7a. Virtual machines"
for vmname in win11 winserver kali fedora-sway-test; do
    VMSTATE=$(host virsh --connect qemu:///system domstate "$vmname" 2>/dev/null || echo "not found")
    if [[ "$VMSTATE" == "not found" ]]; then
        if [[ "$vmname" == "win11" ]]; then
            # A warning, not a failure. Nothing in this repo creates win11 — its
            # own remedy says "create manually" — yet this section gates the
            # orchestrator's phase P2, which ends in `verify.sh --profile
            # post-reboot`. A freshly installed machine cannot have Damian's
            # personal Windows VM, so an otherwise perfect unattended install
            # could never report success (observed 2026-08-19 in the test VM).
            # A check whose fix is a manual step must not fail an automated one.
            warn "VM '$vmname'  not present (personal VM, created manually — see CLAUDE.md)"
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
fi  # end kvm (KVM / VMs / Hardware)

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

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD} VERIFICATION RESULT${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${GREEN}✓${NC} Passed:   ${BOLD}$PASS${NC}"
echo -e "  ${RED}✗${NC} Failed:   ${BOLD}$FAIL${NC}"
echo -e "  ${CYAN}◔${NC} Pending:  ${BOLD}$PENDING${NC}"
echo -e "  ${YELLOW}⚠${NC} Warnings: ${BOLD}$WARN${NC}"

# Pending items are listed but never counted as failure: each one is something
# the install finished as far as it could, waiting on a login or a reboot.
if [[ $PENDING -gt 0 ]]; then
    echo ""
    echo -e "${CYAN}${BOLD}  $PENDING item(s) waiting on you — the install did its part:${NC}"
    for i in "${!PENDINGS[@]}"; do
        echo -e "    ${CYAN}◔${NC} ${PENDINGS[$i]}"
        [[ -n "${PENDING_FIXES[$i]}" ]] && echo -e "       ${PENDING_FIXES[$i]}"
    done
fi

if [[ $FAIL -eq 0 ]]; then
    echo ""
    if [[ $PENDING -gt 0 ]]; then
        echo -e "${GREEN}${BOLD}  Nothing is broken — $PENDING item(s) just need a login or reboot.${NC}"
    else
        echo -e "${GREEN}${BOLD}  All checks passed — system installed correctly!${NC}"
    fi
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

# Exit nonzero when any required check failed, so automation / a phase handoff /
# anyone checking $? sees a broken install as a failure instead of success.
# (Warnings do not fail the run.) NOTE: until install profiles land (BACKLOG #3/#11),
# optional/personal items still counted as FAIL will make this exit 1 too.
if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
