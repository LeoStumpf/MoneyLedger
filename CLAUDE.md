# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git workflow

Single-developer project — **commit directly to `main`** (the default branch). Do
not create feature branches or open PRs unless explicitly asked; just commit to
`main` and push. Still only commit/push when the user asks.

## Project Overview

MoneyLedger is a decentralized expense-sharing app (Splitwise/Tricount alternative) with no central server. The Matrix network is used as the sync and transport layer: users authenticate with their Matrix ID, groups are Matrix rooms, and expenses are custom Matrix timeline events. All ledger data is stored locally on each device.

## Tech Stack

- **Flutter 3.44+** — cross-platform UI (Android, iOS, web)
- [`matrix`](https://pub.dev/packages/matrix) 7.x — Matrix protocol: auth, room management, event sync
- [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod) 3.x + `riverpod_annotation` 4.x — state management (code-gen style)
- [`drift`](https://pub.dev/packages/drift) 2.x + `drift_flutter` — type-safe SQLite ORM for local ledger state
- [`go_router`](https://pub.dev/packages/go_router) — navigation
- [`uuid`](https://pub.dev/packages/uuid) — UUIDv7 generation for expense IDs
- [`sqflite`](https://pub.dev/packages/sqflite) — required by the matrix SDK's internal SQLite store

## Building

```bash
./build.sh          # codegen → tests → web release build (one-liner)
```

The script runs in order: `flutter pub get` → `dart run build_runner build` → `flutter test` → `flutter build web --release`. It exits non-zero on the first failure, so a green run means codegen, all tests, and the release build all passed.

To override the Flutter binary: `FLUTTER=/path/to/flutter ./build.sh`

Output lands in `build/web/`.

## Commands

```bash
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0   # dev web server
flutter run -d android               # run on a connected Android device/emulator
flutter run -d ios                   # run on iOS simulator/device (macOS only)
flutter devices                      # list available run targets
flutter test --reporter compact      # run all tests (exit 0 = green)
flutter test test/foo_test.dart      # run a single test file
flutter build apk                    # Android release build
flutter build ios                    # iOS release build
flutter build web                    # web build
dart run build_runner build          # regenerate Drift + Riverpod code-gen files
dart run build_runner watch          # watch mode for code generation
```

On a fresh clone, run `flutter pub get && dart run build_runner build` before anything else. After any change to a file annotated with `@riverpod`, `@DriftDatabase`, or `@DriftAccessor`, regenerate with `dart run build_runner build`.

**Always run `flutter test --reporter compact` before committing.** Write tests alongside every feature or bug fix — do not defer coverage. Tests run fully offline against in-memory fakes (`test/helpers/fake_ledger_network.dart`, `test/helpers/fake_auth_gateway.dart`) — no real homeserver or network.

User-facing build/run/test instructions also live in [`README.md`](README.md); keep the two in sync when changing commands.

## Project Structure

```
lib/
  main.dart          # entry point — ProviderScope(App)
  app.dart           # MaterialApp.router
  core/
    router.dart      # go_router + routerRedirect() pure function (generated: router.g.dart)
    database/
      app_database.dart        # Drift DB + table definitions (AppDatabase.forTesting() for tests)
      daos/
        expenses_dao.dart      # Expenses + Settlements queries (LWW upserts, tombstone-aware)
        groups_dao.dart        # Groups table queries → GroupModel (LWW upsert)
        members_dao.dart       # Members (MXID + active/removed status, LWW upsert)
        sync_states_dao.dart   # PeerSyncStates: per-(group,peer) anti-entropy bookkeeping
    matrix/
      ledger_transport.dart       # LedgerTransport port + TransportMessage + event-type constants
      matrix_ledger_transport.dart # Real adapter — encrypted to-device send/receive
    sync/
      ledger_payloads.dart     # Plain-Dart payload codec (protocol v1) + bootstrap builder
      sync_engine.dart         # Anti-entropy: digest exchange + targeted repair + resync
      sync_status_provider.dart # groupSyncStatusProvider — drives the cloud icons
  models/
    expense_model.dart         # Plain Dart models (ExpenseModel, SettlementModel)
    group_model.dart           # Plain Dart model (GroupModel)
    member_model.dart          # MemberModel; sync_state_model.dart (PeerSyncStateModel)
  features/
    auth/                      # Matrix login, session management
    groups/                    # Group list + create (local-only groups, member add/remove)
    expenses/                  # Expense list, add/edit/delete, ledger sync
      ledger_syncer.dart       # LedgerSyncer: subscribes to to-device onMessage → writes to Drift
                               # Static @visibleForTesting methods for unit-testable event processing
    balance/
      balance_calculator.dart  # Pure function: List<Expense> + settlements → List<DebtEntry>
      balance_provider.dart    # Riverpod: watches Drift streams, recomputes on change
test/
  flutter_test_config.dart     # Loads bundled sqlite3 FFI before every test file
  helpers/
    test_providers.dart        # Riverpod override helpers for widget tests
    in_memory_database.dart    # AppDatabase.forTesting(NativeDatabase.memory())
  core/
    router_redirect_test.dart  # Unit tests for routerRedirect()
  database/
    groups_dao_test.dart       # GroupsDao upsert/watch/delete
    expenses_dao_test.dart     # ExpensesDao upsert/watch, room isolation
  features/
    ledger_syncer_test.dart    # processExpense/Settlement/GroupState static methods
    group_provider_test.dart   # ledgerGroupsProvider wiring via in-memory Drift
  balance_calculator_test.dart # Unit tests for debt calculation logic
  login_page_test.dart         # Widget tests for LoginPage
  balance_page_test.dart       # Widget tests for BalancePage
  expenses_page_test.dart      # Widget tests for ExpensesPage
  groups_page_test.dart        # Widget tests for GroupsPage
web/
  sqlite3.wasm                 # Required by Drift for web SQLite (do not delete)
  drift_worker.js              # Required by Drift for web SQLite (do not delete)
```

## Architecture

### Roomless local-first design (Phase B/C — current)

**There are no ledger rooms.** Groups, members, expenses, and settlements live
**only in local Drift** on each device. Matrix is used purely as an **encrypted
to-device relay** (E2EE, vodozemac): records are sent as encrypted to-device
messages to each member's MXID; the homeserver retains **no ledger data** and
sees only ciphertext. (Earlier docs/commits describe a room-based design — that
is obsolete.)

| Concept | MoneyLedger (roomless) |
|---------|------------------------|
| Expense group | Local Drift row (`Groups`), UUIDv7 id; **not** a Matrix room |
| Group participants | `Members` rows (MXID + `active`/`removed` status, LWW) |
| Expense / settlement | `Expenses` / `Settlements` rows (LWW clock + tombstone) |
| Sync / transport | Encrypted **to-device** messages via `LedgerTransport` |
| Replication log | The Drift DB itself — digests drive anti-entropy |

Authentication is pure Matrix — no separate auth system. Users connect to their own homeserver (self-hosted, matrix.org, etc.). The single transport seam is `LedgerTransport` (real adapter `MatrixLedgerTransport`); fakes back all tests.

### Data Flow

Inbound to-device message → `LedgerSyncer._onMessage` → DAO LWW upsert → Drift
stream providers → UI rebuild. Local writes are **local-first**: persisted to
Drift immediately, then best-effort replicated to members (`_replicate`). Drift
is the **local source of truth** — the UI always reads Drift streams, never
Matrix in-memory state.

### Anti-entropy (Phase C)

Replication is **not** fire-and-forget. `SyncEngine`
(`lib/core/sync/sync_engine.dart`) makes peers periodically exchange per-group
**digests** (`{recordId: updatedAt}` maps, tombstones included). Comparing a
digest tells each side exactly which records to re-send, so a lost to-device
message, a new device, or a reinstall is **repaired** by the next digest cycle
instead of diverging forever. Every record carries an `updatedAt` LWW clock and
a `deleted` tombstone flag; all merges are last-writer-wins. Edit = full
re-send with a higher `updatedAt`; delete = a permanent tombstone. New-device
recovery: an empty DB sends `resync_request{scope: all}` to the user's own MXID
(another of their devices answers with bootstraps); an unknown group named in a
peer's digest triggers organic bootstrap. Sync status (`cloud_done`/
`cloud_queue` icons) is derived from `PeerSyncStates.lastInSyncAt`
(`lib/core/sync/sync_status_provider.dart`). Full design: `plan.md`.

### Key Implementation Notes

**Riverpod provider naming (3.x):** Class `AuthNotifier` → provider `authProvider` (not `authNotifierProvider`). The "Notifier" suffix is stripped. Class `ExpenseAdder` → `expenseAdderProvider`.

**Drift + Riverpod code-gen conflict:** Drift generates data classes (`Expense`, `Settlement`, `Group`) in part files. Riverpod's generator can't reference those types as provider return types in the same build phase. Solution: use plain model classes (`ExpenseModel`, `SettlementModel`, `GroupModel` in `lib/models/`) as the DAO layer's public API, and map from Drift types internally. **Never use Drift-generated data classes as return types of `@riverpod` providers.**

**`drift` + `matrix` SQLite compatibility:** Use `drift ^2.31` and `drift_flutter ^0.2.8` — these depend on `sqlite3 ^2.x` which aligns with the matrix SDK's requirement. Avoid upgrading drift to 2.32+ without checking; that version switches to `sqlite3 ^3.x` which conflicts with matrix and breaks test compilation.

**Drift web setup:** `_openConnection()` passes `DriftWebOptions(sqlite3Wasm: Uri.parse('sqlite3.wasm'), driftWorker: Uri.parse('drift_worker.js'))` when `kIsWeb`. The two files in `web/` must not be deleted — they are not generated by the build and are not in `.gitignore`.

**Router pattern:** `routerProvider` is `keepAlive: true` and uses `refreshListenable` (a `ValueNotifier`) to rerun the redirect when `isLoggedInProvider` changes. Do **not** make it non-keepAlive — that recreates the `GoRouter` on every auth state change, which crashes at the default initial location `/`.

**Testing without Matrix imports:** The `matrix` SDK pulls in native sqlite3 which can cause issues in test processes. Keep test files free of `package:matrix` imports. Extract testable logic from classes that use Matrix types as `@visibleForTesting` static methods that accept plain Dart types (maps, strings, ints). See `LedgerSyncer.processExpense` for the pattern.

**Matrix SDK (7.x) API:**
- `Client(name, database: db)` — database is required in constructor (not a builder callback)
- `MatrixSdkDatabase.init(name, database: openedDb, sqfliteFactory: databaseFactory)` — on **native you MUST pass an already-opened sqflite `Database`** via `database:` (open it with `sqflite.openDatabase(path)` first). `sqfliteFactory` alone is **not** enough: `BoxCollection` throws `You must provide a Database 'sqfliteDatabase' for use on native` (the factory is only used for high-level ops like delete). On web, call `MatrixSdkDatabase.init(name)` with no DB (it uses IndexedDB). See `buildMatrixClient()` in `lib/core/matrix/matrix_service.dart`.
- `client.init(waitForFirstSync: false)` — **always pass `false`.** The default `true` makes `init()` block on the first network `/sync` when a session is restored, which hangs app startup indefinitely on a stalled sync. Drift is the local source of truth; sync runs in the background.
- **Roomless to-device** is the only transport (no rooms). See `MatrixLedgerTransport` (`lib/core/matrix/matrix_ledger_transport.dart`):
  - `client.onToDeviceEvent.stream` — inbound encrypted to-device events; filter by the `com.moneyledger.*` type prefix.
  - `client.updateUserDeviceKeys(additionalUsers: targets)` before each send — roomless device lists aren't persisted (the SDK evicts device keys for users you share no encrypted room with), so re-resolve every time (cheap, idempotent).
  - `client.sendToDeviceEncryptedChunked(devices, type, content)` — encrypts + sends to every target device; your own current device is auto-excluded, and other devices of the sender **do** receive (the fake relay mirrors this).

### Data Model & wire protocol (v1)

Expenses and settlements use **UUIDv7** IDs. All amounts are **integer cents** to avoid float errors. Every to-device payload carries `"v": 1` (protocol version — enables sharding/migration later) and a `"group": "<groupId>"`. Record payloads carry a `created_at`, an `updated_at` LWW clock (ms epoch), and a `deleted` tombstone flag. Receivers apply **whole-record LWW** on `updated_at`. The codec lives in `lib/core/sync/ledger_payloads.dart`; event type constants in `lib/core/matrix/ledger_transport.dart`.

**`com.moneyledger.expense`** (settlement analogous). Edit = full re-send with a higher `updated_at`; delete = same with `deleted: true`:
```json
{
  "v": 1,
  "id": "<uuidv7>",
  "group": "<groupId>",
  "description": "Dinner",
  "amount": 4200,
  "currency": "EUR",
  "paid_by": "@alice:matrix.org",
  "split": { "@alice:matrix.org": 2100, "@bob:matrix.org": 2100 },
  "created_at": 1760000000000,
  "updated_at": 1760000050000,
  "deleted": false
}
```

**`com.moneyledger.settlement`** content: `{ "v", "id", "group", "amount", "currency", "from", "to", "created_at", "updated_at", "deleted" }`.

**`com.moneyledger.digest`** (anti-entropy) — sent per group to all active members *including self*. Maps are `id → updated_at`, **tombstones included**; the `members` map doubles as membership gossip. A `reply: false` digest is answered once with `reply: true` (bounded two-message exchange):
```json
{
  "v": 1,
  "group": "<groupId>",
  "reply": false,
  "meta_updated_at": 1760000000000,
  "members": { "@alice:x.org": {"status": "active", "updated_at": 1759990000000} },
  "expenses":    { "<uuid>": 1760000050000 },
  "settlements": { "<uuid>": 1759995000000 }
}
```

**`com.moneyledger.resync_request`** — `{ "v": 1, "scope": "group", "group": "<groupId>" }` or `{ "v": 1, "scope": "all" }`. Handler replies with `bootstrap` payload(s) only if the requester is an active member of that group, or is the responder's own MXID (`scope: all` honored only for self — new-device recovery).

**`com.moneyledger.bootstrap`** — whole-group snapshot (group meta + members + expenses + settlements), each record with `updated_at`/`deleted`, **tombstones included** (so a stale device can't keep a live copy of a deleted record). Sent when adding a member and in response to a `resync_request`.

The receiver rules for digests (targeted repair, membership gossip, reply bounding, sync-status marking, unknown-group/removed-sender handling) are documented in full on `SyncEngine` (`lib/core/sync/sync_engine.dart`) and in `plan.md` §3.1.
