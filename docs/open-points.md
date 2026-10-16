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
  could vouch for fake keys ("vouched" in the details).
- **Homeserver.** A user's homeserver can add devices for that user (the
  Matrix E2EE trust model). *Mitigated, opt-in (G11):* with "Only sync with
  verified devices" a device we never emoji-verified gets nothing from us,
  and the record details say "You haven't verified this device".
- **Divergence by disagreement.** An honest device that accepted a version as
  "unverified" and one that refused it (key conflict) keep different
  versions; the digest `rejected` map stops the repair loop and the refusing
  side shows a notice on the record.
- **Grandfathered rows.** Rows from before G6 stay local legacy/unsigned;
  peers refuse them when relayed, so they can't be bootstrapped to new
  members/devices (re-edit to sign). Unsigned member / meta rows of an old
  group likewise; group meta of such a group must be re-saved (edit) before a
  new member can be bootstrapped.
- **Size.** Signatures roughly double a record's wire size (~0.86 KB per
  record in a bootstrap) — handled by chunked bootstraps (G14, below).
- **Refusal granularity is the clock.** A refused version at `T` also blocks
  any other version of that record stamped exactly `T` (G27 compares hashes
  only between versions that pass the gate).

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
- **Hashing cost** — every digest hashes every record (SHA-256 over
  canonical JSON; ~150 ms per 5k records on desktop). Cache per-row hashes
  (a DB column) if phones show it.
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
- SAS emoji names come from the SDK in English (German UI shows "Trumpet").
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

### Smaller items
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
  digests from non-participants are ignored (rule 8). Residual risks above.
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
