#!/bin/bash
# =============================================================================
#  travel-bridge  ·  installer
# -----------------------------------------------------------------------------
#  Turns a Raspberry Pi into a small "travel router" that joins a public /
#  hotel / airport WiFi and re-broadcasts its OWN private WiFi. A filtered
#  device connects only to the Pi's private hotspot and never sees the
#  captive-portal login page. The Pi passes the portal once; everything
#  behind it rides the authenticated session and stays fully filtered.
#
#  IMPORTANT: this appliance forwards raw packets (it has to, or the portal
#  can't work). The FILTER stays on the end device and keeps filtering every
#  byte exactly as it does at home — the bridge never touches it. But the
#  bridge itself is unfiltered, so protect it (password + optional MAC
#  allow-list + hidden SSID) so no OTHER device can ride it unfiltered.
#
#  TARGET: Raspberry Pi OS Bookworm (64-bit), which uses NetworkManager.
#          A Pi 3 / 4 / 5 or Zero 2 W all work. "Lite" (headless) is fine.
#  RUN:    sudo bash install.sh
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
log(){  printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
warn(){ printf '\n\033[1;33m[!]\033[0m %s\n' "$*"; }
die(){  printf '\n\033[1;31m[x]\033[0m %s\n' "$*"; exit 1; }

[ "$(id -u)" = "0" ] || die "Please run with sudo:  sudo bash install.sh"

# -----------------------------------------------------------------------------
# 1. Load configuration
# -----------------------------------------------------------------------------
CONF="$HERE/travel-bridge.conf"
if [ ! -f "$CONF" ]; then
  if [ -f "$HERE/travel-bridge.conf.example" ]; then
    cp "$HERE/travel-bridge.conf.example" "$CONF"
    warn "No travel-bridge.conf found — created one from the example."
    warn "Edit it (at least change AP_PASS), then run this installer again:"
    warn "    nano $CONF"
    exit 1
  fi
  die "travel-bridge.conf(.example) not found next to install.sh"
fi
# shellcheck disable=SC1090
source "$CONF"

: "${AP_SSID:?set AP_SSID in travel-bridge.conf}"
: "${AP_PASS:?set AP_PASS in travel-bridge.conf}"
[ "${#AP_PASS}" -ge 8 ] || die "AP_PASS must be at least 8 characters."
AP_COUNTRY="${AP_COUNTRY:-US}"
AP_CHANNEL="${AP_CHANNEL:-6}"
AP_IP="${AP_IP:-192.168.50.1}"
DHCP_START="${DHCP_START:-192.168.50.50}"
DHCP_END="${DHCP_END:-192.168.50.150}"
AP_HIDDEN="${AP_HIDDEN:-0}"
MAC_ALLOWLIST="${MAC_ALLOWLIST:-0}"
FORCE_MODE="${FORCE_MODE:-auto}"

# -----------------------------------------------------------------------------
# 2. Sanity checks
# -----------------------------------------------------------------------------
log "Checking the system"
grep -q -i bookworm /etc/os-release 2>/dev/null || \
  warn "Not detected as Raspberry Pi OS Bookworm — the script assumes NetworkManager. It may still work."
command -v nmcli >/dev/null || die "NetworkManager (nmcli) not found. This build needs Bookworm's NetworkManager."

# -----------------------------------------------------------------------------
# 3. Detect radios and decide single- vs dual-radio mode
# -----------------------------------------------------------------------------
#   Dual-radio (a USB WiFi dongle present) is the RELIABLE build:
#       built-in wlan (brcmfmac) = HOTSPOT (AP mode is guaranteed on it)
#       USB dongle               = UPLINK  (any dongle can do plain "managed")
#   Single-radio (built-in only) is EXPERIMENTAL:
#       wlan0 = UPLINK, a virtual "ap0" on the same chip = HOTSPOT (same channel,
#       ~5 clients, and 5 GHz/DFS uplinks can drop the hotspot).
# -----------------------------------------------------------------------------
log "Detecting WiFi radios"
mapfile -t WIFIS < <(for d in /sys/class/net/*/wireless; do basename "$(dirname "$d")"; done 2>/dev/null)
[ "${#WIFIS[@]}" -ge 1 ] || die "No WiFi interface found. Is WiFi enabled / the dongle plugged in?"

builtin_iface(){  # the brcmfmac (on-board) interface, if any
  for i in "${WIFIS[@]}"; do
    drv="$(basename "$(readlink -f "/sys/class/net/$i/device/driver" 2>/dev/null)" 2>/dev/null || true)"
    [ "$drv" = "brcmfmac" ] && { echo "$i"; return; }
  done
}
usb_iface(){      # the first USB-attached interface, if any
  for i in "${WIFIS[@]}"; do
    readlink -f "/sys/class/net/$i/device" 2>/dev/null | grep -q usb && { echo "$i"; return; }
  done
}

BUILTIN="$(builtin_iface || true)"; DONGLE="$(usb_iface || true)"
MODE="single"
if [ "$FORCE_MODE" = "dual" ]; then
  [ "${#WIFIS[@]}" -ge 2 ] || die "FORCE_MODE=dual but only one WiFi radio was found."
  MODE="dual"
elif [ "$FORCE_MODE" = "single" ]; then
  MODE="single"
else # auto
  [ "${#WIFIS[@]}" -ge 2 ] && MODE="dual"
fi

if [ "$MODE" = "dual" ]; then
  AP_IFACE="${BUILTIN:-wlan0}"
  UPLINK_IFACE="${DONGLE:-}"
  [ -n "$UPLINK_IFACE" ] || for i in "${WIFIS[@]}"; do [ "$i" != "$AP_IFACE" ] && UPLINK_IFACE="$i" && break; done
  [ -n "$UPLINK_IFACE" ] || die "Could not pick an uplink interface for dual-radio mode."
else
  UPLINK_IFACE="${BUILTIN:-${WIFIS[0]}}"
  AP_IFACE="ap0"
fi

log "Mode: $MODE   |   uplink = $UPLINK_IFACE   |   hotspot = $AP_IFACE"

# -----------------------------------------------------------------------------
# 4. Packages
# -----------------------------------------------------------------------------
log "Installing packages (hostapd, dnsmasq, iw, nftables)"
echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4   # hotspots rarely have IPv6
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y hostapd dnsmasq iw nftables iproute2 rfkill

log "Setting WiFi country ($AP_COUNTRY) and unblocking the radio"
raspi-config nonint do_wifi_country "$AP_COUNTRY" 2>/dev/null || iw reg set "$AP_COUNTRY" 2>/dev/null || true
rfkill unblock wifi 2>/dev/null || true

# -----------------------------------------------------------------------------
# 5. Runtime config + MAC allow-list
# -----------------------------------------------------------------------------
mkdir -p /etc/travel-bridge
cp "$CONF" /etc/travel-bridge/travel-bridge.conf
cat > /etc/travel-bridge/runtime.conf <<EOF
# Written by install.sh — reflects the radios detected at install time.
MODE="$MODE"
AP_IFACE="$AP_IFACE"
UPLINK_IFACE="$UPLINK_IFACE"
EOF
if [ ! -f /etc/travel-bridge/allowed-macs ]; then
  cat > /etc/travel-bridge/allowed-macs <<'EOF'
# MAC allow-list — only enforced when MAC_ALLOWLIST=1.
# One lower-case MAC per line, e.g.:
# aa:bb:cc:dd:ee:ff   # my filtered laptop
EOF
fi

# -----------------------------------------------------------------------------
# 6. AP-device helper + service (brings the hotspot interface up with its IP)
# -----------------------------------------------------------------------------
log "Installing the hotspot-interface helper + service"
cat > /usr/local/sbin/travel-bridge-apdev.sh <<'EOF'
#!/bin/bash
set -e
source /etc/travel-bridge/runtime.conf
source /etc/travel-bridge/travel-bridge.conf
if [ "$MODE" = "single" ]; then
  # create a virtual AP interface on the uplink's radio chip
  if ! iw dev | grep -q "Interface ${AP_IFACE}\b"; then
    iw dev "${UPLINK_IFACE}" interface add "${AP_IFACE}" type __ap
  fi
fi
ip addr flush dev "${AP_IFACE}" 2>/dev/null || true
ip addr add "${AP_IP}/24" dev "${AP_IFACE}"
ip link set "${AP_IFACE}" up
EOF
chmod +x /usr/local/sbin/travel-bridge-apdev.sh

cat > /etc/systemd/system/travel-bridge-apdev.service <<'EOF'
[Unit]
Description=travel-bridge: bring up the hotspot interface
Wants=network.target
After=network.target
Before=hostapd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/travel-bridge-apdev.sh

[Install]
WantedBy=multi-user.target
EOF

# -----------------------------------------------------------------------------
# 7. Tell NetworkManager to leave the hotspot interface alone
# -----------------------------------------------------------------------------
log "Telling NetworkManager to manage only the uplink ($UPLINK_IFACE)"
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/99-travel-bridge.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:${AP_IFACE}
EOF

# -----------------------------------------------------------------------------
# 8. hostapd (the hotspot itself)
# -----------------------------------------------------------------------------
log "Writing hostapd config (the hotspot)"
cat > /etc/hostapd/hostapd.conf <<EOF
interface=${AP_IFACE}
driver=nl80211
ssid=${AP_SSID}
country_code=${AP_COUNTRY}
ieee80211d=1
hw_mode=g
channel=${AP_CHANNEL}
ieee80211n=1
wmm_enabled=1
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=${AP_PASS}
ignore_broadcast_ssid=${AP_HIDDEN}
macaddr_acl=${MAC_ALLOWLIST}
accept_mac_file=/etc/travel-bridge/allowed-macs
EOF
chmod 600 /etc/hostapd/hostapd.conf
sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

# -----------------------------------------------------------------------------
# 9. dnsmasq (DHCP + DNS for devices on the hotspot)
# -----------------------------------------------------------------------------
log "Writing dnsmasq config (DHCP for hotspot clients)"
cat > /etc/dnsmasq.d/travel-bridge.conf <<EOF
interface=${AP_IFACE}
bind-interfaces
except-interface=${UPLINK_IFACE}
domain-needed
bogus-priv
dhcp-range=${DHCP_START},${DHCP_END},255.255.255.0,24h
dhcp-option=3,${AP_IP}
dhcp-option=6,${AP_IP}
EOF

# -----------------------------------------------------------------------------
# 10. IP forwarding + NAT (masquerade out the uplink)
# -----------------------------------------------------------------------------
log "Enabling IP forwarding + NAT out $UPLINK_IFACE"
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-travel-bridge.conf
sysctl --system >/dev/null

cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain forward { type filter hook forward priority 0; policy accept; }
}
table ip nat {
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    oifname "${UPLINK_IFACE}" masquerade
  }
}
EOF
systemctl enable nftables >/dev/null 2>&1 || true
systemctl restart nftables

# -----------------------------------------------------------------------------
# 11. Single-radio only: follow the uplink's channel + country
# -----------------------------------------------------------------------------
if [ "$MODE" = "single" ]; then
  log "Installing channel-follow hook (single-radio: hotspot must match the uplink)"
  cat > /etc/NetworkManager/dispatcher.d/90-travel-bridge <<EOF
#!/bin/bash
# Single-radio chips can only run AP+STA on ONE channel. When the uplink
# ($UPLINK_IFACE) connects, move the hotspot onto the same channel and adopt
# the local regulatory country so it stays legal & working anywhere.
IFACE="\$1"; ACTION="\$2"
[ "\$IFACE" = "${UPLINK_IFACE}" ] || exit 0
case "\$ACTION" in up|dhcp4-change|connectivity-change) ;; *) exit 0 ;; esac
sleep 2
CH=\$(iw dev ${UPLINK_IFACE} info 2>/dev/null | awk '/channel/{print \$2; exit}')
[ -n "\$CH" ] || exit 0
REG=\$(iw reg get 2>/dev/null | awk '/^country/{print \$2; exit}' | tr -d ':')
if { [ -z "\$REG" ] || [ "\$REG" = "00" ]; } && [ "\$CH" -ge 12 ] && [ "\$CH" -le 14 ]; then
  iw reg set GB 2>/dev/null; sleep 1; REG=GB
fi
if [ "\$CH" -gt 14 ]; then HW=a; else HW=g; fi
if [ -n "\$REG" ] && [ "\$REG" != "00" ]; then
  sed -i "s/^country_code=.*/country_code=\$REG/" /etc/hostapd/hostapd.conf
fi
sed -i "s/^channel=.*/channel=\$CH/" /etc/hostapd/hostapd.conf
sed -i "s/^hw_mode=.*/hw_mode=\$HW/" /etc/hostapd/hostapd.conf
systemctl restart hostapd
logger -t travel-bridge "uplink ch=\$CH band=\$HW reg=\${REG:-unknown} -> hotspot updated"
EOF
  chmod +x /etc/NetworkManager/dispatcher.d/90-travel-bridge
else
  rm -f /etc/NetworkManager/dispatcher.d/90-travel-bridge
fi

# -----------------------------------------------------------------------------
# 12. Enable + start everything
# -----------------------------------------------------------------------------
log "Enabling and starting services"
systemctl daemon-reload
systemctl unmask hostapd >/dev/null 2>&1 || true
systemctl enable travel-bridge-apdev.service hostapd dnsmasq >/dev/null 2>&1 || true
systemctl restart NetworkManager
sleep 2
systemctl restart travel-bridge-apdev.service
systemctl restart dnsmasq
systemctl restart hostapd

# -----------------------------------------------------------------------------
# 13. Done
# -----------------------------------------------------------------------------
log "DONE"
cat <<EOF

  Mode         : $MODE
  Hotspot SSID : $AP_SSID
  Hotspot IP   : $AP_IP   (devices get $DHCP_START–$DHCP_END)
  Uplink       : $UPLINK_IFACE

  Next — join a real internet source as the uplink:
      sudo nmcli device wifi list
      sudo nmcli device wifi connect "SomeWiFi" password "thepassword"
      (open network: omit the password)

  Then connect any device to the "$AP_SSID" WiFi and browse.
  Captive-portal venues: log in ONCE from a spare unfiltered device that
  is joined to "$AP_SSID" — see docs/AIRPORT-GUIDE.md.

EOF
ip -br addr show "$AP_IFACE" 2>/dev/null || warn "Hotspot interface not up — check: systemctl status hostapd travel-bridge-apdev"
