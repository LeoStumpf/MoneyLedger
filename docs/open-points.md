# MoneyLedger — Open Points

Known gaps, risks, and durable design limitations. Resolved work is summarised at
the bottom; the architecture itself is documented in [`CLAUDE.md`](../CLAUDE.md).
Last reviewed: 2026-10-15. **The prioritised, actionable list (major/minor)
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
  future item (with G11).
- **Malicious inviter.** A new member trusts the inviter's bootstrap
  (TOFU, as before) including its `device_keys` attestations, so the inviter
  could vouch for fake keys ("vouched" in the details).
- **Homeserver.** A user's homeserver can add devices for that user (the
  Matrix E2EE trust model; G11 / SAS verification).
- **Divergence by disagreement.** An honest device that accepted a version as
  "unverified" and one that refused it (key conflict) keep different
  versions; the digest `rejected` map stops the repair loop and the refusing
  side shows a notice on the record.
- **Grandfathered rows.** Rows from before G6 stay local legacy/unsigned;
  peers refuse them when relayed, so they can't be bootstrapped to new
  members/devices (re-edit to sign). Unsigned member / meta rows of an old
  group likewise; group meta of such a group must be re-saved (edit) before a
  new member can be bootstrapped.
- **Size.** Signatures roughly double a record's wire size — tighter single
  message bootstrap ceiling (G14).
- Same-clock different versions (two signed versions with one `updated_at`):
  first stored wins (G27 tie-break still open).

### Device-verification enforcement
SAS (emoji) verification exists for **visibility + manual** trust only
(`DevicesPage`). Replication still reaches unverified devices. An opt-in
"replicate only to verified devices" mode was deliberately left out of the MVP
(it can strand legitimate unverified sessions).

### Offline demo mode (`OFFLINE_DEMO`) — nice-to-have
A `--dart-define=OFFLINE_DEMO=true` that overrides `ledgerTransportProvider` +
`authGatewayProvider` with pre-seeded fakes would let the **real UI** run with no
homeserver — useful for screenshots and manual multi-user inspection. The fakes
already exist for tests.

### Real-device smoke tests
Three flows can only be verified on a real device + homeserver, not in
`flutter test` or the web build — worth a manual pass before relying on them:
- **SSO** native deep link (`moneyledger://sso-callback`).
- **Registration** UIA on a real homeserver (dummy path + the captcha/email/terms
  fallback).
- **SAS device verification** round-trip (needs a second device + olm).

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
  (ms epoch). Inbound `updated_at` is clamped to `now + 5 min` so a skewed/hostile
  future clock can't win every merge forever; within that window a later honest
  clock still wins.
- **Digest ceiling.** A digest is O(records in group) — fine to ~1,000
  records/group under to-device size limits. The `"v"` protocol-version field on
  every payload enables sharding later.
- **Port boundary.** Sync/transport goes through `LedgerTransport`
  (`MatrixLedgerTransport`), auth through `AuthGateway` (`MatrixAuthGateway`), and
  device verification through `DeviceGateway` (`MatrixDeviceGateway`). The only
  direct `package:matrix` usage in app code is `matrixClientProvider` and those
  three adapters — every port has an in-memory fake, so multi-user/login/device
  flows are exercised fully offline.

---

## Resolved

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
