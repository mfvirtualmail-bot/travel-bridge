#!/bin/bash
# =============================================================================
#  travel-bridge  ·  optional add-on: auto-join the strongest OPEN WiFi
# -----------------------------------------------------------------------------
#  When the Pi has no internet, it scans and connects to the strongest open
#  (no-password) network, then checks whether real internet followed.
#  Run this AFTER install.sh:   sudo bash enable-autojoin-open.sh
#
#  NOTE: most "open" WiFi still shows a captive portal, so auto-connecting does
#  NOT guarantee working internet — you may still need to tap through a login
#  page on a spare helper device. The service logs which case it hit.
#  Turn it off later:  sudo systemctl disable --now travel-bridge-autojoin
# =============================================================================
set -euo pipefail
[ "$(id -u)" = "0" ] || { echo "Run with sudo"; exit 1; }

source /etc/travel-bridge/runtime.conf 2>/dev/null || { echo "Run install.sh first."; exit 1; }
CHECK_INTERVAL=30
PORTAL_URL="http://connectivitycheck.gstatic.com/generate_204"
command -v curl >/dev/null || { apt-get update -y && apt-get install -y curl; }

cat > /usr/local/sbin/travel-bridge-autojoin.sh <<EOF
#!/bin/bash
set -uo pipefail
UPLINK="${UPLINK_IFACE}"
CHECK_INTERVAL=${CHECK_INTERVAL}
PORTAL_URL="${PORTAL_URL}"

has_internet(){ [ "\$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "\$PORTAL_URL" 2>/dev/null || echo 000)" = "204" ]; }
is_connected(){ nmcli -t -f DEVICE,STATE device 2>/dev/null | grep -q "^\${UPLINK}:connected"; }

logger -t tb-autojoin "auto-join service started on \$UPLINK"
while true; do
  if is_connected && has_internet; then sleep "\$CHECK_INTERVAL"; continue; fi
  mapfile -t OPENNETS < <(
    nmcli --escape no -t -f SIGNAL,SECURITY,SSID device wifi list ifname "\$UPLINK" --rescan yes 2>/dev/null \
      | awk -F: '(\$2=="" || \$2=="--") && \$3!="" {print \$1"\t"\$3}' | sort -k1 -nr | cut -f2- | awk '!seen[\$0]++' )
  if [ "\${#OPENNETS[@]}" -eq 0 ]; then logger -t tb-autojoin "no open networks in range"; sleep "\$CHECK_INTERVAL"; continue; fi
  for SSID in "\${OPENNETS[@]}"; do
    logger -t tb-autojoin "trying open SSID: \$SSID"
    if nmcli device wifi connect "\$SSID" ifname "\$UPLINK" >/dev/null 2>&1; then
      sleep 6
      if has_internet; then logger -t tb-autojoin "CONNECTED + real internet: \$SSID";
      else logger -t tb-autojoin "\$SSID connected but NO internet (captive portal?) — log in on the helper device"; fi
      break
    fi
  done
  sleep "\$CHECK_INTERVAL"
done
EOF
chmod +x /usr/local/sbin/travel-bridge-autojoin.sh

cat > /etc/systemd/system/travel-bridge-autojoin.service <<'EOF'
[Unit]
Description=travel-bridge: auto-join strongest open WiFi when offline
After=NetworkManager.service
Wants=NetworkManager.service

[Service]
Type=simple
ExecStart=/usr/local/sbin/travel-bridge-autojoin.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now travel-bridge-autojoin.service
echo
echo "Auto-join enabled.  Watch it:  sudo journalctl -t tb-autojoin -f"
echo "Turn it off:                   sudo systemctl disable --now travel-bridge-autojoin"
