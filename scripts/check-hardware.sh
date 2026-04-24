#!/bin/bash
# check-hardware.sh — hardware verification after reboot
# Run after first reboot: bash ~/dotfiles-sway/scripts/check-hardware.sh

DOTFILES="$HOME/dotfiles-sway"
source "$DOTFILES/scripts/lib-install.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}=== Hardware Check ===${NC}"

ok()   { echo -e "  ${GREEN}✓${NC}  $1"; }
bad()  { echo -e "  ${RED}✗${NC}  $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }

FAIL=0

check() {
    local label="$1" cmd="$2"
    if eval "$cmd" &>/dev/null 2>&1; then
        ok "$label"
    else
        bad "$label"
        ((FAIL++))
    fi
}

check "GPU render node (/dev/dri/renderD128)" "ls /dev/dri/renderD128"
check "VA-API hardware acceleration"          "vainfo"
check "USB controller"                        "lsusb"
check "Audio output (ALSA sink)"             "pactl list sinks short | grep -q alsa_output"
check "Microphone (ALSA input)"              "pactl list sources short | grep -q alsa_input"
check "Touchpad detected"                    "libinput list-devices 2>/dev/null | grep -qi touchpad"

# Wifi — warn only
if nmcli device status 2>/dev/null | grep -q "wifi.*connected"; then
    ok "Wi-Fi connected"
else
    warn "Wi-Fi not connected (pair manually)"
fi

# Bluetooth — warn only
if rfkill list bluetooth 2>/dev/null | grep -q "Soft blocked: no"; then
    ok "Bluetooth enabled"
else
    warn "Bluetooth soft blocked — enable via: rfkill unblock bluetooth"
fi

# Battery — warn only (not present on desktops)
if ls /sys/class/power_supply/BAT* &>/dev/null 2>&1; then
    ok "Battery detected"
else
    warn "No battery detected (OK on desktop)"
fi

# Backlight — warn only
if ls /sys/class/backlight/ 2>/dev/null | grep -q .; then
    ok "Screen backlight device"
else
    warn "No backlight device (OK on desktop)"
fi

# Camera — warn only
if ls /dev/video0 &>/dev/null 2>&1; then
    ok "Camera (/dev/video0)"
else
    warn "No camera detected"
fi

# nomodeset — should not be set (breaks AMD GPU)
if rpm-ostree kargs 2>/dev/null | grep -q "nomodeset"; then
    bad "nomodeset is SET — remove it: rpm-ostree kargs --delete=nomodeset"
    ((FAIL++))
else
    ok "nomodeset not set (correct)"
fi

echo ""
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}Hardware check passed.${NC}"
    step_done "HARDWARE_CHECK"
else
    echo -e "${RED}${BOLD}$FAIL hardware issue(s) found.${NC}"
    step_failed "HARDWARE_CHECK"
fi

echo ""
