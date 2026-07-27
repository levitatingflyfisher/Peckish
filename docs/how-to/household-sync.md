# How-to: sync the household

One plan, one grocery list, every device — encrypted, over your own Wi-Fi,
touching no server anywhere. Recipes, the weekly plan, groceries, custom
foods and saved meals sync; **food diaries and targets never leave their
device**.

## Pair two devices

1. On the first device: **Settings → Household sync → Create a household
   code**. Copy it.
2. On the second device: **Settings → Household sync → I have a code from
   another device**, paste it.

The code is the pairing — every device holding it derives the same
encryption key, and nothing else can read (or forge) a single byte of a
sync. Guard it like a house key; replace it any time (re-enter a new one
on every device).

## Sync

1. On one device, turn on **Reachable for sync** and note its Wi-Fi
   address (your router's device list shows it, e.g. `192.168.1.23`).
2. On the other device, enter that address and tap **Sync now**.

Sync is bidirectional: it pulls the other device's changes, then pushes
yours. Run it whenever you like — after planning the week, before walking
into the store. Conflicts resolve newest-wins per item; a deletion on one
device deletes on the other.

## What to expect

- Checking items off the list on two phones in the same store works — sync
  when you're both done (or as you go).
- "Update Peckish on your other device" means the other build is too old
  to speak this protocol — it will never fall back to unencrypted sync.
- The browser (PWA) can't host or join a sync; it's for the phones and
  tablets. Web data stays local to the browser.

Design + the honest security scorecard:
[ADR-0006](../adr/0006-household-sync.md).
