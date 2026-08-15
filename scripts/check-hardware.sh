#!/bin/bash
# check-hardware.sh — hardware verification after reboot
# Run after first reboot: bash ~/dotfiles-sway/scripts/check-hardware.sh

DOTFILES="$HOME/dotfiles-sway"
source "$DOTFILES/scripts/lib-install.sh"
setup_logging "scripts/check-hardware.sh"

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
# `libinput list-devices` needs root to open /dev/input/event*; as a normal user
# it prints "Permission denied" for every device and finds nothing, so this check
# reported a missing touchpad on a laptop whose touchpad works. /proc/bus/input/devices
# is world-readable and lists the same hardware. libinput stays as the fallback for
# systems without procfs input, and no device name is hardcoded either way.
check "Touchpad detected"                    "grep -qi touchpad /proc/bus/input/devices 2>/dev/null || libinput list-devices 2>/dev/null | grep -qi touchpad"

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
print_state_summary

# Exit code must agree with the verdict already written to the state file.
# Callers that want to continue regardless say so explicitly — orchestrate.sh
# phase P2 uses `|| true` because this check is advisory there.
[[ $FAIL -eq 0 ]]
