# MoneyLedger

A decentralized expense-sharing app (a Splitwise / Tricount alternative) with
**no central server**. MoneyLedger uses the [Matrix](https://matrix.org) network
as its sync and transport layer: you sign in with your Matrix ID, each expense
group is a Matrix room, and expenses / settlements are custom Matrix timeline
events. Computed balances and ledger state live locally on each device.

- **Cross-platform:** Android, iOS, and web (Flutter).
- **No backend to run:** bring your own Matrix homeserver (matrix.org, self-hosted, …).
- **Local source of truth:** Matrix is transport only; balances are computed from
  a local SQLite (Drift) database.

## Tech stack

- Flutter 3.44+ / Dart 3.12+
- [`matrix`](https://pub.dev/packages/matrix) 7.x — protocol / transport
- [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod) 3.x +
  `riverpod_annotation` — code-gen state management
- [`drift`](https://pub.dev/packages/drift) 2.x — local SQLite ORM
- [`go_router`](https://pub.dev/packages/go_router) — navigation

## Prerequisites

- Flutter SDK **3.44+** (Dart **3.12+**) — verify with `flutter doctor`.
- Android: Android SDK + a device or emulator.
- iOS: Xcode (macOS only).
- A Matrix account on any homeserver to actually sign in.

## Setup

```bash
git clone https://github.com/LeoStumpf/MoneyLedger.git
cd MoneyLedger
flutter pub get
dart run build_runner build      # generate Drift + Riverpod code (required)
```

This project relies on **code generation** (Drift tables, Riverpod providers). Run
`build_runner` after a fresh clone and after editing any file annotated with
`@riverpod`, `@DriftDatabase`, or `@DriftAccessor`. For continuous regeneration
while developing:

```bash
dart run build_runner watch
```

## Run

```bash
# Web (dev server on http://localhost:8080)
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0

# Android (a device/emulator must be connected)
flutter run -d android

# iOS (macOS + simulator/device)
flutter run -d ios

flutter devices                  # list available run targets
```

On first launch, enter your homeserver (e.g. `matrix.org`) and sign in with
password or SSO.

## Test

```bash
flutter test --reporter compact                  # whole suite (exit 0 = green)
flutter test test/balance_calculator_test.dart   # a single file
```

Tests run **fully offline** — no real homeserver is involved. Multi-user,
federated, and login flows are exercised against in-memory fakes
(`test/helpers/fake_ledger_network.dart`, `test/helpers/fake_auth_gateway.dart`).
Run the suite before committing; write tests alongside every change.

## Build (release)

```bash
./build.sh        # one-liner: pub get → codegen → tests → web release build
```

`build.sh` runs `flutter pub get` → `dart run build_runner build` →
`flutter test` → `flutter build web --release`, stopping on the first failure —
so a green run means codegen, all tests, and the release build passed. Output
lands in `build/web/`. Override the Flutter binary with
`FLUTTER=/path/to/flutter ./build.sh`.

Per-platform release builds:

```bash
flutter build web --release      # → build/web/
flutter build apk --release      # → build/app/outputs/flutter-apk/
flutter build ios --release      # macOS only
```

> The web build needs `web/sqlite3.wasm` and `web/drift_worker.js` (checked in,
> not generated) — don't delete them.

## Architecture & contributing

See [`CLAUDE.md`](CLAUDE.md) for the architecture, the Matrix↔app concept mapping,
the data model, and the project structure. Known gaps and planned work are tracked
in [`docs/open-points.md`](docs/open-points.md).
