#!/usr/bin/env bash
set -euo pipefail

STEAM="${STEAM_PATH:-$HOME/.local/share/Steam}"

sudo -k
sudo -v

echo "closing Steam..."
killall -9 steam 2>/dev/null || true
sleep 1

echo "removing systemd-sysext sync service..."
sudo systemctl disable --now millennium-sysext-sync.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/millennium-sysext-sync.service
sudo systemctl daemon-reload

echo "unmerging and removing systemd-sysext overlay..."
sudo systemd-sysext unmerge 2>/dev/null || true
sudo rm -rf /var/lib/extensions/millennium

echo "removing Millennium files from Steam..."
rm -f "$STEAM/steamrt64/libXtst.so.6" "$STEAM/steamrt64/libmillennium_hhx64.so"

echo "done; Millennium has been completely removed. Start Steam to restore stock runtime files."
