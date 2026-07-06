# TravelBridge — Windows companion app

A small control panel for your travel-bridge Raspberry Pi. It lets you see
status, scan for WiFi around you, and connect the Pi to a network — over SSH,
from your laptop, without typing any Linux commands.

It talks to the Pi **locally** over the hotspot WiFi. It needs no internet of
its own.

## Requirements
- Windows 10 or 11 (the built-in OpenSSH client — no install needed).
- Your laptop connected to the Pi's hotspot WiFi (e.g. `TravelBridge`).

## Run it
Double-click **`TravelBridge.bat`**. (First run may take a second while it
builds a tiny login helper.)

To make a desktop shortcut: right-click `TravelBridge.bat` → *Send to* →
*Desktop (create shortcut)*.

## First launch
It asks for:
- **Pi address(es)** — default `192.168.50.1` (the hotspot IP set in
  `pi/travel-bridge.conf`) and `raspberrypi.local`. Comma-separate several.
- **Login user** — the Pi's username (e.g. `pi`).
- **Password** — stored **encrypted for your Windows account only** (DPAPI),
  in `%APPDATA%\TravelBridge\settings.json`. It is never written in plain text.

Tick **"Set up passwordless login"** to install an SSH key on the Pi, after
which the app (and your own `ssh`) never need the password again.

## What the buttons do
- **Check now** — shows Hotspot / Pi-joined-WiFi / Internet, plus recent
  history that the Pi logs even while offline. Writes a plain-text report to
  your Desktop.
- **Scan** — lists the WiFi networks the Pi can see around you.
- **Connect** — joins the Pi to the selected network (type the WiFi password if
  it has one). At a captive-portal venue, do the one-time login from a spare
  unfiltered device — see [../docs/AIRPORT-GUIDE.md](../docs/AIRPORT-GUIDE.md).

## Notes
- Nothing here is stored in the cloud; settings live only on your PC.
- Delete `%APPDATA%\TravelBridge` to reset the app completely.
