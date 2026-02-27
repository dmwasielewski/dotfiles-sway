#!/bin/bash
echo "=== Hardware Check ==="

echo -n "GPU render node: "
ls /dev/dri/renderD128 &>/dev/null && echo "✅" || echo "❌ missing"

echo -n "VA-API acceleration: "
vainfo &>/dev/null && echo "✅" || echo "❌ broken"

echo -n "Wi-Fi: "
nmcli device status | grep -q "wifi.*connected" && echo "✅" || echo "⚠️  not connected"

echo -n "Bluetooth: "
rfkill list bluetooth | grep -q "Soft blocked: no" && echo "✅" || echo "❌ blocked"

echo -n "Camera: "
ls /dev/video0 &>/dev/null && echo "✅" || echo "❌ missing"

echo -n "Microphone: "
pactl list sources short | grep -q "alsa_input" && echo "✅" || echo "❌ missing"

echo -n "Touchpad: "
libinput list-devices 2>/dev/null | grep -qi "touchpad" && echo "✅" || echo "❌ not detected"

echo -n "Battery detected: "
ls /sys/class/power_supply/BAT* &>/dev/null && echo "✅" || echo "⚠️  no battery"

echo -n "Screen backlight: "
ls /sys/class/backlight/ &>/dev/null && ls /sys/class/backlight/ | grep -q "." && echo "✅" || echo "❌ no backlight device"

echo -n "Audio output: "
pactl list sinks short | grep -q "alsa_output" && echo "✅" || echo "❌ missing"

echo -n "USB controller: "
lsusb &>/dev/null && echo "✅" || echo "❌ missing"

echo -n "nomodeset (bad): "
rpm-ostree kargs | grep -q "nomodeset" && echo "❌ present - remove it!" || echo "✅ not set"

echo "=== Done ==="
