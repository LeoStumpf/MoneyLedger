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

## Commands

```bash
flutter run                          # run on connected device/emulator
flutter test                         # run all tests
flutter test test/foo_test.dart      # run a single test file
flutter build apk                    # Android release build
flutter build ios                    # iOS release build
flutter build web                    # web build
dart run build_runner build          # regenerate Drift + Riverpod code-gen files
dart run build_runner watch          # watch mode for code generation
```

After any change to a file annotated with `@riverpod`, `@DriftDatabase`, or `@DriftAccessor`, regenerate with `dart run build_runner build`.

## Project Structure

```
lib/
  main.dart          # entry point — ProviderScope(App)
  app.dart           # MaterialApp.router
  core/
    router.dart      # go_router definition (generated: router.g.dart)
    database/
      app_database.dart        # Drift DB + table definitions
      daos/
        expenses_dao.dart      # Expenses + Settlements queries → ExpenseModel/SettlementModel
        groups_dao.dart        # Groups table queries
  models/
    expense_model.dart         # Plain Dart models (ExpenseModel, SettlementModel)
  features/
    auth/                      # Matrix login, session management
    groups/                    # Group list + create (Matrix rooms)
    expenses/                  # Expense list, add expense, ledger sync
      ledger_syncer.dart       # Manual provider: subscribes to Matrix onSync → writes to Drift
    balance/
      balance_calculator.dart  # Pure function: List<Expense> + settlements → List<DebtEntry>
      balance_provider.dart    # Riverpod: watches Drift streams, recomputes on change
test/
  balance_calculator_test.dart # Unit tests for debt calculation logic
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

### Key Implementation Notes

**Riverpod provider naming (3.x):** Class `AuthNotifier` → provider `authProvider` (not `authNotifierProvider`). The "Notifier" suffix is stripped. Class `ExpenseAdder` → `expenseAdderProvider`.

**Drift + Riverpod code-gen conflict:** Drift generates data classes (`Expense`, `Settlement`) in part files. Riverpod's generator can't reference those types as provider return types in the same build phase. Solution: use plain model classes (`ExpenseModel`, `SettlementModel` in `lib/models/`) as the DAO layer's public API, and map from Drift types internally. **Never use Drift-generated data classes (`Expense`, `Settlement`) as return types of `@riverpod` providers.**

**`sqflite_common_ffi` + `sqlite3` version pinning:** `drift` requires `sqlite3 ^3.x` but `matrix` declares `sqlite3 ^2.x`. Resolved via `dependency_overrides` in `pubspec.yaml` that force `sqlite3 >=3.1.5`, `sqflite_common_ffi ^2.4.0`, `sqflite_common ^2.5.0`. These overrides must be kept.

**Matrix SDK (7.x) API:**
- `Client(name, database: db)` — database is required in constructor (not a builder callback)
- `MatrixSdkDatabase.init(name, sqfliteFactory: databaseFactory)` — uses sqflite internally
- `client.rooms` — `List<Room>`, rooms with `app.moneyledger.group` state event are ledger groups
- `room.name` — display name (not `displayName`)
- `room.sendEvent(content, type: '...')` — send custom events
- `client.onSync.stream` — `Stream<SyncUpdate>` for incoming events

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
