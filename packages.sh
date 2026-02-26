#!/bin/bash
# Run this once after fresh install, then reboot
echo "==> Layering system packages (reboot required after)..."
rpm-ostree install mako
echo "==> Done. Please reboot: systemctl reboot"
