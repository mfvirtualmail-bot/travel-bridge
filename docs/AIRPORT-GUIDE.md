# Airport / hotel cheat-sheet

Everything here works with **no internet** — it's all local between your device
and the Pi. Keep a copy on your phone. Replace `192.168.50.1` / `PiUser` /
`TravelBridge` below if you changed them in `pi/travel-bridge.conf`.

**You need:** the Pi + a USB charger or power bank, and your device.

---

### Step 1 — Power on the Pi
Wait about a minute to boot. It creates its own WiFi (default name
**`TravelBridge`**) automatically. This needs no internet — it is always there.

### Step 2 — Connect your device to it
- **Network:** `TravelBridge`
- **Password:** the one you set as `AP_PASS`

### Step 3 — Join the venue WiFi
Easiest: open the **TravelBridge companion app** on Windows → **Scan** → pick
the venue network → **Connect**.

Or by hand, over SSH:
```
ssh PiUser@192.168.50.1
sudo nmcli device wifi list
sudo nmcli device wifi connect "VENUE_WIFI_NAME"                 # open network
sudo nmcli device wifi connect "VENUE_WIFI_NAME" password "pw"   # if it has one
```

### Step 4 — Do you have internet?
The app's **Check now** tells you. By hand, from the Pi:
```
curl -4 -s -o /dev/null -w "%{http_code}\n" --max-time 8 http://connectivitycheck.gstatic.com/generate_204
```
- `204` → you have real internet. **Done.**
- `000` / hangs → there's a **login page**. Do the portal step below.

---

## Portal step (only if you didn't get `204`)

The venue wants a login on a web page. Your **filtered device can't open it**.
Pick one:

**Option A — easiest (a spare unfiltered phone/tablet):**
1. Connect that spare device to `TravelBridge`.
2. Open its browser — the venue login page appears — log in / accept.
3. Done. Your filtered device now has internet through the bridge.

**Option B — laptop only (a one-time login tunnel):**
1. New PowerShell window (leave it open):
   ```
   ssh -D 1080 PiUser@192.168.50.1
   ```
2. Start a browser through the tunnel (run one line):
   ```
   & "C:\Program Files\Google\Chrome\Application\chrome.exe" --user-data-dir="$env:TEMP\portal" --proxy-server="socks5://127.0.0.1:1080" http://neverssl.com
   ```
3. The login page appears → log in → **close that browser and the tunnel**.

> Option B briefly opens an unfiltered login window on the laptop. Close it right
> after, and check with your rav that this is acceptable — Option A avoids it.

---

## Switching venues later
Repeat steps 3–4. The Pi auto-reconnects to networks it has seen before.

## If it doesn't work
- Most venues use **2.4 GHz** WiFi = fine. If the only WiFi is **5 GHz** and
  you're on the single built-in radio, the hotspot can drop — add a **USB WiFi
  dongle** (dual-radio mode) and it just works.
- Can't SSH in? Re-check you're on the `TravelBridge` WiFi and the Pi finished
  booting (~1 min).
- Restart the hotspot on the Pi:
  ```
  sudo systemctl restart travel-bridge-apdev hostapd dnsmasq
  ```
