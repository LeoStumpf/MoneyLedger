# MoneyLedger — Open Points

A living overview of known gaps, risks, and unfinished work. Grouped by category
and roughly ordered by priority within each. Last reviewed: 2026-06-13.

---

## Correctness / bugs

### 1. Balances ignore currency (multi-currency groups are wrong) — ✅ RESOLVED
`calculateDebts` now partitions expenses + settlements by `currency` and runs the
greedy simplification independently per currency; each `DebtEntry` carries its
`currency`, and `BalancePage` displays/settles per-debt currency. Covered by new
tests in `test/balance_calculator_test.dart` (mixed currencies not summed; a
settlement only clears debt in its own currency). _Done 2026-06-03._

### 2. Historical expenses may be incomplete after joining — ✅ RESOLVED (then superseded)
_Original (room era):_ the transport exposed `loadHistory(roomId)` and
`LedgerSyncer._reconcileTimeline` paged back through the room timeline before
replay. **Obsolete since Phase B/C:** there are no rooms or timelines to page —
groups live only in local Drift and replication is the digest-based
anti-entropy engine (`lib/core/sync/sync_engine.dart`). Backfill after joining
is now a `bootstrap` payload on add, and any gap is repaired by the periodic
digest cycle (`test/integration/anti_entropy_test.dart`,
`test/integration/multi_device_test.dart`). _Stale; left for history._

### 3. SSO on native platforms doesn't actually launch — ✅ RESOLVED (needs device verification)
Native now opens the system browser via `url_launcher` (`launchExternalUrl`) and
receives the `moneyledger://sso-callback` deep link via `app_links`
(`incomingSsoLinks` → `ssoCallbackProvider`), exchanging the token through the
same path as web. Added the Android intent-filter + `<queries>` and iOS
`CFBundleURLTypes` + `LSApplicationQueriesSchemes`. Token/homeserver parsing is a
pure function (`sso_callback.dart`) with unit tests. _Done 2026-06-03._
- **Caveat:** the end-to-end deep-link round trip can only be verified on a real
  device/emulator — not in `flutter test` or the web build. Worth a manual smoke
  test on Android + iOS before relying on it.

---

## Tech debt / cleanup

### 4. Dead code in `matrix_service.dart` — ✅ RESOLVED
Removed the unused `Client` extension members `groupCurrency`, `ssoRedirectUri`,
`isLoggedIn`, and `ledgerGroups`. The extension now holds only what the transport
adapter uses (`createLedgerGroup`, `sendExpenseEvent`, `sendSettlementEvent`,
`loadRoomHistory`). _Done 2026-06-03._

### 5. SSO URL building still lives in the UI — ✅ RESOLVED
Extracted the redirect-URL assembly into the pure `buildSsoRedirectUrl`
(`sso_url.dart`), now unit-tested (`test/features/sso_url_test.dart`).
`LoginPage._startSso` only computes the platform-specific callback base and calls
it. _Done 2026-06-03._

### 6. Drift "multiple databases" warning in tests — ✅ RESOLVED
`test/flutter_test_config.dart` now sets
`driftRuntimeOptions.dontWarnAboutMultipleDatabases = true`. _Done 2026-06-03._

---

## Features (planned / unfinished)

### 7. Virtual users (Tricount-style local participants) — ✅ DONE (2026-06-13)
A participant is now a stable per-group entity with a `displayName` and an
**optional** `matrixId` (the "claim"); records reference the participant id, not
the MXID. You can add a local person (name, no account), link/detach a Matrix
account at any time (history is kept), and rename. Routing targets only claimed
participants. An invited account can **self-claim** an existing participant on
its own device (invite → pick who you are → link), so no duplicate is created.
Design + milestones (M1–M6) in `plan.md`; covered by `members_dao_test`,
`group_provider_test`, `group_members_page_test`, the add-expense payer test,
and `integration/self_claim_on_join_test`. See also the trust-model limitation
under Phase C (inbound records, incl. claims, are unauthenticated — release
hardening).

### 8. Removed members show as raw MXIDs — ✅ RESOLVED (with #7)
Balances and history resolve participant ids through `participantNames`
(`group_provider.dart`), which is built from the full members stream (removed
included), so a removed or detached participant still renders by their display
name. Covered by a `group_provider_test` case.

### 9. Offline demo runnable mode (`OFFLINE_DEMO`) — nice-to-have
The fakes (`FakeLedgerNetwork`, `FakeAuthGateway`) exist for tests. A
`--dart-define=OFFLINE_DEMO=true` that overrides `ledgerTransportProvider` +
`authGatewayProvider` with pre-seeded fakes would let the **real UI** be driven
with no homeserver — useful for manual multi-user inspection and screenshots.

---

## Auth / session

### 10. Re-login after logout on the same client is untested — MEDIUM
`logout()` no longer rebuilds the Matrix client (the old
`invalidate(matrixClientProvider)` was dropped in favour of gateway-driven
`loginState`). Logging in again reuses the same `Client` instance. This path
isn't covered by a test and should be verified against a real homeserver, or the
gateway should rebuild/clear the client on logout.

### 11. External login-state changes are surfaced but unproven — LOW
`AuthGateway.loginStateChanges` (from `client.onLoginStateChanged`) feeds
`loginStateProvider`, so token expiry / remote logout *should* propagate to the
router. Not exercised by a test.

---

## Security

### 12. Rooms are unencrypted — ✅ OBSOLETE (roomless + E2EE since Phase B)
This described the old room-based design. **No longer applies:** there are no
ledger rooms. Groups are local-only and replication goes over **encrypted
to-device** messages (E2EE enabled, vodozemac) — the homeserver retains no
ledger data and sees only ciphertext. See the Phase B commits and the
project memory note on the local-first direction. The remaining security gap is
the trust model, not transport encryption — see _Known limitations_ below.

---

## Testing gaps

### 13. No widget tests for several pages — ✅ RESOLVED
Added widget tests for `AddExpensePage`, `GroupMembersPage`, and
`CreateGroupPage`, driven by `FakeMatrixNetwork` (members, currency, submit/kick).
A `testRouterApp` harness gives pages that `context.pop()` somewhere to return to.
Note: `CreateGroupPage`'s submit writes to a real in-memory Drift DB, which only
completes on the real event loop — so that interaction runs under
`tester.runAsync` (the fake test clock won't drive Drift). _Done 2026-06-03._

### 14. No multi-currency balance test — ✅ RESOLVED (with #1)
Added mixed-currency and per-currency-settlement tests to
`test/balance_calculator_test.dart`.

### 15. Router provider wiring is only partially tested — LOW
`routerRedirect` (pure) is well covered; the `router` provider's
`refreshListenable`/redirect wiring against `isLoggedInProvider` is not.

---

## Phase C — sync reliability + expense edit/delete — ✅ DONE (2026-06-13)

Record-digest anti-entropy plus editable/deletable expenses landed across
milestones M1–M7 (see `plan.md`):

- **Anti-entropy engine** (`lib/core/sync/sync_engine.dart`): peers periodically
  exchange per-group **digests** (`{recordId: updatedAt}`, tombstones included)
  and re-send exactly the records the other side lacks. The Drift DB is the
  replication log — no sequence numbers, no outbox. A lost to-device message,
  a new device, or a reinstall is repaired by the next digest cycle instead of
  diverging forever.
- **Per-record LWW + tombstones**: every record carries an `updatedAt` clock and
  a `deleted` flag; all merges are last-writer-wins (`upsert*Lww`). Edit = full
  re-send with a higher `updatedAt`; delete = a permanent tombstone that
  propagates so a stale peer can never resurrect it.
- **Edit/delete** of expenses (and delete of settlements) in the data layer,
  replication, and UI (`add_expense_page.dart` prefill, `expenses_page.dart`
  tap-to-edit + delete confirmation).
- **New-device / reinstall recovery**: empty DB → `resync_request{scope: all}`
  to the user's own MXID (answered by another of their devices); a peer's digest
  naming an unknown group triggers organic bootstrap.
- **Sync-status UI** (`lib/core/sync/sync_status_provider.dart`): app-bar
  `cloud_done`/`cloud_queue` and per-tile pending indicators driven by
  `PeerSyncStates.lastInSyncAt`.
- ~2,100→2,600 lines of tests incl. `test/integration/{anti_entropy,
  edit_delete_convergence,multi_device}_test.dart` with message-loss injection.

### Known limitations (carried into release hardening)

- **Trust model unchanged** — any sender can forge state. Inbound records are
  applied LWW with no membership/authorship check (TOFU); only `resync_request`
  is gated by a membership check. Fix deferred to public-release hardening.
- **Digest ceiling** — a digest is O(records in group); fine to ~1,000
  records/group under to-device size limits. The `"v"` protocol-version field on
  every payload enables sharding later.
- **Wall-clock LWW** — a skewed clock can win edits; merge granularity is the
  whole record. Consistent with the existing Members LWW; optional future clamp
  of inbound `updated_at` to `now + 5 min`.

---

## Architecture status (for context)

The port migration is essentially complete:
- **Sync/transport** goes through `LedgerTransport` (`ledger_transport.dart`); the
  real adapter is `MatrixLedgerTransport`. All pages/providers use it.
- **Auth** goes through `AuthGateway` (`auth_gateway.dart`); real adapter
  `MatrixAuthGateway`.
- The only remaining direct `package:matrix` usage in app code is
  `matrixClientProvider` (builds/inits the client) and the two adapters — exactly
  the intended boundary. `package:matrix` no longer appears in any page or
  feature provider.
- Fakes exist for both ports, enabling offline multi-user + login tests.

Suggested next focus (post virtual users): the **self-claim-on-join handshake**
(plan M6), then Phase D (CSV export/import), custom splits, and public-release
hardening (membership check on inbound records, onboarding,
device-verification UX). Smaller items: #15, auth edge cases #10/#11, #9 offline
demo mode.
Resolved / superseded: #1, #2 (superseded by Phase C), #3 (needs device smoke
test), #4, #5, #6, #7 (virtual users), #8 (with #7), #12 (obsolete — roomless +
E2EE), #13, #14.
