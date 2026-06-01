# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
flutter test --reporter compact      # run all tests (exit 0 = green)
flutter test test/foo_test.dart      # run a single test file
flutter build apk                    # Android release build
flutter build ios                    # iOS release build
flutter build web                    # web build
dart run build_runner build          # regenerate Drift + Riverpod code-gen files
dart run build_runner watch          # watch mode for code generation
```

After any change to a file annotated with `@riverpod`, `@DriftDatabase`, or `@DriftAccessor`, regenerate with `dart run build_runner build`.

**Always run `flutter test --reporter compact` before committing.** Write tests alongside every feature or bug fix — do not defer coverage.

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
        expenses_dao.dart      # Expenses + Settlements queries → ExpenseModel/SettlementModel
        groups_dao.dart        # Groups table queries → GroupModel
  models/
    expense_model.dart         # Plain Dart models (ExpenseModel, SettlementModel)
    group_model.dart           # Plain Dart model (GroupModel)
  features/
    auth/                      # Matrix login, session management
    groups/                    # Group list + create (Matrix rooms)
    expenses/                  # Expense list, add expense, ledger sync
      ledger_syncer.dart       # LedgerSyncer: subscribes to Matrix onSync → writes to Drift
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

### Matrix Primitives → App Concepts

| Matrix | MoneyLedger |
|--------|-------------|
| Matrix room (tagged `app.moneyledger.group`) | Expense group |
| Room members | Group participants |
| Custom event `com.moneyledger.expense` | Expense entry |
| Custom event `com.moneyledger.settlement` | Settlement/payment |
| Room state event `app.moneyledger.group` | Group metadata (currency) |
| Local SQLite (Drift) | Computed balances + cached ledger state |

Authentication is pure Matrix — no separate auth system. Users connect to their own homeserver (self-hosted, matrix.org, etc.).

### Data Flow

Matrix sync → `LedgerSyncer.onSync` → Drift upsert → stream providers → UI rebuild.
Drift is the **local source of truth**. The UI never reads directly from Matrix in-memory state — it always reads from Drift streams. Matrix is transport only.

### Key Implementation Notes

**Riverpod provider naming (3.x):** Class `AuthNotifier` → provider `authProvider` (not `authNotifierProvider`). The "Notifier" suffix is stripped. Class `ExpenseAdder` → `expenseAdderProvider`.

**Drift + Riverpod code-gen conflict:** Drift generates data classes (`Expense`, `Settlement`, `Group`) in part files. Riverpod's generator can't reference those types as provider return types in the same build phase. Solution: use plain model classes (`ExpenseModel`, `SettlementModel`, `GroupModel` in `lib/models/`) as the DAO layer's public API, and map from Drift types internally. **Never use Drift-generated data classes as return types of `@riverpod` providers.**

**`drift` + `matrix` SQLite compatibility:** Use `drift ^2.31` and `drift_flutter ^0.2.8` — these depend on `sqlite3 ^2.x` which aligns with the matrix SDK's requirement. Avoid upgrading drift to 2.32+ without checking; that version switches to `sqlite3 ^3.x` which conflicts with matrix and breaks test compilation.

**Drift web setup:** `_openConnection()` passes `DriftWebOptions(sqlite3Wasm: Uri.parse('sqlite3.wasm'), driftWorker: Uri.parse('drift_worker.js'))` when `kIsWeb`. The two files in `web/` must not be deleted — they are not generated by the build and are not in `.gitignore`.

**Router pattern:** `routerProvider` is `keepAlive: true` and uses `refreshListenable` (a `ValueNotifier`) to rerun the redirect when `isLoggedInProvider` changes. Do **not** make it non-keepAlive — that recreates the `GoRouter` on every auth state change, which crashes at the default initial location `/`.

**Testing without Matrix imports:** The `matrix` SDK pulls in native sqlite3 which can cause issues in test processes. Keep test files free of `package:matrix` imports. Extract testable logic from classes that use Matrix types as `@visibleForTesting` static methods that accept plain Dart types (maps, strings, ints). See `LedgerSyncer.processExpense` for the pattern.

**Matrix SDK (7.x) API:**
- `Client(name, database: db)` — database is required in constructor (not a builder callback)
- `MatrixSdkDatabase.init(name, sqfliteFactory: databaseFactory)` — uses sqflite internally
- `client.rooms` — `List<Room>`, rooms with `app.moneyledger.group` state event are ledger groups
- `room.name` — display name (not `displayName`)
- `room.sendEvent(content, type: '...')` — send custom events
- `client.onSync.stream` — `Stream<SyncUpdate>` for incoming events
- `roomUpdate.state` — `List<MatrixEvent>?` (not a `State` object with `.events`)

### Data Model

Expenses and settlements use **UUIDv7** IDs. All amounts are **integer cents** to avoid float errors.

**`com.moneyledger.expense` event content:**
```json
{
  "id": "<uuidv7>",
  "description": "Dinner",
  "amount": 4200,
  "currency": "EUR",
  "paid_by": "@alice:matrix.org",
  "split": { "@alice:matrix.org": 2100, "@bob:matrix.org": 2100 }
}
```

**`com.moneyledger.settlement` event content:**
```json
{
  "id": "<uuidv7>",
  "amount": 2100,
  "currency": "EUR",
  "from": "@bob:matrix.org",
  "to": "@alice:matrix.org"
}
```
