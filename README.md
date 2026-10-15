# MoneyLedger

A decentralized expense-sharing app (a Splitwise / Tricount alternative) with
**no central server**. You sign in with your [Matrix](https://matrix.org)
account, and all ledger data — groups, members, expenses, settlements — lives
**only in a local SQLite (Drift) database on each device**. There are no ledger
rooms: Matrix is used purely as an **end-to-end-encrypted to-device relay** to
replicate records between members, so the homeserver retains no financial data
and sees only ciphertext.

- **Cross-platform:** Android, iOS, and web (Flutter).
- **No backend to run:** bring your own Matrix homeserver (matrix.org, self-hosted, …).
- **Local source of truth:** every device holds the full ledger and computes
  balances locally; peers reconcile via digest-based anti-entropy.
- **Private by design:** records are E2EE (vodozemac); inbound records are
  membership-gated so only group members can write to a group's ledger.

### Features

- Local-only expense **groups** with Matrix-account or **local (name-only)**
  participants; link a Matrix account to a local person at any time.
- **Custom splits**: equal (pick who), exact amounts, shares/weights, or
  percentages — always summing to the total exactly.
- Multi-currency **balances** with greedy debt simplification, plus settlements.
- **CSV export/import** for backup and sharing (idempotent merge-by-id).
- **In-app registration** (open / dummy-UIA homeservers) and **SSO** login.
- **Device verification** (SAS emoji) and a sync-health indicator.

## Tech stack

- Flutter 3.44+ / Dart 3.12+
- [`matrix`](https://pub.dev/packages/matrix) 7.x — protocol / transport
- [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod) 3.x +
  `riverpod_annotation` — code-gen state management
- [`drift`](https://pub.dev/packages/drift) 2.x — local SQLite ORM
- [`go_router`](https://pub.dev/packages/go_router) — navigation

## Prerequisites

- Flutter SDK **3.44+** (Dart **3.12+**) — verify with `flutter doctor`.
- Android: Android SDK + NDK and a device or emulator.
- Android: a **Rust toolchain** (`rustup`, **stable**) — E2EE uses
  [`flutter_vodozemac`](https://pub.dev/packages/flutter_vodozemac) (≥ 0.6.0),
  which compiles the vodozemac Rust crate during the Gradle build (via cargokit).
  Install from <https://rustup.rs>, then add the Android targets:
  ```bash
  rustup target add aarch64-linux-android armv7-linux-androideabi \
                    x86_64-linux-android i686-linux-android
  ```
  (cargokit tries to `rustup target add` missing targets itself, but
  pre-installing them keeps offline/CI builds deterministic.) Web needs no Rust:
  it uses the prebuilt wasm checked in under `web/pkg/`.
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

### Release signing (Android)

Release APKs/App Bundles are signed with an **upload keystore** that lives
**outside the repo** (`~/moneyledger-upload-keystore.jks`, alias `upload`).
Gradle reads it via `android/key.properties`, which is **gitignored** (as are
`*.jks` / `*.keystore`):

```properties
storePassword=<store password>
keyPassword=<key password>
keyAlias=upload
storeFile=/home/<you>/moneyledger-upload-keystore.jks
```

**Back up the keystore and its password** (e.g. password manager + offline copy).
Losing it means you can never ship an update under the same signature — Play
Store updates become impossible and sideloaded users would have to uninstall
(losing local data) to install a newly signed build.

If `android/key.properties` is absent (dev machines, CI without secrets), the
release build falls back to the **debug key** so `flutter build apk --release`
still works — such APKs are for testing only, never for distribution.

## Architecture & contributing

See [`CLAUDE.md`](CLAUDE.md) for the architecture, the Matrix↔app concept mapping,
the data model, and the project structure. Known gaps and planned work are tracked
in [`docs/open-points.md`](docs/open-points.md).
