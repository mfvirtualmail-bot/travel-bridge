# travel-bridge

Turn a Raspberry Pi into a small **travel router** that joins public WiFi
(airport, hotel, café) and re-broadcasts its own private WiFi. Your device
connects to the Pi and **never sees the captive-portal login page** — the Pi
handles that once, and everything behind it rides the authenticated session.

It was built for one specific need: **a filtered device can't get through a
WiFi login page**, so a filtered laptop or phone can't use public WiFi. The
bridge solves that **without ever touching the filter** — your device stays
100% filtered the whole time. See **[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md)**
for the plain-language explanation.

**🌐 Visual overview / how it works:** https://mfvirtualmail-bot.github.io/travel-bridge/
*(live once GitHub Pages is enabled — see below).*

> **What it does / does NOT do**
> - ✅ Passes the WiFi **login page** on behalf of your device.
> - ✅ Your device's **filter keeps filtering every byte**, unchanged.
> - ❌ It does **not** disable, pause, or weaken any filter.
> - ❌ It is **not** a filter and does not replace one.
>
> The bridge itself carries unfiltered packets (it has to, for the login page to
> work), so it's a locked-down, non-browsable appliance — lock it down (below)
> so only *your* device can use it.

---

## What you need
- A **Raspberry Pi** (3, 4, 5, or Zero 2 W) running **Raspberry Pi OS Bookworm
  (64-bit)** — "Lite" (headless) is fine.
- A power source (USB charger or power bank).
- **Recommended:** a **USB WiFi dongle** (any that supports "AP/managed"; see the
  [morrownr/USB-WiFi](https://github.com/morrownr/USB-WiFi) list). With a dongle
  the build uses **two radios** and is far more reliable. Without one it uses the
  single built-in radio (works, but experimental — see *Radio modes*).
- For captive-portal venues: one spare **unfiltered** device to tap the login
  page once (or use the tunnel trick in the airport guide).

## Quick start (Pi)
1. Copy this repo's `pi/` folder onto the Pi (via `scp`, a USB stick, or
   `git clone`).
2. Set your hotspot name/password:
   ```bash
   cd pi
   cp travel-bridge.conf.example travel-bridge.conf
   nano travel-bridge.conf        # at minimum change AP_PASS and AP_COUNTRY
   ```
3. Install:
   ```bash
   sudo bash install.sh
   ```
   It auto-detects whether a USB dongle is present and configures the right mode.
4. Join a real internet source as the uplink:
   ```bash
   sudo nmcli device wifi list
   sudo nmcli device wifi connect "SomeWiFi" password "thepassword"
   ```
5. Connect any device to your new **`TravelBridge`** WiFi and browse. 🎉

## Quick start (Windows companion app — optional)
A small control panel so you don't have to type Linux commands: see status,
scan for WiFi, and connect the Pi to a network from your laptop.
Double-click **`windows/TravelBridge.bat`**. Details in
[windows/README.md](windows/README.md).

## At an airport / hotel
Step-by-step, including the one-time captive-portal login:
**[docs/AIRPORT-GUIDE.md](docs/AIRPORT-GUIDE.md)**.

---

## Radio modes
| Mode | Hardware | Reliability | Notes |
|------|----------|-------------|-------|
| **dual** *(recommended)* | built-in WiFi **+ USB dongle** | High | Built-in = hotspot, dongle = uplink. Any channel, more devices, full speed. |
| **single** | built-in WiFi only | Experimental | One chip does hotspot **and** uplink on the **same channel**; ~5 devices; 5 GHz/DFS uplinks can drop the hotspot. Fine for trying the idea. |

`install.sh` picks `auto` by default (dual if a dongle is present, else single).
Force it with `FORCE_MODE` in `travel-bridge.conf`.

## Lock it down (after your first successful test)
The bridge re-broadcasts raw internet, so protect it. In `travel-bridge.conf`:
- **`AP_PASS`** — a strong password only you know.
- **`MAC_ALLOWLIST=1`** — then add your device's MAC to
  `/etc/travel-bridge/allowed-macs` (one per line). Only listed devices connect.
- **`AP_HIDDEN=1`** — hide the network name.

Re-run `sudo bash install.sh` after editing. Also keep SSH on a strong
password or key, and never port-forward the Pi to the internet.

## Optional: auto-join open WiFi
`sudo bash pi/enable-autojoin-open.sh` makes the Pi grab the strongest open
network when it's offline. (Most "open" WiFi still has a login page, so you may
still do the portal step — the service logs which case it hit.)

## Handy commands
```bash
systemctl status hostapd dnsmasq travel-bridge-apdev --no-pager
sudo journalctl -t travel-bridge          # single-radio channel-follow log
sudo nmcli device wifi list               # what's around
nmcli connection show                     # saved networks (auto-reconnect)
sudo bash pi/uninstall.sh                 # remove everything
```

## Status & contributions
This is a young project. **Dual-radio** (with a dongle) is the reliable path;
**single-radio** AP+STA is inherently finicky and depends on your Pi's WiFi
driver. Real-world reports — which venues, which dongles, what worked — are very
welcome via issues. It is a network appliance, not a filter; if you use it for
compliance reasons, clear the approach with your own rav/posek first.

## License
MIT — see [LICENSE](LICENSE).
