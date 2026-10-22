# MoneyLedger — Open Points

Known gaps, risks, and durable design limitations. Resolved work is summarised at
the bottom; the architecture itself is documented in [`CLAUDE.md`](../CLAUDE.md).
Last reviewed: 2026-10-16. **The prioritised, actionable list (major/minor)
lives in [`plan.md`](../plan.md) → Phase G**; this file keeps the background.

---

## Open gaps

### Signed records (G6) — residual risks
Every record version is signed by its editor's Matrix device key and verified
on receipt (see CLAUDE.md "Signed records (G6)" and
`docs/design/g6-signed-records.md`). What is still open:
- **Fabricated device ids.** A member can sign a version "as" X with an
  invented device id and their own key. Receivers that never saw that device
  (and don't find it on X's server device list) can't tell it from a device X
  signed out of before they pinned it: the version is **accepted but shown
  unverified**; X's own devices flag it ("not from one of your devices").
  Closing this needs **cross-signing** (device keys signed by X's
  self-signing key survive logout) — the app never sets cross-signing up;
  future item. With G11's verified-only setting such records still arrive
  (inbound isn't refused) and stay "unverified".
- **Malicious inviter.** A new member trusts the inviter's bootstrap
  (TOFU, as before) including its `device_keys` attestations, so the inviter
  could vouch for fake keys ("vouched" in the details). *Narrowed (G18
  review):* attestations are scoped to the group whose snapshot carried them,
  and a peer's attestation never vouches for a device missing from an
  account's first-hand device list we hold. What remains (the inviter's own
  group, accounts we never got a device list for) needs cross-signing.
- **TOFU group creation.** Anyone can still bootstrap a *new* group onto our
  device (that's how invites work); since G18 such a snapshot can only write
  into its own group, never into one we know. Unwanted groups can be deleted.
- **Signer rule vs. unclaim (G18 review).** Versions of a group are only
  accepted when their signer claims a participant there (or relays them
  itself). After an account is **detached** (unclaim), the versions it signed
  stay on devices that hold them, but a device that never had them (a new
  member) won't accept them from others' relays — its balances can then
  differ. Detach rarely, or have someone re-save those records.
- **Homeserver.** A user's homeserver can add devices for that user (the
  Matrix E2EE trust model). *Mitigated, opt-in (G11):* with "Only sync with
  verified devices" a device we never emoji-verified gets nothing from us,
  and the record details say "You haven't verified this device".
- **Divergence by disagreement.** An honest device that accepted a version as
  "unverified" and one that refused it (key conflict) keep different
  versions; the digest `rejected` map stops the repair loop and the refusing
  side shows a notice on the record.
- **Divergence is not auto-resolved.** Nothing arbitrates between the two
  sides (no "majority" or authority); it stays until the record is edited
  again (a newer, verifiable version wins everywhere) — accepted for v1.
- **Grandfathered rows — decided (G35): no migration.** Rows from before G6
  stay local legacy/unsigned; peers refuse them when relayed, so they can't
  be bootstrapped to new members/devices (an unsigned group meta → the whole
  group is refused; unsigned records → the group arrives incomplete). The app
  is unreleased and only the test groups contain such rows, so there is **no
  re-sign step**; the test groups were recreated with the G38 device reset
  (done — no pre-G6 rows left on the test devices).
  The receiving side is told instead of silently showing a half-empty or
  missing group: a `[g6] refused unsigned …` log line and a dismissible
  groups-page hint ("Some data couldn't be received … ask X to recreate the
  group", `SyncHealthState.legacyRefusals`, session-only). A user's own
  backup still restores them as legacy (G5).
- **Size.** Signatures roughly double a record's wire size (~0.86 KB per
  record in a bootstrap) — handled by chunked bootstraps (G14, below).
- **Refusals are per version, a small set per record (G18 review 2, schema
  v10).** A refusal blocks exactly the refused version (clock + hash); the 4
  highest refused versions per record are remembered (`rejected` carries the
  highest, `rejected_more` the rest). A record with more than 4 *different*
  refused versions still held by peers would see the lowest ones re-offered
  each digest cycle (one message per cycle, not a tight loop) — needs a peer
  producing that many bad versions of one record.
- **Unsigned backup rows (G18 review 2).** A backup file isn't
  authenticated. Unsigned rows of a restored backup stay *unsigned legacy*
  (with **no** origin — attribution never vouches for unsigned content) and are never signed by this
  device — except a **truly local** group of a local-mode backup (no Matrix
  claim in the file or already here, nothing signed), which is adopted and
  signed as the user's own (the preview warns to restore only one's own
  file). A crafted local backup can therefore make this device sign a new,
  purely local group with made-up content — harmless to others (nobody else
  is in it). Limit: a local backup of a group **shared with Matrix accounts**
  (only possible after restoring a Matrix backup in local mode) restored
  into an account or local mode loses its `local:self` claim and stays
  unsigned — restore the original Matrix backup instead.

### Scalability (G14) — measured ceilings
Real limit: Synapse refuses to-device content > **65 536 bytes** per device
(`MAX_TO_DEVICE_CONTENT_SIZE`, HTTP 413; not yet in the spec — matrix-spec
PR #2340). Encrypted (Olm, base64) that leaves ≈ **48.4 KB** of our JSON per
message; we pack to **40 KB** (`payload_budget.dart`). Measured
(`test/core/payload_size_test.dart`, 4 members, signed v2 records):

| records | flat digest | single bootstrap | bootstrap parts | bucketed summary |
|---|---|---|---|---|
| 100 | 8 KB | 89 KB | 3 | (flat) |
| 1 000 | 66 KB | 860 KB | 24 | 2.6 KB (64 buckets) |
| 5 000 | 322 KB | 4.3 MB | 117 | 9.3 KB (512 buckets) |

Unchunked, a bootstrap broke at **~52 records** (new members / new devices of
any real group would silently get nothing — the SDK only logs the 413) and a
flat digest at **~720 records**. Now: chunked bootstraps + bucketed digests.
Remaining ceilings / costs:
- **Members per group** — every bootstrap part and every digest repeats all
  members (~0.4 KB each, signed): fine to ~80 members.
- **Records per group** — the bucket summary is capped at 2 048 buckets
  (~31 KB): ~30k records. A full restore of 5k records is ~117 messages.
- **Hashing cost** — solved (G37): measured on the Pixel 4a (5k records,
  in-memory DB, `tool/bench/digest_bench.dart`, profile build): digest =
  DB read 120 ms + `buildDigestMessages` 414 ms (hashing everything twice:
  flat attempt + bucketed) = **537 ms**, plus 211 ms for the receiver's
  local hashes. Now cached in `version_hash` (schema v8): **174 ms** (read
  125 + build 49), local hashes ~0 ms; the one-off v8 backfill of 5k rows
  took 367 ms. The DB read (row → model mapping) is now the main cost.
- **Refused versions (G37, assessed for v1 — accepted).** Only groups with
  a *bucketed* digest (≳ 720 records) pay anything: a refused version keeps
  its bucket's hash different from the peer's, so every digest cycle with
  that peer is summary → reply detailing that bucket (~16 entries, ≈ 1 KB)
  → `final` — one extra message per cycle and peer, never a loop, and both
  sides still count as in sync (pinned by
  `test/integration/large_group_sync_test.dart`, "G37: …"). Flat digests
  cost nothing extra. The old "refusals are per clock" part is fixed (G18
  review: a refusal names the exact version, clock + hash; up to 4 per
  record). Removing the remaining cost would need refusal-aware bucket
  hashes — not worth it for v1.
- **Wall-clock LWW**: within the 5-min clamp a skewed clock can still win.

### Device-verification enforcement (G11) — limits
Opt-in "Only sync with verified devices" (per account, device-local, default
off) withholds everything *this device* sends from unverified devices (own and
peers'), and SAS works with other members' devices (members page). Open:
- **Only our sends.** A peer's own devices still sync with each other (and a
  device we trust relays to devices it trusts); it is only end-to-end
  effective when every member turns it on and verifies.
- **Inbound is not refused** (decision: G6 refusals are permanent and a
  legitimate new device would lose edits) — only flagged in the details.
- **No cross-signing.** Verification is per device: every new device of a
  member must be emoji-verified again; an account that uses cross-signing in
  another client gets its SSSS step skipped. Fabricated device ids (G6) stay
  "unverified", not refused.
- New own device + setting on elsewhere: self-restore (G30) waits until the
  new device is verified; the restoring banner times out meanwhile.
- (G36) SAS emoji names are localized (Matrix spec table, EN + DE); the
  in-app texts now say plainly that the setting only limits this device's
  sends. Not yet seen on a device: the German emoji names in a live SAS
  (all test devices were already verified) — smoke 9.8.
- The verified-device record lives in the per-account DB on this device
  (not in backups; lost with the app data).

### Categories / notes / archive (G16) — limits
- **Receipt photos** are out of scope: there is no media channel (to-device
  messages are capped at ~64 KB, and the homeserver must keep no ledger data).
  A future design would need encrypted attachments (MSC / content repo with
  per-file keys) plus retention rules — not planned for v1.
- **Unknown fields break signatures on older builds**: the G6 signed body is
  rebuilt from the *parsed model*, so a pre-G16 build refuses a version that
  carries `category` / `note` (bad signature → `rejected_versions`). The v7
  migration forgets refused expense versions so they are re-sent after the
  update; mixed old/new devices disagree until every device is updated. A
  future protocol could sign the raw payload (minus transport fields) so
  unknown optional fields survive older verifiers.
- **Built-in category set is fixed** (10 ids); an unknown id from a newer
  peer is kept verbatim and shown as "Other". Category statistics: only
  the balance page overview (G69) — totals per category, no time ranges or
  charts.
  Per-group custom categories: G47 below.
- **Archive is device-local** (not synced to your other devices) and only
  ledger activity (expenses / payments incl. deletions) un-archives; member
  or group-name changes don't. A same-millisecond LWW tie-break version
  (G27) doesn't change the fingerprint (practically irrelevant).

### Custom categories (G47) — limits
- **Mixed versions:** the custom categories live in the signed group meta
  (`categories`, only when non-empty). A pre-G47 build rebuilds the meta body
  without them → bad signature → it refuses **every** later meta version of
  that group (also renames / currency changes) until it is updated. Same
  caveat and fix as G16: the v11 migration forgets refused *meta* versions,
  so peers re-send them after the update. Unreleased app → accepted.
- **Concurrent edits are whole-meta LWW:** two members adding a category at
  the same time (or one renaming the group while another adds a category)
  → the newer meta version wins and the other change is lost (the loser sees
  it vanish). A per-category CRDT / merge would fix it; rare in practice.
  Options + questions: `docs/design/g57-category-merge.md` (G57, open).
- **No delete** — only *hide* (old expenses stay labelled). An expense whose
  `c:` id the group doesn't define (e.g. a CSV from another group without a
  name column, or the definition lost to the LWW case above) shows as
  "Other" and keeps its id. At most 50 per group (≈ 5 KB in every meta /
  bootstrap part at the maximum).
- **CSV:** the `Category Name` column recreates missing definitions on
  import (default icon); icons and the hidden flag aren't in the CSV. The
  JSON backup is lossless (signed meta).
- Duplicate names are prevented in the dialog (case-insensitive) but not by
  the content rules (two peers may create "Dog" concurrently).

### Exchange rates (G73) — limits
- **Mixed versions:** the rates live in the signed group meta
  (`exchange_rates`, only when set). A pre-G73 build rebuilds the meta body
  without them → bad signature → it refuses that and every later meta
  version of the group until updated (link-only groups: it stores the
  unsigned meta without the rates). The v17 migration forgets refused meta
  versions, like v11 / v16. Unreleased app → accepted.
- **Whole-meta LWW** (as G47): a rate change concurrent with a rename /
  category edit loses one of them — part of the G57 decision
  (`docs/design/g57-category-merge.md`).
- **One base per group**, set when the first rate is added (the group
  currency then); changing it means removing all rates first. Rates are
  fixed (no history): changing a rate re-values **every** earlier expense
  in that currency for the balances — intended ("fixed rate for this
  trip"), not a per-expense rate.
- **Settle in one currency is per group, for everyone** (it is in the meta),
  not a personal view. Group stats (G69 overview) stay per original
  currency; the CSV has neither rates nor converted amounts.
- **Fetch current rate:** Frankfurter covers ~30 currencies (ECB list +
  some central banks); others must be typed. The request reveals the
  device's IP and the currency pair to Frankfurter (and its host,
  Cloudflare) — only on tap, said in the dialog + privacy text. Rates are
  rounded to 10 decimals; a rate < 10⁻¹⁰ or ≥ 10⁹ can't be stored.

### Expense / payment date (G49 / G60) — limits
- **Mixed versions:** a back-dated expense carries the optional signed
  `date` (ISO `YYYY-MM-DD`, only when it differs from the creation day). A
  pre-G49 build rebuilds the body without it → bad signature → it refuses
  that version (and later versions that keep the date) until it is updated.
  Same fix as G16: the v13 migration forgets refused *expense* versions, so
  peers re-send them after the update. An expense dated "today" carries no
  `date` and is accepted by every build. Unreleased app → accepted.
- **Payments (G60)** carry the same optional signed `date` with the same
  caveat: a pre-G60 build refuses a back-dated payment version (also its
  delete, which keeps the date) until it is updated; the v14 migration
  forgets refused *settlement* versions. A payment dated today carries no
  `date`. Payments still have no edit — a wrong day is delete + re-record.
- **Undated expenses follow the device's time zone** (as before): their day
  is the local day of `created_at`, so two members in very different zones
  can see an evening expense on adjacent days. A dated expense shows the
  same day everywhere. Only a picked day that differs from the local
  creation day is stored, so the creator's zone decides whether a date is
  written.
- **Content rule bound:** a date more than 400 days after the verifying
  device's today is refused (permanently, for that version) — the picker
  allows one year ahead, so only a peer with a clock off by over a month
  could trip it.
- **CSV:** `Date` is now the display day (`YYYY-MM-DD`, was the full ISO
  creation time); the exact creation time moved to a trailing `Created At`
  column. An older parser reads `Date` as the creation time → a re-import
  of a new CSV into a pre-G49 build would change `created_at` (and break
  the origin of a record it re-signs as creator). Edited `Date` cells
  back-date expenses and (G60) payments on import.

### Currencies (G66) — storage in hundredths, not ISO minor units
- **Why not ISO minor units:** every amount has always been stored and sent
  as hundredths of the major unit, also for JPY (offered since the first
  version: ¥1,000 = `100000`). Switching to real minor units (yen, fils)
  would change what the integer means: existing signed JPY records would
  show 100× too much (or need re-signed new versions), and old and new
  builds would read the same record differently — a wire change that would
  need a protocol marker (bundle with G57 if ever wanted). G66 therefore
  only changes display and input; nothing stored changes.
- **3-decimal currencies** (BHD, KWD, JOD, OMR, TND, LYD) show and accept
  **2 decimals** — a thousandth (1 fils ≈ €0.0025) can't be stored in
  hundredths. Splits are exact to 0.01.
- **0-decimal currencies** (JPY, KRW, ISK, HUF, IDR, …) are typed and split
  in whole units; a legacy non-whole amount (typed before G66, e.g.
  ¥12.34) is shown rounded (`¥12`) and kept as stored — never refused,
  an unchanged edit keeps it, a CSV export writes its 2 decimals.
- **`kMaxAmountCents`** (10^13 hundredths = 10^11 major units) is the same
  for every currency — ample for IDR / VND (≈ 6 M USD); a wire rule, so not
  made per currency.
- **Names** are ISO's (via Debian `iso-codes`) with a few clarified (JPY
  "Japanese Yen" …); search finds a currency by code or a word of its EN /
  DE name, not by country.

### Backups (G5 / G34) — limits
- **Encrypted backups** (optional passphrase): Argon2id (32 MiB, t = 3,
  p = 1) + AES-256-GCM via the pure-Dart `cryptography` implementations.
  A forgotten passphrase can't be recovered (by design). The passphrase
  strength hint is a heuristic, not a guarantee; a weak passphrase on a file
  that leaks can still be guessed offline (Argon2id only makes each guess
  expensive). The KDF cost is fixed per release (stored per file, so it can
  be raised later); on the web it takes ≈ 2 s.
- **Second own device** (nudge): counts only a *verified* other device of
  ours, or one that proved within 30 days (matching digest) that it holds our
  state. An unverified device that is offline for a month makes the nudge
  come back — intended.
- **Saved-file name**: Android's Downloads provider returns a document id
  (`msf:…`), not the name; then the snackbar says "Backup saved" without one.
- **Restore vs. removal after the backup**: a group restored from a backup
  taken before the other members removed us comes back active and turns
  read-only only at the next digest exchange with them (integration-tested:
  `test/integration/backup_restore_sync_test.dart`). If none of them is
  online, the group looks editable until then; edits made meanwhile are
  refused by the peers (we are not an active member there).
- Restore is **all-or-nothing per group** (one transaction; the homeserver
  lookups for signature verification happen before it). Different groups of
  one file are independent: a failing group is rolled back and reported, the
  others restore.

### Restore points / reset group (G48) — limits
- **Version history** (`record_history`, device-local): every version a DAO
  stores is appended (local, inbound, restore, revert, CSV import). Kept
  90 days + a 20 000-row soft cap; one **base** version per record survives
  pruning, so every reset point at/after the pruning floor is exact. Points
  before the floor (or before the group arrived on this device, or before the
  v12 migration) aren't offered. Rows written outside the DAOs (pre-G4 legacy
  adoption, the offline demo seed) have no history and are never touched by a
  reset. Upsert cost: one extra insert (+ a JSON encode) per **changed**
  version — measured within noise of the 3 000-upsert bench (≈ 0.7 ms per
  upsert in the test VM either way).
- **Reset = "how it looked on this device"**: a version that reached this
  device late is placed by when *we* stored it, not by its `updated_at`. A
  peer that never had a record can't be reset into having had it — the reset
  writes new versions everybody adopts (LWW), it never rewrites history.
- **Members are never reset** (removal must stick — G26; claims / "me" must
  not move). Restored expenses may name a participant that is removed now —
  balances show them under former members, as for any old expense. Group
  meta (name, currency, custom categories) *is* reset.
- **Concurrent edits**: a record a peer edits with a newer clock after our
  preview keeps the peer's version (LWW). Two members resetting at once
  converge per record by LWW, possibly to a mix — reset again if needed.
- **Big resets** (> 25 writes) aren't relayed record by record; the group is
  poked and the digest exchange (anti-entropy) carries them (a few seconds
  later on peers).
- **Snapshots** (`snapshots/<db name>/YYYY-MM-DD.json` in the app support
  dir, plaintext JSON like the DB itself, app-private, Android backup off):
  daily at app start if the ledger changed, 7 daily + 4 weekly. **Not on
  web** (no file system; the in-DB history still allows resetting a group, a
  backup file covers the rest). A snapshot restore is by default the normal
  LWW restore — it brings back groups / records that are *missing* (deleted
  group, DB wiped / corrupted), not older content of records changed since.
  G58 added the opt-in **"Exactly this state"**: after the merge, each group
  that exists here (and we're an active member of) is reset to the
  snapshot's expenses / payments / meta (shared G48 planner, new signed
  versions, everybody adopts them). Limits: it only writes **content this
  device itself stored** (the version must be in its `record_history`), so
  a snapshot version whose history entry was pruned (20 000-row cap moved
  the floor past it) or a record written outside the DAOs is skipped
  (counted in the preview) — snapshots are ≤ ~5 weeks old, history keeps
  90 days, so normally nothing is skipped. Participants are never reset
  (missing ones come back via the merge); removed / not-participating /
  left groups only get the merge. Not offered for a picked backup file (it
  may come from another device / account — most content would be skipped,
  and the per-group reset covers this device's own past). Like a reset,
  a concurrent newer edit by a peer wins (LWW). Since G58 Android background rounds (G31) take the daily
  snapshot too (skipped when a round is short of time); web, iOS and a
  device with background sync off still only snapshot at app start. A left/deleted group stays in the snapshots
  until they rotate out (≈ 5 weeks, said in the privacy texts).
- **Arrival batch absorbs early live records** (G62): a peer's live record
  arriving ≤ 30 s (`kBaseArrivalGap`) after a group's bootstrap counts as
  part of the arrival (base) batch and can't be undone on its own — the
  history doesn't store the message type / relaying sender. Rare (right
  after joining); accepted as a limit (Leo 2026-10-17).

### Receipt photos (G78) — limits
- **Android only, this device only**: no photo on the web / desktop / in the
  offline demo; never synced, never in a backup file, restore point or CSV.
  A new phone (or reinstall) has no photos — intended (Leo 2026-10-17).
- **Deleted lazily**: a deleted expense's photo stays until the next app
  start (so *Undo* / a G48 reset in the same session bring it back with it);
  a reset or restore *after* that restart brings the expense back without
  its photo. A left / deleted group's photos go at once; a group purged
  because we left on another device is swept at the next start. Background
  rounds (G31) don't sweep.
- **Lost camera result**: if Android kills the app while the camera app is
  open (low memory), the shot is lost (`image_picker`'s `retrieveLostData`
  isn't wired up) — take it again.
- **Picker temp files**: the camera shot / gallery copy `image_picker`
  writes to the app cache is deleted after reading; an original it kept
  beside a scaled copy (gallery picks) stays in the cache until Android
  clears it. App-private either way.
- The photo keeps the EXIF data `image_picker` copies (incl. GPS, if the
  camera recorded it) — never leaves the device, so not stripped.
- Format: JPEG (PNG stays PNG — `image_picker` doesn't recompress it), file
  still named `.jpg`; `Image.memory` decodes either.

### Payment details (G74) — limits
- **Device-local only (for now)**: the own bank account / PayPal.me name
  lives in this ledger's `AppSettings` (per account / local mode; moves along
  with a local-mode adoption). The payee shows the QR code on *their own*
  screen; the payer's app never learns the details. Showing them on the
  payer's device ("when they settle with me", plan.md G74) needs a synced
  field — wire / privacy decisions open (plan.md G74, needs Leo).
- **Not in backups / restore points**: a new phone needs them entered again.
- **GiroCode = euro only** (EPC SEPA credit transfer); other currencies get
  the IBAN as text. Banking apps outside DE / AT / NL may not scan it.
- The EPC remittance text is the group name (≤ 140 characters, cut to the
  331-byte limit); some banks only accept Latin characters there.

### Real-device smoke tests
Flows that can only be verified on a real device + homeserver, not in
`flutter test` or the web build (`docs/smoke-test.md`):
- **SSO** native deep link (`moneyledger://sso-callback`) — used for the
  matrix.org sign-in of the G41 run (emu-5556); the invalid-token path is
  smoke 2.6.
- **Registration** UIA: the web fallback (matrix.org, no client
  registration) is verified; the in-app **dummy-UIA path** on an open
  homeserver (smoke 2.9) has never run on a device.
- **SAS device verification** round-trip — done app↔app on 2026-10-16
  (G11, again G38 with German emoji names); against Element not tried.

### Dependencies (G22) — what is still held back
- **`sqlite3` ≥ 3.6** (and so the newest drift point releases' minimums) needs
  `meta` ^1.19 via `record_use` 1.x; Flutter 3.44 pins `meta` 1.18 → stuck on
  3.5.x until a Flutter upgrade.
- **`build_runner` ≥ 2.17** needs `build` 5.x; `drift_dev` 2.35 still requires
  `build` < 5 → 2.15.x until drift_dev moves.
- **Flutter itself** (3.44.0, pinned in CI) — not part of G22.
- **No SDK downgrade path:** matrix 14 migrated the device stores (v11 → v12,
  old device-key boxes cleared). Reinstalling a matrix-7 build over it would
  not lose the session (it only clears caches), but don't rely on rollbacks.
- **Web COOP/COEP:** flutter_rust_bridge logs "Buffers cannot be shared due to
  missing cross-origin headers" on the web build (wasm works, just without
  shared buffers). Setting `Cross-Origin-Opener-Policy`/`-Embedder-Policy` on
  the host would silence it — needs a check that SSO redirects still work.

### Sync loop after a network switch (G36)
Seen once on emu-5556 (G11 run): the Matrix sync loop stalled until restart.
Not reproduced in four emulator switches (offline ≤ 3 min, wifi ↔ data) —
the SDK retries every 3 s and caps the long-poll at 40 s. Hardened anyway:
every homeserver request must get response headers within 90 s
(`RequestTimeoutHttpClient`; the SDK only timed the body), and a watchdog
restarts a loop that isn't running and logs `[watchdog]` when a round makes
no progress for 2 min. Remaining: a stall inside a non-HTTP await (DB) would
only be logged — restarting the SDK loop while an old round can still finish
runs two loops (see CLAUDE.md). No connectivity listener (no plugin).

### Delivery acks / resync answers (G36)
- Writer's "waiting" after its own change: ~10 s → ~6 s (fast ack, 1 s
  debounce, one per group per 10 s). The rest is two relay hops; a second
  change within 10 s still waits for the 5 s debounce.
- Resync answers are deduped per (device, scope/group) for 60 s: a lost
  answer is only re-requested after the window (G30 retries / next digest).

### Legacy ledger cleanup (G36)
The adopted pre-G4 `money_ledger_db` is deleted on a later start — only when
every account it claimed is the adopter. With other claimed accounts it is
kept (`legacy_cleanup_done = kept`), although adoption is single-account
today: another claimed account can't adopt it anymore. A per-group adoption
for further accounts would be needed to make use of it (test devices only).

### Local mode / welcome (G39 / G40) — limits
- (G41, done) A backup made in local mode restored into a Matrix account is
  adopted like *Connect a Matrix account* (re-claim + sign); a Matrix backup
  restored in local mode makes the user that account's participant locally.
  Limit: restored into a **different** account than the backup's, the
  re-claimed participant is only ours locally — peers ignore it (non-member),
  like any other-account restore.
- The adoption waits up to 30 s for the new device's signing key; if it isn't
  ready, the sync engine signs the rows later — records edited in local mode
  then have no creation statement ("added by" missing; they still verify).
  (G18 review 2: the engine no longer signs while the adoption is pending —
  only after it finished without a key.)
- (G18 review 2) "Connect a Matrix account" follows the session state: a
  sign-in that finishes late (after the timeout) or before a crash is
  adopted; a sign-in that lands **after** the connect was cancelled is
  signed out again (`logout` — it is the fresh device of that attempt). If
  the app is killed between such a late sign-in and its sign-out, the next
  *Connect* finds the stored session and adopts into that account at once
  (the user did authenticate it).
- (G18 review 2) Only rows local mode wrote (`pendingSign`) are signed on
  adoption; legacy rows restored from a Matrix backup in local mode stay
  unsigned, and a Matrix backup in local mode only hands over a participant
  the backup account really signed.
- A pending adoption (`local_adopt_into`) only runs when *that* account is
  signed in; signing out before it ran and using another account leaves the
  local ledger waiting for the first one (it is never lost, just not shown).
- `vod.init()` still runs at every start, also in local mode (cheap; needed
  as soon as an account is connected).
- Existing installs: the device-wide `welcome_seen` flag starts unset, so a
  user who signs out after the update sees the welcome once.
- (G41) The local DB files are deleted after *Delete local data* / an
  adoption — unless some instance is still open at that moment (logged, kept;
  the next deletion takes it). No start-up sweep for leftovers.

### No third-party contacts (G43) — limits

- **Web glyph coverage.** The web build fetches no Noto fallback fonts from
  Google any more. It serves Roboto Regular (Latin, Greek, Cyrillic) plus two
  web-only subsets (the 64 SAS emoji; arrows / math / dingbats). Anything else
  — most emoji typed into a description, CJK / Arabic / … names — renders as
  boxes on the web, and the engine asks our own origin for the Noto file
  (`fonts/<family>/v…/….woff2` → 404) again on every layout of such text
  (local requests + console warnings, no privacy issue). Android is
  unaffected (system fonts). Fix if it matters: mirror the engine's whole
  fallback set at build time (725 files listed in `main.dart.js`, ≈ 30 MB,
  downloaded from fonts.gstatic.com by the build machine, OFL) into
  `build/web/fonts/` — full parity, nothing fetched by users from Google.
  **Accepted as is (Leo, 2026-10-17):** the web is secondary, the app stays small.
- **Only Roboto Regular** on the web (as before with the CDN): bold weights are
  synthesized by the engine.
- **Engine paths.** The Roboto file name is the engine's (`roboto/v32/…`);
  a Flutter upgrade may change it — `tool/web/check_web_build.sh` fails the
  build then (re-run `tool/fonts/make_web_fonts.py --roboto-path …`).
- **Offline vs. server down** can't be told apart at sign-in any more (the
  matrix.org probe is gone): one message covers both.
- **Login flows** load only when the user acts, so the SSO-only / password-only
  shape of a server shows after *Check server* / Enter / *Sign in*; before
  that the generic form (SSO + password) is shown.
- **Still contacted by design:** the server entered on the login page (once
  confirmed), the user's homeserver (sync, keys, profile names via federation),
  the browser pages of SSO / web sign-up (incl. `app.element.io` as matrix.org's
  fallback) and links the user taps (GitHub). The web host itself serves the
  app. Dev runs (`flutter run -d web-server`) still use the CDN unless given
  `--no-web-resources-cdn`.

---

## Architecture limitations (reference)

Durable constraints of the current design — not bugs, but worth knowing.

- **Trust model — membership-gated relays, signed authorship (G6).** The
  relaying sender must be a group member; each version's author is proven by
  its device signature. Digest member gossip is verified per entry, and
  digests from non-participants are ignored (rule 8). Since the G18 review a
  non-member can't make itself a participant (invites assign the slot), a
  removal sticks, plaintext to-device events are dropped, and invalid
  content is refused. Since the second G18 review a participant's
  `matrix_id` must be a valid MXID (`local:self` / garbage refused as
  `invalid_record`; replication targets are filtered too) and a record id
  of another group is refused (gate, CSV import, DAO). Residual risks above.
- **Background gate (G18 review).** A background round never treats a
  registered app as stale: an app that doesn't answer is assumed busy and the
  round is skipped. The app releases its slot when its engine detaches; if it
  dies without that (crash), rounds stay skipped until the process restarts —
  the safe side. Conversely the app waits for a running round (showing
  "Finishing background sync…") and only proceeds after `maxWait` (2 min) if
  a round answers but never finishes (logged). (G18 review 2) A stopped round
  closes its own HTTP client first (aborts the requests in flight — they may
  take up to 90 s), so no late `/sync` result lands in closed stores.
- **Wall-clock LWW.** Merges are whole-record last-writer-wins on `updated_at`
  (ms epoch), ties broken by the content hash (G27 — deterministic, but not
  "fair": the higher hash wins, whoever wrote it). Inbound `updated_at` is
  clamped to `now + 5 min` so a skewed/hostile future clock can't win every
  merge forever; within that window a later honest clock still wins.
- **Message size.** One to-device message carries ≤ 64 KiB encrypted;
  bootstraps are chunked and large digests bucketed (G14 above).
- **Port boundary.** Sync/transport goes through `LedgerTransport`
  (`MatrixLedgerTransport`), auth through `AuthGateway` (`MatrixAuthGateway`), and
  device verification through `DeviceGateway` (`MatrixDeviceGateway`). The only
  direct `package:matrix` usage in app code is `matrixClientProvider` and those
  three adapters — every port has an in-memory fake, so multi-user/login/device
  flows are exercised fully offline.

---

## Resolved

- **G38 / G18 release pass** (2026-10-16): app id
  `io.github.leostumpf.moneyledger`, test devices reset and test groups
  recreated (no pre-G6 rows left); G37 refused-version cost assessed and
  documented (above); release notes in [`release-notes.md`](release-notes.md).
- **Smaller items** (G10 / G17 / G25 / G18 review 2): group rename +
  currency edit, participant avatars, the real `routerProvider`
  refresh/redirect wiring is tested (`test/core/router_provider_test.dart`),
  suggested payments / payment rows (`NamesLine`) wrap onto two lines.
- **2026-10-15 audit** (G1 / G3 / G4 / G8 / G9): release INTERNET
  permission, upload-key signing, per-account ledger DBs, settlements list +
  undo, leave / delete group.
- **Offline demo mode** (G15): `--dart-define=OFFLINE_DEMO=true` runs the real
  UI on seeded fakes (screenshots, quick checks).
- **G18 second review** (2026-10-16): a crafted backup can no longer make
  this device sign forged versions (only truly local groups of a local
  backup / rows local mode wrote are signed; unsigned restored rows keep no
  foreign origin); "Connect a Matrix account" adopts late sign-ins and signs
  out a session that lands after a cancel; inbound `matrix_id` validated;
  refusal set per record (schema v10, digest `rejected_more`); record ids
  bound to their group; the engine leaves adopted rows to the adoption; the
  background round aborts in-flight requests before closing its stores;
  `NamesLine` wraps onto two lines.
- **G36+ follow-ups** (2026-10-16): localized SAS emoji names; verified-only
  wording; sync-loop request timeout + watchdog; fast ack (writer pending
  ~10 s → ~6 s); single-flight login/registration (late success adopted, no
  parallel `client.login`); deduped resync answers; debug-only one-off
  background round; NamesLine on the balance page; digest hash cached in
  the DB (Pixel 537 → 174 ms per 5k-record digest); adopted legacy DB
  deleted.

- **G22 — dependency upgrades** (2026-10-16): matrix 7.2.2 → 14.0.0
  (flutter_vodozemac 0.6 → 0.8.1, vodozemac Rust 0.9 → 0.10, `web/pkg` wasm
  rebuilt), drift 2.31 → 2.35 / sqlite3 2 → 3 (sqlite3_flutter_libs dropped,
  web sqlite3.wasm + drift_worker.js refreshed), file_picker 8 → 13 (web save
  built in; compileSdk-36 gradle override removed), riverpod 3.4 / go_router 18
  / app_links 7 / package_info_plus 10, CI `actions/checkout@v7`. No app-code
  changes for the SDK; existing installs kept their session. Found + fixed on
  device: CSV import failed ("Ref … disposed") — `CsvImporter` is keepAlive now.

- **G14 + G27 — message size + LWW tie-break** (2026-10-16): measured the
  to-device ceiling; chunked bootstraps (were broken above ~52 records),
  hash-bucketed digests (above ~720), a size guard in the transport; equal
  `updated_at` now resolves by content hash in every upsert and digest.

- **Phase F — public-release hardening** (2026-06-14): membership-gated inbound
  records + clock clamp; `SyncHealth` failure surfacing + retry; auth edge cases
  (re-login after logout, external remote logout); in-app registration; first-run
  onboarding; device-verification (SAS) UX.
- **Phase E — custom splits** (2026-06-13): `SplitEditor` four modes; pure
  largest-remainder `split_calculator`; cents-only persistence. Fixed a latent
  equal-split cent loss.
- **Phase D — CSV export/import** (2026-06-13): human-readable per-group CSV,
  idempotent LWW merge-by-id. _Limitation:_ settlements/tombstones aren't in the
  sheet and identity is by display name.
- **Virtual users** (2026-06-13): participant identity decoupled from the Matrix
  account; local participants, claim/unclaim, self-claim on join. Removed members
  resolve to their display name, not raw MXIDs.
- **Phase C — sync reliability + edit/delete** (2026-06-13): digest anti-entropy;
  per-record LWW + tombstones; edit/delete; new-device/reinstall recovery;
  sync-status UI.
- **Phase B — roomless + E2EE**: dropped ledger rooms; encrypted to-device relay;
  homeserver retains no ledger data.
- **Multi-currency balances** (2026-06-03): per-currency partitioning in
  `calculateDebts`; settlements clear debt only in their own currency.
- **SSO** (2026-06-03): native browser launch + deep-link callback; pure
  URL/callback builders (`sso_url.dart`, `sso_callback.dart`). _Caveat:_ native
  round trip is device-smoke only.
- **Widget-test + tooling cleanup** (2026-06-03): page widget tests; pure
  `buildSsoRedirectUrl`; removed dead `matrix_service` extensions; silenced the
  Drift multiple-databases test warning.
