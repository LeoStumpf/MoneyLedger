# MoneyLedger — Release notes

## v1.0.0 (versionName `1.0.0`, versionCode `1`)

_First public release. Android app id `io.github.leostumpf.moneyledger`;
web build from the same source. License: AGPL-3.0-or-later._

### What MoneyLedger is

MoneyLedger is a free, open-source app for sharing expenses in groups — trips,
flat shares, dinners — in the spirit of Splitwise or Tricount, but **without a
MoneyLedger server**. Your groups, expenses and payments live in a local
database on your devices. To share a group, MoneyLedger uses your
[Matrix](https://matrix.org) account (on any homeserver, e.g. matrix.org) as an
**end-to-end-encrypted relay** to the other members' devices; the homeserver
stores no ledger data and only ever sees ciphertext. You can also use the app
with no account at all.

### Highlights

- **Local-first, no server of ours.** Every device holds the full ledger of its
  groups and computes balances itself; devices reconcile with digest-based
  anti-entropy, so lost messages, new devices and reinstalls are repaired
  automatically.
- **Matrix as an E2EE relay.** Records travel as Olm-encrypted to-device
  messages (vodozemac); no Matrix rooms, nothing for the homeserver to read.
  Sign in with password or SSO, or create a Matrix account in the app (open
  homeservers; others get a link to their sign-up page).
- **Signed records.** Every version of every expense, payment, member and
  group change is signed by the device that wrote it (Ed25519). Tampered or
  unsigned versions are refused; each entry shows "Added by … · Last edited
  by …".
- **Device verification.** Emoji (SAS) verification with your own devices and
  other members' devices, and an opt-in "Only sync with verified devices".
- **Local mode.** *Use without an account*: everything stays on this device,
  other people are names only. *Connect a Matrix account* later moves all
  local groups into that account (signed by the new device) so you can invite
  people and sync.
- **Welcome.** A short first-open explanation of the app, Matrix and who sees
  what — before any sign-in.
- **Splitting.** Equal (pick who), exact amounts, shares or percentages —
  always summing to the cent; multiple currencies (settled separately);
  simplified "who pays whom"; record a payment between any two participants.
- **Organising.** 10 categories (suggested from the description), notes,
  search and filters, archive settled groups, rename a group / change its
  currency, leave or delete a group.
- **Backups.** Full JSON backup of all groups (or one group), restore with a
  preview; optionally **encrypted with a passphrase** (Argon2id +
  AES-256-GCM). A reminder appears when a group exists nowhere else.
- **CSV export / import** per group for spreadsheets.
- **English + German**, following the device language; light and dark theme.
- **Background sync on Android** about every 15 minutes (network connected,
  battery not low; can be turned off), so a closed phone still answers its
  group members and your new devices.
- **Private by design.** No analytics, no crash reporting, no ads, no
  tracking; Android cloud backup of the app data is disabled (the ledger and
  the Matrix keys never land in a Google backup). Privacy policy in the app
  and in [`PRIVACY.md`](../PRIVACY.md).

### Known limitations

Details in [`open-points.md`](open-points.md).

- **iOS is not supported** in v1 (no macOS build setup; the E2EE library has
  never been built for iOS). Android and web only.
- **Web syncs only while its tab is open** (no background sync).
- **Sync needs the other devices to come online.** Messages queue on the
  homeserver; a device that never runs (or has background sync off) answers
  nothing. A new device restores your groups from another device of yours
  only once that one runs.
- **No cross-signing.** Every new device of a member is a separate device to
  verify; a member could sign with an invented device id (shown as
  "unverified", not refused). An inviter's initial snapshot is trusted on
  first use.
- **Conflicts are last-writer-wins** per record (wall clock, future clocks
  clamped to +5 min); two devices that disagree about a refused version keep
  their versions until the record is edited again.
- **Size ceilings:** about 80 members and about 30,000 records per group.
- **Backups:** a forgotten passphrase can't be recovered; plain backups and
  CSV files are readable by anyone who gets the file. CSV identifies people
  by name and leaves out deletions — use the JSON backup for a full copy.
- **No receipt photos** (no media channel by design).
- **Verified-only sync** only limits what *your* device sends.
- Never run on a device: in-app registration on a homeserver with an open
  (dummy) sign-up flow.

### Install / upgrade notes

- **Test installs must be removed once.** Builds signed with the debug key,
  and builds with the old app id `app.moneyledger.money_ledger`, can't be
  updated to this release: uninstall them first. Back up all groups
  (*Settings → Back up all groups*) beforehand if they hold data nobody else
  has — your shared groups come back from the other members' devices after
  signing in again.
- **Play App Signing with the upload key.** Release builds are signed with the
  upload keystore `~/moneyledger-upload-keystore.jks` (alias `upload`) via the
  gitignored `android/key.properties`; enrol the app in Play App Signing with
  that upload key. **Back up the keystore and `key.properties` (incl. their
  passwords) offline / in a password manager** — without them no update can
  be uploaded. Never commit either file. Without `key.properties` the build
  falls back to the debug key (testing only).
- Build: `flutter build appbundle --release` (Play) or
  `flutter build apk --release`; Android builds need a Rust stable toolchain
  (see README). Web: `./build.sh` → `build/web/`.
- Bump `version:` in `pubspec.yaml` (`1.0.0+1` → e.g. `1.0.1+2`) for every
  Play upload — the versionCode must increase.

### Play Store "What's new"

**English (en-US)**

```
First release of MoneyLedger — share expenses in groups without a central server.
• Your ledger stays on your devices; groups sync end-to-end encrypted via your Matrix account (any homeserver)
• Or use it without any account — connect one later
• Equal, exact, shares or percent splits, multiple currencies, payments
• Categories, notes, search, archive
• Encrypted backups and CSV export
• English and German, light and dark theme
No ads, no tracking.
```

**German (de-DE)**

```
Erste Version von MoneyLedger – Ausgaben in Gruppen teilen, ohne zentralen Server.
• Deine Daten bleiben auf deinen Geräten; Gruppen synchronisieren Ende-zu-Ende-verschlüsselt über dein Matrix-Konto (jeder Homeserver)
• Oder ganz ohne Konto nutzen – später verbinden
• Gleich, Beträge, Anteile oder Prozent, mehrere Währungen, Zahlungen
• Kategorien, Notizen, Suche, Archiv
• Verschlüsselte Backups und CSV-Export
• Deutsch und Englisch, helles und dunkles Design
Keine Werbung, kein Tracking.
```
