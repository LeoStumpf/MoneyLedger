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
- [`matrix`](https://pub.dev/packages/matrix) 7.x — Matrix protocol: auth, room management, event sync
- [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod) 3.x + `riverpod_annotation` 4.x — state management (code-gen style)
- [`drift`](https://pub.dev/packages/drift) 2.x + `drift_flutter` — type-safe SQLite ORM for local ledger state
- [`go_router`](https://pub.dev/packages/go_router) — navigation
- [`uuid`](https://pub.dev/packages/uuid) — UUIDv7 generation for expense IDs
- [`sqflite`](https://pub.dev/packages/sqflite) — required by the matrix SDK's internal SQLite store
- `flutter_localizations` + [`intl`](https://pub.dev/packages/intl) — EN/DE UI strings (ARB) + locale formatting (G12)
- [`package_info_plus`](https://pub.dev/packages/package_info_plus) — app version on the About page

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

Android E2EE: `flutter_vodozemac` (**≥ 0.6.0** — older versions break on Gradle 9 / compileSdk < 36) compiles the vodozemac Rust crate during the Gradle build via cargokit, so Android builds need `rustup` (**stable** toolchain) with targets `aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android`. No pub-cache patches are needed (0.5.0 required hand-patches; don't downgrade). Web uses the prebuilt wasm committed in `web/pkg/` (no Rust needed).

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
        settings_dao.dart      # AppSettings KV — local flags (onboarding-seen, left-group tombstones, per account); never synced
    matrix/
      ledger_transport.dart       # LedgerTransport port + TransportMessage + event-type constants
                                  #   + SendResult, TransportUnavailableException, pure planDeviceSend
      matrix_ledger_transport.dart # Real adapter — encrypted to-device send/receive (forClient)
      buffered_inbox.dart         # BufferedInbox: holds inbound payloads while nobody listens, replays
    sync/
      ledger_payloads.dart     # Plain-Dart payload codec (protocol v1) + bootstrap builder
      sync_engine.dart         # Anti-entropy: digest exchange + targeted repair + resync
      left_groups.dart         # LeftGroupTombstone + pure classifyPeerViewOfMe (G9 leave/delete)
      sync_status_provider.dart # groupSyncStatusProvider — drives the cloud icons
      peer_convergence.dart    # G29 fast in-sync proof from an inbound record (pure)
  models/
    expense_model.dart         # Plain Dart models (ExpenseModel, SettlementModel)
    group_model.dart           # Plain Dart model (GroupModel)
    member_model.dart          # MemberModel; sync_state_model.dart (PeerSyncStateModel)
  features/
    auth/                      # Matrix login, in-app registration, session mgmt
                               #   register_flows.dart: pure UIA-flow classifier; register_page.dart
                               #   auth_errors.dart: pure friendly-error mapper (G20) + auth_error_card.dart
                               #   sign_up_url.dart: pure web sign-up URL resolution
    groups/                    # Group list + create (local-only groups, member add/remove)
                               #   GroupExiter (leave/delete, G9) + group_exit_dialog.dart
    expenses/                  # Expense list, add/edit/delete, ledger sync
      ledger_syncer.dart       # LedgerSyncer: subscribes to to-device onMessage → writes to Drift
                               # Static @visibleForTesting methods for unit-testable event processing
      split_calculator.dart    # Pure-Dart split math (largest-remainder) — see "Custom splits"
      split_editor.dart        # SplitEditor widget: Equal/Exact/Shares/% modes → SplitPlan
    balance/
      balance_calculator.dart  # Pure function: List<Expense> + settlements → List<DebtEntry>
      balance_provider.dart    # Riverpod: watches Drift streams, recomputes on change
      record_payment_dialog.dart # G28 "X paid Y" dialog (any two participants)
    backup/                    # CSV export/import (Phase D) — see "Backup (CSV)" below
      ledger_csv.dart          # Pure-Dart RFC4180 codec: buildGroupCsv / parseGroupCsv
      csv_export.dart          # DB → CSV seam (buildGroupCsvForExport) + csvFileName
      csv_import.dart          # CsvImporter: LWW merge-by-id back into Drift
      csv_files.dart           # file_picker glue (web download / native save+pick)
    onboarding/                # First-run intro (OnboardingPage) + onboarding_seen flag
    devices/                   # Device list + SAS verification UI (DevicesPage)
    about/                     # AboutPage (version, source, AGPL, licenses) + PrivacyPolicyPage
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
| Group participant | `Members` row — a stable participant id + `displayName` + optional `matrixId` (the "claim"); `active`/`removed` status, LWW |
| Expense / settlement | `Expenses` / `Settlements` rows (LWW clock + tombstone) |
| Sync / transport | Encrypted **to-device** messages via `LedgerTransport` |
| Replication log | The Drift DB itself — digests drive anti-entropy |

Authentication is pure Matrix — no separate auth system. Users connect to their own homeserver (self-hosted, matrix.org, etc.). The single transport seam is `LedgerTransport` (real adapter `MatrixLedgerTransport`); fakes back all tests. Login (password + SSO) and **in-app registration** go through `AuthGateway` (`auth_provider.dart`'s `AuthNotifier`).

**Registration (Phase F).** `RegisterPage` → `AuthGateway.register`. The real adapter attempts `client.register`, and on a UIA challenge classifies the flows with the pure `register_flows.dart`: a flow needing only `m.login.dummy` is completed in-app; anything requiring a CAPTCHA / email / phone / terms / token throws `RegistrationRequiresWebException` (with friendly labels) and the page shows a **web-registration fallback**; so does an `M_FORBIDDEN` with no UIA flows (`isClientRegistrationDisabled` — e.g. matrix.org, whose sign-up moved to MAS/OIDC) (we don't reimplement every UIA stage). `/register` is reachable while signed out (see `routerRedirect`).

**Device verification (Phase F).** `DeviceGateway` (`core/matrix/device_gateway.dart`, matrix-free port; real adapter `matrix_device_gateway.dart`) lists the user's own devices and runs an SAS (emoji) verification. `DevicesPage` (`/devices`, from the groups app bar) shows each device's verified status and an emoji-compare dialog driven by a `VerificationSession` stream. **MVP scope: visibility + manual verification only — not enforced** (replication still reaches unverified devices). The pure view-model (`DeviceInfo`, `sortDevices`, `deviceTrustSummary`) is unit-tested; the SDK SAS round-trip needs a second real device + olm and is **manual-smoke** (like the SSO deep link). The real adapter imports `package:matrix/matrix.dart` **`hide DeviceInfo`** (the SDK exports a same-named type) plus `package:matrix/encryption.dart` (for `KeyVerification`).

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
rename). The legacy DB is left in place (never re-adopted). Failures are logged
and retried on the next open.

### Data Flow

Inbound to-device message → `LedgerSyncer._onMessage` → **membership gate** →
DAO LWW upsert → Drift stream providers → UI rebuild. Local writes are
**local-first**: persisted to Drift immediately, then best-effort replicated to
members (`_replicate`). Drift is the **local source of truth** — the UI always
reads Drift streams, never Matrix in-memory state.

**Membership gate (Phase F).** To-device messages are E2EE, so `msg.senderId` is
authenticated. `LedgerSyncer.isSenderAuthorized` (pure, `@visibleForTesting`)
drops any record whose sender isn't an active member of the target group:
expense/settlement/group-meta require an active claimed member; a `bootstrap` for
an **unknown** group is TOFU-accepted (else member-only); a `member` payload from
a non-member is allowed only as a **self-claim/join** for the sender's own MXID
and never hijacks a participant another account owns. Inbound `updated_at` is
clamped to `now + 5 min` (`clampInboundClock`) to bound clock-skew LWW wins. Not
yet covered: per-record cryptographic authorship (a member can still forge
another member's record) — see `docs/open-points.md`.

**Leaving / deleting a group (G9).** The expenses app bar's overflow menu (⋮,
next to *Export CSV*) offers **Leave group** when this account is an active
participant and another claimed account is active (`groupExitKind`), else
**Delete group** (solo / local-only group, or we're no longer active). The
confirmation warns (non-blocking) if our balance isn't settled and offers the
CSV export. `GroupExiter.leave` marks our participant `removed` (LWW) and relays
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
  side (register first, check second; unanswered = stale mapping, removed). The
  app claims its slot in `main()` **before** opening anything
  (`prepareBackgroundSync`) and asks a running round to `stop` (it aborts and
  closes its stores, bounded wait). A round that finds the app alive doesn't
  touch the stores: it asks the app to `sync` (one `oneShotSync` in the app's
  client) and keeps the process awake meanwhile.
- Setting: per account, device-local `AppSettings` `background_sync_enabled`
  (default on), *Settings* sheet (gear) on the groups page;
  `backgroundSyncSchedulingProvider` (watched by `LedgerSyncHost`) registers /
  cancels the OS task (cancel on sign-out). The round re-checks the flag.
- The app manifest removes the plugin's `POST_NOTIFICATIONS` permission (no
  expedited / foreground workers). Web/iOS: no background sync.
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

### Backup (CSV export/import — Phase D)

A group can be exported to a **single human-readable CSV** and imported back
(backup / sharing / migrating old room-era groups). `lib/features/backup/`:
the codec `ledger_csv.dart` is pure Dart (models + strings, no DB/Flutter, fully
unit-testable); `csv_export.dart` is the Drift-read seam; `csv_import.dart`
(`CsvImporter`) is the merge; `csv_files.dart` wraps `file_picker` (manual-smoke
only, like the SSO deep link). **Export** is on the expenses screen, **import**
on the groups screen.

**Format** — one row per **non-deleted** expense. Spreadsheet columns first, then
a **decimal share column per participant** (header = display name), then trailing
machine columns that drive the merge:

```
Date, Description, Currency, Amount, Paid By, <Participant A>, <Participant B>, …, Expense ID, Group, Group ID, Updated At
2026-06-13T…, Dinner, EUR, 42.00, Alex, 21.00, 21.00, …, <uuid>, Trip, <gid>, 1760000050000
```

Amounts are **decimal** in the sheet (`cents/100`, 2 dp) but **integer cents**
everywhere else. The parser locates fixed columns by header name and treats any
column between `Paid By` and `Expense ID` as a participant share column, so
extra/missing optional columns are tolerated.

**Merge** is idempotent: ensure the group by `Group ID` (LWW-upsert meta, create
if absent — a CSV with no id mints a UUIDv7), resolve participants **by display
name** (unknown name → new local participant), then **LWW-upsert each expense by
`Expense ID`** using `Updated At` as the clock. Re-importing a backup never
duplicates; merging into a live group lets the newer copy win.

**Documented limitations** (acceptable for a human-readable backup): settlements
and tombstones are **not** in the sheet — balances reconstruct from expenses
only, and a deleted expense simply isn't exported (so it won't re-delete on a
peer via CSV). Participant identity is **by name, not stable id** — a name
collision merges two people and a rename splits one. A future full-fidelity
format could add settlements, tombstones, and id-based identity.

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
  largest fractional remainders (deterministic by insertion order). Every mode
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
  which accepts `,` **and** `.` as decimal separator. The **CSV stays machine
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
  on wide screens — wrap page content in it), `EmptyState`, `BrandLogo`.
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

**`drift` + `matrix` SQLite compatibility:** Use `drift ^2.31` and `drift_flutter ^0.2.8` — these depend on `sqlite3 ^2.x` which aligns with the matrix SDK's requirement. Avoid upgrading drift to 2.32+ without checking; that version switches to `sqlite3 ^3.x` which conflicts with matrix and breaks test compilation.

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

**Auth errors (G20):** login / SSO callback / register pages never show raw exception text. `MatrixAuthGateway` translates failures into plain port types (`auth_gateway.dart`): `AuthServerException(errcode, retryAfterMs)`, `AuthNetworkException(host, deviceOffline)` (on a transport error it probes matrix.org to tell "offline" from "server unreachable"), `NotAHomeserverException` (`checkHomeserver` failed with a non-network error). The pure `describeAuthError(error, action:)` (`features/auth/auth_errors.dart`; falls back to matching the error text) maps them to `AuthErrorMessage{title, hint, detail}`, rendered by `AuthErrorCard` with the raw text behind a collapsed **Details**. All English strings live in `AuthErrorStrings` (one place, for G12). **Timeouts (G30):** `checkHomeserver` is capped at `kHomeserverCheckTimeout` (10 s), login/register requests at `kAuthRequestTimeout` (20 s) via the pure `withAuthTimeout` → `AuthTimeoutException` (a `TimeoutException`, wrapped as `AuthNetworkException(deviceOffline: false)` without the offline probe) → "The server took too long to respond". The SDK call isn't cancelled — a late success still signs in. Web sign-up fallback: `RegistrationRequiresWebException.signUpUrl` comes from the pure `resolveSignUpUrl` (`sign_up_url.dart`): OIDC auth metadata (MAS with `prompt=create` → `<issuer>register`, else `account_management_uri`) → `.well-known` `org.matrix.msc2965.authentication.account` → matrix.org: `app.element.io/#/register` → homeserver URL.

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

**Deterministic sync tests:** never wait with a fixed sleep. `FakeMatrixNetwork.settle()` waits until the relay is quiescent (N consecutive 2 ms ticks with no send/delivery — load-independent because pending microtasks and earlier-due timers like the 1 ms poke debounce always run first). Teardown: dispose the `ProviderContainer` **before** closing its DB.

**Testing without Matrix imports:** The `matrix` SDK pulls in native sqlite3 which can cause issues in test processes. Keep test files free of `package:matrix` imports. Extract testable logic from classes that use Matrix types as `@visibleForTesting` static methods that accept plain Dart types (maps, strings, ints). See `LedgerSyncer.processExpense` for the pattern.

**Matrix SDK (7.x) API:**
- `Client(name, database: db)` — database is required in constructor (not a builder callback)
- `MatrixSdkDatabase.init(name, database: openedDb, sqfliteFactory: databaseFactory)` — on **native you MUST pass an already-opened sqflite `Database`** via `database:` (open it with `sqflite.openDatabase(path)` first). `sqfliteFactory` alone is **not** enough: `BoxCollection` throws `You must provide a Database 'sqfliteDatabase' for use on native` (the factory is only used for high-level ops like delete). On web, call `MatrixSdkDatabase.init(name)` with no DB (it uses IndexedDB). See `buildMatrixClient()` in `lib/core/matrix/matrix_service.dart`.
- `client.init(waitForFirstSync: false)` — **always pass `false`.** The default `true` makes `init()` block on the first network `/sync` when a session is restored, which hangs app startup indefinitely on a stalled sync. Drift is the local source of truth; sync runs in the background.
- **Roomless to-device** is the only transport (no rooms). See `MatrixLedgerTransport` (`lib/core/matrix/matrix_ledger_transport.dart`):
  - `client.onToDeviceEvent.stream` — inbound encrypted to-device events; filter by the `com.moneyledger.*` type prefix. It is **not buffered** (an event emitted with no subscriber is lost until the next digest), so `matrixClientProvider` calls `MatrixLedgerTransport.forClient(client)` (one transport per client, via `Expando`) **before `client.init()`**: it subscribes immediately and feeds a `BufferedInbox`, which holds payloads while nobody listens (app start, account-DB switch; bounded 500, per-account tagged) and replays them to the next listeners after a short delay. `transport_provider` reuses the same instance.
  - `client.updateUserDeviceKeys(additionalUsers: targets)` before each send — roomless device lists aren't persisted (the SDK evicts device keys for users you share no encrypted room with), so re-resolve every time (cheap, idempotent).
  - `client.sendToDeviceEncryptedChunked(devices, type, content)` — encrypts + sends to every target device; your own current device is auto-excluded, and other devices of the sender **do** receive (the fake relay mirrors this). It **returns silently** when `!client.encryptionEnabled` or no device remains — so the adapter checks `isLogged()`/`encryptionEnabled` first (→ `TransportUnavailableException`) and picks devices via the pure `planDeviceSend`, returning a `SendResult`. The fake (`FakeMatrixNetwork(bufferInbound:)`, `FakeTransport.unavailable`, `removeDevice`, `sent` log) simulates both cases.

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

`paid_by` and the `split` keys are **participant ids** (see Participant identity above), not necessarily MXIDs.

**`com.moneyledger.settlement`** content: `{ "v", "id", "group", "amount", "currency", "from", "to", "created_at", "updated_at", "deleted" }` (`from`/`to` are participant ids).

**`com.moneyledger.member`** (participant) content: `{ "v", "group", "participant_id", "name", "matrix_id", "status", "updated_at" }` — `matrix_id` is null for a local participant. (`user` is the pre-virtual-users key, still read on the receiver for forward-compat.)

**`com.moneyledger.digest`** (anti-entropy) — sent per group to all claimed members *including self*. Maps are `id → updated_at`, **tombstones included**; the `members` map (keyed by participant id) doubles as membership/identity gossip. A `reply: false` digest is answered once with `reply: true` (bounded two-message exchange):
```json
{
  "v": 1,
  "group": "<groupId>",
  "reply": false,
  "meta_updated_at": 1760000000000,
  "members": { "<participantId>": {"status": "active", "updated_at": 1759990000000, "name": "Alex", "matrix_id": "@alice:x.org"} },
  "expenses":    { "<uuid>": 1760000050000 },
  "settlements": { "<uuid>": 1759995000000 }
}
```

**`com.moneyledger.resync_request`** — `{ "v": 1, "scope": "group", "group": "<groupId>" }` or `{ "v": 1, "scope": "all" }`. Handler replies with `bootstrap` payload(s) only if the requester is an active member of that group, or is the responder's own MXID (`scope: all` honored only for self — new-device recovery).

**`com.moneyledger.bootstrap`** — whole-group snapshot (group meta + members + expenses + settlements), each record with `updated_at`/`deleted`, **tombstones included** (so a stale device can't keep a live copy of a deleted record). Sent when adding a member and in response to a `resync_request`.

The receiver rules for digests (targeted repair, membership gossip, reply bounding, sync-status marking, unknown-group/removed-sender handling) are documented in full on `SyncEngine` (`lib/core/sync/sync_engine.dart`).
