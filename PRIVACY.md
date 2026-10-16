# MoneyLedger — Privacy Policy

_Last updated: 2026-10-16_

<!-- Keep in sync with the in-app privacy policy (About → Privacy policy),
     whose text lives in lib/l10n/app_en.arb / app_de.arb (privacy* keys). -->

MoneyLedger is an expense-sharing app without a central server. It has no
account system of its own — you sign in with your Matrix account — shows no
ads, contains no analytics or tracking, and does not sell or share your data.
MoneyLedger is published by Leo Stumpf, an individual developer. There is no
MoneyLedger server that could receive your data.

## Summary

| | |
|---|---|
| MoneyLedger server | None |
| Account | Your existing Matrix account (on a homeserver you choose) |
| Where your ledger lives | On the devices of the group's members |
| What the homeserver can read | Nothing of the ledger — only encrypted messages and their metadata |
| Analytics, crash reporting, ads, tracking | None |
| Leaves the device | Encrypted sync messages to your homeserver; a CSV or backup file only when you export one |

## Your ledger stays on your devices

Groups, participants, expenses and payments are stored only in a local database
on each device signed in to a member's account. Every member of a group has a
copy of that group's ledger — that is how sharing works: the names, Matrix IDs,
expenses and payments in a group are visible to all of its members.

## What your Matrix homeserver sees

To sync, MoneyLedger sends every change as an end-to-end-encrypted Matrix
to-device message to the other members' devices. Your homeserver (and the
homeservers of the other members) relay these messages and queue them until
they are delivered, but cannot read them. They do see metadata: which accounts
and devices exchange messages, when, how often and roughly how large they are.
Your Matrix account itself — user name, devices, encryption keys, IP addresses
and sign-in history — is handled by your homeserver under its own privacy
policy.

## No analytics, no servers of ours

The app only talks to your homeserver — and, if you use single sign-on or sign
up on the web, to the pages your homeserver sends you to in your browser. There
is no analytics, no crash reporting, no advertising ID and no tracking of any
kind.

## Background sync on Android

On Android, MoneyLedger can sync about every 15 minutes while the app is closed
(only with a network connection and not on low battery). It uses the same
encrypted messages to your homeserver and shows no notifications. You can turn
it off in Settings. The web version syncs only while its tab is open.

## Export, backup and import

Exporting a group writes a CSV file with its expenses, payments, the
participants' names and the amounts; "Back up all groups" (Settings) writes one
JSON file with every group of your account, including the participants' Matrix
IDs and deleted entries. Both happen only when you ask for it. Where the file
goes is your choice; it is plain text, not encrypted, and MoneyLedger has no
visibility into it afterwards. Importing or restoring reads only the file you
pick.

## Device backups

MoneyLedger opts out of Android's automatic app backup and device-to-device
transfer. Your ledger and your Matrix session (including its encryption keys)
are never copied into a Google backup or onto another phone by Android. On a
new device, sign in and your groups are restored from your other devices and
the other members; for groups only you use, a backup file (Settings → Back up
all groups) is your own offline copy.

## Deleting your data

- Leave or delete a group (group menu ⋮): it and all its records are removed
  from this device. When you leave, the other members are told that you left.
- Signing out keeps this account's ledger on the device, so it is back when you
  sign in again.
- Uninstalling the app (or clearing its storage) removes everything it stored
  on the device.
- Copies on other members' devices are theirs: they keep the group's history,
  including your expenses in it.
- Your Matrix account can be deactivated through your homeserver.

## Contact

Questions, or anything that looks wrong here: open an issue at
<https://github.com/LeoStumpf/MoneyLedger> or email <leo.m.stumpf@gmail.com>.
