# How it works (plain language)

This page explains, without jargon, exactly what the travel-bridge does and —
just as important — what it does **not** do.

## The problem it solves

Public WiFi at an airport, hotel or café almost always shows a **login page**
first (a "captive portal") — you have to open a browser, accept terms or enter
a room number before you get internet. A **filtered device cannot open that
login page**, so a filtered laptop or phone simply can't get onto that WiFi.
The person is left feeling the only option is to remove the filter — which it
is not.

## What the travel-bridge is

A small, separate box — a Raspberry Pi — that sits **between** the public WiFi
and your device. It has **no screen and no keyboard**; you never browse on it.
It does two things and nothing else:

1. It joins the public WiFi and handles the **login page** once.
2. It hands that connection to your device over its **own private WiFi**.

Think of it as your own little travel router — the same kind of "hotspot box"
people buy — except it gets its internet from the venue's WiFi instead of a SIM
card. Your device connects to the box, not to the venue.

## The key point — the filter is never touched

**The filter on your device stays on, fully, the entire time.** The bridge does
**not** disable it, pause it, or weaken it — not even for a second. Every byte
your device requests still goes through your filter (NetFree, TAG Lock, MB
Smart, Gader, Gentech, etc.) exactly as it does at home.

The bridge deals only with the **login page** — the part that isn't content,
that a filter can't render anyway. It has nothing to do with filtering what you
see. Content filtering happens on your device, before and after, unchanged.

Compare this to the on-device methods where the filter "steps aside for a few
seconds" during the portal handshake: here the filter never steps aside at all,
because a *separate* box handles the portal.

## One honest point to weigh

Because the bridge has to pass raw packets for your device, the **bridge itself
is not a filtered device** — it is a dumb pipe, like the airplane's own router.
It can't browse (no screen, no apps), but it does carry unfiltered traffic for
whatever connects to it. That is why it must be **locked down** so that only
*your* filtered device can use it:

- a WiFi password only you know,
- optionally a hidden network name,
- optionally a list of exactly which devices may connect (MAC allow-list).

Whether relying on such a separate bridge is appropriate is a question for a
rav/posek. This document is meant to describe *precisely what it does* so that
question can be asked accurately.

## What it is not

- It is **not** a way to get around your filter. Your device stays filtered.
- It is **not** a filter itself, and does not replace one.
- It does **not** store, log, or send your browsing anywhere.
