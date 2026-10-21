# MoneyLedger — Privacy Policy

_Last updated: 2026-10-21_

<!-- Keep in sync with the in-app privacy policy (About → Privacy policy),
     whose text lives in lib/l10n/app_en.arb / app_de.arb (privacy* keys). -->

MoneyLedger is an expense-sharing app without a central server. It has no
account system of its own — you sign in with your Matrix account, or use the
app without any account (local mode) — shows no ads, contains no analytics or tracking, and does not sell or share your data.
MoneyLedger is published by Leo Stumpf, an individual developer. There is no
MoneyLedger server that could receive your data.

## Summary

| | |
|---|---|
| MoneyLedger server | None |
| Account | Your existing Matrix account (on a homeserver you choose) — or none at all (local mode) |
| Where your ledger lives | On the devices of the people in the group |
| What the homeserver can read | Nothing of the ledger — only encrypted messages and their metadata |
| What the homeserver keeps | Your account, its devices and their encryption keys, and encrypted messages until they are delivered — no rooms, no presence, no account settings from MoneyLedger |
| Analytics, crash reporting, ads, tracking | None |
| Leaves the device | Encrypted sync messages, sign-in and profile / device lookups — to your homeserver only; for groups you share with an invite link, an encrypted copy of the group to public Nostr relays; a CSV or backup file only when you export one |
| Third parties (Google, CDNs, …) | None — except the public Nostr relays of groups you share with an invite link; links open in your browser only when you tap them |

## Your ledger stays on your devices

Groups, people, expenses and payments are stored only in a local database on
each device signed in to the account of someone in the group. Everyone in a
group has a copy of that group's ledger — that is how sharing works: the names,
Matrix IDs, expenses and payments in a group are visible to everyone in it.

## What your Matrix homeserver sees

To sync, MoneyLedger sends every change as an end-to-end-encrypted Matrix
to-device message to the devices of the others in the group. Your homeserver
(and their homeservers) relay these messages and keep each one only
until the receiving device has fetched it, but cannot read them. They do see
metadata: which accounts and devices exchange messages, when, how often and
roughly how large they are. MoneyLedger creates no rooms, saves nothing in your
account's settings and never marks you as online; when it syncs, it asks your
homeserver only for these messages and for encryption-key updates — not for
your rooms, presence or account settings. What your homeserver still keeps is
what every Matrix app needs: your account, its list of devices (this one is
named “MoneyLedger”, with when and from which IP address it was last used),
each device's public encryption keys and one-time keys, and the messages above
until they are delivered (for a device that never comes back, until it is
removed). Your Matrix account itself — user name, devices, encryption keys, IP
addresses and sign-in history — is handled by your homeserver under its own
privacy policy.

## No analytics, no servers of ours

Apart from the Nostr relays of groups you share with an invite link (see
“Shared groups (invite link)”), the app talks only to Matrix homeservers: on
the sign-in page to the server you enter — and only once you confirm it or sign
in — and after that only to your own homeserver. Through it, the app also looks
up the Matrix profile names and devices of the people in your groups (your
homeserver may ask theirs). If you use single sign-on or sign up on the web,
your browser opens the pages your homeserver sends you to (for matrix.org
possibly Element's sign-up page, app.element.io). Links in the app — to the
source code on GitHub, for example — open in your browser only when you tap
them. The web version is loaded entirely from the site that hosts it: no code
or fonts from Google or any other third party. There is no analytics, no crash
reporting, no advertising ID and no tracking of any kind.

## Background sync on Android

On Android, MoneyLedger can sync about every 15 minutes while the app is closed
(only with a network connection and not on low battery). It uses the same
encrypted messages to your homeserver and, for groups you share with an invite
link, the same encrypted copies on the Nostr relays (also without an account),
and shows no notifications. With a Matrix account you can turn it off in
Settings; without one it runs only while you have a group shared with an invite
link. The web version syncs only while its tab is open.

## Local mode (without an account)

If you use MoneyLedger without a Matrix account, groups you don't share send
nothing: for them the app contacts no server and nothing is synced (the web
version is only loaded from the site that hosts it). A group you share with an
invite link syncs through public Nostr relays (see “Shared groups (invite
link)”). Links you tap, e.g. to the source code, open in your browser. Your
name, groups, expenses and payments are stored only in a local database on this
device, plus a small preferences file (whether you saw the welcome, your local
profile name). Deleting local data in the settings, or uninstalling the app,
removes them. If you later connect a Matrix account, the local data moves into
that account and from then on the sections above apply.

## Shared groups (invite link)

A group you share with an invite link syncs through public Nostr relays — by
default nos.lol and nostr.mom, which have one operator. They are independent
services with their own terms. Every device in the group publishes its copy of
the group there, encrypted (AES-256-GCM) with a key that only the link
contains; the key never goes to a relay or to any server of ours. The relays
can't read names, amounts or notes, but they see your device's IP address, when
it syncs, roughly how large the group is and how many devices take part, and
that the data comes from MoneyLedger. We ask them to delete each copy after 30
days (renewed while the group is in use), but relays may keep or archive data
longer — and anyone who gets the link, now or later, can read and change the
group, also from archived copies. A group only on this device never contacts a
relay: a group starts syncing only when you invite with a link, create it
with “Share with an invite link” or join it with a link someone sent you.
Opening an invite link contacts nothing until you tap “Join”; the relays are
then asked for that group.

## Export, backup and import

Exporting a group writes a CSV file with its expenses, payments, the
people's names and the amounts; a backup ("Back up all groups" in
Settings, or one group from its menu) writes one JSON file with the groups,
including the people's Matrix IDs and deleted entries. Both happen only
when you ask for it. Where the file goes is your choice. A CSV is always plain
text; a backup is plain text too unless you set a passphrase — then it is
encrypted on your device (Argon2id + AES-256-GCM) and can only be restored
with that passphrase, which MoneyLedger never stores or sends anywhere.
MoneyLedger has no visibility into the file afterwards. Importing or restoring
reads only the file you pick.

## Device backups

MoneyLedger opts out of Android's automatic app backup and device-to-device
transfer. Your ledger and your Matrix session (including its encryption keys)
are never copied into a Google backup or onto another phone by Android. On a
new device, sign in and your groups are restored from your other devices and
the other people in your groups; for groups only you use, a backup file (Settings → Back up
all groups) is your own offline copy.

## Restore points on this device

To let you undo mistakes, MoneyLedger keeps earlier versions of your groups'
entries on this device for 90 days, and on Android once a day (when something
changed) a copy of all your groups in the app's private storage — the last 7
days plus 4 older weeks. These versions and copies are never sent anywhere,
are not part of any backup file, and are excluded from Android's backups like
all app data. Leaving or deleting a group removes its earlier versions at
once; the daily copies still contain it until they rotate out (after about
five weeks), so that a group deleted by mistake can be restored. Deleting
local data, or uninstalling the app, removes all of them.

## Receipt photos (Android)

On Android you can attach a photo of the receipt to an expense, taken with
your camera app or picked from your photos. MoneyLedger stores a smaller copy
only in the app's private storage on this device. It is never sent anywhere —
not to the others in the group, not to any homeserver — is not part of any
backup file, restore point or CSV, and is excluded from Android's backups like
all app data. It is deleted with its expense (the next time the app starts),
when you leave or delete the group, and when you delete local data or
uninstall the app; signing out keeps it. The camera and photo picker are
Android's own: MoneyLedger asks for no camera or storage permission and only
receives the one photo you choose.

## Deleting your data

- Leave or delete a group (group settings): it and all its records are removed
  from this device (the daily restore points keep it for about five weeks —
  see "Restore points on this device"). When you leave, the others in the group
  are told that you left.
- Signing out keeps this account's ledger on the device, so it is back when you
  sign in again.
- In local mode, Settings → *Delete local data* removes every local group from
  this device and ends local mode.
- Uninstalling the app (or clearing its storage) removes everything it stored
  on the device.
- Copies on other people's devices are theirs: they keep the group's history,
  including your expenses in it.
- Your Matrix account can be deactivated through your homeserver.

## Contact

Questions, or anything that looks wrong here: open an issue at
<https://github.com/LeoStumpf/MoneyLedger> or email <leo.m.stumpf@gmail.com>.
