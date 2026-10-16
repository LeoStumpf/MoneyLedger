# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git workflow

Single-developer project — **commit directly to `main`** (the default branch). Do
not create feature branches or open PRs unless explicitly asked; just commit to
`main` and push. **Always commit and push after a task/milestone is done**
(tests green first) — no need to wait to be asked each time.

## Project Overview

MoneyLedger is a decentralized expense-sharing app (Splitwise/Tricount alternative) with no central server. The Matrix network is used as the sync and transport layer: users authenticate with their Matrix ID, groups are Matrix rooms, and expenses are custom Matrix timeline events. All ledger data is stored locally on each device.

## Tech Stack

- **Flutter 3.44+** — cross-platform UI (Android + web; **iOS not supported for v1** — see below)
- [`matrix`](https://pub.dev/packages/matrix) 14.x — Matrix protocol: auth, to-device E2EE, device keys / SAS (G22: 7 → 14)
- [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod) 3.x + `riverpod_annotation` 4.x — state management (code-gen style)
- [`drift`](https://pub.dev/packages/drift) 2.35 + `drift_flutter` 0.3 — type-safe SQLite ORM for local ledger state (`sqlite3` 3.x, native lib via build hooks)
- [`go_router`](https://pub.dev/packages/go_router) 18.x — navigation
- [`uuid`](https://pub.dev/packages/uuid) — UUIDv7 generation for expense IDs
- [`sqflite`](https://pub.dev/packages/sqflite) — required by the matrix SDK's internal SQLite store
- `flutter_localizations` + [`intl`](https://pub.dev/packages/intl) — EN/DE UI strings (ARB) + locale formatting (G12)
- [`package_info_plus`](https://pub.dev/packages/package_info_plus) 10.x — app version on the About page
- [`file_picker`](https://pub.dev/packages/file_picker) 13.x — CSV/backup save + open (static `FilePicker.saveFile` / `pickFile`, web download included)
- `vodozemac` (Ed25519 verify), [`canonical_json`](https://pub.dev/packages/canonical_json) + [`crypto`](https://pub.dev/packages/crypto) (SHA-256) — G6 signed records
- [`cryptography`](https://pub.dev/packages/cryptography) 2.9 (Apache-2.0) — encrypted backups (G34): its **pure-Dart** `DartArgon2id` + `DartAesGcm` on every platform

**License: AGPL-3.0-or-later** (`LICENSE`; `matrix` + `flutter_vodozemac` are
AGPL). Dependency licenses: `THIRD_PARTY_NOTICES.md` — update it when adding a
dependency (and check the license is AGPL-compatible). Privacy policy:
`PRIVACY.md`, mirrored in-app (About → Privacy policy, `privacy*` ARB keys) —
keep both in sync.

## Building

```bash
./build.sh          # codegen → format check → tests → web release build (one-liner)
```

The script runs in order: `flutter pub get` → `dart run build_runner build` → `dart format --output=none --set-exit-if-changed lib test` → `flutter test` → `flutter build web --release`. It exits non-zero on the first failure, so a green run means codegen, formatting, all tests, and the release build all passed.

**Formatting:** the repo is `dart format`ted (lib/ + test/, generated files included — the generators emit formatted code). Run `dart format lib test` before committing; build.sh and CI fail on unformatted code.

To override the Flutter binary: `FLUTTER=/path/to/flutter ./build.sh`

Output lands in `build/web/`.

Android E2EE: `flutter_vodozemac` (**0.8.x**, pinned by `matrix` 14's `vodozemac ^0.8.0`; Rust vodozemac 0.10) compiles the vodozemac Rust crate during the Gradle build via cargokit, so Android builds need `rustup` (**stable** toolchain) with targets `aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android`. No pub-cache patches are needed (0.5.0 required hand-patches; don't downgrade). Web uses the prebuilt wasm committed in `web/pkg/` (no Rust needed to build the app).

**Rebuilding `web/pkg/`** (only when `flutter_vodozemac`/`vodozemac` changes — the wasm must match the Dart bindings' FRB content hash): needs Rust **nightly** + `rust-src` + `wasm32-unknown-unknown`, `wasm-pack`, and `flutter_rust_bridge_codegen` **pinned to the resolved `flutter_rust_bridge`** (`cargo install flutter_rust_bridge_codegen --version <x> --locked`; 2.13.0 for 0.8.x). Clone `famedly/dart-vodozemac` at the tag = the `flutter_vodozemac` version (e.g. `0.8.1`), then in its `dart/` dir: `flutter_rust_bridge_codegen build-web --dart-root . --rust-root $(readlink -f ../rust) --release`, and copy `dart/web/pkg/vodozemac_bindings_dart{_bg.wasm,.js}` to `web/pkg/`. Check `FLUTTER_RUST_BRIDGE_CODEGEN_CONTENT_HASH` in `rust/src/frb_generated.rs` equals `rustContentHash` in the pub-cache `vodozemac` package. `web/sqlite3.wasm` + `web/drift_worker.js` come from the matching **drift GitHub release** assets (`drift-<version>`).

**iOS is not supported for v1**: development is on Linux (no macOS to build/sign),
and `flutter_vodozemac` needs an iOS Rust/XCFramework build that has never been
done; `ios/Runner` is template level. Don't spend effort on iOS unless asked.

**CI:** `.github/workflows/ci.yml` (GitHub Actions, push/PR to `main`) runs
pub get → build_runner → `git diff --exit-code` (codegen/l10n must be
committed) → format check → `flutter analyze` → tests → web release build.
Flutter is pinned there (`flutter-version`) — bump it together with the local
toolchain. No Android build in CI (Rust + NDK).

**Offline demo mode (G15):** `--dart-define=OFFLINE_DEMO=true` (`kOfflineDemo`,
`lib/core/demo/`) — `main()` runs the app with `demoOverrides()`: signed in as
`@anna:example.org` (`DemoAuthGateway`), `DemoTransport` (sends succeed,
nothing arrives), `DemoDeviceGateway`, no background sync, and the ledger in
its own `money_ledger_offline_demo` DB, wiped + reseeded on every open by
`seedDemoLedger` (3 groups, EUR/CHF, custom splits, payments, dates relative
to now, all peers in sync). No Matrix client is ever built. Normal builds
tree-shake it (`const bool.fromEnvironment`). Never import `test/` from `lib/`.
Smoke test: `test/core/demo_mode_test.dart`. Used for README/store screenshots.

Manual smoke checklist (real devices, real homeserver): `docs/smoke-test.md` —
update its "Last run" table after a device pass.

Android release signing: `android/app/build.gradle.kts` signs `release` with the upload keystore (`~/moneyledger-upload-keystore.jks`) configured via the gitignored `android/key.properties`; without that file it falls back to the debug key. Never commit `key.properties` or keystores — see README "Release signing".

Android backup (G32): `android:allowBackup="false"`, `fullBackupContent="false"` and
`res/xml/data_extraction_rules.xml` (cloud backup + device transfer exclude every
domain) — the app data holds the ledger DBs and the Matrix session incl. crypto
keys. Pinned by `test/core/android_manifest_test.dart`; PRIVACY.md + the in-app
privacy text say so.

## Commands

```bash
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0   # dev web server
flutter run -d android               # run on a connected Android device/emulator
flutter devices                      # list available run targets
flutter test --reporter compact      # run all tests (exit 0 = green)
flutter test test/foo_test.dart      # run a single test file
flutter build apk                    # Android release build
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
  l10n/              # app_en.arb (template) + app_de.arb → generated app_localizations*.dart (committed)
  app.dart           # MaterialApp.router
  core/
    background/      # G31 Android periodic background sync (round, gate, WorkManager glue)
    demo/            # G15 offline demo mode: kOfflineDemo, demo fakes, seedDemoLedger, demoOverrides
    timer_factory.dart # TimerFactory typedef (injectable timers, G15)
    widgets/         # shared widgets (incl. text_prompt_dialog.dart: one-field prompt owning its controller)
    theme/           # G17 design tokens: app_theme.dart, app_colors.dart (LedgerColors)
    widgets/         # G17 PersonAvatar/AvatarStack, ContentWidth, EmptyState, BrandLogo
    router.dart      # go_router + routerRedirect() pure function (generated: router.g.dart)
    l10n/
      l10n.dart        # context.l10n / context.money() / context.date() + re-exports
      formatting.dart  # pure intl helpers: formatMoney, formatDate, parseAmountCents (`,`/`.`)
    splash_page.dart # neutral loading route while the onboarding flag is unknown (G25)
    database/
      app_database.dart        # Drift DB + table definitions (AppDatabase.named / .forTesting())
      account_database.dart    # Per-account DB naming, legacy adoption, SignedOutExecutor (G4)
      probe/database_probe*.dart # "does DB <name> exist?" — native file check / web WasmDatabase.probe
      daos/
        expenses_dao.dart      # Expenses + Settlements queries (LWW upserts, tombstone-aware)
        groups_dao.dart        # Groups table queries → GroupModel (LWW upsert)
        members_dao.dart       # Participants (id + name + optional matrixId; LWW; activeClaimedMatrixIds)
        sync_states_dao.dart   # PeerSyncStates: per-(group,peer) anti-entropy bookkeeping
        signing_dao.dart       # G6: KnownDeviceKeys (device-key history) + RejectedVersions
        settings_dao.dart      # AppSettings KV — local flags (onboarding-seen, left-group tombstones, G16 archive, per account); never synced
    matrix/
      record_crypto.dart          # G6 ports: RecordCrypto (sign/verify), DeviceKeyDirectory, SignerId
      hmac_record_crypto.dart     # G6 fake device keys (HMAC stand-in) for tests + offline demo
      ledger_transport.dart       # LedgerTransport port + TransportMessage + event-type constants
                                  #   + SendResult, TransportUnavailableException, pure planDeviceSend
      matrix_ledger_transport.dart # Real adapter — encrypted to-device send/receive (forClient)
      buffered_inbox.dart         # BufferedInbox: holds inbound payloads while nobody listens, replays
    sync/
      ledger_payloads.dart     # Plain-Dart payload codec (protocol v2) + bootstrap builder / parts (G14)
      payload_budget.dart      # G14: to-device size limit, budget, encrypted-size estimate, size guard
      record_version.dart      # G27: (updated_at, content hash) versions + tie-break; G14 digest buckets
      sync_engine.dart         # Anti-entropy: digest exchange + targeted repair + resync
      left_groups.dart         # LeftGroupTombstone + pure classifyPeerViewOfMe (G9 leave/delete)
      sync_status_provider.dart # groupSyncStatusProvider — drives the cloud icons
      delivery_policy.dart     # G11 PolicyTransport: sends follow "only sync with verified devices"
      peer_convergence.dart    # G29 fast in-sync proof from an inbound record (pure)
      record_validation.dart   # G18 content rules (split/amount bounds) — gate, CSV, forms
      record_signing.dart      # G6: signed bodies (canonical JSON), message, sign*, LocalRecordSigner
      record_verifier.dart     # G6: RecordVerifier (accept / refuse) + signatureStatus (display)
      record_gate.dart         # G6: RecordGate — the only inbound apply path (live, bootstrap, gossip, restore)
  models/
    expense_model.dart         # Plain Dart models (ExpenseModel, SettlementModel)
    group_model.dart           # Plain Dart model (GroupModel)
    member_model.dart          # MemberModel; sync_state_model.dart (PeerSyncStateModel)
    expense_category.dart      # G16: ExpenseCategory (stable wire ids), suggestCategory heuristic, normalizeNote
    group_archive.dart         # G16: GroupArchive (device-local) + ledgerFingerprint
  features/
    auth/                      # Matrix login, in-app registration, session mgmt
                               #   register_flows.dart: pure UIA-flow classifier; register_page.dart
                               #   auth_errors.dart: pure friendly-error mapper (G20) + auth_error_card.dart
                               #   sign_up_url.dart: pure web sign-up URL resolution
    groups/                    # Group list + create (local-only groups, member add/remove)
                               #   GroupExiter (leave/delete, G9) + group_exit_dialog.dart
                               #   group_archive_provider.dart: G16 archive (groupArchived, GroupArchiver)
    expenses/                  # Expense list, add/edit/delete, ledger sync
      ledger_syncer.dart       # LedgerSyncer: subscribes to to-device onMessage → writes to Drift
                               # Static @visibleForTesting methods for unit-testable event processing
      split_calculator.dart    # Pure-Dart split math (largest-remainder) — see "Custom splits"
      split_editor.dart        # SplitEditor widget: Equal/Exact/Shares/% modes → SplitPlan
      expense_category_ui.dart # G16: category icon / colours / label, CategoryIconTile, CategoryPicker
      expense_filter.dart      # G16: pure LedgerFilter + expenseMatches / settlementMatches
      ledger_search_provider.dart # G16: per-group search state (null = search bar closed)
    balance/
      balance_calculator.dart  # Pure function: List<Expense> + settlements → List<DebtEntry>
      balance_provider.dart    # Riverpod: watches Drift streams, recomputes on change
      record_payment_dialog.dart # G28 "X paid Y" dialog (any two participants)
    backup/                    # Full JSON backup (G5) + CSV export/import (Phase D, G13) — see "Backup" below
      ledger_backup.dart       # Pure-Dart backup codec (buildBackupJson / parseBackup) + nudge logic + file names
      backup_crypto.dart       # G34: optional passphrase encryption (Argon2id + AES-256-GCM wrapper)
      backup_service.dart      # BackupService: export all groups / preview / restore (DB seam)
      backup_providers.dart    # last-backup + nudge providers (backupNudgeProvider)
      backup_ui.dart           # settings-sheet section, restore + CSV preview dialogs, nudge card
      ledger_csv.dart          # Pure-Dart RFC4180 codec: buildGroupCsv / parseGroupCsv
      csv_export.dart          # DB → CSV seam (buildGroupCsvForExport) + csvFileName
      csv_import.dart          # CsvImporter: preview + LWW merge-by-id back into Drift; resolveCsvNames
      backup_files.dart        # file_picker glue (save dialog / browser download + pick)
    onboarding/                # First-run intro (OnboardingPage) + onboarding_seen flag
    devices/                   # Device list + SAS verification UI (DevicesPage, member device sheet,
                               #   IncomingVerificationListener) — G11
    about/                     # AboutPage (version, source, AGPL, licenses) + PrivacyPolicyPage
test/
  flutter_test_config.dart     # Per-test-file setup (Drift multi-DB warning off; sqlite3 via hooks)
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
| Group participant | `Members` row — a stable participant id + `displayName` + optional `matrixId` (the "claim"); `active`/`removed` status, LWW |
| Expense / settlement | `Expenses` / `Settlements` rows (LWW clock + tombstone) |
| Sync / transport | Encrypted **to-device** messages via `LedgerTransport` |
| Replication log | The Drift DB itself — digests drive anti-entropy |

Authentication is pure Matrix — no separate auth system. Users connect to their own homeserver (self-hosted, matrix.org, etc.). The single transport seam is `LedgerTransport` (real adapter `MatrixLedgerTransport`); fakes back all tests. Login (password + SSO) and **in-app registration** go through `AuthGateway` (`auth_provider.dart`'s `AuthNotifier`).

**Registration (Phase F).** `RegisterPage` → `AuthGateway.register`. The real adapter attempts `client.register`, and on a UIA challenge classifies the flows with the pure `register_flows.dart`: a flow needing only `m.login.dummy` is completed in-app; anything requiring a CAPTCHA / email / phone / terms / token throws `RegistrationRequiresWebException` (with friendly labels) and the page shows a **web-registration fallback**; so does an `M_FORBIDDEN` with no UIA flows (`isClientRegistrationDisabled` — e.g. matrix.org, whose sign-up moved to MAS/OIDC) (we don't reimplement every UIA stage). `/register` is reachable while signed out (see `routerRedirect`).

**Device verification (Phase F + G11).** `DeviceGateway` (`core/matrix/device_gateway.dart`, matrix-free port; real adapter `matrix_device_gateway.dart`) lists the user's own devices **and (G11) another member's** (`userDevices`), runs an SAS (emoji) verification **over to-device messages** — with our own other devices and with another member's device alike (no rooms needed) — and streams **incoming** requests (`incomingVerifications`, answered app-wide by `IncomingVerificationListener` in `App`'s builder: "Accept / Decline" → the same emoji dialog). The client must advertise `verificationMethods: {emoji, numbers}` (`buildMatrixClient`) — without it the SDK ignores every request (it was missing before G11, so SAS never worked). `askSSSS` (account has cross-signing from another client, keys not cached) is skipped automatically: the app does no cross-signing. `DevicesPage` (`/devices`) shows own devices; the **members page** shows a subtle "N unverified devices" line under a member (red "Not reachable — no verified device" when verified-only is on and none is verified) and ⋮ → *Devices* opens their device list with *Verify*. The real adapter imports `package:matrix/matrix.dart` **`hide DeviceInfo`** plus `package:matrix/encryption.dart`. **SAS emoji names (G36)** are localized: `SasEmoji.number` (the SDK's `KeyVerificationEmoji.number`, 0–63) → `sasEmojiName(number, languageCode)` from `features/devices/sas_emoji_names.dart`, an EN+DE table generated once from the Matrix spec's `data-definitions/sas-emoji.json` (Apache-2.0 — THIRD_PARTY_NOTICES + an in-app license entry in `main.dart`); unknown number → the SDK's English name.
- **The app keeps its own verified-device record** (`AppSettings` `verified_device:<mxid>|<device>` → Ed25519 key, per account, device-local; `SettingsDao.markDeviceVerified`, written by `recordingTrust` on SAS success whether or not the dialog is still open). Reason: in a roomless app the SDK evicts other users' device lists from memory on every `updateUserDeviceKeys` that doesn't name them and re-stores them with `verified: false` — a peer's SAS result would not survive. "Verified" = SDK flag **or** our record for the exact (user, device, **current key**) (`isDeviceTrusted`; a changed key voids it). Own devices: the SDK flag persists too.
- **Opt-in enforcement (G11): "Only sync with verified devices"** (settings sheet, per account, device-local `verified_only_sync`, default **off**; turning it on asks first and explains). Every app sender — `_WriteContext` / `_GroupWriteContext` / `SyncEngine` (replication, member bootstraps, digests, resync answers) — wraps the transport in `PolicyTransport` (`core/sync/delivery_policy.dart`) built from the **same** account DB it writes to; each send reads `SettingsDao.deliveryPolicy()` (fails closed if unreadable) and passes it to `sendToUsers(…, policy:)` → pure `planDeviceSend` withholds unverified devices (own and peers'). `SendResult.unverifiedUsers` (⊆ `unreachableUsers`: has devices, none verified) feeds `SyncHealthState.unverifiedPeers`; the cloud tooltip (`pendingPeerHint`) says "X has no verified device" instead of "Waiting for X". Withholding is not a failure. **Inbound is not refused** when the setting is on: refusals in G6 are permanent (`rejected_versions`) and would not heal after verifying later, and a member's legitimate new device would silently lose edits; the setting is about where *our* data goes. The record details dialog shows "You (haven't) verified this device" for the signing device of others (`signerVerifiedByMe`). Limits: only what *this* device sends is restricted — a peer's own devices still sync among themselves unless the peer turns it on too; a new own device can't self-restore from a device with the setting on until verified. **G36:** the settings subtitle and the confirm dialog say exactly that ("only limits what this device sends", "a new login of yours can't restore … until you verify it").
- Tests: pure planner/policy (`test/core/device_plan_test.dart`), `SettingsDao`, `SyncHealth`/`pendingPeerHint`, `withTrust`/`peerDeviceTrust`/`recordingTrust`, an end-to-end fake-relay test (`test/integration/verified_only_sync_test.dart`) and widget tests (`test/verified_only_ui_test.dart`). The SDK SAS round-trip itself is manual-smoke (`docs/smoke-test.md` §9).

### Participant identity (virtual users)

A participant's **ledger identity is decoupled from their Matrix account.** The
`Members` table's `userId` column is the **stable participant id** — for a
from-scratch / claimed user it equals the MXID, for a Tricount-style local
person it's a UUID. `matrixId` (nullable) is the claimed account; `null` = a
pure-local participant (ledger data only, never a sync/replication target).
Expenses (`paid_by`, `split` keys) and settlements (`from`/`to`) reference the
**participant id**, so linking/detaching a Matrix account (claim/unclaim) or
removing a member never rewrites history. Replication targets
`MembersDao.activeClaimedMatrixIds`; "who am I in this group" is
`currentParticipant` (the participant whose `matrixId` is this device's MXID);
the UI resolves ids → names via `participantNames(groupId)`
(`group_provider.dart`).

### Per-account ledger databases (Phase G4)

Every Matrix account signed in on a device has its **own** Drift database, so
two accounts sharing a device/browser never see — or gossip digests for — each
other's groups. The name is `accountDatabaseName(mxid)` =
`money_ledger_<16 hex>` (deterministic 64-bit FNV-1a variant, web-safe
arithmetic; the raw MXID never appears in a filename — **never change the hash**,
a goldens test pins it). `appDatabaseProvider` (`expenses_provider.dart`) watches
`accountUserIdProvider` (`auth_provider.dart`; filters equal values, so
re-validating login doesn't reopen) and opens the DB via the injectable
`accountDatabaseOpenerProvider`; on an account switch the old DB is closed
(`ref.onDispose`) and every DAO / stream / `SyncEngine` / `LedgerSyncer` (both
`ref.watch(appDatabaseProvider)`) rebuilds. **Logout is non-destructive**:
re-login reopens the same DB (the sign-out button asks first and says so — G29). **Signed out, no DB is opened**: the provider
returns `AppDatabase.signedOut(SignedOutExecutor())` (reads → no rows, writes →
`StateError`; `isSignedOutPlaceholder` is true). `SyncEngine`/`LedgerSyncer`
**don't start** on the placeholder — pages watching `syncEngineProvider` during a
login/logout transition would otherwise send a spurious empty-DB `resync_request`
(G24). `AppSettings` lives in the per-account DB, so the **onboarding
flag is per account** (signed out, `onboardingSeenStream` reports `true`).

**Legacy migration.** Pre-G4 installs kept everything in one global
`money_ledger_db`. On every open of a per-account DB, drift's `beforeOpen` runs
`adoptLegacyLedger` until the target has the `legacy_checked` setting: if the
legacy DB exists (`databaseExists` — native: `<docs>/money_ledger_db.sqlite`;
web: `WasmDatabase.probe`, so probing never creates an empty DB), isn't already
marked `legacy_adopted_into`, and either has no claimed MXIDs or claims *this*
MXID (`shouldAdoptLegacy` — so another account logging in first doesn't inherit
it), all rows are copied with `INSERT OR IGNORE` in one transaction, then the
legacy DB is marked. Works identically on native and web (row copy, no file
rename). The legacy DB is never re-adopted. Failures are logged and retried on
the next open. **G36 cleanup:** on a *later* open (the target already had
`legacy_checked` before), `cleanupLegacyLedger` deletes the legacy DB
(`deleteDatabase`: native file + `-wal`/`-shm`/`-journal`, web via
`WasmProbeResult.deleteDatabase`) iff it is adopted and **every** MXID it
claimed is the adopter **or has signed in here since** and found it already
adopted (it can never adopt it; recorded as `legacy_checked_by:<db name>` in
the legacy DB — G18 review) (`canDeleteLegacy` — or it claimed none);
otherwise it is kept for that account (only a manual recovery could use it)
and re-checked on later starts. The per-account DB is marked
`legacy_cleanup_done` (`deleted` / `absent`) once settled.

### Data Flow

Inbound to-device message → `LedgerSyncer._onMessage` → **membership gate** →
DAO LWW upsert → Drift stream providers → UI rebuild. Local writes are
**local-first**: persisted to Drift immediately, then best-effort replicated to
members (`_replicate`). Drift is the **local source of truth** — the UI always
reads Drift streams, never Matrix in-memory state.

**Membership gate (Phase F, tightened G18 review).** To-device messages are
E2EE, so `msg.senderId` is authenticated — **plaintext** to-device events are
dropped (`isAcceptedLedgerEvent` in the real transport; `TransportMessage.encrypted`,
checked again by `LedgerSyncer` / `SyncEngine`; the fake relay marks its
messages encrypted, `FakeMatrixNetwork.injectPlaintext` simulates the rest).
`LedgerSyncer.isSenderAuthorized` (pure, `@visibleForTesting`) drops any
record whose sender isn't an active member of the target group:
expense/settlement/group-meta require an active claimed member; a `bootstrap`
for an **unknown** group is TOFU-accepted (else member-only) — but only its
**own group's** entries are applied (`snapshotEntries`: nested meta / member /
expense / settlement entries naming another group are dropped, also for the
G9 re-add check); a `member` payload from a non-member is accepted **only** to
update the participant an active member already assigned to that MXID
(`matrixId == sender`, latest status `active`) — a non-member can **never**
create a participant, reactivate a `removed` one or claim a local person, so a
removal sticks (its records, member payloads, digests and resync requests are
all ignored). Joining is done by an active member: **invite** = the inviter
picks the slot (`MemberAdder.invite(group, mxid, participantId:)` → `claim` of
a local person, else `add`; members page "Who is X in this group?"). The
invitee-side picker (`selfClaim` / `joinAsNew`) remains only for groups this
device holds without being a participant (e.g. a CSV import) — peers refuse it
from non-members. Inbound `updated_at` is
clamped to `now + 5 min` (`clampInboundClock`) to bound clock-skew LWW wins.
The gate authenticates the *relaying* sender; the *author* of each version is
authenticated by its signature (G6, below). Digests from an account that isn't
a participant of the group at all are ignored (rule 8 — no gossip, repair or
reply).

**Signed records (G6, protocol v2).** Policy: any active member may create /
edit / delete any expense or settlement (and edit members / group meta), but
**every version is signed by the device that wrote it** — the editing device's
Matrix **Ed25519 fingerprint key** (vodozemac olm account,
`olmManager.signString`; verify via `vod.Ed25519PublicKey.verify`), exposed as
`LedgerTransport.crypto` (`RecordCrypto`) + `LedgerTransport.deviceKeys`
(`DeviceKeyDirectory`, the homeserver's current device list). Design doc:
`docs/design/g6-signed-records.md`.
- **What's signed** (`record_signing.dart`): a body built from the parsed
  *model* (type tag, group, id, all fields — for expenses incl. the optional
  G16 `category` / `note`, present **only when set** so pre-G16 bodies and
  hashes are unchanged — `updated_at`, `deleted`, signer
  {user, device, key}; `v`/`sig` excluded) → Matrix canonical JSON →
  message `mlsig1:` + base64url(SHA-256) (ASCII). Expenses / settlements also
  carry an immutable **`origin`** (creator's signed creation statement →
  "added by"), copied by every editor; `sig` → "last edited by". A delete is
  a signed version too.
- **Local writes** sign via `LocalRecordSigner` (captured in the write
  contexts before the first await, G19). Signer not ready → row saved with
  `pending_sign` (local-first), never sent; `SyncEngine._signPending` signs it
  (same clock) before digests / bootstraps.
- **Inbound** goes only through `RecordGate` (live records, bootstrap
  snapshots, digest member gossip, backup restore): not newer than stored →
  no-op (an unsigned relay of a grandfathered row we hold is harmless);
  **exactly** the version we refused (clock + G27 hash) → dropped (G18 review:
  other versions — higher or lower — are looked at on their own; a refusal
  never freezes a record); **invalid content** (`record_validation.dart`:
  split not a non-empty `{participant: int ≥ 0}` map summing to the amount,
  amount outside 1 … `kMaxAmountCents` = 10^13 cents, no payer, payment to
  oneself) → refused `invalid_record`; else `RecordVerifier`: a clock > now +
  5 min is dropped **first** (transient, signed or not); **refused** if
  unsigned, bad signature, bad / changed origin, wrong signer (a non-member's
  member payload must be signed by itself) or **key conflict** (the embedded
  key contradicts the key we pinned for that (user, device) or the server
  lists). Then (defence in depth) the **signer** of an expense / payment /
  meta version must claim a participant of that group (a removed one only
  for versions not newer than its removal) or be the relaying account itself
  — else dropped as `signer_not_member` (transient; a snapshot's meta may be
  signed by one of the snapshot's own members). Refused versions go to
  `rejected_versions` (one row per record: the highest refused version incl.
  `version_hash`, schema v9; never one stamped beyond now + 5 min) and the
  digest's `rejected` map (`"<ms>:<hash8>"` per id), so peers stop re-sending
  exactly that version (no repair loop; "agree to disagree" counts as in
  sync). A user-started restore bypasses and clears earlier sync refusals of
  the versions it stores, and isn't subject to the signer rule.
- **Key binding after logout:** every device pins every member device key it
  sees first-hand (`known_device_keys`, source `server`: after each digest
  broadcast + on demand when verifying), so signatures stay verifiable after
  the signer signs out (`client.logout` deletes the device). Bootstraps /
  backups carry `device_keys` attestations, trusted only from a new group's
  inviter, our own devices or a user-started restore (source `attested` →
  "vouched"). **G18 review:** an attestation is stored **per group**
  (`known_device_keys.attested_group`, part of the PK, schema v9) and only
  vouches for that group's records; and a peer's attestation never vouches
  for a device of an account whose first-hand (server) device list we hold
  without it (`attestationVouches` — an account vouching for its own device,
  e.g. our own backup, still counts). Unknown device → accepted, shown
  **unverified**. `signatureStatus(sig, allKeys, group:)` derives verified /
  vouched / unverified / conflict / legacy at display time.
- **UI** (`record_attribution.dart`): edit-expense footer + payment dialog
  "Added by X · Last edited by Y" (details dialog: device + how verified, or
  vouched by whom; refused-newer-version notice); the list flags only key
  conflicts and someone posing as us.
- Rows from before G6 (schema ≤ 5) are **grandfathered** as legacy/unsigned
  locally; peers refuse them if relayed (they can't be bootstrapped to new
  members/devices). **Decided (G35): no migration / re-sign step** — the app
  is unreleased and only the test groups have such rows; they get
  **recreated before the release**. The refusal is visible on the receiving
  side: `RecordGate.onRefused` → `LedgerSyncer` logs `[g6] refused unsigned
  …` and calls `SyncHealth.reportLegacyRefused` → dismissible groups-page
  banner "Some data couldn't be received … ask X to recreate the group"
  (`SyncHealthState.legacyRefusals`, session-only, never a sync failure).
- Residual risks (fabricated device ids / malicious inviter → **need
  cross-signing**, future; homeserver-added devices; divergence by
  disagreement, not auto-resolved): `docs/open-points.md` + design doc §5.4.

**Leaving / deleting a group (G9).** The expenses app bar's overflow menu (⋮,
next to *Export CSV*) offers **Leave group** when this account is an active
participant and another claimed account is active (`groupExitKind`), else
**Delete group** (solo / local-only group, or we're no longer active). The
confirmation warns (non-blocking) if our balance isn't settled and offers the
full backup (*Back up all groups*, G5). `GroupExiter.leave` marks our participant `removed` (LWW) and relays
it to every claimed account (best-effort — peers see "X left"; our own other
devices too, which then leave as well, see G26 below); `delete` sends nothing. Both then `AppDatabase.purgeGroup` (group, members,
expenses, settlements incl. tombstones, peer sync states — one transaction) and
write a device-local **`LeftGroupTombstone`** (`AppSettings` key
`left_group:<id>`, JSON `{left_at, member?}`; no schema change). Receivers
(group unknown + tombstone present): `LedgerSyncer` drops **every** record for
the group except a `bootstrap` that **re-adds** us (our MXID `active` with
`updated_at > left_at`, `acceptsForLeftGroup`) — that clears the tombstone and
goes through the normal TOFU path; `SyncEngine` rule 7 (see its doc) never
asks for a resync of a left group unless the digest shows us re-added, and
answers a digest that still lists us active with an older clock (lost leave
notice) with our stored `removed` member payload. Peers stop targeting us on
their own: replication and digests go to *active* claimed members only.

**Member lifecycle (G26).** Adding an MXID that already claims a participant
in the group (left / removed, or a claimed placeholder) **reactivates** that
participant (same id + name, history kept) instead of inserting a duplicate.
All "which participant does this MXID claim?" lookups go through
`claimedBy()` (`member_model.dart`; prefers active, then newest — so DBs with
pre-G26 duplicates don't throw in `memberByMatrixId`). Local edits stamp
`nextLwwClock(old)` = `max(now, old + 1)`, so a re-add always beats the
`removed` record even when the leaver's clock ran ahead (and thus passes the
re-added device's `updated_at > left_at` check). An inbound `member` payload
**sent by our own MXID** marking **our own** participant `removed` means we
left on another device → `LedgerSyncer` purges the group + writes the
tombstone like `GroupExiter.leave` (`SettingsDao.purgeGroupAsLeft`), sending
nothing. Removed by **another** member → the group stays as read-only history
(`currentParticipant` is inactive): banner "You were removed from this group"
+ *Delete from this device*; no add-expense / settle / edit / member changes.
The members page lists removed participants greyed under **Former members**
(*Re-add*: claimed ones via `add`, local people via `MemberAdder.reactivate` — same participant, never a duplicate). Who removed whom isn't recorded, so a removal
learned only via a peer's digest gossip (our own leave notice lost) also shows
as "removed".

**Editing a group (G10).** ⋮ → *Edit group* (any active member):
name + default currency (`group_edit_dialog.dart`, currencies from
`kGroupCurrencies`). `GroupEditor.edit` LWW-upserts the meta with
`nextLwwClock` and relays a `com.moneyledger.group` payload to the active
claimed members; a lost relay is repaired by the digest's `meta_updated_at`.
The default currency only applies to **new** expenses (balances are per
currency).

**Sync health (Phase F).** Replication/digest errors used to only `debugPrint`.
`SyncHealth` (`lib/core/sync/sync_health.dart`, a `keepAlive` Riverpod notifier)
now collects `reportDelivery(targets, SendResult)`/`reportFailure()` from
`replicate` (`expenses_provider.dart`) and `_sendDigest` (`sync_engine.dart`).
**"Nothing sent" is observable (G24):** `sendToUsers` throws
`TransportUnavailableException` when signed out / encryption is off (a failure),
and returns a `SendResult` whose `unreachableUsers` lists targets (never self)
with **no device** — not a failure, tracked in `SyncHealthState.unreachablePeers`
(cleared once a later send reaches them; the pending cloud's tooltip says "X has
no active device"). Digests are only marked sent to peers that had a device. It flips to
`failing` only after `kSyncFailureThreshold` (2) **consecutive** failures — a
single offline blip is normal (the homeserver queues to-device messages and
anti-entropy repairs). The expenses app-bar `_SyncStatusIcon` shows a tappable
error cloud when failing (sheet with last error / last-synced + a **Retry now**
that calls `broadcastDigests()`); otherwise the existing `cloud_done`/
`cloud_queue` states.

### Background sync (G31, Android)

To-device messages queue on the homeserver and are only fetched while the app
runs, so a closed device used to answer nothing (digests, resync requests). A
periodic **WorkManager** task (`workmanager` ^0.10, MIT; every 15 min, network
connected + battery not low; `lib/core/background/`) fixes that:

- `background_round.dart` — **plain Dart** `runBackgroundRound(tryAcquire,
  openSession, openDatabase, abort, timeout)`: opens the per-account DB, runs
  the app's own `LedgerSyncer` + `SyncEngine` in a private `ProviderContainer`
  (no startup digest via `digestOnStartProvider`, short poke debounce, no
  periodic timer / self-resync retries), `fetchOnce()` (one `/sync`), waits
  until the relay is quiet (no send in flight), broadcasts its own digests
  **only if** `SyncStatesDao.latestDigestSentAt()` is older than 15 min, does up
  to 2 follow-up fetches while there was traffic, then disposes + closes (DB,
  then the session). Bounded at 60 s. Tested with fakes
  (`test/core/background_round_test.dart`).
- `background_sync_native.dart` — the headless entry
  (`backgroundSyncDispatcher`, `@pragma('vm:entry-point')`) and the real
  session: `vod.init()`, `buildMatrixClient()`, `client.backgroundSync = false`
  **before** `init(waitForFirstSync: false)` (init's first `/sync` + our
  `oneShotSync` only — no endless loop), `forClient` before init;
  close = `client.dispose(closeDatabase: true)` — **never logout**.
  `background_sync.dart` conditionally exports it or the web stub (no-ops).
- **Concurrency guard** (`background_gate.dart`): app and round run in the same
  process but different isolates, each with its own Matrix client / Drift
  connection on the same files (Olm sessions!) — they must never overlap. Both
  register a port in the process-wide `IsolateNameServer` and ping the other
  side (register first, check second). **G18 review:** the round **never**
  removes a mapping — a registered app that doesn't answer may just be busy,
  so the round is skipped (it asks the app to `sync` instead: one
  `oneShotSync` in the app's client, keeping the process awake). The app
  claims its slot in `main()` **before** opening anything
  (`prepareBackgroundSync`), asks a running round to `stop` and waits until
  the round has released its slot (released only after its stores are
  closed), answered `stopped`, or stayed silent for 10 s (dead isolate → the
  app removes the stale mapping); meanwhile it shows *Finishing background
  sync…* (`BackgroundSyncWaitApp`). `maxWait` (2 min) is only a last resort
  against a wedged round (logged). A stopped round waits up to
  `kBackgroundInFlightGrace` (10 s) for the step in flight (a `/sync`, a
  digest broadcast, a session still opening) before it closes the stores. The
  app gives its slot back when its engine detaches (`AppLifecycleListener
  .onDetach` — backed out of; otherwise rounds would stay skipped until the
  process dies). Gate logic is tested on a fake `PortRegistry`
  (`test/core/background_gate_test.dart`).
- Setting: per account, device-local `AppSettings` `background_sync_enabled`
  (default on), *Settings* sheet (gear) on the groups page;
  `backgroundSyncSchedulingProvider` (watched by `LedgerSyncHost`) registers /
  cancels the OS task (cancel on sign-out). The round re-checks the flag.
- The app manifest removes the plugin's `POST_NOTIFICATIONS` permission (no
  expedited / foreground workers). Web/iOS: no background sync.
- **Debug builds only (G36):** the settings sheet has *Run background sync now
  (debug)* (`kDebugMode`) → `BackgroundScheduler.runOnce(delay: 15 s)` = a
  WorkManager one-off task (`moneyledger-background-sync-once`, same
  dispatcher) — swipe the app away within the delay so the round runs
  headless instead of delegating to the app. Release builds never show it
  (and `runOnce` is a no-op there).
- Manual trigger on a device: `adb shell cmd jobscheduler run -f
  app.moneyledger.money_ledger <jobId>` (id from `dumpsys jobscheduler`); logs
  are tagged `[bg]` / `[bg-gate]`.

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
(another of their devices answers with bootstraps — **only while the app runs
there**: no push/background sync on mobile, the homeserver queues the request
until then). **G30:** the request is retried after 5 s / 30 s / 2 min
(`selfResyncRetryDelaysProvider`) while the DB is empty and no bootstrap has
arrived (covers a lost request / encryption not ready right after login); the
groups page shows "Restoring your groups from your other devices…"
(`selfRecoveryProvider`, `self_recovery.dart`) until data lands, a send finds
**no other own device** (`SendResult.deviceCount == 0` → nothing to restore,
normal empty state at once) or 3 min pass. An unknown group named in a
peer's digest triggers organic bootstrap (at most one `resync_request` per group
per `kGroupResyncCooldown`, 30 s — a burst of digests doesn't fan out); never for a group we left/deleted unless we were re-added — G9). Sync status (`cloud_done`/
`cloud_queue` icons) is derived from `PeerSyncStates.lastInSyncAt`
(`lib/core/sync/sync_status_provider.dart`). Full receiver rules: the `SyncEngine`
doc comment. **Fast proof (G29):** a matching digest needs the poke debounce +
two relay hops (~20 s on matrix.org), so after a peer's *own* change we showed
"Waiting for …" though we held exactly its state. `LedgerSyncer` now marks a
peer in sync right after applying a record **from that peer** when every
record we hold newer than its `lastInSyncAt` is one that peer itself sent us
at the same revision (`peer_convergence.dart`, in-memory per peer; bootstrap /
gossip / our own writes block the proof). `markInSync` is monotonic and always
stamps our wall clock (never a peer's possibly skewed record clock).
**Fast ack (G36):** the writer's own cloud waits for the receiver's digest;
after a **live record** (expense / settlement / member / meta, not a
bootstrap) from a peer, `pokeGroup(liveRecord: true)` debounces the ack digest
by `ackDebounceProvider` (1 s) instead of `pokeDebounceProvider` (5 s) — at most
one fast ack per group per `kFastAckMinGap` (10 s), never longer than the poke
debounce (pure `SyncEngine.pokeDelay`). Measured phone → emulator: writer
pending → synced 9.4–11.2 s (median 9.8) before, 5.4–6.0 s (median 5.7)
after. **Resync answers are deduped (G36):** a `resync_request` is
answered at most once per (requesting device, scope/group) per
`resyncAnswerWindowProvider` (60 s) — an offline device used to answer every
queued request (a new device's request + its G30 retries) with a full
bootstrap. The device comes from `TransportMessage.senderDevice` (Matrix: the
Olm sender key; fake: the device id); a failed answer is forgotten so a retry
may try again.

**LWW tie-break (G27).** A record *version* is `(updated_at, content hash)`
(`record_version.dart`): SHA-256 hex of the canonical JSON of the content
fields — the G6 signed body minus `origin` / `signer` (`expenseContent` &
co. in `record_signing.dart`). Higher clock wins; **equal clock → higher hash
wins**; equal clock + hash = same version (no-op). Signatures are excluded on
purpose: the `pending_sign` and signed copy of a local write are the same
version (the re-sign at the same clock must still land), and identical content
written by two devices in the same ms just agrees. Applied in **every** LWW
upsert — the DAOs (`upsert*Lww` read + compare + write in one transaction, so
concurrent inbound versions resolve the same in any order; the same version is
re-written) and `RecordGate` (a not-newer version is a no-op before
verification) — and in the digests: entries are `"<ms>:<hash8>"` (first 8 hex
chars; prefix order agrees with full-hash order), meta has `meta_hash`, members
are hashed from their gossiped versions. A digest entry without a hash (bare
int) compares by clock only. Refusals (`rejected_versions`) name the exact
version (clock + hash, G18 review). **Cached hash (G37,
schema v8):** expenses / settlements have a `version_hash` column; the DAO's
LWW upsert stores the hash of what it wrote (only for a companion carrying
the whole content — a partial one stores NULL), the v8 migration backfills
existing rows (`backfillVersionHashes`), and models read from rows carry it
(`versionHash`; `withSigning` keeps it — content unchanged), so
`expenseVersionHash` / `settlementVersionHash` only hash rows without one
(`compute*VersionHash` always hashes). Never set `versionHash` on a model
whose content you changed. Measured on the Pixel (5k records, in-memory DB,
`tool/bench/digest_bench.dart`, run as a separate `.bench` package so it never
touches the installed app): digest 537 ms → 174 ms; v8 backfill 367 ms once.

**Message size (G14).** Synapse refuses to-device content over **65 536
bytes** per device (`MAX_TO_DEVICE_CONTENT_SIZE`, 413 — the SDK only logs it
and drops it from its queue). Olm + base64 + the SDK envelope leave ≈ 48.4 KB
of our JSON (`kHardMaxPayloadBytes`, `payload_budget.dart`); senders pack to
`payloadBudgetProvider` (default `kMaxPayloadBytes` = 40 000; tests override
it small), and both transports throw `PayloadTooLargeException` above the hard
limit (the fake: above `FakeMatrixNetwork.maxPayloadBytes`). Measured
(`test/core/payload_size_test.dart`, 4 members, signed records): ~0.86 KB per
record in a bootstrap, ~64 B per digest entry → an unchunked bootstrap broke
at **~52 records**, a flat digest at **~720**. Hence:
- **Chunked bootstraps** (`buildBootstrapParts`): a snapshot over the budget
  is sent as several `bootstrap` messages, each **self-contained** — signed
  meta + **all** members + `device_keys` + a disjoint slice of the records
  (`part`/`parts`, informational). Parts are idempotent and
  order-independent: any part creates an unknown group (TOFU on its verified
  meta), passes the G9 re-add check, and makes the sender a known active
  member for the others. Used by `SyncEngine` (resync answers) and the group
  mutators (`_GroupWriteContext.sendBootstrap`: add / invite / claim). The
  backup file uses the unchunked `buildBootstrapContent`.
- **Bucketed digests** (`buildDigestMessages`): flat when it fits, else
  records hash by id (FNV-1a) into `2^bits` buckets (`bucket_bits` 4…11,
  ~16 records per bucket); each message carries the header (meta, members,
  rejected), `buckets` (12-char hash of every bucket, positional) and full
  entries only for its `detail` buckets (spread over several messages when
  needed). Exchange, bounded to three messages (SyncEngine rule 9):
  primary summary → reply (same bits) detailing our *unresolved* (hash differs,
  no entries) + differing buckets → one `final` detailing the same buckets
  (never answered). Rule 4 (in sync) needs no unresolved bucket.
- Ceilings now: ~80 members per group (all members ride in every part /
  digest), ~30k records (2 048-bucket summary ≈ 31 KB). See
  `docs/open-points.md` for the table and costs.

### Backup (full JSON — G5)

Ledger data exists only on members' devices, so a group nobody else has a copy
of (solo, or only local people) is lost with the device. The **full backup** is
the lossless answer: settings sheet (gear on the groups page) → *Back up all
groups* writes **one JSON file for the whole account**, *Restore from backup*
merges one back. `lib/features/backup/`: `ledger_backup.dart` is the pure codec
(+ the nudge logic), `backup_service.dart` (`BackupService`,
`backupServiceProvider`) the DB seam, `backup_ui.dart` the UI.

**Format** (`moneyledger-backup-YYYY-MM-DD.json`, pretty-printed, plain text
unless a passphrase is set — see *Encrypted backups* below):

```json
{ "format": "moneyledger-backup", "version": 1, "exported_at": 1760000000000,
  "account": "@alice:example.org",
  "groups": [ <bootstrap payload per group, sorted by name> ] }
```

Each group is exactly a `com.moneyledger.bootstrap` payload
(`buildBootstrapContent`): meta, every participant (stable id, matrix id,
status), every expense + settlement **incl. tombstones**, all with `updated_at`.
`parseBackup` throws `BackupFormatException(kind)` — `notABackup` (not JSON / no
`format` marker, e.g. a CSV), `newerVersion` (version > `backupVersion`; bump
it only for incompatible changes, keep old versions readable), `malformed`
(missing group id, non-list sections, a record of another group, records
without id / `updated_at`) — mapped to localized messages
(`backupErrorMessage`).

**Restore** = pick → (encrypted → passphrase, see below) →
`BackupService.preview` (per group: new / left earlier / *read-only — you
were removed* (`backupShowsMeRemoved`: the newer of backup and local copy of
our participant is `removed`) / N records that are absent or older locally /
up to date; totals; *other account* warning when `account` ≠ the signed-in
MXID) → confirm → `BackupService.restore`: per group, **one DB transaction**
(G35) around `RecordGate.snapshot` — the syncer's own verifying apply path
(**LWW by stable id**, tombstones win when newer) — idempotent, re-restoring
is a no-op. The homeserver lookups verification needs run **before** the
transactions (`RecordVerifier.prefetch` for every signer in the file; the
restore verifier caches them 10 min), so a group is restored completely or
not at all; a failing group is rolled back (incl. its cleared left-group
tombstone), the others still restore, and `RestoreIncompleteException`
reports it ("N groups couldn't be restored and were left unchanged"). A group
whose meta is refused isn't restored either — its transaction is rolled back
too, so its left-group tombstone stays (G18 review).
**G6:** every signed version is
**verified** like an inbound record (a tampered one is refused, the rest
restores); the file's `device_keys` are trusted as vouched-for keys (the user
chose the file; scoped to their group); unsigned rows (pre-G6 history) are
restored as legacy, and earlier sync refusals of the restored versions are
cleared. Export
includes `pending_sign` rows (unsigned) and the attestations. User
intent, so **no membership gate**; a group this account had **left/deleted**
here gets its `LeftGroupTombstone` cleared first (else the syncer would keep
dropping it). If the peers have us `removed` with a newer clock, the next
digest exchange turns it into read-only history again (G26; rule 6 answers
our digest with the `removed` record) — the preview says so, and
`test/integration/backup_restore_sync_test.dart` covers restore → digest →
read-only with no repair loop. After
the restore every restored group gets a `SyncEngine.pokeGroup` (digest →
normal anti-entropy repair with peers; best-effort). Backups of **another
account** are allowed (warning): their groups land in this account's DB, where
we may not be a participant ("not participating").

**Nudges:** onboarding has a 4th card "Keep a copy". The settings sheet shows
*Last backup: <date> / never* (`AppSettings` `last_backup_at`, device-local,
per account, written after a successful save). The sheet's backup / restore
tiles **close the sheet first** and run the flow on the navigator's context,
so dialogs and snackbars aren't hidden under it. The groups page shows a
dismissible `BackupNudgeCard` (`backupNudgeProvider`) when some group has **no
other active claimed member** (`unprotectedGroups`) and there was no backup in
`kBackupNudgeInterval` (30 days); *Later* snoozes it 30 days
(`backup_nudge_snoozed_until`). **G34:** no nudge when a **second device of
our own** holds the groups too — pure `secondOwnDeviceProtects`: another
current own device is **verified** (`myDevicesProvider`, SDK or G11 record)
or one proved within `kOwnDeviceSeenWindow` (30 days) that it holds our
state (newest `PeerSyncStates.lastInSyncAt` for our own MXID —
`SyncStatesDao.watchLatestInSyncWith`; a matching digest from another own
device sets it). `ownDeviceProtectionProvider` is null while loading (nudge
hidden); the device list failing (offline) counts as "no verified device".
Widget tests: `testOverrides` sets it to false.

**Files:** `backup_files.dart` (`saveTextFile` / `pickTextFile`,
`LedgerFileKind.csv|backup`) — native: file_picker save dialog (returns null
when cancelled → no `last_backup_at`, else `SavedFile(path)`); web:
file_picker's own download mode (always "saved", no path; the custom Blob
glue went with G22). Backups are picked without an extension filter (Android
doesn't map `.json` reliably); the parser rejects wrong files. **Saved name
(G34):** Android may rename (`… (1).json`) — the snackbar shows
`savedFileDisplayName(path)` (last path segment, only if it ends in the
extension; the Downloads provider returns `msf:<id>` → neutral "Backup
saved" / "CSV exported" without a possibly wrong name; web: the proposed
name). Same for the CSV export.

**Per-group backup (G34):** group ⋮ → *Back up this group* →
`exportGroupBackup` → `exportJson(onlyGroup:)`: the same format with one
entry in `groups`, file `moneyledger-backup-<slug>-YYYY-MM-DD.json`
(`fileNameSlug`: lower case, letters incl. umlauts + digits, ≤ 40 chars).
Doesn't update `last_backup_at` (it doesn't protect the other groups).
**Leave/delete dialog:** its *Back up all groups first* runs
`runBackupExport` and shows the outcome **inside** the dialog
(`exitBackupResult`) — a snackbar would be hidden behind it.

**Encrypted backups (G34).** Every export (settings, nudge, group menu,
leave dialog) first shows `BackupPassphraseDialog`: optional passphrase +
confirmation + strength hint (`passphraseStrength`, heuristic); empty →
plaintext as before, with the "not encrypted" warning. `backup_crypto.dart`
(pure Dart, `cryptography` package, **pure-Dart implementations on every
platform** — same behaviour on Android and web, no platform channel):

```json
{ "format": "moneyledger-backup-encrypted", "version": 1,
  "kdf": { "name": "argon2id", "memory_kib": 32768, "iterations": 3,
           "parallelism": 1, "salt": "<b64 16 B>" },
  "cipher": { "name": "aes-256-gcm", "nonce": "<b64 12 B>" },
  "ciphertext": "<b64 ciphertext ‖ 16-byte tag>" }
```

The plaintext is the normal backup JSON; the header (key-sorted JSON of
format/version/kdf/cipher) is the AES-GCM associated data, so changing a
parameter fails like a wrong passphrase. Parameters are read from the file
(bounded: ≤ 256 MiB, ≤ 16 passes, ≤ 8 lanes — a crafted file can't make us
allocate gigabytes), so the defaults (`BackupKdfParams.standard`) can be
raised later without breaking old files. Measured (encrypt, incl. KDF):
0.8 s Pixel 4a, 1.1 s emulator, 0.4 s desktop AOT, ≈ 2.1 s dart2js (node);
decrypt is the same cost (logcat `[backup] encrypted in N ms`). Import:
`isEncryptedBackup` → `unlockEncryptedBackup` (passphrase prompt; a wrong one —
or a tampered file, GCM can't tell — → "Wrong passphrase … try again", loop
until cancel) → `decryptBackup` → `parseBackup`. Key derivation runs behind a
modal progress dialog (`DartArgon2id` yields to the event loop). Test seams:
`backupKdfParamsProvider` (cheap params), `backupDecrypterProvider`,
`backupFilePickerProvider`.

### Backup (CSV export/import — Phase D, G13)

A group can be exported to a **single human-readable CSV** and imported back
(sharing / spreadsheets / migrating old room-era groups — the lossless backup
is the JSON above). `lib/features/backup/`: the codec `ledger_csv.dart` is pure
Dart (models + strings, no DB/Flutter, fully unit-testable); `csv_export.dart`
is the Drift-read seam; `csv_import.dart` (`CsvImporter`) is the preview +
merge; `backup_files.dart` wraps `file_picker` (manual-smoke only, like the SSO
deep link). **Export** is on the expenses screen, **import** on the groups
screen.

**Format** — one row per **non-deleted** expense, then one per **non-deleted
payment** (settlement). Spreadsheet columns first, then a **decimal share
column per participant** (header = display name), then trailing machine
columns that drive the merge:

```
Date, Type, Description, Category, Note, Currency, Amount, Paid By, <Participant A>, <Participant B>, …, Expense ID, Group, Group ID, Updated At
2026-06-13T…, Expense, Dinner, food, Tip incl., EUR, 42.00, Alex, 21.00, 21.00, …, <uuid>, Trip, <gid>, 1760000050000
2026-06-14T…, Payment, Payment, , , EUR, 21.00, Sam, 21.00, , …, <uuid>, Trip, <gid>, 1760000090000
```

**G16:** `Category` (the stable English wire id) and `Note` follow
`Description` (empty when unset and for payments). A CSV without them
(pre-G16) imports with no category / note; older parsers ignore them (they sit
before `Paid By`, outside the share columns).

A **payment row** reads like an expense the payer covered entirely for the
recipient: `Paid By` = from, the recipient's share column = the amount (so the
sheet's per-person sums still match the balances); its settlement id sits in
`Expense ID`. On import a `Payment` row with exactly one share becomes a
settlement (else it is imported as an expense). A CSV **without** a `Type`
column (pre-G13) is all expenses.

Amounts are **decimal** in the sheet (`cents/100`, 2 dp) but **integer cents**
everywhere else. The parser locates fixed columns by header name and treats any
column between `Paid By` and `Expense ID` as a participant share column, so
extra/missing optional columns are tolerated.

**Import** first shows a **preview** (`CsvImporter.preview` →
`CsvImportPreviewDialog`): new vs. existing group, expense / payment counts,
and warnings for names that match **no** participant of an existing group
(→ a new local person will be created) or **several** (→ the active one, else
the first, is used). Both preview and import resolve names with the pure
`resolveCsvNames`. **Merge** is idempotent: ensure the group by `Group ID`
(LWW-upsert meta, create if absent — a CSV with no id mints a UUIDv7), resolve
participants **by display name**, then **LWW-upsert each expense / settlement
by id** using `Updated At` as the clock (clamped to now — a far-future clock
would win every later edit). Re-importing never duplicates; merging
into a live group lets the newer copy win. **G18 review:** the import is
**all-or-nothing** (one transaction): a money cell that isn't a finite,
non-negative amount (`1,234.56` / `12,50` grouping is tolerated, `12,34.5`
isn't) or a row breaking the record rules (`expenseProblem` /
`settlementProblem`, e.g. shares not summing to the amount) aborts it with a
`CsvImportException` ("Row N: …") and nothing is written. **G6:** the CSV has no signatures —
every row that **wins** (new or newer than local) becomes a version signed by
**the importing device** (as editor; new records also as creator, "added
by"); rows that don't win are counted but never re-signed.

**Documented limitations** (acceptable for a human-readable export):
tombstones are **not** in the sheet — a deleted record simply isn't exported
(so it won't re-delete on a peer via CSV). Participant identity is **by name,
not stable id** — a name collision merges two people and a rename splits one.
Use the full JSON backup for a lossless copy.

### Categories, notes, search, archive (G16)

- **Categories** (`models/expense_category.dart`): a fixed set of 10 —
  `food`, `groceries`, `transport`, `accommodation`, `entertainment`,
  `shopping`, `home`, `health`, `travel`, `other` — stable English **wire
  ids** (never translated; labels `category*` in the ARBs). An unknown id from
  a newer peer is kept verbatim (it's signed) and shown as *Other*. UI
  (`expense_category_ui.dart`): Material icon + colours from the
  `LedgerColors` avatar palette (light/dark, contrast already pinned), the
  `CategoryIconTile` replaces the receipt icon in the ledger list, and the
  add/edit form has a horizontally scrolling `CategoryPicker` (choice chips;
  tap the selected one → none). `suggestCategory(description)` is a small
  EN+DE keyword heuristic (word-start stems, ≤ 4-letter stems whole-word
  only) that **prefills** the chip for new expenses until the user picks one
  — never on edit.
- **Notes**: optional free text (form limit `kMaxNoteLength` = 500; trimmed,
  blank → none via `normalizeNote`; inbound notes are kept as signed). Shown
  on the edit form; the list marks a note with a small icon after the title.
- **Wire / storage:** optional `category` / `note` on the expense payload,
  in the signed content and the G27 hash **only when set** (absent = none;
  `""` normalises to none on parse — `ExpenseModel` never holds `""`). Drift
  **schema v7**: nullable `expenses.category` / `expenses.note`. The v6 → v7
  migration also deletes `rejected_versions` rows of kind `expense`: a
  pre-G16 build refuses signed versions that carry the new fields (its
  rebuilt body lacks them), so after the update they must be re-requested
  (the digest no longer lists them as refused → peers re-send → verified).
  Mixed old/new devices disagree until all are updated (open point).
  Bootstraps, the JSON backup (bootstrap payloads) and the CSV carry them.
- **Search / filter** (`expense_filter.dart`, pure; `ledgerSearchProvider`
  per group, auto-disposed with the page): 🔍 in the group app bar swaps the
  title for a search field (description, note, payer name; case- and
  Latin-accent-insensitive; payments match their two names or "Payment") and
  shows filter chips — *Involving me* (I paid / share / am a side of the
  payment) and the categories the group uses (any of; payments never match a
  category). While searching, the summary card and FAB are hidden and an
  "N entries" line / *Nothing found* + *Clear filters* is shown.
- **Settle-up explanation:** suggested payments were already per currency
  (`calculateDebts` simplifies each currency on its own). The balance page
  adds an ⓘ on each *Suggested payments* header (dialog "Simplified debts":
  fewest payments, nets unchanged, never converted) and, with several
  currencies, a "settled separately per currency" note.
- **Archive** (device-local, per account — a personal view preference, not
  synced): ⋮ → *Archive group* (always allowed; an unsettled group gets
  "your open balance still counts in the totals" in the snackbar, which has
  *Undo*) → back to the groups list, where archived groups sit in a collapsed
  **Archived (N)** section at the bottom. Inside an archived group a banner +
  the ⋮ item offer *Unarchive*. Stored as `AppSettings`
  `archived_group:<id>` = `{at, fp}` (`GroupArchive`), where `fp` is
  `ledgerFingerprint` — SHA-256 over every expense / payment `id@updated_at`
  incl. tombstones. **Any new / edited / deleted record un-archives the group
  automatically** (`groupArchivedProvider` derives it: entry present and
  fingerprint unchanged; nothing is written on the inbound path, so this also
  works for background-sync arrivals) — a new expense in a hidden group is
  usually a new debt and must not stay out of sight. Member / name changes
  don't count. The totals card still counts archived groups (an open balance
  stays real). Leaving / deleting a group drops its archive entry
  (`purgeGroupAsLeft`). Widget tests: the archive stream is overridden in
  `signingUiOverrides(archives:)` / `testOverrides(archives:)` (drift stream
  timers would outlive the test tree).
- **Out of scope:** receipt photos (no media channel — `docs/open-points.md`).

### Settlements / recording payments (G28)

Any **active** member may record a payment between **any two participants**
(Splitwise-style), incl. local persons: every debt row on the balance page is
tappable (dialog prefilled debtor → creditor, the debt amount + currency;
amount editable, warns if it exceeds the debt), and the app-bar *Record
payment* action opens the same `RecordPaymentDialog` with from/to pickers
(active participants), amount and currency (default: group currency). Removed
(read-only, G26) → no recording. Wire/replication unchanged (a settlement's
`from`/`to` were always arbitrary participant ids). Expenses likewise carry
their own currency (G29 picker on the add/edit form, default = group
currency; balances are per currency).

### Custom splits (Phase E)

An expense can be divided **unequally**. The split is already a
`{participantId: cents}` map *everywhere* (DB `splitsJson`, wire `split`, balance
calc, CSV) — so custom splits is a **UI + split-math feature, not a protocol
change.** Only the add/edit form changed.

- **`split_calculator.dart`** (pure Dart, no Flutter/DB): `splitEqually`,
  `splitByShares`, `splitByPercent` all route through one `distributeByWeights`
  **largest-remainder** core — floor each share, then hand leftover cents to the
  largest fractional remainders (ties broken by insertion order — an explicit
  index tie-breaker, Dart's sort isn't stable beyond 32 elements). Every mode
  **sums to the total exactly** (this also fixed the old equal-split cent loss,
  where `round()` per person could drop a cent on e.g. 100¢ ÷ 3). Also
  `isEqualSplit(map)` (edit-mode inference) and `remainingForExact`.
- **`split_editor.dart`** — the `SplitEditor` widget: a `SegmentedButton` with
  four modes (**Equal** + per-person include checkboxes · **Exact** amounts ·
  **Shares**/integer weights · **Percent**), live per-person previews and a
  status line. It surfaces an immutable **`SplitPlan`** (mode + raw inputs) via
  `onPlanChanged`; the **parent (`AddExpensePage`) resolves it against the live
  amount** on demand — so editing the amount never strands a stale split, and no
  `didUpdateWidget` round-trip is needed.
- **Persistence is cents-only** — only the resolved map is stored; the mode and
  raw inputs (weights/percents) are **not** persisted. On **edit** the opening
  mode is inferred: `isEqualSplit` → Equal, otherwise Exact prefilled with the
  stored cents (a shares/percent expense thus reopens as exact amounts — same
  result, different knobs). **Excluded participants are absent from the map**
  (not stored as `0`); the editor's included set on edit = the map's keys.
- **Out of scope:** itemised receipts, per-item assignment, tax/tip lines,
  saving a default split per group; settlements remain split-free.

### Localization (G12)

The UI is **English + German**, following the device locale with English as the
fallback (`preferred-supported-locales: [en]` in `l10n.yaml`). Strings live in
`lib/l10n/app_en.arb` (template, with `@key` descriptions/placeholders) and
`lib/l10n/app_de.arb`; `flutter gen-l10n` (also run by `pub get`/`run`/`build`
via `generate: true`) writes `lib/l10n/app_localizations*.dart`, which are
**committed** (no synthetic package) so analyze/test need no extra step.

- **Never hard-code a user-visible string** (Text, tooltip, label, hint,
  snackbar, dialog, error message) — add a key to **both** ARB files, run
  `flutter gen-l10n`, use `context.l10n.key` (`import '…/core/l10n/l10n.dart'`).
  Plurals/placeholders use ICU syntax (`{count, plural, =1{…} other{…}}`) with
  an explicit `placeholders` type. German: informal "du", terms *Gruppe,
  Ausgabe, Zahlung, Saldo, Mitglied, ehemalige Mitglieder, Synchronisiert*.
  `test/about_page_test.dart` checks both ARBs have the same keys/placeholders.
- **Pure helpers return structure, not text**, or take an `AppLocalizations`
  parameter (`describeAuthError` → `AuthErrorMessage.title(l)/hint(l)`,
  `unsettledWarning(debts, me, l)`, `deviceTrustSummary(devices, l)`,
  `registrationRequirementLabel(stage, l)`). Unit tests use `en`/`de` from
  `test/helpers/l10n.dart` (`lookupAppLocalizations`).
- **Amounts/dates:** `context.money(cents, currency)` (`€1,234.50` /
  `1.234,50 €`, always 2 decimals) and `context.date(ms)`; editable amount
  fields prefill with `formatAmountInput` and parse with `parseAmountCents`,
  which accepts `,` **and** `.` as decimal separator. G18 review: pass the UI
  `locale:` — a **lone** locale grouping separator followed by exactly 3
  digits is thousands (`de`: `1.234` = 1234; `en`: `1.234` stays 1.234,
  `1,234` = 1234); malformed grouping (`12,34.5`) is rejected. The amount
  fields show a live preview of the parsed value (`amountPreview`, "=
  1.234,00 €"), and only accept 1 cent … `kMaxAmountCents` (the expense
  form's *Add* and the payment dialog's *Record* stay disabled otherwise;
  `SplitPlan.resolve` is never valid for such a total). The **CSV stays machine
  format** (dot decimals, ISO dates, English headers) in every language.
- **Widget tests:** `testApp`/`testRouterApp` add the localization delegates
  (English by default, `locale: Locale('de')` for German tests); any other
  test `MaterialApp` needs `localizationsDelegates: testLocalizationsDelegates`.

### Design system (G17)

- **Tokens** live in `lib/core/theme/`: `app_theme.dart` (`AppTheme.light()` /
  `.dark()`, `ThemeMode.system`; component themes for cards, list tiles, FAB,
  inputs, buttons, segmented buttons, dialogs, sheets, snackbars; spacing
  `Insets`, radii `Radii`, `kContentMaxWidth` = 680, `kTabularFigures` for
  amounts; `AppTheme.cardColor`) and `app_colors.dart` (`BrandColors` — the
  teal seed `#0E7D6C`, logo gradient, launch backgrounds — and the
  **`LedgerColors` ThemeExtension**, read via `context.ledgerColors`).
  **Never hard-code `Colors.*`** in widgets — use the scheme or LedgerColors.
- **Semantic money colours:** `positive` (green — "you are owed", "you lent",
  "gets back") and `negative` (warm red-orange — "you owe", "you borrowed"),
  plus `*Container` variants; light and dark values are pinned to WCAG-AA
  contrast by `test/core/design_system_test.dart`.
- **Font:** Manrope (SIL OFL), bundled in `assets/fonts/manrope/` — never
  fetched at runtime (privacy); its license is registered in `main.dart`.
- **People:** always shown by `MemberModel.label` (display name → MXID
  localpart → raw id; `participantNamesProvider` uses it) with a
  `PersonAvatar` (`lib/core/widgets/person_avatar.dart`): colour from the
  **participant id** (FNV-1a, stable across renames/platforms), initials from
  the name (`initialsOf`; digit words of MXID localparts skipped). Lists use
  `AvatarStack`. A participant added by MXID (or a new group's creator) is
  named by the account's **Matrix profile display name**
  (`LedgerTransport.profileName`, never throws; fake: `FakeMatrixNetwork.profiles`),
  falling back to the localpart; `profileNameRefreshProvider` (watched by the
  groups page, once per account session) upgrades stored names that are still
  the bare localpart (LWW rename + relay, only in groups where we're active).
- **Shared widgets** (`lib/core/widgets/`): `ContentWidth` (centre + cap width
  on wide screens — wrap page content in it), `EmptyState`, `BrandLogo`,
  `NamesLine` (G33: a localized sentence whose **names ellipsize
  independently** — build the template with `NamesLine.sentinel(i)` in place
  of each name, e.g. settlement rows "A paid B", and the balance page's
  suggested payments "A pays B / You pay B / A pays you").
- **Lists under an extended FAB** pad their bottom with
  `Insets.fabClearance(context)` (88 dp + the system navigation inset — a
  ListView with explicit padding doesn't add it itself), never a fixed number.
- **Ledger rows** (G33) are two independent lines — *title … amount* and
  *payer … you lent/borrowed* — so a long (German) note never squeezes the
  title. The attribution footer ("Added by X · Last edited by Y") wraps
  between its parts, each ellipsized.
- **E2EE unavailable** (`vod.init()` threw in `main()`):
  `cryptoAvailableProvider` is overridden to `false` and the groups page shows
  a persistent banner (sync is off). A failed background-sync (un)registration
  lands in `backgroundSyncSchedulingErrorProvider` and is shown under the
  settings toggle.
- **Screens:** groups page = totals card (`balanceTotals`, owed and owing kept
  apart per currency) + `GroupCard`s (`groupOverviewProvider`: members, my
  balance via `netBalanceOf`, last activity); group page = summary card
  (*Settle up* → `recordPaymentFlow` from `features/balance/settle_up.dart`,
  prefilled by `settleUpSuggestion`; *Balances*) + day-grouped ledger
  (`context.dayHeader`: Today / Yesterday / weekday date) whose expense rows
  show `expenseEffectFor` ("you lent / you borrowed / not involved"); balance
  page = per-person nets (`netsFromDebts`) + tappable suggested payments; add
  expense keeps the submit button in a bar below the scrolling form (stays
  above the keyboard).
- **Brand assets:** `tool/brand/render_icons.py` (cairosvg) renders the split
  coin logo from one geometry into `assets/brand/*.svg`, the in-app
  `logo_512.png`, Android launcher icons (adaptive + monochrome), the pre-12
  splash logo, web favicon / PWA (+ maskable) icons and the iOS set. Launch
  backgrounds: `res/values{,-night}/colors.xml`, `values{,-night}-v31` styles.

### Key Implementation Notes

**Riverpod provider naming (3.x):** Class `AuthNotifier` → provider `authProvider` (not `authNotifierProvider`). The "Notifier" suffix is stripped. Class `ExpenseAdder` → `expenseAdderProvider`.

**Drift + Riverpod code-gen conflict:** Drift generates data classes (`Expense`, `Settlement`, `Group`) in part files. Riverpod's generator can't reference those types as provider return types in the same build phase. Solution: use plain model classes (`ExpenseModel`, `SettlementModel`, `GroupModel` in `lib/models/`) as the DAO layer's public API, and map from Drift types internally. **Never use Drift-generated data classes as return types of `@riverpod` providers.**

**`drift` + `matrix` SQLite compatibility:** `matrix` ≥ 9 and `drift` ≥ 2.32 / `drift_flutter` ≥ 0.3 all use **`sqlite3` 3.x** (G22) — upgrade them together (matrix 7 + drift ≤ 2.31 were the `sqlite3` 2.x pair). sqlite3 3.x loads SQLite via **build hooks**: no `sqlite3_flutter_libs` (EOL), no `DynamicLibrary`/`open.overrideForAll` in tests (`flutter test` bundles it), and on the web `web/sqlite3.wasm` must come from a 3.x-era release. `sqlite3` ≥ 3.6 needs `meta` ^1.19 (newer than Flutter 3.44 pins) → 3.5.x for now.

**Per-account DB (G4):** never open a database with a fixed name — always go
through `appDatabaseProvider` (per-account). Long-lived objects that use the DB
(engines, subscriptions, timers) must `ref.watch(appDatabaseProvider)` in their
provider and cancel everything in `onDispose`, or they will keep touching a
closed DB after an account switch. Tests that need persistence across a switch
override `accountDatabaseOpenerProvider` with temp-file `NativeDatabase`s keyed by
`accountDatabaseName` (see `test/features/per_account_database_test.dart`).
Riverpod 3 pauses unlistened providers — `listen` before awaiting a stream
provider's `.future` in a `ProviderContainer` test.

**Drift web setup:** `openNamedConnection(name)` passes `DriftWebOptions(sqlite3Wasm: Uri.parse('sqlite3.wasm'), driftWorker: Uri.parse('drift_worker.js'))` when `kIsWeb`. The two files in `web/` must not be deleted — they are not generated by the build and are not in `.gitignore`.

**Router pattern:** `routerProvider` is `keepAlive: true` and uses `refreshListenable` (a `ValueNotifier`, toggled) to rerun the redirect when `isLoggedInProvider` **or** `onboardingGateProvider` changes. Do **not** make it non-keepAlive — that recreates the `GoRouter` on every auth state change, which crashes at the default initial location `/`. `routerRedirect(isLoggedIn, OnboardingStatus, location)` is the pure, unit-tested seam: signed-out users reach only `/login` + `/register`; signed in, the one-time **onboarding** flag (`onboarding_seen` in the per-account `AppSettings`) is tri-state (G25, `OnboardingGate` in `onboarding_provider.dart`): **unknown** (DB/flag still loading, incl. reloading after an account switch) → neutral `/splash`; **notSeen** → forced `/onboarding`; **seen** → off auth pages / `/` / `/splash` / `/onboarding` to `/groups`. If the flag hasn't loaded after `kOnboardingFlagTimeout` (8 s) or the stream errors, the gate logs and latches *seen* for that account (never strands the user on the splash; a late "not seen" doesn't yank them to onboarding). The wiring is tested end-to-end in `test/core/router_provider_test.dart` (listen to `routerProvider` in a container test — unlistened providers are paused; don't `pumpAndSettle` on the splash, its spinner never settles).

**Errors in user actions (G15):** a user-initiated action that fails must
show it (snackbar `l.failedWithError` / `exportFailed` / `importFailed`, or
an error state) — never only `debugPrint`. Mutator notifiers expose the result
via `AsyncValue.guard` → read `.error` after awaiting, and only for the action
that actually ran. Background send failures go to `SyncHealth` (the
SyncEngine's repair / bootstrap answers use `_sendTracked`); malformed inbound
data is only logged (a peer must not flip our health). Never log SSO login
tokens (`redactSsoUri`). Text-prompt dialogs must own their
`TextEditingController` (`showTextPrompt`) — disposing it when `showDialog`
returns crashes the closing animation.

**Auth errors (G20):** login / SSO callback / register pages never show raw exception text. `MatrixAuthGateway` translates failures into plain port types (`auth_gateway.dart`): `AuthServerException(errcode, retryAfterMs)`, `AuthNetworkException(host, deviceOffline)` (on a transport error it probes matrix.org to tell "offline" from "server unreachable"), `NotAHomeserverException` (`checkHomeserver` failed with a non-network error). The pure `describeAuthError(error, action:)` (`features/auth/auth_errors.dart`; falls back to matching the error text) maps them to `AuthErrorMessage{title, hint, detail}`, rendered by `AuthErrorCard` with the raw text behind a collapsed **Details**. All English strings live in `AuthErrorStrings` (one place, for G12). **Timeouts (G30):** `checkHomeserver` is capped at `kHomeserverCheckTimeout` (10 s), login/register requests at `kAuthRequestTimeout` (20 s) via the pure `withAuthTimeout` → `AuthTimeoutException` (a `TimeoutException`, wrapped as `AuthNetworkException(deviceOffline: false)` without the offline probe) → "The server took too long to respond". The SDK call isn't cancelled — a late success still signs in (**adopted**, G36). **Single flight (G36):** `AuthSingleFlight` (`auth_gateway.dart`) wraps each login / token login / registration (`operation`) and every raw homeserver request inside it (`track`) in `MatrixAuthGateway`; while an operation **or a timed-out request** is still running, a new attempt throws `AuthInProgressException` → "Still signing in…" (`AuthErrorKind.inProgress`) instead of starting a parallel `client.login` (two devices / session race). `FakeAuthGateway` uses the same guard (`pendingRequest`, `requestTimeout`, `requestsStarted`); tests: `test/features/auth_single_flight_test.dart`. Web sign-up fallback: `RegistrationRequiresWebException.signUpUrl` comes from the pure `resolveSignUpUrl` (`sign_up_url.dart`): OIDC auth metadata (MAS with `prompt=create` → `<issuer>register`, else `account_management_uri`) → `.well-known` `org.matrix.msc2965.authentication.account` → matrix.org: `app.element.io/#/register` → homeserver URL.

**Async work vs. account switch / dispose (G19):** on an account switch Riverpod 3 closes the old ledger DB **eagerly** (when `appDatabaseProvider` rebuilds), but dependents like `SyncEngine`/`LedgerSyncer` are only disposed on the next scheduler flush — so in-flight async work can outlive both its DB and its `Ref`. Rules: (1) capture the DB + DAOs (and transport/health notifier) **before the first await** — `SyncEngine`/`LedgerSyncer` read them in their constructor, `ExpenseAdder` via `_WriteContext`, the group mutators (`GroupCreator`/`MemberAdder`/`MemberRemover`/`GroupExiter`) via `_GroupWriteContext` (G23) — never re-read DAO providers after an await; (2) after **every** await check `_alive` (`!_disposed && !_db.isClosed`; `AppDatabase.isClosed` is set by `close()`) and bail silently; (3) in notifiers, only set `state` / use `ref` after an await when `ref.mounted`; (4) errors caught after the DB closed are expected — don't log them or report them to `SyncHealth` (its `report*` also no-op when unmounted). Regression tests: `test/integration/account_switch_sync_test.dart`, `test/features/group_mutators_lifecycle_test.dart`.

**Timeouts/backoff in tests (G15):** production timers that a test must
observe come from an injectable `TimerFactory` provider
(`lib/core/timer_factory.dart`; `selfRecoveryTimerFactoryProvider`,
`onboardingTimerFactoryProvider`) — tests fire them with `ManualTimers`
(`test/helpers/manual_timers.dart`) instead of short real timeouts. Pure
timer/stream code can use `fakeAsync` (dev dep `fake_async`). In widget tests,
wait for a Drift write with `eventually(condition, tester: tester)`
(`test/helpers/eventually.dart`, inside `tester.runAsync`) — never a fixed
`Future.delayed(50 ms)`.

**Widget tests with a real in-memory DB (G33):** a Drift *watch* stream
never settles under the widget-test fake clock (`pumpAndSettle` hangs, its
timers outlive the tree). A page test that overrides `appDatabaseProvider`
with a real `AppDatabase.forTesting(...)` must still give the DB-watching
providers the page shell reads static values — `ledgerGroupsProvider`,
`groupArchivesProvider`, the G6 signature streams: spread
`...realDbWidgetOverrides(groups: [...])` (`test/helpers/test_providers.dart`)
and override what the test is about (members, expenses, …) yourself
(example: `test/group_exit_test.dart`).

**Deterministic sync tests:** never wait with a fixed sleep. `FakeMatrixNetwork.settle()` waits until the relay is quiescent (N consecutive 2 ms ticks with no send/delivery — load-independent because pending microtasks and earlier-due timers like the 1 ms poke debounce always run first). Teardown: dispose the `ProviderContainer` **before** closing its DB.

**Testing without Matrix imports:** The `matrix` SDK pulls in native sqlite3 which can cause issues in test processes. Keep test files free of `package:matrix` imports. Extract testable logic from classes that use Matrix types as `@visibleForTesting` static methods that accept plain Dart types (maps, strings, ints). See `LedgerSyncer.processExpense` for the pattern.

**Matrix SDK (14.x) API:**
- G22 upgrade 7.2.2 → 14.0.0 needed **no app code changes** (all APIs below unchanged). The SDK store migrates v11 → v12 on first start (device-key boxes merged into one `deviceKeysLists` box; Olm account/sessions kept) — verified on both test devices: still signed in, sync + signatures + SAS intact. **Before a future SDK major**, check `MatrixSdkDatabase._migrateFromVersion`: anything beyond `clearCache()` that drops the client box / Olm sessions would force a re-login.
- `Client(name, database: db)` — database is required in constructor (not a builder callback)
- `MatrixSdkDatabase.init(name, database: openedDb, sqfliteFactory: databaseFactory)` — on **native you MUST pass an already-opened sqflite `Database`** via `database:` (open it with `sqflite.openDatabase(path)` first). `sqfliteFactory` alone is **not** enough: `BoxCollection` throws `You must provide a Database 'sqfliteDatabase' for use on native` (the factory is only used for high-level ops like delete). On web, call `MatrixSdkDatabase.init(name)` with no DB (it uses IndexedDB). See `buildMatrixClient()` in `lib/core/matrix/matrix_service.dart`.
- **Sync loop robustness (G36):** `buildMatrixClient` passes `httpClient: RequestTimeoutHttpClient(http.Client())` — every request must deliver response **headers** within `kHttpHeaderTimeout` (90 s). The SDK's own `FixedTimeoutHttpClient` (35 s) only times the body, so a request on a socket that died in a network switch could hang a sync round (to-device queue, key queries) until the OS gave up. `matrixClientProvider` also starts a `MatrixSyncWatchdog` (every 30 s + on app resume; pure policy `syncWatchdogDecision` in `core/sync/sync_watchdog_policy.dart`): signed in but no round pending → `client.backgroundSync = true`; a round pending with no finished/failed status for 2 min → logged (`[watchdog]`). **Never `abortSync()` + restart** while an old round can still complete: its `whenComplete` clears `_currentSync` and re-arms → two loops that drop each other's responses. The SDK loop itself retries errors every 3 s and caps the long-poll at 40 s; four emulator network switches (wifi/data off ≤ 3 min, wifi ↔ data) recovered without help.
- `client.init(waitForFirstSync: false)` — **always pass `false`.** The default `true` makes `init()` block on the first network `/sync` when a session is restored, which hangs app startup indefinitely on a stalled sync. Drift is the local source of truth; sync runs in the background.
- **Roomless to-device** is the only transport (no rooms). See `MatrixLedgerTransport` (`lib/core/matrix/matrix_ledger_transport.dart`):
  - `client.onToDeviceEvent.stream` — inbound encrypted to-device events; filter by the `com.moneyledger.*` type prefix. It is **not buffered** (an event emitted with no subscriber is lost until the next digest), so `matrixClientProvider` calls `MatrixLedgerTransport.forClient(client)` (one transport per client, via `Expando`) **before `client.init()`**: it subscribes immediately and feeds a `BufferedInbox`, which holds payloads while nobody listens (app start, account-DB switch; bounded 500, per-account tagged) and replays them to the next listeners after a short delay. `transport_provider` reuses the same instance.
  - `client.updateUserDeviceKeys(additionalUsers: targets)` before each send — roomless device lists aren't persisted (the SDK evicts device keys for users you share no encrypted room with), so re-resolve every time (cheap, idempotent).
  - `client.sendToDeviceEncryptedChunked(devices, type, content)` — encrypts + sends to every target device; your own current device is auto-excluded, and other devices of the sender **do** receive (the fake relay mirrors this). It **returns silently** when `!client.encryptionEnabled` or no device remains — so the adapter checks `isLogged()`/`encryptionEnabled` first (→ `TransportUnavailableException`) and picks devices via the pure `planDeviceSend`, returning a `SendResult`. The fake (`FakeMatrixNetwork(bufferInbound:)`, `FakeTransport.unavailable`, `removeDevice`, `sent` log) simulates both cases.

### Data Model & wire protocol (v2)

Expenses and settlements use **UUIDv7** IDs. All amounts are **integer cents** to avoid float errors. Every to-device payload carries `"v": 2` (protocol version; v2 = G6 signed records — v1 code never read `v`, so the bump is additive) and a `"group": "<groupId>"`. Record payloads carry a `created_at`, an `updated_at` LWW clock (ms epoch), and a `deleted` tombstone flag. Receivers apply **whole-record LWW** on `updated_at`, ties broken by the content hash (G27). The codec lives in `lib/core/sync/ledger_payloads.dart`; event type constants in `lib/core/matrix/ledger_transport.dart`.

**`com.moneyledger.expense`** (settlement analogous). Edit = full re-send with a higher `updated_at`; delete = same with `deleted: true`. Every version carries `sig` (its editor's device signature); expenses/settlements also `origin` (the creator's, unchanged across edits) — see "Signed records (G6)":
```json
{
  "v": 2,
  "id": "<uuidv7>",
  "group": "<groupId>",
  "description": "Dinner",
  "amount": 4200,
  "currency": "EUR",
  "paid_by": "@alice:matrix.org",
  "split": { "@alice:matrix.org": 2100, "@bob:matrix.org": 2100 },
  "created_at": 1760000000000,
  "updated_at": 1760000050000,
  "deleted": false,
  "category": "food",
  "note": "Tip included",
  "origin": { "user": "@alice:matrix.org", "device": "AAAA", "key": "<b64 ed25519>", "sig": "<b64>" },
  "sig":    { "user": "@bob:matrix.org",   "device": "BBBB", "key": "<b64 ed25519>", "sig": "<b64>" }
}
```

`paid_by` and the `split` keys are **participant ids** (see Participant identity above), not necessarily MXIDs. `category` (a G16 wire id) and `note` are **optional** — omitted when unset, signed and hashed only when present (see "Categories, notes, search, archive (G16)").

**`com.moneyledger.settlement`** content: `{ "v", "id", "group", "amount", "currency", "from", "to", "created_at", "updated_at", "deleted", "origin", "sig" }` (`from`/`to` are participant ids).

**`com.moneyledger.member`** (participant) content: `{ "v", "group", "participant_id", "name", "matrix_id", "status", "updated_at", "sig" }` — `matrix_id` is null for a local participant. (`user` is the pre-virtual-users key, still read on the receiver for forward-compat.) **`com.moneyledger.group`** (meta): `{ "v", "group", "name", "currency", "updated_at", "sig" }`.

**`com.moneyledger.digest`** (anti-entropy) — sent per group to all claimed members *including self*. Maps are `id → "<updated_at>:<hash8>"` (G27; a bare int = clock only), **tombstones included**; `meta_hash` is the meta's hash8; the `members` map (keyed by participant id) doubles as membership/identity gossip — each entry is the full **signed** member version (verified like a member payload). `rejected` (optional, G6) lists versions the sender refused (`{expenses: {id: T}, settlements: {…}, members: {pid: T}, meta: T}`) so peers don't re-send them. A `reply: false` digest is answered once with `reply: true` (bounded two-message exchange):
```json
{
  "v": 2,
  "group": "<groupId>",
  "reply": false,
  "meta_updated_at": 1760000000000,
  "meta_hash": "1f0c9a3e",
  "members": { "<participantId>": {"status": "active", "updated_at": 1759990000000, "name": "Alex", "matrix_id": "@alice:x.org", "sig": {"user": "…", "device": "…", "key": "…", "sig": "…"}} },
  "expenses":    { "<uuid>": "1760000050000:a1b2c3d4" },
  "settlements": { "<uuid>": "1759995000000:0f9e8d7c" },
  "rejected":    { "expenses": { "<uuid>": 1760000090000 } }
}
```

**Bucketed digest (G14)** — when the flat digest exceeds the payload budget: same header plus `"bucket_bits": n`, `"buckets": ["<hash12>" | "", …]` (2^n entries, one per bucket; `""` = empty), `"detail": [bucket indices]`, and `expenses` / `settlements` holding only the entries of those buckets. A third message of an exchange carries `"final": true` (never answered). See "Message size (G14)" above and `SyncEngine` rule 9.

**`com.moneyledger.resync_request`** — `{ "v": 2, "scope": "group", "group": "<groupId>" }` or `{ "v": 2, "scope": "all" }`. Handler replies with `bootstrap` payload(s) only if the requester is an active member of that group, or is the responder's own MXID (`scope: all` honored only for self — new-device recovery).

**`com.moneyledger.bootstrap`** — whole-group snapshot (group meta + members + expenses + settlements), each record with `updated_at`/`deleted` and its signatures, **tombstones included** (so a stale device can't keep a live copy of a deleted record). `meta` is the signed group-meta payload (top-level `name`/`currency`/`updated_at` mirror it); `device_keys` (`{user: {device: key}}`) attests the signers' keys the sender pinned first-hand. Rows still `pending_sign` are left out. Each record is verified on its own; an unknown group is only created if its meta verifies. Sent when adding a member and in response to a `resync_request`. **G14:** over the payload budget it is sent as several self-contained parts (`"part": i, "parts": n`, each with meta + all members + `device_keys` + a slice of the records).

The receiver rules for digests (targeted repair, membership gossip, reply bounding, sync-status marking, unknown-group/removed-sender handling) are documented in full on `SyncEngine` (`lib/core/sync/sync_engine.dart`).
