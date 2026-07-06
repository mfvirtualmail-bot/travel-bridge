#!/bin/bash
# =============================================================================
#  travel-bridge  ·  uninstaller
#  Removes everything install.sh added and hands the WiFi back to NetworkManager.
#  Your saved WiFi networks are left untouched. Run:  sudo bash uninstall.sh
# =============================================================================
set -uo pipefail
[ "$(id -u)" = "0" ] || { echo "Please run with sudo: sudo bash uninstall.sh"; exit 1; }

echo "==> Stopping and disabling services"
systemctl disable --now hostapd dnsmasq travel-bridge-apdev.service travel-bridge-autojoin.service 2>/dev/null || true

echo "==> Removing files"
rm -f /usr/local/sbin/travel-bridge-apdev.sh \
      /usr/local/sbin/travel-bridge-autojoin.sh \
      /etc/systemd/system/travel-bridge-apdev.service \
      /etc/systemd/system/travel-bridge-autojoin.service \
      /etc/NetworkManager/conf.d/99-travel-bridge.conf \
      /etc/NetworkManager/dispatcher.d/90-travel-bridge \
      /etc/dnsmasq.d/travel-bridge.conf \
      /etc/sysctl.d/99-travel-bridge.conf \
      /etc/hostapd/hostapd.conf

# tidy the virtual AP interface if it exists
iw dev 2>/dev/null | grep -q "Interface ap0" && iw dev ap0 del 2>/dev/null || true

echo "==> Reloading"
systemctl daemon-reload
systemctl restart NetworkManager 2>/dev/null || true
systemctl restart nftables 2>/dev/null || true

echo
echo "Done. travel-bridge removed. (The packages hostapd/dnsmasq are left"
echo "installed — remove them with: sudo apt-get purge hostapd dnsmasq )"
echo "Config in /etc/travel-bridge was kept; delete it with: sudo rm -rf /etc/travel-bridge"
