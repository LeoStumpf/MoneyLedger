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
  re-sign step**; **before the release the test groups get recreated**.
  The receiving side is told instead of silently showing a half-empty or
  missing group: a `[g6] refused unsigned …` log line and a dismissible
  groups-page hint ("Some data couldn't be received … ask X to recreate the
  group", `SyncHealthState.legacyRefusals`, session-only). A user's own
  backup still restores them as legacy (G5).
- **Size.** Signatures roughly double a record's wire size (~0.86 KB per
  record in a bootstrap) — handled by chunked bootstraps (G14, below).
- **Refusals are per version, one row per record (G18 review).** A refusal
  blocks exactly the refused version (clock + hash). Only the highest refused
  version per record is remembered — a peer still holding an *older* refused
  version re-offers it each digest cycle (re-verified and refused again; one
  message per cycle, not a tight loop).

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
- A refused version (G6) keeps its bucket's hash different, so each cycle
  costs one extra three-message detail exchange for that bucket (bounded;
  still counts as in sync).
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

### Offline demo mode (`OFFLINE_DEMO`) — nice-to-have
A `--dart-define=OFFLINE_DEMO=true` that overrides `ledgerTransportProvider` +
`authGatewayProvider` with pre-seeded fakes would let the **real UI** run with no
homeserver — useful for screenshots and manual multi-user inspection. The fakes
already exist for tests.

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
- **Category set is fixed** (10 ids); an unknown id from a newer peer is kept
  verbatim and shown as "Other". No per-group custom categories, no
  category statistics yet.
- **Archive is device-local** (not synced to your other devices) and only
  ledger activity (expenses / payments incl. deletions) un-archives; member
  or group-name changes don't. A same-millisecond LWW tie-break version
  (G27) doesn't change the fingerprint (practically irrelevant).

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

### Real-device smoke tests
Three flows can only be verified on a real device + homeserver, not in
`flutter test` or the web build — worth a manual pass before relying on them:
- **SSO** native deep link (`moneyledger://sso-callback`).
- **Registration** UIA on a real homeserver (dummy path + the captcha/email/terms
  fallback).
- **SAS device verification** round-trip — done app↔app on 2026-10-16
  (G11); against Element not tried.

### Found in the 2026-10-15 audit (see plan.md)
- **Android release build has no INTERNET permission** (only debug/profile
  manifests have it) — release APK can't reach a homeserver. (G1)
- **Release signing uses the debug key.** (G3)
- **Local ledger is shared across accounts** on one device: the Drift DB is
  global and logout doesn't touch it. (G4)
- **Settlements can't be listed or undone** — `deleteSettlement` has no UI caller. (G8)
- **No delete/leave group** — `GroupsDao.deleteGroup` is unused. (G9)

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
- A **backup made in local mode** restored into a Matrix account keeps its
  rows unsigned (restored as legacy, G35 — peers refuse them if relayed) and
  the user's participant stays claimed by `local:self` (not offered by the
  "Which participant are you?" picker). The supported path is *Connect a
  Matrix account* (adoption signs and re-claims). A restore that applies the
  same adoption transform would fix it.
- The adoption waits up to 30 s for the new device's signing key; if it isn't
  ready, the sync engine signs the rows later — records edited in local mode
  then have no creation statement ("added by" missing; they still verify).
- A pending adoption (`local_adopt_into`) only runs when *that* account is
  signed in; signing out before it ran and using another account leaves the
  local ledger waiting for the first one (it is never lost, just not shown).
- `vod.init()` still runs at every start, also in local mode (cheap; needed
  as soon as an account is connected).
- Existing installs: the device-wide `welcome_seen` flag starts unset, so a
  user who signs out after the update sees the welcome once.
- The local DB file stays on disk (empty) after *Delete local data* / an
  adoption — rows are wiped, the file is reused by the next local profile.

### Smaller items
- Balance page suggested payments are one line (G33 `NamesLine`): on a phone
  a long MXID-localpart name shrinks to a few characters ("mone… zahlt an
  dich") — readable with display names; the avatars show who it is.
- The `router` provider's `refreshListenable`/redirect wiring (against
  `isLoggedInProvider` + `onboardingSeenProvider`) is untested; `routerRedirect`
  (pure) is well covered.
- Group rename + currency edit; participant avatars.

---

## Architecture limitations (reference)

Durable constraints of the current design — not bugs, but worth knowing.

- **Trust model — membership-gated relays, signed authorship (G6).** The
  relaying sender must be a group member; each version's author is proven by
  its device signature. Digest member gossip is verified per entry, and
  digests from non-participants are ignored (rule 8). Since the G18 review a
  non-member can't make itself a participant (invites assign the slot), a
  removal sticks, plaintext to-device events are dropped, and invalid
  content is refused. Residual risks above.
- **Background gate (G18 review).** A background round never treats a
  registered app as stale: an app that doesn't answer is assumed busy and the
  round is skipped. The app releases its slot when its engine detaches; if it
  dies without that (crash), rounds stay skipped until the process restarts —
  the safe side. Conversely the app waits for a running round (showing
  "Finishing background sync…") and only proceeds after `maxWait` (2 min) if
  a round answers but never finishes (logged).
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
