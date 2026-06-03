# MoneyLedger — Open Points

A living overview of known gaps, risks, and unfinished work. Grouped by category
and roughly ordered by priority within each. Last reviewed: 2026-06-03.

---

## Correctness / bugs

### 1. Balances ignore currency (multi-currency groups are wrong) — ✅ RESOLVED
`calculateDebts` now partitions expenses + settlements by `currency` and runs the
greedy simplification independently per currency; each `DebtEntry` carries its
`currency`, and `BalancePage` displays/settles per-debt currency. Covered by new
tests in `test/balance_calculator_test.dart` (mixed currencies not summed; a
settlement only clears debt in its own currency). _Done 2026-06-03._

### 2. Historical expenses may be incomplete after joining — ✅ RESOLVED
The transport now exposes `loadHistory(roomId)` (real adapter pages back via
`loadRoomHistory`), and `LedgerSyncer._reconcileTimeline` calls it before replay.
Crucially, the syncer now also reconciles a ledger room the **first time it sees
it live** (not only at startup), so a user who joins mid-session backfills the
full pre-join history — tracked per-room in `_reconciled` to avoid re-paging.
Covered by `test/integration/...: 'a second user sees expenses that predate their
join'`. _Done 2026-06-03._

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

### 7. Virtual users (Tricount-style local participants) — planned
Local users (name + optional Matrix ID), claimable when a real user joins;
removing a member should clear only their Matrix ID, keeping their ledger
history. Today member removal is a Matrix `kick` and the UI shows raw MXIDs.
This also improves the post-kick display (#8). See the project memory note.

### 8. Removed members show as raw MXIDs — LOW
After a kick, their historical splits still reference `@user:server`, displayed
verbatim in balances. Virtual users (#7) would give them a stable display name.

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

### 12. Rooms are unencrypted — by design, but note the consequence
`createLedgerGroup` uses the raw `createRoom` with `privateChat`, which does **not**
enable E2EE. Expense/settlement events are plaintext on the homeserver. If
encryption is ever enabled, the syncer/transport must handle decryption and key
sharing (currently `NativeImplementations.dummy`). Decide explicitly whether
ledgers should be E2EE.

---

## Testing gaps

### 13. No widget tests for several pages — MEDIUM
Missing: `AddExpensePage`, `GroupMembersPage`, `CreateGroupPage`. The first two
now use the transport port and could be tested with a `FakeLedgerNetwork`
override (participants, currency, submit).

### 14. No multi-currency balance test — ✅ RESOLVED (with #1)
Added mixed-currency and per-currency-settlement tests to
`test/balance_calculator_test.dart`.

### 15. Router provider wiring is only partially tested — LOW
`routerRedirect` (pure) is well covered; the `router` provider's
`refreshListenable`/redirect wiring against `isLoggedInProvider` is not.

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

Suggested next focus: **#13** (widget tests for the AddExpense / GroupMembers /
CreateGroup pages — now easy with the fake transport), then the remaining
features (#7 virtual users, #9 offline demo mode). Resolved so far: #1, #2, #3
(needs device smoke test), #4, #5, #6, #14.
