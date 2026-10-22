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
- [`share_plus`](https://pub.dev/packages/share_plus) 13.x (BSD-3) — system share sheet (G69 balance text; G52 invite sheet), via `core/platform/text_sharer.dart`
- [`qr`](https://pub.dev/packages/qr) 3.0 (BSD-3) — G52 invite QR code (pure-Dart encoder, painted by `core/widgets/qr_code_view.dart`)
- [`image_picker`](https://pub.dev/packages/image_picker) 1.2 (BSD-3) — G78 receipt photo (Android only): camera app via intent / system photo picker, scaled natively
- [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications) 22.x (BSD-3) — G72 change notifications from the Android background round (no push / Firebase)
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

The script runs in order: `flutter pub get` → `dart run build_runner build` → `dart format --output=none --set-exit-if-changed lib test` → `flutter test` → `flutter build web --release --no-web-resources-cdn` → `tool/web/check_web_build.sh`. It exits non-zero on the first failure, so a green run means codegen, formatting, all tests, and the release build all passed.

**Formatting:** the repo is `dart format`ted (lib/ + test/, generated files included — the generators emit formatted code). Run `dart format lib test` before committing; build.sh and CI fail on unformatted code.

To override the Flutter binary: `FLUTTER=/path/to/flutter ./build.sh`

Output lands in `build/web/`.

**Web build without CDNs (G43):** the privacy promise is that the app talks
only to Matrix homeservers (plus link groups' Nostr relays and — only on tap —
G73's exchange-rate service), so the web build loads nothing from Google:
- **Always** `flutter build web --release --no-web-resources-cdn` (build.sh, CI)
  → CanvasKit from `build/web/canvaskit/` (`"useLocalCanvasKit":true` in the
  built `flutter_bootstrap.js`); without the flag it comes from
  `www.gstatic.com/flutter-canvaskit/<engine rev>/`.
- **Fonts:** the engine fetches its default Roboto and Noto fallback fonts
  from `fontFallbackBaseUrl` (default `https://fonts.gstatic.com/s/`).
  `web/flutter_bootstrap.js` (custom; keeps the service-worker settings) sets
  it to `fonts/` on our origin and `web/fonts/roboto/v32/KFOm….woff2` is
  Roboto Regular at exactly the engine's path. Glyphs Roboto lacks come from
  two **web-only assets** (`platforms: [web]` in pubspec, so the APK ships
  neither) registered by `loadWebOnlyFonts()` (`core/theme/web_fonts.dart`,
  awaited in `main()` before `runApp`) and used as the theme's
  `fontFamilyFallback` on the web only (`AppTheme.light(isWeb:)`): `SasEmoji`
  (the 64 SAS emoji, Noto Color Emoji subset, OFL) and `AppSymbols` (arrows,
  "⋮", ✓ … — DejaVu Sans subset). Anything else (most emoji, CJK, …) shows as
  boxes on the web, and the engine asks our origin for a Noto file (404,
  retried on each layout) — see `docs/open-points.md`. **Never declare a
  `Roboto` font family in pubspec** — Android would then use it instead of
  the system font.
- Font files come from `tool/fonts/make_web_fonts.py` (fontTools; committed).
  `tool/web/check_web_build.sh build/web` fails if CanvasKit would come from
  the CDN, the bootstrap lost `fontFallbackBaseUrl`, or the engine's Roboto
  path (a string in `main.dart.js`, it changes with Flutter upgrades) has no
  file under `build/web/fonts/` — then re-run the script with
  `--roboto-path <new path>`. Remaining `gstatic` strings in `flutter.js` /
  `main.dart.js` are the dead defaults of those two settings.
- `flutter run -d web-server` (dev) still uses the CDN unless you pass
  `--no-web-resources-cdn` too.

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
`seedDemoLedger` (4 groups — one archived —, EUR/CHF, custom splits, payments, dates relative
to now, all peers in sync; screenshot extras: a G47 custom category
"Souvenirs" used by an expense, a back-dated expense (G49) and payment (G60),
and a back-filled G48 version history — `_seedHistory`: every record's
versions with `recorded_at` = its clock, Anna's writes `local`, the rest
`inbound`, incl. one edited and one deleted expense — so the reset page has
restore points), device prefs in memory (welcome seen — G39). G79: the
settings show the **real platform's** texts (store screenshots): the
background-sync toggle on Android (`backgroundSyncSupportedProvider` = the
platform value, scheduler a no-op) and restore points kept **in memory**
(`demoSnapshotStores()`: one `InMemorySnapshotStore` per DB name on native,
none on the web) — never the web's "only in the installed app" texts.
**G52 step 11:** a 5th group, *Climbing gym* (`kDemoLinkGroupId`), is a
**link group** — unsigned, `by` hints, Anna = participant
`demo-person-anna` (no claim), a `link_channels` row (random secret, "me",
a seeded publish) and two `link_peers` whose digest equals ours
(`_seedLinkChannel`), so the invite sheet shows a QR and the sync sheet
"has everything"; `linkSyncEnabledProvider` is **false** (no relay is ever
contacted, also in tests), no NIP-11 fetcher, `OfflineRelayConnector` (every
connect fails — the not-started engine still serves *Reset invite link* /
*Sync now*, and a reset would otherwise subscribe + publish), and
`linkGroupSyncStatusProvider` is derived from the channel (synced). No
Matrix client is ever built. (Separate from the real local mode, G40.) Normal builds
tree-shake it (`const bool.fromEnvironment`). Never import `test/` from `lib/`.
Smoke test: `test/core/demo_mode_test.dart`. Used for README/store screenshots.

Manual smoke checklist (real devices, real homeserver): `docs/smoke-test.md` —
update its "Last run" table after a device pass.

Android app id (G38): **`io.github.leostumpf.moneyledger`** (namespace +
applicationId; permanent once on Play — never change it). Release notes:
`docs/release-notes.md` (incl. the Play "What's new" texts).

Android release signing: `android/app/build.gradle.kts` signs `release` with the upload keystore (`~/moneyledger-upload-keystore.jks`) configured via the gitignored `android/key.properties`; without that file it falls back to the debug key. Never commit `key.properties` or keystores — see README "Release signing".

Android backup (G32): `android:allowBackup="false"`, `fullBackupContent="false"` and
`res/xml/data_extraction_rules.xml` (cloud backup + device transfer exclude every
domain) — the app data holds the ledger DBs and the Matrix session incl. crypto
keys. Pinned by `test/core/android_manifest_test.dart`; PRIVACY.md + the in-app
privacy text say so.

F-Droid (G44): `android { dependenciesInfo { includeInApk = false;
includeInBundle = false } }` — no AGP encrypted dependency blob in the APK /
bundle (pinned in `test/core/android_manifest_test.dart`). The About page
shows the license as `AGPL-3.0-or-later` (`kAppLicense`).

**Release logging (G44):** release builds log nothing of ours —
`silenceDebugPrintInRelease()` (`lib/core/logging.dart`) replaces `debugPrint`
with a no-op under `kReleaseMode`, called first in `main()` **and** in
`backgroundSyncDispatcher` (own isolate, own `debugPrint`); `buildMatrixClient`
sets the SDK's `Logs().level = Level.wtf` in release (the SDK `print`s, not
`debugPrint`; there is no "off"). Our logs name MXIDs / homeservers / group
ids. Debug and profile builds keep logging, so the `adb logcat` workflow
(`[bg]`, `[g6]`, `[watchdog]` …) needs a debug (or profile) build. Always log
via `debugPrint`, never `print`.

## Commands

```bash
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0   # dev web server
flutter run -d android               # run on a connected Android device/emulator
flutter devices                      # list available run targets
flutter test --reporter compact      # run all tests (exit 0 = green)
flutter test test/foo_test.dart      # run a single test file
flutter build apk                    # Android release build
flutter build web --release --no-web-resources-cdn   # web build (no CDN — G43)
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
    widgets/         # shared widgets (incl. text_prompt_dialog.dart: one-field prompt owning its controller;
                     #   currency_field.dart: G66 CurrencyField + searchable picker sheet, deviceRegionProvider)
    theme/           # G17 design tokens: app_theme.dart, app_colors.dart (LedgerColors),
                     #   web_fonts.dart (G43 web-only fallback fonts + their licenses)
    widgets/         # G17 PersonAvatar/AvatarStack, ContentWidth, EmptyState, BrandLogo
    router.dart      # go_router + routerRedirect() pure function (generated: router.g.dart)
    session/         # G39/G40: who uses the app — device_prefs.dart (device-wide flags: welcome seen,
                     #   local profile, connect/adoption state; file / localStorage store),
                     #   app_session.dart (kLocalAccountId, localModeActive, ledgerIdentity, appSession,
                     #   welcomeStatus), local_transport.dart (LocalOnlyTransport), local_adoption.dart
    l10n/
      l10n.dart        # context.l10n / context.money() / context.date() + re-exports
      formatting.dart  # pure intl helpers: formatMoney, formatDate, parseAmountCents (`,`/`.`)
      currencies.dart  # G66: ISO-4217 list, display decimals / split step, region default, picker order + search
      currency_names.dart # G66 GENERATED (tool/currencies/make_currency_names.py): code → (EN, DE) name
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
        history_dao.dart       # G48: record_history (version history) — append helper, HistorySource, prune, floor
        link_dao.dart          # G52: LinkChannels (link secret, per-group Nostr key, my participant, publish state) + LinkPeers (per-part event dedup); device-local, never logged
        settings_dao.dart      # AppSettings KV — local flags (onboarding-seen, left-group tombstones, G16 archive, G52 link relays + relay state, per account); never synced
    link/                      # G52 link groups: link_uri, link_keys (HKDF), link_envelope (gzip + AES-GCM),
                               #   link_snapshot (sharding, digest), group_policy, link_channel (open),
                               #   link_relay_policy, link_sync_engine; nostr/ (events, frames, relay pool,
                               #   WebSocket adapter, nip09, nip11)
    matrix/
      record_crypto.dart          # G6 ports: RecordCrypto (sign/verify), DeviceKeyDirectory, SignerId
      hmac_record_crypto.dart     # G6 fake device keys (HMAC stand-in) for tests + offline demo
      ledger_transport.dart       # LedgerTransport port + TransportMessage + event-type constants
                                  #   + SendResult, TransportUnavailableException, pure planDeviceSend
      sync_filter.dart            # G45 minimal /sync filter + presence + filter-id marker (matrix-free)
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
      pending_signer.dart      # G6/G40: signPendingRows — signs pendingSign rows (engine + local adoption)
  models/
    expense_model.dart         # Plain Dart models (ExpenseModel, SettlementModel)
    group_model.dart           # Plain Dart model (GroupModel)
    member_model.dart          # MemberModel; sync_state_model.dart (PeerSyncStateModel)
    expense_category.dart      # G16: ExpenseCategory (stable wire ids), suggestCategory heuristic, normalizeNote
    expense_date.dart          # G49/G60: ISO day helpers, storedExpenseDate, recordDateProblem, displayDay (expense + payment)
                               # G47: CustomCategory, resolveCategory, kCustomCategoryIcons, bounds
    exchange_rates.dart        # G73: ExchangeRates (signed meta), rate strings, convertCents
    link_model.dart            # G52: LinkChannelModel (toString omits the secrets) + LinkPeerModel
    group_archive.dart         # G16: GroupArchive (device-local) + ledgerFingerprint
  features/
    auth/                      # Matrix login, in-app registration, session mgmt
                               #   register_flows.dart: pure UIA-flow classifier; register_page.dart
                               #   auth_errors.dart: pure friendly-error mapper (G20) + auth_error_card.dart
                               #   sign_up_url.dart: pure web sign-up URL resolution
    groups/                    # Group list + create (local-only groups, people chips — G64; add/remove people)
                               #   GroupExiter (leave/delete, G9) + group_exit_dialog.dart
                               #   group_archive_provider.dart: G16 archive (groupArchived, GroupArchiver)
                               #   group_settings_page.dart: G65 group settings (/groups/:id/settings)
                               #   group_actions.dart: G65 shared flows (edit, archive, backup, CSV, leave/delete)
                               #   group_categories_page.dart: G47 custom categories (add / rename / hide)
                               #   group_rates_page.dart: G73 exchange rates + settle switch + RateDialog
    expenses/                  # Expense list, add/edit/delete, ledger sync
      ledger_syncer.dart       # LedgerSyncer: subscribes to to-device onMessage → writes to Drift
                               # Static @visibleForTesting methods for unit-testable event processing
      split_calculator.dart    # Pure-Dart split math (largest-remainder) — see "Custom splits"
      split_editor.dart        # SplitEditor widget: Equal/Exact/Shares/% modes → SplitPlan
      item_split_page.dart     # G77 ItemSplitPage: split a receipt item by item → Exact amounts
      record_date_field.dart   # G49/G60 RecordDateField: Date field + Today/Yesterday chips (expense form + payment dialog)
      expense_category_ui.dart # G16: category icon / colours / label, CategoryIconTile, CategoryPicker
                               # (G47: dropdown-style selector + showCategoryDialog, custom icon keys)
      expense_filter.dart      # G16: pure LedgerFilter + expenseMatches / settlementMatches
      ledger_search_provider.dart # G16: per-group search state (null = search bar closed)
    balance/
      balance_calculator.dart  # Pure function: List<Expense> + settlements → List<DebtEntry>
      balance_share.dart       # G69 pure "who pays whom" share text
      group_stats.dart         # G69 pure overview stats (total, paid vs. share, categories)
      balance_provider.dart    # Riverpod: watches Drift streams, recomputes on change
      settle_currency.dart     # G73 pure ledgerForSettling (convert into the base currency)
      exchange_rate_fetcher.dart # G73 Fetch current rate (Frankfurter, only on tap)
      record_payment_dialog.dart # G28 "X paid Y" dialog (any two participants)
    backup/                    # Full JSON backup (G5) + CSV export/import (Phase D, G13) — see "Backup" below
      ledger_backup.dart       # Pure-Dart backup codec (buildBackupJson / parseBackup) + nudge logic + file names
      backup_crypto.dart       # G34: optional passphrase encryption (Argon2id + AES-256-GCM wrapper)
      backup_service.dart      # BackupService: export all groups / preview / restore (DB seam)
      backup_providers.dart    # last-backup + nudge providers (backupNudgeProvider)
      backup_ui.dart           # settings-page tile, export / restore flows, restore + CSV preview dialogs, nudge card
      backup_restore_page.dart # G70 /backup: decision aid + backup file / restore points / reset one group
      ledger_csv.dart          # Pure-Dart RFC4180 codec: buildGroupCsv / parseGroupCsv
      csv_export.dart          # DB → CSV seam (buildGroupCsvForExport) + csvFileName
      csv_import.dart          # CsvImporter: preview + LWW merge-by-id back into Drift; resolveCsvNames
      backup_files.dart        # file_picker glue (save dialog / browser download + pick)
    welcome/                   # G39 WelcomePage: first-open explanation + choices; revisit = "How it works"
                               #   G54 why_matrix_page.dart (/why-matrix) + why_matrix_hint.dart (one-time card)
    local/                     # G40 LocalSetupPage (name), local_mode_ui.dart (chip, sheet, settings, delete)
    onboarding/                # Post-login / local-start intro (OnboardingPage) + onboarding_seen flag
    history/                   # G48 restore points: group_history.dart (pure: change batches + reset plan),
                               #   group_reset.dart (GroupResetService), group_reset_page.dart,
                               #   restore_points.dart (daily maintenance, snapshots), snapshot_policy.dart (pure
                               #   rotation), snapshot_store*.dart (native files / none on web), restore_points_page.dart
    payment/                   # G74 own payment details (device-local): payment_details.dart (pure: IBAN / BIC /
                               #   PayPal.me parsing, EPC GiroCode payload, PayPal.me link), _provider, _page
                               #   (/settings/payment), payment_request_sheet.dart (balance page QR sheet)
    receipts/                  # G78 receipt photo (Android, this device only): receipt_store*.dart (files /
                               #   none), receipt_picker.dart (image_picker seam), receipt_field.dart (form + viewer)
    devices/                   # Device list + SAS verification UI (DevicesPage, member device sheet,
                               #   IncomingVerificationListener) — G11
    about/                     # AboutPage (version, source, AGPL, licenses) + PrivacyPolicyPage
    settings/                  # G65 SettingsPage (/settings): account, sync, advanced (Matrix), backup, data, about, debug
    web/                       # G75 (U31) web_limits.dart: one-time web limits notice + About entry
    link/                      # G52 step 6 link_invite.dart: invite state, disclosure page, invite sheet, flow
                               #   step 9 relay_settings{,_page}.dart: Settings → Relays (/settings/relays)
    sync/                      # G68 group_sync_sheet.dart (tappable sync icon + per-person sheet, Sync now),
                               #   peer_sync_rows.dart (pure rows: Matrix proofs / link publishers)
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

**Login page requests (G43).** Opening `/login` contacts **no** server — not
even the prefilled `matrix.org` (welcome → Sign in, signed-out starts,
connect-from-local-mode). `LoginPage._lookupInput` is null until the user
acts: edits the server field (600 ms debounce), presses Enter / the
*Check server* arrow (`checkServerBtn`), leaves the field after editing it,
types a full MXID in the username field, or taps *Sign in* / SSO (which look
the flows up first via `_flowsForEnteredServer`, then log in on the resolved
URL; an SSO-only server → no password attempt, the form switches to its SSO
buttons). Until then the optimistic form (generic SSO + password) is shown.
`RegisterPage` sends nothing before *Create account*. Pinned by
`test/features/login_no_requests_test.dart` (`FakeAuthGateway.loginFlowsRequests`).

**Device verification (Phase F + G11).** `DeviceGateway` (`core/matrix/device_gateway.dart`, matrix-free port; real adapter `matrix_device_gateway.dart`) lists the user's own devices **and (G11) another member's** (`userDevices`), runs an SAS (emoji) verification **over to-device messages** — with our own other devices and with another member's device alike (no rooms needed) — and streams **incoming** requests (`incomingVerifications`, answered app-wide by `IncomingVerificationListener` in `App`'s builder: "Accept / Decline" → the same emoji dialog). The client must advertise `verificationMethods: {emoji, numbers}` (`buildMatrixClient`) — without it the SDK ignores every request (it was missing before G11, so SAS never worked). `askSSSS` (account has cross-signing from another client, keys not cached) is skipped automatically: the app does no cross-signing. `DevicesPage` (`/devices`) shows own devices (G56: opened from the settings page's *Devices & security* tile — no groups app-bar icon any more); the **members page** shows — **only while verified-only sync is on** (G46: otherwise it's technical noise) — a subtle "N unverified devices" line under a member (red "Not reachable — no verified device" when none is verified) and ⋮ → *Devices* opens their device list with *Verify*. The real adapter imports `package:matrix/matrix.dart` **`hide DeviceInfo`** plus `package:matrix/encryption.dart`. **SAS emoji names (G36)** are localized: `SasEmoji.number` (the SDK's `KeyVerificationEmoji.number`, 0–63) → `sasEmojiName(number, languageCode)` from `features/devices/sas_emoji_names.dart`, an EN+DE table generated once from the Matrix spec's `data-definitions/sas-emoji.json` (Apache-2.0 — THIRD_PARTY_NOTICES + an in-app license entry in `main.dart`); unknown number → the SDK's English name.
- **The app keeps its own verified-device record** (`AppSettings` `verified_device:<mxid>|<device>` → Ed25519 key, per account, device-local; `SettingsDao.markDeviceVerified`, written by `recordingTrust` on SAS success whether or not the dialog is still open). Reason: in a roomless app the SDK evicts other users' device lists from memory on every `updateUserDeviceKeys` that doesn't name them and re-stores them with `verified: false` — a peer's SAS result would not survive. "Verified" = SDK flag **or** our record for the exact (user, device, **current key**) (`isDeviceTrusted`; a changed key voids it). Own devices: the SDK flag persists too.
- **Opt-in enforcement (G11): "Only sync with verified devices"** (settings page, per account, device-local `verified_only_sync`, default **off**; turning it on asks first and explains). Every app sender — `LedgerWriteContext` / `_GroupWriteContext` / `SyncEngine` (replication, member bootstraps, digests, resync answers) — wraps the transport in `PolicyTransport` (`core/sync/delivery_policy.dart`) built from the **same** account DB it writes to; each send reads `SettingsDao.deliveryPolicy()` (fails closed if unreadable) and passes it to `sendToUsers(…, policy:)` → pure `planDeviceSend` withholds unverified devices (own and peers'). `SendResult.unverifiedUsers` (⊆ `unreachableUsers`: has devices, none verified) feeds `SyncHealthState.unverifiedPeers`; the cloud tooltip (`pendingPeerHint`) says "X has no verified device" instead of "Waiting for X". Withholding is not a failure. **Inbound is not refused** when the setting is on: refusals in G6 are permanent (`rejected_versions`) and would not heal after verifying later, and a member's legitimate new device would silently lose edits; the setting is about where *our* data goes. The record details dialog shows "You (haven't) verified this device" for the signing device of others (`signerVerifiedByMe`). Limits: only what *this* device sends is restricted — a peer's own devices still sync among themselves unless the peer turns it on too; a new own device can't self-restore from a device with the setting on until verified. **G36:** the settings subtitle and the confirm dialog say exactly that ("only limits what this device sends", "a new login of yours can't restore … until you verify it").
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
`MembersDao.activeClaimedMatrixIds` (valid MXIDs only — G18 review 2); "who am I in this group" is
`currentParticipant` (the participant whose `matrixId` is this device's MXID —
in local mode the pseudo account `kLocalAccountId`, see "Local mode (G40)");
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
**G40:** `appDatabaseProvider` actually watches `ledgerIdentityProvider` (the
MXID, or `kLocalAccountId` in local mode → `money_ledger_local` via
`localDatabaseOpenerProvider`; never collides with `money_ledger_<16 hex>`).

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

### Welcome (G39)

A first-time user sees the **welcome before anything else** (`WelcomePage`,
`/welcome`): four swipeable explanation pages — what MoneyLedger does
(Splitwise/Tricount-style), free + open source (AGPL, repo link) with no
MoneyLedger server, **G54:** *Share a group with a link* (relays, encrypted,
anyone with the link) and *Want more security? Matrix* (what Matrix is, who
sees what, *Why Matrix?* button) — then the choices in G54 order: **Start
without an account** (primary, `/local-setup`, G40), **Join with an invite
link** (`/join`), and under a *Secure mode* heading **Sign in with Matrix**
(`/login`) / **Create a Matrix account** (`/register`). Illustrations:
`BrandLogo` /
Material icons in a soft circle with three satellite icons (`WelcomeHero`;
page dots `WelcomeDots`, excluded from semantics — the page label + Back /
Next are the accessible way). Any
choice sets the **device-wide** flag `welcome_seen` in `DevicePrefs`
(`lib/core/session/device_prefs.dart`): a tiny JSON map that works with no
ledger DB open — native `device_prefs.json` in the app support dir (temp file +
rename), web one `localStorage` entry (`device_prefs_store_{io,web}.dart`,
conditional export); no new dependency. `devicePrefsProvider` (AsyncNotifier)
loads it; an unreadable store → `DevicePrefs.unreadable` (welcome counts as
seen — never strands the user; logged). Tests: `devicePrefsStoreProvider` →
`InMemoryDevicePrefsStore` (`testOverrides` does it; `localProfile:` /
`connecting:` params put a widget test in local mode). Revisit mode
(`/how-it-works`, public page; `?topic=matrix` opens at a page): About →
*How MoneyLedger works*, login page → *What is Matrix?* — same pages, no
choices, *Done* pops. **Lazy Matrix client (G79):** while the welcome
isn't seen (no mode chosen) `matrixSessionWantedProvider` is false — no
Matrix client, so a fresh install creates no SDK store
(`money_ledger_matrix.sqlite`, `kMatrixStoreName`) — **unless** that store
already exists (`matrixStoreExistsProvider`, `core/matrix/store_probe/`:
native file check; web always false), so a session from before the welcome
still starts straight in (`appSessionProvider` stays `loading` → splash
while that check runs). *Sign in* / *Create account* on the welcome mark it
seen → the client is built then (the login page still sends nothing until
the user acts, G43). Tests: `test/core/lazy_matrix_client_test.dart`. The
post-login **onboarding** (per ledger DB, unchanged
gate) is slimmed to what's new: Matrix → invite people, background sync, keep
a copy; no account → groups you don't share stay here, invite with a link
(G54, replaces "share later"), keep a copy.

### "Why Matrix?" (G54)

A calm info page in the welcome style (design doc §10.2 / §10.3), no nag:
`WhyMatrixPage` (`features/welcome/why_matrix_page.dart`,
`kWhyMatrixLocation` = `/why-matrix`, a **public** page in `routerRedirect`).
Three swipe pages: *Links are easy* · *There's another mode* (four topics in
plain sentences, "Link: … / Matrix: …": who can see / change, removing
someone, new or lost phone, who sees what) · *Ready when you are* — the
action from the pure `whyMatrixOffer(session, infoOnly:)`: no account →
*Connect a Matrix account* (`startConnectAccount`, then `go('/login')` — the
page is public, so the router keeps it) / *Not now*; signed out → *Sign in*
/ *Create account* (marks the welcome seen) / *Not now*; Matrix → a hint
(groups shared by link: *Make group secure*) + *Done*; `infoOnly` (from the
link disclosure, which sits in front of an invite / join) → "later in the
settings" + *Done*. The ready text says link groups keep their link and
also sync over Matrix after connecting (G53 mixed). Entry points: group ⋮
*Why Matrix?* in a group with an open link (`whyMatrixMenuItem`), the
welcome's Matrix page (`welcomeWhyMatrix`, also in *How it works*), the
link disclosure (`linkDisclosureWhyMatrix`, pushed with `Navigator`), the
no-account sheet (`localSheetWhyMatrix`) and **once** a dismissible groups-page
card (`WhyMatrixHintCard`, `why_matrix_hint.dart`): pure
`shouldShowWhyMatrixHint` — **no account only** (local mode), not dismissed
(`AppSettings` `why_matrix_hint_dismissed`, per ledger,
`SettingsDao.watchWhyMatrixHintDismissed` / `dismissWhyMatrixHint`) and a
link group (`linkGroupIdsProvider`) with ≥ `kWhyMatrixHintMinRecords` (10)
live records (`GroupOverview.recordCount`); *Tell me more* and *Not now*
both dismiss it for good. Widget tests: `testOverrides(linkGroupIds:,
whyMatrixHintDismissed:)`. The local-mode chip reads **"No account"** /
*Kein Konto* (§8.2; text scale capped at 1.3 in the app bar, the groups
title drops the logo when narrow). Tests: `test/g54_why_matrix_test.dart`
(EN + DE, 360 dp / 200 %), `welcome_page_test.dart`, G71 guidelines.

### Local mode (G40)

**Use the app without any Matrix account.** `/local-setup` (`LocalSetupPage`)
asks for a name → `DevicePrefs.localProfile` `{name, created_at}`. While a
local profile is active (`localModeActiveProvider`, `app_session.dart`):
- **No Matrix at all:** `matrixSessionWantedProvider` is false →
  `isLoggedInProvider` / `accountUserIdProvider` return false / null **without
  reading `loginStateProvider`**, so `matrixClientProvider` is never built (also
  false while the prefs load). `ledgerTransportProvider` returns a
  `LocalOnlyTransport` (sends reach nothing, nothing arrives, `crypto.identity`
  null); `deviceGatewayProvider` throws (device lists = unavailable, no
  incoming verification); `SyncEngine` / `LedgerSyncer` return from `start()`
  for `kLocalAccountId` (no digests, no new-device resync); background sync is
  cancelled (`backgroundSyncSchedulingProvider`; G52 step 8: registered
  while a link group exists — link phase only) and the foreground
  `onSyncRequest` is a no-op. `vod.init()` still runs in `main()` (cheap; needed
  the moment an account is connected). `test/features/local_mode_test.dart`
  pins "no Matrix client / send / schedule".
- **"Me":** this device's identity is the reserved pseudo account
  **`kLocalAccountId` = `local:self`** (not an MXID — no `@` — so it never
  collides and every Matrix-only path skips it). The transport's `userId` is
  it, so `currentUserIdProvider`, `currentParticipant`, `claimedBy`,
  `groupExitKind` (→ always *Delete*), the backup nudge (every local group is
  unprotected) etc. work unchanged: the user's own participant in each local
  group is **claimed by `local:self`** with a fresh UUIDv7 participant id
  (`GroupCreator` / `_applyAdd`); `LocalOnlyTransport.profileName(local:self)`
  = the profile name. Other people are local participants.
- **Signing:** nothing can be signed → every local write is stored
  `pendingSign` immediately (`LocalRecordSigner` sees no identity); the
  attribution footer is hidden in local mode.
- **UI:** groups app bar shows the **"No account" chip** (G54, was "Local
  only"; `LocalModeChip` → sheet: unshared groups never leave the device,
  back up, connect an account, *Why Matrix?*) next to the
  settings gear; the settings page's *Account* section is
  `LocalModeSettingsSection` (name, *Connect a Matrix account*, *Delete local
  data*) instead of the Matrix account + *Sign out*, and it has no *Sync &
  devices* section (G65); no sync cloud on the group page; members page: no invite, name-only
  *Add person*, no devices / link / detach, self = "You (on this device)" +
  hint card; router sends `/devices` to `/groups`. Backup / CSV / restore work
  as usual (the backup's `account` is `local:self`).
- **Connect a Matrix account** (upgrade): `setConnecting(true)` (persisted, so a
  web SSO reload keeps it) → router allows only login / register / public
  pages (login page: close button = cancel, subtitle says the groups move) →
  **G18 review 2:** the trigger is derived from **state**, not the sign-in
  call — `localConnectGuardProvider` (kept alive by
  `localLedgerAdoptionProvider`): device prefs loaded + local profile +
  `connecting` + a signed-in MXID → `beginLocalAdoption(mxid,
  onlyWhileConnecting: true)` (local profile cleared + `adoptInto = mxid` in
  one write; `localModeActive` already flips false once the MXID is known).
  So a sign-in that finishes **late** (after the page's timeout — the SDK
  call isn't cancelled) or right before a crash (the connect flag is
  persisted, the session restored) is adopted too. Local profile **without**
  `connecting` (cancelled) + an auth gateway this run built → any session
  that exists or signs in later is **logged out** (it is the fresh device of
  that connect attempt; no Matrix session lives on in local mode).
  `localLedgerAdoptionProvider` (watched by `LedgerSyncHost`) then runs
  `adoptLocalLedger` (`local_adoption.dart`) once that account's DB is open:
  every row of the local DB is **LWW-merged** into the account DB (an account
  that already has groups merges, no duplicates; idempotent after a crash),
  the participant claimed by `local:self` becomes claimed by the MXID
  (`adoptedMember`, `nextLwwClock`), and the rows **local mode wrote**
  (stored `pendingSign`; G18 review 2: only those — a legacy row restored
  from a backup file stays unsigned) are **signed by the account's device**
  right away
  (`signPendingRows(originIfMissing: true)` — creation statements too, so
  "added by" works and peers never refuse them as unsigned; waits up to
  `localAdoptionKeyWaitProvider` = 30 s for the device key, else the sync
  engine signs before the first digest — without origin for edited rows; it
  holds off while `adoptInto` is this account, G18 review 2),
  archive entries + attested keys copied, then the **local DB is wiped**,
  `finishLocalAdoption(mxid)` (`lastAdoptedInto`), the local DB's files are
  deleted (G41, see below), a groups-page banner, and
  each adopted group is poked → the digest reaches our other devices (unknown
  group → resync → bootstrap). Inviting Matrix members afterwards = the normal
  G18 invite flow. Signing out later is the normal non-destructive logout.
- **Leave local mode:** settings → *Delete local data* (confirm with group
  count) → `AppDatabase.wipeAll()` + `endLocalProfile()` → **the welcome**
  (G46: `signedOutLandingProvider` = `welcome` is set first, `routerRedirect(
  landing:)` sends a signed-out device there instead of `/login`; the router
  resets it to `login` once a session is in again; a seen welcome opens on its
  choices, `WelcomePage(startAtChoices:)`). Starting
  local mode again (also after an adoption) starts with an empty ledger; the
  setup page says where earlier local groups went (`lastAdoptedInto`).
- **Local DB files (G41):** after *Delete local data* (`deleteLocalLedger`:
  wipe → end profile → `invalidate(appDatabaseProvider)` → await the close)
  and after a finished adoption (the adoption's own instance closed), the
  `money_ledger_local` files are deleted via `localDatabaseDeleterProvider`
  → `LocalLedgerFiles` (`account_database.dart`): it tracks every instance
  `openLocalDatabase` handed out, **refuses while one is still open**
  (logged, files kept), awaits each close, then `deleteDatabase` (native
  `.sqlite` + `-wal`/`-shm`/`-journal`; web: drift probe). An open during the
  deletion connects only after it (`AppDatabase.named(after:)` →
  `LazyDatabase`), so starting local mode again gets a fresh DB. Tests:
  `test/core/local_ledger_files_test.dart`, `local_mode_test.dart`.
- **Backups across the boundary (G41)** — `BackupService.restore`,
  `restoreTakeover(backup.account, me)`:
  - **G18 review 2 — a backup file is unauthenticated** (anyone can write a
    "local" one): this device signs restored rows **only** for a **truly
    local** group of a local-mode backup (`isOwnLocalGroup`: no participant
    claimed by a Matrix account in the file or already in the DB, nothing in
    the file signed). Any other group of a local backup is restored with its
    `local:self` claims dropped (`withoutLocalClaims`: a participant already
    here keeps its stored version, a new one becomes an unclaimed person) as
    unsigned legacy rows — never signed. Unsigned restored versions carry **no**
    `origin` (`RecordGate` — attribution never lies); `local:self`
    claims are refused unless `RecordGate.allowLocalClaims` (that truly local
    group). A normal restore (`RestoreTakeover.none`) never signs anything;
    local mode's own backup restored **in local mode** marks a truly local
    group's rows `pendingSign` (`markUnsignedPending` — they are local mode's
    own writes again, signed on connect).
  - a **local-mode backup** (`account` = `local:self`) restored into a Matrix
    account = the adoption above **for its truly local groups**, per group
    **inside the restore transaction**: `reclaimGroupInPlace(from:
    local:self, to: mxid, signLater: true)` (same `reclaimedMember` /
    `nextLwwClock` as `adoptedMember`; every unsigned row of that group →
    `pendingSign`), then after the transactions `signAdoptedGroups` (shared
    with `adoptLocalLedger`; `signPendingRows(originIfMissing: true)`, "added
    by" included). Key not ready → the sync engine signs before the first
    digest. The preview says so (`RestoreTakeover.localIntoAccount`,
    `restoreLocalIntoAccount`; no "other account" warning) and warns to
    restore only one's own file (`restoreLocalOwnFile`);
  - a **Matrix backup restored in local mode**: signatures are verified
    (`LocalOnlyTransport` verifies Ed25519 via `verifyEd25519` — no Matrix
    client needed; before G41 it refused every signature, so nothing was
    restored), then the participant claimed by the backup's account is
    re-claimed by `local:self` (`reclaimGroupInPlace(signLater: false,
    onlySignedClaims: true)` — G18 review 2: only a claim that account
    really signed; never a second "me": skipped when `local:self` already
    claims an active participant) — the user is "me" there; nothing is sent. *Connect a
    Matrix account* later adopts it back (same account → peers accept it;
    another account → peers ignore it as a non-member). Preview:
    `restoreAccountIntoLocal`;
  - a local backup in local mode / a Matrix backup into an account: unchanged.
  Tests: `test/features/local_backup_restore_test.dart`,
  `test/integration/security_review2_test.dart` (crafted backups, Major 1).

### Link-group policy (G52 step 4)

`GroupPolicy` (`lib/core/link/group_policy.dart`, `LinkDao.policyOf`):
a **signed** stored meta decides on its own (G53) — with `link` → `mixed`
(also before this device bridged), without → `matrix` (a Matrix group or a
**locked** one, `GroupPolicyInfo.lockedAt`); an unsigned / missing meta →
`linkOnly` with a device-local `link_channels` row, else `matrix`. Derived
from local state only — inbound data can't take a Matrix group off G6 (only
a member's verified signed meta opens / closes a link).
`linkOnly`: `SyncEngine` (digests, bootstraps, resync answers, rule 10),
`LedgerSyncer` (drops to-device records), `signPendingRows`,
`reclaimGroupInPlace` / `markUnsignedPending` skip it; `LocalRecordSigner(
policy:)` stores local writes unsigned + not `pendingSign` + no `origin`,
`linkAuthor` (`by`, unsigned / unhashed display hint, `link_author` column)
= `my_participant_id`, so nothing is relayed; Matrix claims / invites throw
`LinkOnlyGroupException`; `currentParticipant` falls back to the channel's
`my_participant_id` (active). `RecordGate(linkPolicy:)` = the link path:
unsigned accepted in `linkOnly` / `mixed` (stored without `origin`), signed
verified, content / wrong-group / future-clock / refused-version rules kept,
Matrix-ID claims refused in `linkOnly` (unsigned ones in `mixed`), unsigned
meta only in `linkOnly`; the Matrix path drops `by`. G40 adoption copies
`link_channels` / `link_peers` and keeps a link-only group unclaimed and
unsigned. Design doc §6.4 "As built"; tests `test/core/link_policy_test.dart`,
`test/integration/link_group_matrix_skip_test.dart`.

### Reset invite link (G52 step 12)

Invite sheet → *Reset invite link* (or group settings → People → `resetLinkTile`;
confirmation `linkResetDialog`) → `resetInviteLinkFlow` → `linkResetterProvider`
→ `LinkSyncEngine.resetLink`: the group's publishes / merges are held (in-flight
ones awaited), this device's copy is **unpublished** from the old topic (like a
leave, bounded by `kLinkUnpublishMaxWait`), then `replaceLinkChannel`
(`link_channel.dart`, one transaction): new random secret, epoch + 1, **fresh
Nostr key**, "me" kept, publish state reset, the old `link_peers` dropped →
published under the new topic at once; the sheet shows the new link +
`linkInviteAfterReset` ("send it to everyone"). **No pointer on the old topic**
(the removed person could read it). Other members **switch** by opening the new
link: the join look-up's `LinkJoinError.otherLink` now shows *Switch to this
link?* (`joinLinkSwitch`, `linkSwitchActionProvider` → `switchLinkGroup` →
`LinkSyncEngine.switchLink`: same unpublish + replace with the link's secret,
"me" kept, no picker, then a full fetch). `joinLinkChannel` still refuses
another secret. Until everyone switched, members still on the old link carry
old-link writes over (whole-snapshot LWW). Removing a person in a link group
shows `removeMemberLinkNote`. No wire / schema change. Tests:
`test/integration/link_reset_test.dart`, `test/g52_link_reset_ui_test.dart`,
`link_channel_test.dart`, `g52_link_join_test.dart`.

### Invite by link (G52 step 6)

`lib/features/link/link_invite.dart`. **Who gets *Invite with a link***
(pure `linkInviteStateOf` → `linkInviteStateProvider(groupId)`, one-shot
channel read, invalidated by the flow): a group with a `link_channels` row →
`open` (show its link, any mode); in **local mode** a group
`linkChannelBlocker` accepts (unsigned meta, no other Matrix claim) →
`canOpen`; everything else — every **Matrix group** — `unavailable`: no
entry at all (stays Matrix until G53, design §14 Q13). Entry points: group
⋮ (`inviteLinkMenuItem`, first), the solo empty state (`emptyInviteLink`
primary, *Add people* outlined) and the G56 card (`cardInviteLink`), group
settings → People (`inviteLinkTile`), people page app bar
(`membersInviteLink`). `inviteByLinkFlow`: `canOpen` → first-use
disclosure (`ensureLinkDisclosure` → `LinkDisclosurePage`, §9.2, explicit
*Continue*; device-wide `DevicePrefs.linkDisclosureSeen`,
`link_disclosure_seen`) → `linkChannelOpenerProvider` (=
`LinkSyncEngine.openChannel`; tests replace it) → invalidate state +
`currentParticipant` → `LinkInviteSheet`: QR (`QrCodeView`, `qr` package,
ink on paper + quiet zone in both themes), *Share link*
(`textSharerProvider`, text `linkInviteShareText`), *Copy*, the warning
"Anyone with this link …" + the G48 reset hint. The link is
`linkInviteUri` (https form with `n` = group name). **Create group on a
Matrix account:** a *Share with an invite link* switch
(`createGroupViaLink`, default off; not in local mode — there the first
invite opens the link, §14 Q9 — nor the offline demo) → disclosure →
`GroupCreator.create(viaLink: true)`: in one transaction the channel is
stored **first** (`newLinkChannel`, `my_participant_id` = a fresh UUIDv7
creator id), so the group is `linkOnly` before its first write — meta and
people unsigned, not `pendingSign`, `by` = creator, creator **without** a
claim (no MXID reaches the relays; nothing goes over Matrix). The people
page treats a link group like local mode (names only, no Matrix
invite / claim / devices; hint `linkMembersHint`) and finds "me" via
`currentParticipant` (`selfId`). PRIVACY.md + `privacyLink*` (new
section), `privacyLocalBody` / `privacyNoTrackingBody` updated (pinned by
`test/g52_link_invite_test.dart`). Tests: `test/g52_link_invite_test.dart`,
`test/integration/link_invite_sync_test.dart`, G71 guideline tests (sheet,
disclosure).

### Link sync engine (G52 step 5)

`LinkSyncEngine` (`lib/core/link/link_sync_engine.dart`,
`linkSyncEngineProvider` — per ledger DB like `SyncEngine`, G19 rules;
kept alive by `linkSyncActiveProvider` in `LedgerSyncHost` for MXIDs **and**
local mode; off on the signed-out placeholder and in the demo) syncs link
groups over Nostr. **No link channel → no connection, no NIP-11 request.**
- **Publish:** drift table updates (groups / members / expenses /
  settlements) → debounced check (3 s, ≥ 5 s apart per group) → bootstrap
  content (tombstones + `pendingSign` rows, sorted) → `linkSnapshotDigest`
  vs `last_published_hash` (or ≥ 10 days old → refresh) → `planLinkSnapshot`
  within the target relays' NIP-11 budget → one event per part (monotonic
  `created_at` via `LinkDao.nextCreatedAt`, `expiration` +30 d, `alt`),
  retired parts header-only (+1 d). Recorded only when every event reached
  ≥ 1 relay. Nothing is published while "me" (`my_participant_id`) is unset.
- **Relays** (`link_relay_policy.dart`): `rate-limited:` 1 min → 1 h back-off;
  `blocked:` / `restricted:` / `invalid:` (not "too large") / `pow:` /
  `auth-required:` → skipped until restart; `replaced:` → fetch our newest
  event, `bumpCreatedAt`, republish once; undelivered → retry 1 min → 1 h.
  `AppSettings` `link_relays` (list) + `link_relay_state:<url>` (NIP-11 cache
  7 d, last OK / rejection). NIP-11: `nostr/nip11.dart`; NIP-09:
  `nostr/nip09.dart`.
- **Receive:** one live subscription over all topics × 8 parts (first `REQ`
  without `since` = the full fetch; closed 30 s after pause, `since` on
  resume); own events skipped, processed ones (`link_peers`) skipped before
  decrypting, undecryptable / wrong group / wrong part ignored **and not
  recorded**; else `RecordGate(linkPolicy:)`.snapshot + `recordPeerEvent` in
  one transaction. Merges trigger a republish (unchanged digest → nothing).
- **Status:** `linkGroupSyncStatusProvider(groupId)` → `LinkGroupSyncStatus`
  (synced / pending / failing + `LinkSyncProblem`), engine-local (not
  `SyncHealth`).
- **Seams:** `openChannel` (`link_channel.dart`: drops our own claim, sets
  "me", plain link versions, fresh secret + key; refuses signed-meta groups —
  G53), `refresh(groupId:)` (join / pull / background), `publishAll()`,
  `unpublish(groupId)` (header-only parts + NIP-09), `onAppPaused/Resumed`.
- Tests: `test/integration/link_sync_engine_test.dart` (`FakeRelayNetwork`,
  now with NIP-09), `test/core/link/link_relay_policy_test.dart`,
  `test/core/link/link_channel_test.dart`. Container tests override
  `linkRelayConnectorProvider`, `linkRelayInfoFetcherProvider`,
  `linkClockProvider`, the debounce / interval / back-off providers,
  `linkAppLifecycleProvider` (false) and `linkAppVersionProvider`, and wait
  with `FakeRelayNetwork.settle()` + `LinkSyncEngine.isIdle`.

### Joining a link group (G52 step 7)

`/join` (`kJoinLocation`, `features/link/link_join.dart`) is **never
redirected** (`routerRedirect`; the page shows a spinner while the session
loads). Links arrive as: Android intent filter `moneyledger://join` + App
Link `https://leostumpf.github.io/moneyledger/join` (`autoVerify`; pinned in
`android_manifest_test.dart`) → `app_links` (`incomingAppLinks()`,
`joinLinkStreamProvider` (`JoinLinkEvent`s — identity equality, so the same link opened again still navigates; `incomingAppLinks` skips only the one launch-link replay), `JoinLinkListener` in `App` → `/join?<fragment>`;
`flutter_deeplinking_enabled=false`, app_links is the only reader; nothing
logs a link); web: `#/join?v=1&k=…` (the route's query); or pasted (`/join`
without a link — welcome, empty groups list, *Create group*). Flow
(`JoinLinkPage`): parse (`parseLinkFragment`; newer `v` → "update the app")
→ intro (no network) → *Join* → disclosure (first use) → **look-up**
(`linkJoinLookupProvider` → `lookUpLinkGroup`: a short-lived
`NostrRelayPool` + `probeLinkGroup` / pure `linkGroupPreviewFrom`
(`core/link/link_join_probe.dart`) — **no DB, nothing stored**; refused
when this device holds the group as a non-link group or with another link,
`linkJoinBlocker`; already joined → opens the group) → "Who are you?"
(active, unclaimed people; "already picked on another phone" from the
headers' `me`; *I'm someone new* + name) → `linkJoinActionProvider` →
`joinLinkGroup`: signed out → `startLocalProfile(name)` (welcome seen, local
mode); `LinkSyncEngine.join` = `joinLinkChannel` (channel stored **before**
the first merge, same refusals, epoch 1, me null) + `refresh(groupId:)`;
group not merged → channel dropped, "not found"; then in one transaction
`setMyParticipant` (+ for someone new the participant, unsigned, `by` =
itself); `currentParticipant` / `linkInviteState` invalidated → the engine
sees "me" and publishes. Works on Matrix accounts too (link-only group,
unsigned). Tests: `test/g52_link_join_test.dart`,
`test/integration/link_join_test.dart`, router + G71 cases.

### Relays + sync sheet (G52 step 9, G68)

- **Settings → Relays** (`/settings/relays`, `RelaySettingsPage`,
  `features/link/relay_settings_page.dart`; pure helpers
  `relay_settings.dart`): tile `relaysTile` in *Sync* — on Matrix accounts
  **and** in local mode (local mode's *Sync* = relays + the background
  switch while a link group exists; `backgroundSyncEnabledProvider` is
  autoDispose and reads the local ledger in local mode, the scheduling
  honours it). Per relay: status (`relayStatusOf`: refuses our updates this
  run / rate-limited / NIP-11 says needs an account or no NIP-40 / refused
  last time / accepted {ago} / not used yet), terms link (NIP-11
  `terms_of_service`, http(s) only; the defaults' wikifreedia pages in
  `kDefaultRelayTerms`), remove (confirm; never the last one). *Add relay…*
  (`AddRelayDialog`): `parseRelayInput` (`wss://` only, adds the scheme,
  refuses `ws://` / junk / duplicates) → NIP-11 fetch (the only request the
  page makes, G43) → needs account / no NIP-40 refused, no answer → *Add
  anyway*. *Use the default relays* clears `link_relays` (a later app
  update's defaults apply). Data: `linkRelaysViewProvider` →
  `LinkSyncEngine.watchRelays()` (list + `link_relay_state:<url>` + the
  policy's rejections / rate limits; loads the list without any connection);
  changes via `linkRelaysSetterProvider` → `LinkSyncEngine.setRelays`
  (stores, rebuilds the pool + subscription, NIP-11 for new ones, **forced
  publish** of every link group to an added relay). The list is per ledger,
  device-local; the invite link names no relays (the page says so). The
  disclosure names the configured relays (`linkDisclosureRelaysProvider`,
  "(one operator)" for the defaults) + "add your own relay".
- **Sync sheet (G68)** (`features/sync/group_sync_sheet.dart`): the group
  page's cloud is a `GroupSyncButton` (always an enabled button; tooltip =
  status) → `showGroupSyncSheet`. Link group (`groupSyncsByLinkProvider` =
  invite state `open`) → `linkGroupSyncStatusProvider`; local mode without a
  link → no icon; else the Matrix status / `SyncHealth`. Sheet: summary
  (problem text), one row per person — Matrix: pure `matrixPeerRows`
  (`GroupSyncStatus.peerInSyncAt` / `maxRecordUpdatedAt`: has everything ·
  checked {ago} / waiting / no device / no verified device; our other
  devices last; a hint when people have no account); link: pure
  `linkPeerRows` from `link_peers` grouped by `me` ("has everything" when a
  one-part publisher's digest equals our delivered one, else "last update
  {ago}", device count, unknown person) + *Relays* entry. *Sync now*
  (`groupSyncNowProvider`): Matrix `SyncEngine.syncGroupNow` (digest now),
  link `LinkSyncEngine.syncNow` (full fetch, then publish at once, retry
  back-off cut short). Replaces the old failing-only health sheet / *Retry
  now*. `agoText` moved to `core/l10n/l10n.dart`.
- Tests: `test/g68_sync_sheet_relays_test.dart` (EN + DE, 360 dp, 200 %),
  `test/features/peer_sync_rows_test.dart`, `link_sync_engine_test.dart`
  (relay list, forced publish, sync now), settings / scheduling / router /
  G71 cases.

### Leaving a link group, backups (G52 step 10)

- **Leave / delete** (design doc §7.3): a link group has no Matrix claims,
  so `groupExitKind` → *Delete* (= "delete from this device"; our
  participant stays in the ledger, no "X left" record). `GroupExiter._purge`
  first calls `linkUnpublisherProvider` (`LinkSyncEngine.unpublish`:
  header-only parts expiring after 1 day + a NIP-09 deletion, bounded by
  `kLinkUnpublishMaxWait` = 8 s, never throws) when the group has a channel,
  then purges as before (`purgeGroup` drops the channel + peers). The exit
  dialog says the others keep their copies (`deleteLinkGroupNote`);
  `exitGroupFlow` shows a progress dialog (`runWithProgress`, from
  `backup_ui.dart`) meanwhile. *Delete local data* unpublishes every link
  group (in parallel, same seam) before the wipe; its confirmation adds
  `deleteLocalDataLinkNote`.
- **Backup carries the invite key** (§7.2, §14 Q7): each link group's entry
  in the backup file has `link: {epoch, secret}` next to the bootstrap
  content (`GroupSnapshot.link` / `BackupLink`, parsed by `backupGroupLink`;
  malformed → ignored) — **not** in the signed / hashed meta (G53's meta
  `link` field isn't built), so nothing on the wire changes; older builds
  ignore it. Never the Nostr key or "me". Restore points (G48 snapshots)
  carry it too. Warnings: passphrase dialog without passphrase
  (`backupLinkKeysWarning`), restore preview (`RestorePreview.linkGroups` →
  `restoreLinkKeysWarning`), backup page note while link groups exist
  (`backupFileLinkNote`).
- **Restore re-opens the channel:** inside each group's restore transaction,
  **before** the merge, `reopenLinkChannel` (`link_channel.dart`) stores a
  channel with the file's key + epoch, a fresh Nostr key and **no "me"** —
  only when this device has neither a channel nor the group (an existing
  channel is kept; a group held here without one never becomes a link
  group). So the records go in as a `linkOnly` group (never adopted /
  signed); nothing is published until "me" is chosen: the group page's
  *Which person are you?* banner (`chooseMeBanner`, text
  `linkChooseMeBanner` for a link group) → `chooseLinkParticipant`
  (`link_join.dart`, shared with the join: picked person or someone new,
  one transaction) → the engine publishes.
- Tests: `test/integration/link_leave_backup_test.dart` (delete →
  unpublished, peer keeps its copy → restore → "me" → published),
  `test/core/link/link_channel_test.dart`, `test/features/ledger_backup_test.dart`,
  `test/g52_link_leave_backup_ui_test.dart` (EN + DE, 360 dp, 200 %).

### Landing page + App Links (G52 step 11)

The https invite link (`https://leostumpf.github.io/moneyledger/join#…`)
needs a **separate repo**, `~/git/LeoStumpf.github.io` (GitHub Pages user
site, **shared by all of Leo's apps**: `/<appname>/` per app, root page
lists them, `.nojekyll`): `.well-known/assetlinks.json` (one statement per
package; MoneyLedger = the **upload key**'s SHA-256 — add the Play App
Signing key once enrolled; never the password) and `moneyledger/join.html`
+ `join.js` — reads `location.hash` in the browser only, builds
*Open in MoneyLedger* (`moneyledger://join#<fragment>`), EN/DE, CSP, no
external request / analytics; `WEB_APP_URL` / `PLAY_URL` / `FDROID_URL`
stay empty (hidden) until they exist. The manifest's `autoVerify` App Link
only verifies once the site is live. Smoke: `docs/smoke-test.md` §13.

### Mixed groups + lock (G53)

Design doc §10.1 + "As built (G53 steps 1–4)". **Wire:** the signed group
meta has optional `link: {epoch, secret}` (open invite link → `mixed`) and
`locked_at` (ms) — in payload, signed body and G27 hash only when set
(`GroupLink`, never logged); schema **v16** `groups.link_epoch` /
`link_secret` / `locked_at` (forgets meta refusals). Meta rewrites keep the
link state (`GroupModel.nextVersion` — editor, CSV import, G48 reset).
- **Gate:** `RecordGate(matrixPolicy:)` on the Matrix path (`LedgerSyncer`,
  `SyncEngine`): in `mixed` unsigned expense / payment / participant versions
  relayed by members are accepted (stored unsigned, `by` kept, "Changed by X
  via link · not verified" — `attributionFor(linkAuthor:)`); refused on both
  paths: unsigned metas, unsigned claims, **unsigned changes of a claimed
  participant**, unsigned metas carrying link state. Locked: unsigned only up
  to `locked_at`. Opening a link forgets `unsigned` refusals. Link path: a
  **signed self-claim** (stored, active, unclaimed participant, signed by
  the claimed MXID) is accepted in linkOnly / mixed; other signed claims need
  a signer who is an active member (stored, or in the same snapshot for a
  participant new to this device).
- **Writers without an account** (local mode) in a mixed group write link
  versions; meta / claimed people → `SignatureRequiredException` ("Only
  possible with a Matrix account"); in a locked group nothing. **Review:**
  a Matrix account on the **link side** of a mixed group (joined by link —
  its channel's "me" isn't claimed by it, `GroupPolicyInfo.myMatrixId`)
  writes link versions too (a version it signs would be dropped by every
  peer: `signer_not_member`).
- **Invite by link in a Matrix group** (`canOpenMixed` → disclosure →
  `confirmMixedLink` → `mixedLinkOpenerProvider` / `writeMixedLinkMeta`):
  a signed meta with a fresh secret, epoch = `lastLinkEpoch` + 1, relayed
  over Matrix. **Bridging** (`LinkSyncEngine._scheduleBridge`,
  `linkBridgeAction`): every Matrix device whose account claims an active
  participant creates / replaces its channel from the signed meta (reset in
  a mixed group = a new signed meta, `mixedLinkResetterProvider`); a signed
  meta without link drops any channel. A snapshot / header-only part whose
  meta names another secret is never published on the old topic.
- **Signed self-claim after "Connect a Matrix account"** (`link_self_claim.dart`):
  the G40 adoption marks adopted link groups (`link_self_claim:<group>`);
  `linkSelfClaimProvider` (in `LedgerSyncHost`) signs a claim of
  `my_participant_id` (+ in a linkOnly group a signed meta keeping the link →
  mixed) once the key is ready, relays it over Matrix (sender-gate exception
  `isSenderAuthorized(linkOpen:)`) and the link. Not for link groups a Matrix
  account created / joined while signed in (open point).
- **Lock** (group settings *Make group secure*, `canOfferLock`,
  `lockBlockers`, `groupLockerProvider` → `LinkSyncEngine.lockLink`): every
  active participant must have a valid MXID; a signed meta without link +
  `locked_at`, a final header-only `locked: true` event (part 0, 1-day
  expiry, other parts NIP-09), channel dropped; others drop theirs on the
  meta. A device without a Matrix participant shows the read-only
  `secureOnlyBanner`. Reopen = *Invite with a link* again (new secret).
- Privacy: PRIVACY.md + `privacyLinkBody` (bridging, Matrix IDs visible to
  link holders, lock deletes the copies). Tests: `test/core/link/g53_mixed_gate_test.dart`,
  `test/database/schema_v16_migration_test.dart`, `test/integration/g53_*`,
  `test/g53_*_ui_test.dart`, harness `test/helpers/mixed_harness.dart`;
  smoke §14.

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
  G16 `category` / `note` and the G49 `date`, present **only when set** so
  older bodies and hashes are unchanged — `updated_at`, `deleted`, signer
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
  oneself; G18 review 2: a member `matrix_id` that isn't a valid MXID —
  `isValidMxid`, e.g. `local:self` — `memberProblem`; an expense / payment
  id stored for **another group**) → refused `invalid_record`; else
  `RecordVerifier`: a clock > now +
  5 min is dropped **first** (transient, signed or not); **refused** if
  unsigned, bad signature, bad / changed origin, wrong signer (a non-member's
  member payload must be signed by itself) or **key conflict** (the embedded
  key contradicts the key we pinned for that (user, device) or the server
  lists). Then (defence in depth) the **signer** of an expense / payment /
  meta version must claim a participant of that group (a removed one only
  for versions not newer than its removal) or be the relaying account itself
  — else dropped as `signer_not_member` (transient; a snapshot's meta may be
  signed by one of the snapshot's own members). Refused versions go to
  `rejected_versions` (G18 review 2, schema v10: a small set per record — the
  version (clock + `version_hash`) is part of the PK, the
  `kMaxRefusedVersionsPerRecord` = 4 highest are kept; never one stamped
  beyond now + 5 min) and the digest's `rejected` map (`"<ms>:<hash8>"`, the
  highest per id) + optional `rejected_more` (the others, lists; older peers
  ignore it), so peers stop re-sending exactly those versions (no repair loop; "agree to disagree" counts as in
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
  conflicts and someone posing as us. G46: under the footer only a real
  problem (conflict / not your device) is shown — "not verifiable" lives in
  the details dialog only.
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

**Leaving / deleting a group (G9).** The group settings page (G65, last
section *Leave or delete*) offers **Leave group** when this account is an active
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
The members page (titled *People*, G64) lists removed participants greyed
under **No longer in the group** (*Re-add*: claimed ones via `add`, local people via `MemberAdder.reactivate` — same participant, never a duplicate). Who removed whom isn't recorded, so a removal
learned only via a peer's digest gossip (our own leave notice lost) also shows
as "removed".

**People when creating a group (G64).** `CreateGroupPage` has a *Who's
in?* field under name + currency: Enter / + adds a name as a chip (trimmed,
blank ignored; the field keeps focus — `onEditingComplete` is a no-op), ✕
removes one, a typed-but-not-added name counts at *Create*; the creator is
the fixed *You* chip. `GroupCreator.create(name, currency, people:)` saves
them right after the creator as local participants (same `saveMember`
path as *Add person* → signed / `pendingSign` / link policy; nothing
relayed — nobody else is claimed yet). Matrix invites stay on the members
page. *Add person* dialog (`AddPersonDialog`): *Add & next* writes and
stays open (empty, focused, "Added X, Y"), *Add* writes and closes. **Duplicate
hint (U9):** `duplicateNameOf` (`member_model.dart`, trimmed,
case-insensitive) — a live, non-blocking helper line on both (existing
people incl. former ones + the ones just added). **Removal warning (U10):**
*Remove from group* shows the person's open balance
(`removalBalanceWarning`, `group_exit_dialog.dart`: "Ben still gets €23.50
back" / "owes", per currency) + *Settle up first* (→ `recordPaymentFlow`
prefilled with a suggested debt involving them; removes nobody); removing
stays possible. Tests: `test/g64_people_test.dart`.

**Editing a group (G10).** Group settings → *Name & currency* (any active member):
name + default currency (`group_edit_dialog.dart`; G66 `CurrencyField` —
any ISO-4217 currency, see "Currencies (G66)"). `GroupEditor.edit` LWW-upserts the meta with
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
anti-entropy repairs). The group page's sync icon (`GroupSyncButton`, G68)
shows the error cloud when failing, else `cloud_done` / `cloud_queue`; a tap
opens the per-person sync sheet (last error / last-synced, *Sync now* — see
"Relays + sync sheet").

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
  digest broadcast, a session still opening) before it closes the stores —
  **G18 review 2:** after first aborting the requests in flight
  (`runBackgroundRound(abortRequests:)` = closing the round's own
  `RequestTimeoutHttpClient`, passed to `buildMatrixClient(httpClient:)`;
  `IOClient.close` is forced), since a request may take up to 90 s. The
  app gives its slot back when its engine detaches (`AppLifecycleListener
  .onDetach` — backed out of; otherwise rounds would stay skipped until the
  process dies). Gate logic is tested on a fake `PortRegistry`
  (`test/core/background_gate_test.dart`).
- Setting: per account, device-local `AppSettings` `background_sync_enabled`
  (default on), settings page (gear on the groups page, G65) → *Sync*;
  `backgroundSyncSchedulingProvider` (watched by `LedgerSyncHost`) registers /
  cancels the OS task (cancel on sign-out and in local mode, G40). The round
  re-checks the flag (and overrides `localModeActiveProvider` /
  `ledgerIdentityProvider`, so it only ever syncs the account it opened).
- **Daily snapshot (G58):** after the sync work (still inside the gate and
  the 60 s bound) the round runs the G48 snapshot step
  (`RestorePointsService.snapshotIfDue` via `restorePointsServiceProvider`
  in its container — same `snapshot_checked_day` / fingerprint / rotation as
  an app start, the same `<app support>/snapshots/<db name>/` directory;
  `runBackgroundRound(snapshotStores: createPlatformSnapshotStore)` —
  path_provider works in the headless engine, `buildMatrixClient` resolves
  its store the same way). Skipped when less than
  `kBackgroundSnapshotMinRemaining` (10 s) of the budget is left; a stop
  (abort / budget) is checked between the steps (`cancelled:`) and a write
  in flight is awaited before the DB closes (`guard` / in-flight grace);
  the write is temp file + rename, and a leftover `*.json.tmp` (process
  killed mid-write) is deleted by the next rotation. No history pruning in
  the round (app start only). Tests: `background_round_test.dart` (G58
  group), `restore_points_test.dart`.
- **Link phase (G52 step 8, design doc §8.3):** after the Matrix phase
  (only with a Matrix session) the round runs the link groups when the
  ledger has a `link_channels` row — **in local mode too**:
  `runBackgroundRound(whichLedger:)` decides from the device prefs
  **before** anything is opened (`_whichLedger`, native: local profile →
  `local` — no Matrix client is built, `vod.init()` only; connecting →
  `none`, skipped; else `matrix` — only if the G79 Matrix store exists,
  never creating one: pure `chooseBackgroundLedger`), `openLocalDatabase` opens local mode's
  ledger; local without a link group → `skippedNothingToSync`. The engine
  runs in `linkBackgroundRoundProvider` mode (no live subscription, no
  debounced / start-up / timer publishes, no lifecycle, no NIP-11 fetch):
  `refresh(timeout: kBackgroundLinkFetchTimeout` 10 s`)` = one full fetch
  of every topic on every relay → merge, then `publishAll()` (publishes
  only groups whose snapshot changed or are due for the 10-day refresh) —
  inside the same 60 s budget / `guard`; a stopped round disposes the
  engine (closes its relay pool) before waiting for the step in flight.
  Result: `link`, `linkEvents`, `linkMerged`. A round delegated to the
  running app also runs `refresh` + `publishAll` on the app's engine
  (`_linkSyncInApp`), then `releaseIdleConnections()` (a paused app drops
  the relay sockets that fetch reopened). **Scheduling:** in local mode
  `backgroundSyncSchedulingProvider` registers the task while
  `linkGroupsExistProvider` is true, else cancels (no settings toggle in
  local mode; the round still honours `background_sync_enabled`). Tests:
  `test/core/background_round_link_test.dart`,
  `background_sync_scheduling_test.dart`.
- No expedited / foreground workers. (`POST_NOTIFICATIONS` is declared since
  G72 — the change notifications below.) Web/iOS: no background sync.
- **Debug builds only (G36):** the settings page's *Debug* section has *Run background sync now
  (debug)* (`kDebugMode`) → `BackgroundScheduler.runOnce(delay: 15 s)` = a
  WorkManager one-off task (`moneyledger-background-sync-once`, same
  dispatcher) — swipe the app away within the delay so the round runs
  headless instead of delegating to the app. Release builds never show it
  (and `runOnce` is a no-op there).
- Manual trigger on a device: `adb shell cmd jobscheduler run -f -n
  androidx.work.systemjobscheduler io.github.leostumpf.moneyledger <jobId>`
  (WorkManager schedules in that JobScheduler namespace on Android 14+ — without
  `-n` the job isn't found; id from `dumpsys jobscheduler | grep leostumpf`,
  it changes when WorkManager reschedules, e.g. after a force stop); logs are
  tagged `[bg]` / `[bg-gate]` — debug / profile builds only (G44: release
  builds are silent).

### Change notifications (G72, Android)

Local notifications about **others'** changes, posted by the **background
round** (G31) — on by default (Leo 2026-10-17). `lib/features/notifications/`.
- **Plugin:** `flutter_local_notifications` 22 (BSD-3; no push / Firebase /
  Play services — F-Droid ok). Needs core library desugaring
  (`android/app/build.gradle.kts`: `isCoreLibraryDesugaringEnabled` +
  `desugar_jdk_libs`). The manifest now **declares** `POST_NOTIFICATIONS`
  (G31 used to remove workmanager's copy; still no expedited / foreground
  workers) — pinned by `test/core/android_manifest_test.dart`. Status-bar
  icon `res/drawable/ic_stat_notify.xml` (vector, from
  `tool/brand/render_icons.py`; kept by `res/raw/keep.xml`).
- **What is announced** (`change_notices.dart`, pure `planChangeNotices` +
  `collectChangeNotices`): the round notes `HistoryDao.latestId()` before
  it syncs (only while `notifications_enabled`, `AppSettings`, per ledger,
  default on); after the Matrix + link phases every `record_history` entry
  above it with source `inbound` of kind expense / settlement — newest
  version per record; *added* (not held before — `recordsWithEntriesUpTo`;
  added + deleted in the round = skipped) / *edited* / *deleted*. Not ours:
  signer = this account (another own device) or link `by` = "me"
  (`link_channels.my_participant_id` or the participant this identity
  claims). A group without history before the round → *"You were added to
  this group"* when someone else wrote any of it. One notification per
  group (`noticeIdFor`: FNV-1a, replaced by the next round), title = group
  name, body "Anna added Dinner · €42.10" / "3 changes by Anna, Ben" (+ an
  inbox list, ≤ `kNoticeMaxLines`); payload = group id. Texts via
  `noticeText(n, l)` in the device language (`deviceLocalizations()` —
  no widget tree in the headless engine). Channel `others_changes`
  ("Changes by others"), `visibility: private`. Stopped before the step →
  nothing posted (not announced later either).
  `runBackgroundRound(notify:)` (native: `createPlatformNotifications()
  ?.show`); `BackgroundRoundResult.notified`.
- **History fix:** the G48 history of a link-group expense / payment now
  keeps its `by` (`_expenseFromCompanion` / `_settlementFromCompanion`
  carry `linkAuthor`; a companion without it re-reads the row).
- **App side** (`notifications_provider.dart`): `notificationPlatformProvider`
  (`NotificationPlatform` seam: permission, show, launch / tap payloads;
  null on the web / desktop / test VM — tests use
  `FakeNotificationPlatform`), `notificationsSupportedProvider`
  (= background sync supported + a platform). **Permission prompt** (Android
  13+): `notificationPermissionPromptProvider`, watched by `GroupsPage` (not
  in the offline demo) — once per ledger (`notification_permission_asked`)
  when notifications + background sync are on and a group is **shared**
  (`sharedGroupExistsProvider`: a link group, or another active Matrix
  account — `MembersDao.watchHasOtherClaimedMember`); pure
  `shouldAskNotificationPermission`. **Settings:** `NotificationsTile`
  (`notificationsSwitch`) in *Sync* (Matrix) / local *Sync* (with a link
  group): turning it on asks again; disabled while background sync is off
  (`notificationsNeedBackgroundSync`); OS-blocked → `notificationsBlocked`.
  **Tap:** `NotificationTapListener` (App builder) opens
  `/groups/<id>/expenses` for the launching / a tapped notification once
  the router is past splash / onboarding / sign-in (`notificationOpenAllowed`).
- Privacy: `privacyBackgroundBody` + PRIVACY.md (pinned equal by
  `test/g72_notifications_test.dart`). Limits: `docs/open-points.md`.
  Tests: `test/features/change_notices_test.dart`,
  `test/g72_notifications_test.dart`, `background_round_test.dart` /
  `background_round_link_test.dart` (G72 groups), G71 guideline test,
  smoke 7.13.

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
  (never answered). Rule 4 (in sync) needs no unresolved bucket. **G37:** a
  refused version keeps its bucket's hash different, so a bucketed group
  with a refusal pays summary → reply → `final` on every cycle (one extra
  message per peer, still "in sync", never a loop) — accepted for v1.
- Ceilings now: ~80 members per group (all members ride in every part /
  digest), ~30k records (2 048-bucket summary ≈ 31 KB). See
  `docs/open-points.md` for the table and costs.

### Backup (full JSON — G5)

Ledger data exists only on members' devices, so a group nobody else has a copy
of (solo, or only local people) is lost with the device. The **full backup** is
the lossless answer: settings page (gear on the groups page) → *Backup &
restore* (G70 page) → *Back up all groups* writes **one JSON file for the
whole account**, *Restore from backup* merges one back.
`lib/features/backup/`: `ledger_backup.dart` is the pure codec
(+ the nudge logic), `backup_service.dart` (`BackupService`,
`backupServiceProvider`) the DB seam, `backup_ui.dart` the UI.

**One "Backup & restore" page (G70, U23).** The four ways back — backup
file, restore points (G48), resetting one group (G48) and the snackbar
*Undo* (G67) — are explained side by side on `BackupRestorePage`
(`kBackupLocation` = `/backup`, `backup_restore_page.dart`; an "in" page in
`routerRedirect`). The settings page's *Backup & restore* section is one
compact tile (`backupPageTile`, `BackupSettingsSection`: *Last backup: …* +
chevron). The page: a **decision aid** card (`backupDecisionAid`: just
deleted → *Undo* in the snackbar; mistake noticed later → reset the group;
a whole group gone here → a restore point (web: a backup file); new / lost
phone → only a backup file, plus — Matrix accounts only — "shared groups
usually come back from the others"), then three blocks: **Backup file**
(intro, last backup, `backupExportTile`, `backupRestoreTile`, hint to *Back
up this group* in the group settings; G52 step 10: `backupFileLinkNote`
while link groups exist — the per-file warnings are in the export / restore
dialogs), **Restore points** (`snapshotsSupportedProvider`: intro +
`restorePointsTile` → `/restore-points`; else `noSnapshotsHint`), **Undo
changes in one group** (`resetPickGroupTile` → bottom sheet of all groups
sorted by name → `/groups/<id>/reset`; disabled with no groups; the reset
page handles read-only groups). Group settings keep *Back up this group* and
*Reset*; the nudge card's *Back up now* still exports directly. CSV import
stays in the settings page's *Data* section. Tests:
`test/backup_restore_page_test.dart` (EN + DE, 360 dp, Matrix / local / no
snapshots, navigation).

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

**Nudges:** onboarding has a 4th card "Keep a copy". The settings page's
*Backup & restore* tile and the G70 backup page show *Last backup: <date> /
never* (`AppSettings` `last_backup_at`, device-local, per account, written
after a successful save); the flows run on the page's own context (G65 — the
sheet used to have to close first). The groups page shows a
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

**Per-group backup (G34):** group settings → *Back up this group* →
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

### Restore points + reset group (G48)

Undo for mistakes (and, later, for link-mode groups where anyone with the link
can delete everything). Two layers, both device-local, never synced, never in
a backup file / digest:

- **Version history** (`record_history`, schema **v12**, `history_dao.dart`):
  the four DAO LWW upserts (`upsertExpenseLww` / `upsertSettlementLww` /
  `upsertMemberLww` / `upsertGroupLww`) append the version they **stored** in
  the same transaction — only when it is a different version (new record,
  other clock or G27 hash); re-writing the same version (`pendingSign` →
  signed) or a losing older one appends nothing. Row: group, kind
  (`RecordKind.wire`), record id, `updated_at`, version hash, the wire payload
  as stored (`expensePayload` & co., signatures incl.), `source`
  (`HistorySource`: local / inbound / restore / revert / import / initial —
  callers pass it: `RecordGate` → inbound, or restore when `acceptUnsigned`;
  CSV import → import; reset → revert; default local) and `recorded_at`
  (this device's clock, `historyClock` — tests replace it). The v12 migration
  backfills one `initial` entry per stored record. `purgeGroup` (leave /
  delete) drops the group's history. **Retention** (`HistoryDao.prune`, run
  at app start by `restorePointsMaintenanceProvider`, watched in
  `LedgerSyncHost`): entries older than 90 days go, except the newest one per
  record before the cutoff (its **base** — so the state at any point ≥ the
  cutoff stays exact); over `kHistoryMaxRows` (20 000) the cutoff moves
  forward; the cutoff is stored as `history_floor` (`AppSettings`).
- **Reset group to an earlier state** (group settings → *Reset to an earlier
  state…*, `/groups/:id/reset`, `GroupResetPage`; disabled for read-only
  groups): the history is clustered into **change batches** (pure
  `changeBatches`: entries < 10 min apart **by the same author** — this
  device / our own account, a peer's account, a restore, a CSV import
  (G62); per record added / edited / deleted, group-or-member changes, who
  signed them / "by you"); *Undo from here* = reset to the state **before**
  that batch (`beforeId` = its first entry id) — "how it looked on this
  device then". **G62 base batch:** the group's arrival on this device —
  every entry up to the meta's first one plus what came with it (same
  source, ≤ `kBaseArrivalGap` 30 s apart, `kLocalArrivalGap` 2 s for a
  local write — creation / local-mode adoption —, no record twice; the v12
  `initial` backfill always) — is a batch of its own (`ChangeBatch.base`),
  never resettable, never chained with later changes (before G62 it
  swallowed every change < 10 min later: empty page after an update or for
  a new group). Otherwise a batch is resettable only
  if the group's meta has an earlier entry and it starts at/after the floor.
  Pure `planGroupReset` per expense / payment: the newest entry before the
  point; none or deleted then + live now → tombstone (*removed*); live then +
  deleted now → *restored*; other content → *reverted*; a record the history
  never saw (legacy adoption, demo seed) is left alone; an earlier version
  breaking today's content rules is skipped. Meta (name, currency, custom
  categories) is reset too. **Participants are never reset** (a removal must
  stick, G26; claims / "me" must not move; participants are never deleted, so
  old expenses still resolve). Every planned write is a **new version**:
  `nextLwwClock(stored)`, the creator's `origin` kept, signed by this device
  via the shared `LedgerWriteContext` (formerly `_WriteContext` in
  `expenses_provider.dart`; `pendingSign` without a key, local mode), all
  stored in one transaction (source revert), relayed like normal edits
  (≤ `kResetLiveRelayMax` = 25; more → only the group poke / digest), and the
  group is poked. Preview dialog first (`ResetPreviewDialog`: N come back /
  M undone / K removed, first entries by name). A reset is itself undoable the
  same way. Tests: `test/database/record_history_test.dart`,
  `schema_v12_migration_test.dart`, `test/features/group_history_test.dart`,
  `test/integration/group_reset_sync_test.dart` (peer adopts the revert),
  `test/history_ui_test.dart`.
- **Rotating snapshots** (`restore_points.dart`): at app start — and (G58)
  at the end of every Android **background round** (G31) — once per
  local day (`snapshot_checked_day`), the whole ledger is exported like the
  full backup (`BackupService.exportJson`, `account` = the ledger identity,
  so local mode's file restores like local mode's backup, G41); written only
  if its SHA-256 differs from the last snapshot's (`snapshot_fingerprint`;
  computed with `exported_at: 0`) and the ledger has a group, to
  `<app support>/snapshots/<ledger DB name>/YYYY-MM-DD.json` (temp file +
  rename, `FileSnapshotStore`); rotation (pure `snapshotsToKeep`): the 7
  newest + the newest of each of the next 4 older calendar weeks.
  **Web: none** (`snapshotStoreFactoryProvider` → null; the page says so —
  the in-DB history still allows resets, a backup file covers the rest);
  the offline demo keeps them in memory (G79, native only). Settings → *Backup & restore* → *Show restore
  points* (`/restore-points`,
  `RestorePointsPage`) lists them (date, groups, entries) → *Restore* = the
  normal restore (`BackupRestorer.previewAndRestore`, shared with the file
  restore: preview → confirm → LWW merge → poke). An LWW restore brings back
  **missing** groups / records (deleted group, wiped DB), not older content
  of changed records — that's the group reset. **G58 "Exactly this state"**
  (restore points only — `BackupRestorer.of(ref, exactState: true)`; not for
  a picked backup file): a switch in the restore preview (default off =
  merge; `RestorePreviewDialog(exactPlans:, onExactChanged:)`, keys
  `restoreExactSwitch` / `restoreExactWarning` / `restoreExactTag-<gid>`)
  shows per group "N come back / M undone / K removed" and warns that newer
  changes — also other members' — are overwritten for everyone. On confirm
  the merge runs first (missing groups, records, participants — unchanged),
  then `GroupResetService.resetGroupsToSnapshot` re-plans each group that
  exists here and this account is an **active** participant of
  (`planToSnapshot`; removed / not participating → merge only) and applies it
  exactly like a G48 reset (`apply`: `nextLwwClock`, origin kept, signed /
  `pendingSign`, one transaction, source `revert`, relay ≤
  `kResetLiveRelayMax`, poke). The planner is shared: `planGroupResetTo(
  target: ResetTarget)` — `historyResetTarget` (G48, `planGroupReset`) or
  `snapshotResetTarget` (absent in the snapshot = didn't exist → tombstone;
  an unparsable entry / missing meta = left alone; `held`: only content
  whose (kind, id, version hash) is in this device's `record_history` is
  written again — a hand-edited snapshot can't make it sign new content).
  Participants are never part of a plan. Tests:
  `test/features/exact_state_plan_test.dart`,
  `test/integration/exact_state_restore_sync_test.dart`,
  `test/exact_state_restore_ui_test.dart`. Local mode: its snapshots are
  deleted with its ledger (`localDatabaseDeleterProvider` →
  `deleteLedgerFilesAndSnapshots`, after *Delete local data* and after an
  adoption). Android backup stays off (G32); PRIVACY.md + the in-app
  `privacyRestorePoints*` text say what is kept and for how long. Tests:
  `test/features/restore_points_test.dart`. Limits: `docs/open-points.md`.

### Backup (CSV export/import — Phase D, G13)

A group can be exported to a **single human-readable CSV** and imported back
(sharing / spreadsheets / migrating old room-era groups — the lossless backup
is the JSON above). `lib/features/backup/`: the codec `ledger_csv.dart` is pure
Dart (models + strings, no DB/Flutter, fully unit-testable); `csv_export.dart`
is the Drift-read seam; `csv_import.dart` (`CsvImporter`) is the preview +
merge; `backup_files.dart` wraps `file_picker` (manual-smoke only, like the SSO
deep link). **Export** is in the group settings (G65), **import** on the settings page (*Data*) and the empty groups
screen.

**Format** — one row per **non-deleted** expense, then one per **non-deleted
payment** (settlement). Spreadsheet columns first, then a **decimal share
column per participant** (header = display name), then trailing machine
columns that drive the merge:

```
Date, Type, Description, Category, Category Name, Note, Currency, Amount, Paid By, <Participant A>, <Participant B>, …, Expense ID, Group, Group ID, Updated At, Created At
2026-06-13, Expense, Dinner, food, , Tip incl., EUR, 42.00, Alex, 21.00, 21.00, …, <uuid>, Trip, <gid>, 1760000050000, 1760000000000
2026-06-13, Expense, Vet, c:<uuid>, Dog, , EUR, 80.00, Sam, 40.00, 40.00, …, <uuid>, Trip, <gid>, 1760000070000, 1760000060000
2026-06-14, Payment, Payment, , , , EUR, 21.00, Sam, 21.00, , …, <uuid>, Trip, <gid>, 1760000090000, 1760000080000
```

**G16:** `Category` (the stable English wire id) and `Note` follow
`Description` (empty when unset and for payments). **G47:** `Category Name` (after
`Category`) holds a custom category's name (empty for built-ins); an import
recreates `c:` ids the group lacks from it. A CSV without them
(pre-G16) imports with no category / note; older parsers ignore them (they sit
before `Paid By`, outside the share columns). **G49:** `Date` is the
**display day** (`YYYY-MM-DD`: the expense's `date`, else the local day of
`created_at`; G60: payments likewise — `date ?? created_at`); the exact creation time (part
of the signed `origin`, must survive a round trip) is the trailing
`Created At` (ms). Import: `Created At`, else the `Date` cell (pre-G49 CSVs
wrote the full ISO creation time there); a plain-day `Date` that differs from
the creation's local day back-dates the expense or (G60) payment (`date`); an invalid one
aborts the import.

A **payment row** reads like an expense the payer covered entirely for the
recipient: `Paid By` = from, the recipient's share column = the amount (so the
sheet's per-person sums still match the balances); its settlement id sits in
`Expense ID`. On import a `Payment` row with exactly one share becomes a
settlement (else it is imported as an expense). A CSV **without** a `Type`
column (pre-G13) is all expenses.

Amounts are **decimal** in the sheet (`cents/100`; 2 dp, G66: 0 dp for a
0-decimal currency like JPY — `1000` = ¥1,000 — unless a legacy amount isn't
a whole yen, then 2 dp, lossless; the import reads every cell ×100 as
before) but **integer cents** everywhere else. The parser locates fixed columns by header name and treats any
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
  add/edit form has the `CategoryPicker` — **G47:** a form field (icon tile +
  name, "No category") that opens a bottom-sheet list: *No category*, the
  built-ins, the group's visible custom ones, *New category…* last (keys
  `categoryPickerField`, `category-<id>`, `category-none`, `category-new`).
  `suggestCategory(description)` is a small
  EN+DE keyword heuristic (word-start stems, ≤ 4-letter stems whole-word
  only) that **prefills** the selection for new expenses until the user
  picks one — never on edit.
- **Custom categories (G47)**, per group, synced: the **signed group meta**
  carries an optional `categories` list `[{id: "c:<uuidv7>", name, icon,
  hidden?}]` (`CustomCategory`, `GroupModel.categories`) — in the meta's
  signed body / G27 hash / payload **only when non-empty** (so every
  pre-G47 meta signature and hash is unchanged — golden in
  `test/core/group_categories_wire_test.dart`); `hidden` only when true.
  Content rules (`groupMetaProblem`, `RecordGate.meta` → `invalid_record`):
  ≤ `kMaxCustomCategories` (50), ids `c:…` ≤ 64 chars and unique, names
  trimmed 1 … 40 UTF-16 units (`isValidCategoryName`), icon a key of the
  fixed `kCustomCategoryIcons` (16 stable keys → Material icons in
  `customCategoryIconData`; never rename a key). A malformed `categories`
  value parses to an invalid entry, so it's refused rather than trimmed.
  Expense `category` stays a string: a built-in wire id or a `c:` id;
  `resolveCategory(id, group.categories)` → `ResolvedCategory` (built-in or
  custom; a hidden custom one still labels its expenses; an id the group
  doesn't define → *Other*, kept verbatim). Colour of a custom category:
  `avatarIndexFor(id)`. Managed by `GroupEditor.addCategory` /
  `updateCategory` (rename / icon / hide; no delete) — a new meta version
  with `nextLwwClock`, signed, relayed as `com.moneyledger.group` to the
  active claimed members like a G10 edit (`GroupEditor.edit` keeps the
  categories); any active member may. UI: *New category…* in the selector
  (`showCategoryDialog`: name + icon grid, duplicate names refused
  case-insensitively) and group settings → *Categories*
  (`GroupCategoriesPage`, `/groups/:id/categories`; add / rename / hide,
  read-only for non-members). Drift **schema v11**: nullable
  `groups.categories_json` (`encodeCategories` / `decodeCategories`); the
  v10 → v11 migration deletes `rejected_versions` rows of kind `meta` (a
  pre-G47 build refuses metas carrying categories — like G16). Filters use
  string keys (`LedgerFilter.categories`: built-in wire id / custom id /
  `other`). CSV: `Category` = the id, new `Category Name` column after it
  (custom name; empty for built-ins); an import defines missing `c:` ids
  that have a name (`csvCategoriesToAdd`, default icon; a new meta version
  for an existing group). Local mode: same code, the meta is stored
  `pendingSign`, nothing relayed. Limits (mixed versions, whole-meta LWW
  loses a concurrent edit): `docs/open-points.md`.
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
  synced): ⋮ (or group settings → *On this device*) → *Archive group* (always allowed; an unsettled group gets
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

### Expense date (G49)

Expenses can be **back-dated**. `created_at` can't carry it: it is part of
the creator's signed `origin` statement (and the G27 hash), so changing it
on edit would break "added by" for every peer. Instead an optional signed
**`date`** = the **calendar day** as ISO `YYYY-MM-DD` (no time, no time
zone — a ms timestamp, even local noon, lands on another day for a peer
12+ h away). Like G16: in the payload, the signed body and the G27 hash
**only when set** (golden hash pinned in `test/core/expense_date_wire_test.dart`),
and it's only set when the picked day **differs from the local day of
`created_at`** (`storedExpenseDate`) — an expense dated today looks exactly
like a pre-G49 one, so older builds accept it.
- **Display date** = `date ?? created_at` (`ExpenseModel.displayDay`,
  `models/expense_date.dart`). The ledger list groups and sorts by it (day
  desc, then `created_at` desc), so a back-dated expense lands under its
  day. Balances don't care. Group "last activity" stays `created_at`.
- **Form:** a *Date* field under *Paid by* ("Today" / "Yesterday" / the
  date via `context.dayHeader`; tap → `showDatePicker`, year 2000 … a year
  ahead) + *Today* / *Yesterday* chips. Edit prefills the display day and
  keeps the stored `date` unless the day was changed
  (`ExpenseAdder.updateExpense(date:)` takes the resolved ISO string).
- **Content rule** (`expenseProblem` → `recordDateProblem`): a real
  calendar day, year ≥ 2000, ≤ today + 400 days (the picker allows 365).
- **Storage:** schema **v13** `expenses.expense_date` (nullable). The v12 →
  v13 step forgets refused **expense** versions (a pre-G49 build refused
  signed versions carrying `date` — same as G16's v7; mixed old/new
  devices disagree on back-dated expenses until all are updated, see
  `docs/open-points.md`). The column is added
  before the v8 / v12 backfills when an older DB migrates (they select the
  expenses table with today's columns).
- Bootstrap, JSON backup, G48 history / reset (they store `expensePayload`)
  carry it automatically; CSV see above.
- **Payments (G60)** work exactly the same: optional signed `date` on
  `com.moneyledger.settlement` (payload, signed body, G27 hash **only when
  set** — golden hash + pre-G60 body pinned in
  `test/core/settlement_date_wire_test.dart`), `SettlementModel.date` /
  `displayDay`, `settlementProblem` → `recordDateProblem`. Schema **v14**
  `settlements.settlement_date` (nullable; added before the v8 / v12
  backfills like v13's column); the v13 → v14 step forgets refused
  **settlement** versions (same reason as v13). `RecordPaymentDialog` has
  the same *Date* field + chips (`RecordDateField`, extracted from the
  expense form; keys `paymentDate*`) → `PaymentDraft.day` →
  `ExpenseAdder.addSettlement(day:)`; a delete (tombstone) keeps the date.
  The ledger list sorts payments by `displayDay` too. Payments can be
  edited (G60 follow-up, see "Settlements / recording payments"). Bootstrap / backup / G48 history + reset / CSV carry it. Tests:
  `schema_v14_migration_test.dart`,
  `test/integration/settlement_date_sync_test.dart`.

### Several payers (G76)

An expense can be paid by **several people** (Leo 2026-10-17).
- **Wire / signed content:** optional `payers: {participantId: cents}` on
  the expense payload, in the signed body and the G27 hash **only when
  set**, and then `paid_by` is **`""`** — on purpose: a pre-G76 build parses
  no `payers`, so its content rules refuse the version as "no payer"
  (`invalid_record`, before any signature check — also on the unsigned link
  path) instead of showing one person as the payer of everything. One payer
  = the pre-G76 shape (`paid_by`, no `payers`; golden hash pinned in
  `test/core/expense_payers_wire_test.dart`); every version has exactly one
  encoding (`payerFields`: zeros dropped, one left → plain `paid_by`).
- **Content rule** (`expenseProblem` → `payersProblem`): `paid_by` empty,
  2 … `kMaxPayers` (100) entries, each ≥ 1 cent, summing to the amount.
- **Model / storage:** `ExpenseModel.payersJson` (the wire map verbatim,
  like `splitsJson`); schema **v18** `expenses.payers_json` (nullable; added
  before the v8 / v12 backfills like v13's column); the v17 → v18 step
  forgets refused **expense** versions. Helpers in `models/expense_payers.dart`
  (`paidAmountsOf` — `{paidBy: amount}` for one payer —, `hasSeveralPayers`,
  `payerFields`). Every reader of `paidBy` goes through them: balances
  (each payer credited what they paid; one payer: the split's sum, as
  before), `expenseEffectFor`, the G69 overview, G73 conversion (payers
  re-spread like the split), search / *Involving me*, the payer line
  (`payer_line.dart`: "Paid by Anna and Ben" / "you and Ben" / "Paid by 3
  people"), the read-only details (G67, `detailsPayers`).
- **Form:** *Paid by* → *Several people…* (`payerSeveral`, only with ≥ 2
  people) → `PayersEditor` (`payers_editor.dart`): one amount per person
  (`payerAmount-<id>`, blank = didn't pay), live "X left" / "X too much"
  (`payersRemaining`), ⊕ *Put the rest here* (`payersRest-<id>`); *Add* /
  *Save* only when they add up. `ExpenseAdder.addExpense` / `updateExpense
  (payers:)` (throws `ArgumentError` on a map that doesn't add up). Edit
  reopens the editor prefilled; picking one person again stores the plain
  shape. A duplicate (G75) keeps the payers while all are still in the group.
- **CSV:** a multi-payer row has an **empty `Paid By`** (a pre-G76 import
  aborts, "no payer") + trailing `Paid: <name>` columns after `Created At`
  (`csvPaidPrefix`; written only when the group has such an expense; a
  single payer's column = the whole amount). Bootstrap / JSON backup / G48
  history + reset carry `payers` automatically (`expensePayload`).
- Tests: `test/core/expense_payers_wire_test.dart`,
  `test/features/g76_multi_payer_test.dart`, `schema_v18_migration_test.dart`,
  `test/integration/multi_payer_sync_test.dart`,
  `test/g76_multi_payer_form_test.dart` (incl. 360 dp / 200 % EN + DE),
  `csv_import_test.dart` (G76 group), G71 guideline test. Limits:
  `docs/open-points.md`. Smoke 5.22.

### Receipt photo, this device only (G78)

Leo 2026-10-17: a photo attached to an expense, **stored only on this
device** — never synced, never in a backup file / snapshot / CSV, **Android
only** (hidden on the web, desktop and in the offline demo). `lib/features/receipts/`.
- **Storage:** `<app support>/receipts/<ledger DB name>/<expense id>.jpg`
  (per account / local ledger like the G48 snapshots; temp file + rename,
  a leftover `*.jpg.tmp` is deleted by the next `list`). **No schema
  change** — file existence is the flag. `ReceiptStore` (`FileReceiptStore`
  / `InMemoryReceiptStore` for tests), `receiptStoreFactoryProvider`
  (`(dbName) → store`, null = unsupported: web via conditional export,
  `!Platform.isAndroid` — so the test VM has none —, `kOfflineDemo`),
  `receiptStoreProvider` (current ledger; tests override it),
  `receiptsSupportedProvider`, `receiptIndexProvider` (AsyncNotifier: the
  ids with a photo + `read` / `save` / `remove`).
- **Picker seam:** `receiptPickerProvider` (`ReceiptSource` → bytes / null =
  cancelled). Real: `image_picker` `pickImage(maxWidth/maxHeight: 1600,
  imageQuality: 80, requestFullMetadata: false)` — scaled + recompressed
  natively (no `image` package); its cache copy is deleted after reading.
  Camera = the camera app via intent (**no CAMERA permission** — declaring
  it would make image_picker request it), gallery = system photo picker /
  file chooser (no storage permission). The manifest **removes**
  image_picker's `com.google.android.gms.metadata.ModuleDependencies`
  service (Play-services photo-picker backport hook; F-Droid). Both pinned
  in `test/core/android_manifest_test.dart`.
- **Form** (`ReceiptField`, after the note, only while supported): *Add
  receipt photo* → sheet *Take photo* / *Choose from gallery*; thumbnail
  (tap → `ReceiptViewerPage`, `InteractiveViewer` pinch zoom) + *Replace* /
  *Remove*; hint "Only on this device — not shared with the group, not in
  backups." Nothing is written before *Add* / *Save*: a new expense's photo
  is stored under the id `addExpense` returned; an edit's change on *Save*;
  a **photo-only change** of an edited expense writes **no new version**
  (nothing to sync — snackbar *Receipt photo saved / removed*). A picked /
  removed photo makes the form dirty (G56 discard prompt). A G75 duplicate
  starts without a photo. Ledger rows: `Icons.photo_outlined` with
  `semanticLabel` "Has a receipt photo" (a merged row keeps only one
  tooltip — G71).
- **Lifecycle:** expense deleted (here or by a peer) → photo kept while the
  session lasts (G67 *Undo* / G48 reset bring it back), removed by
  `receiptMaintenanceProvider` (watched in `LedgerSyncHost`, once per
  ledger DB open: `sweepReceipts` deletes photos whose expense is
  tombstoned or gone). Leave / delete group → `GroupExiter._purge` deletes
  the group's photos at once (ids read before `purgeGroup`; a purge on
  another device's leave is swept at the next start). *Delete local data* →
  `localDatabaseDeleterProvider` → `deleteLedgerFilesAndSnapshots(receipts:)`.
  **Local adoption moves** them into the account's store (`moveReceipts`,
  same expense ids) before the local files go. Sign-out keeps them.
- Privacy: PRIVACY.md + `privacyReceipts*` (pinned equal by
  `test/features/receipts_test.dart`). Limits: `docs/open-points.md`.
  Tests: `test/features/receipts_test.dart`, `test/g78_receipt_photo_test.dart`,
  `test/features/local_mode_test.dart` (adoption moves), G71 a11y.

### Payment details + GiroCode, device-local (G74)

Optional **own** bank account (account holder, IBAN, optional BIC) and
PayPal.me name — Settings → *Payment details* (`PaymentDetailsTile` →
`/settings/payment`, `kPaymentDetailsLocation`, `PaymentDetailsPage`).
`lib/features/payment/`.
- **Storage:** `AppSettings` `payment_details` (JSON, `PaymentDetails.encode`;
  `SettingsDao.watchPaymentDetailsRaw` / `setPaymentDetailsRaw` /
  `clearPaymentDetails`) — **per ledger, device-local, never synced**, not in
  a backup file / snapshot / CSV; `adoptLocalLedger` copies it into the
  account (unless the account has its own). `myPaymentDetailsProvider`
  (tests: `testOverrides(paymentDetails:)`). `toString` hides the data —
  never log an IBAN.
- **Pure** (`payment_details.dart`): `normalizeIban` / `isValidIban` (format,
  mod-97, length for known countries `kIbanLengths`), `formatIban` (groups of
  4), `isValidBic`, `normalizePaypalMe` (name, `@name`, pasted link → name;
  letters + digits ≤ 20), `paypalMeUrl(user, cents:, currency:)`
  (`…/12.50EUR`, 0 decimals for JPY & co.), `epcQrPayload` — EPC069-12
  "BCD" **v002** (BIC optional), UTF-8, `SCT`, name ≤ 70, amount
  `EUR12.50` (left out beyond 999 999 999.99), reference = the group name
  (≤ 140, cut until the payload ≤ 331 bytes); null unless EUR + a bank
  account.
- **UI:** balance page — a debt **owed to me** with details set gets a QR
  icon button (`paymentQr-<from>-<to>-<cur>`, tooltip `paymentShowDetails`)
  → `showPaymentRequestSheet`: "{name} pays you {amount}", segmented *Bank
  transfer* / *PayPal* when both, GiroCode (`QrCodeView`, G52) + IBAN +
  *Copy IBAN*, or the PayPal.me link as QR + *Share link* (`shareOrCopy`);
  non-EUR → no GiroCode, IBAN as text. Shown on **this** screen for the
  payer to scan — nothing is sent. Privacy: PRIVACY.md + `privacyPayment*`
  (pinned equal by `test/features/payment_details_test.dart`).
- **Not done — needs Leo (plan.md G74):** showing the payee's details on the
  *payer's* device needs a synced field (wire + privacy decisions: carrier
  record, opt-in per group, link groups, old builds). Tests:
  `test/features/payment_details_test.dart`, `test/g74_payment_details_ui_test.dart`,
  G71 guideline tests. Limits: `docs/open-points.md`.

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
currency; balances are per currency; G66: the full ISO-4217 list with
search in every picker).

**Editing a payment (G60 follow-up).** Tapping a payment row in the ledger
(or its ⋮ → *Edit*; ⋮ → *Delete* stays) runs `editPaymentFlow`
(`settle_up.dart`): `RecordPaymentDialog(editing: true)` prefilled with
from / to / amount / currency / day (`initialDay` = `displayDay`), titled
*Edit payment*, *Save* (key `paymentSubmit`) disabled until something
changed, the G6 attribution ("Added by · Last edited by") as its `footer`.
The payment's own two sides stay selectable even if one has left.
`ExpenseAdder.updateSettlement` writes the new version like an expense edit:
`nextLwwClock(stored)`, `created_at` + the creator's `origin` kept, signed by
this device (editor), stored (G48 history: source local) and relayed; same
day as before → the stored `date` unchanged, else `storedExpenseDate`. A
payment deleted meanwhile (or gone) → `RecordDeletedException`, nothing
written, snackbar `paymentGone`. Read-only (removed) groups: no tap, no
menu. Tests: `test/g60_payment_edit_test.dart`,
`test/integration/settlement_edit_sync_test.dart`.

### Exchange rates + settle in one currency (G73)

Fixed, **hand-entered** rates per group (U18) — in the **signed group meta**,
like G47's categories **only when set** (absent = pre-G73 body / G27 hash —
golden in `test/core/exchange_rates_wire_test.dart`):
`"exchange_rates": {"base": "EUR", "rates": {"CHF": "1.0797"}, "settle": true}`
(`ExchangeRates`, `models/exchange_rates.dart`; `GroupModel.exchangeRates`).
A rate = what **1 unit** of the currency is worth in `base`, as a
**canonical decimal string** (canonical JSON has no floats; `isValidRate`:
no leading / trailing zeros, ≤ 9 + 10 digits, > 0); `settle` only when true
= "settle up in {base}". Content rules (`exchangeRatesProblem` in
`groupMetaProblem` → `invalid_record`): base + codes = 3 capital letters, a
code ≠ base, 1 … `kMaxExchangeRates` (50) rates, no unknown keys; a
malformed value parses to an invalid entry (refused, never dropped). Schema
**v17** `groups.exchange_rates_json` (added before the v12 backfill; the
v16 → v17 step forgets meta refusals like v11 / v16). Whole-meta LWW (a
concurrent rate + name edit loses one — G57). G48 reset / G58 exact state
reset the rates with the meta; bootstrap / backup carry them; not in the CSV.
- **Balances:** `ledgerForSettling` (`features/balance/settle_currency.dart`,
  pure) — with `settle` on, every expense / payment in a currency **with a
  rate** is converted into `base` for the calculation only (amount via
  `convertCents`: BigInt, half away from zero, hundredths → hundredths for
  every currency incl. JPY; the split re-spread over the same people by
  `distributeByWeights`, so it sums exactly); others stay separate (also a
  record whose converted amount would exceed `kMaxAmountCents`). Used by
  `balanceForRoomProvider` (via `settlingLedgerProvider` +
  `groupExchangeRatesProvider`, `balance_provider.dart` → balance page,
  settle-up, share text, leave warning), `groupOverviewProvider` (my
  balance, totals) and the people page's removal warning. Group stats (G69)
  stay per original currency. Nothing is stored converted — turning it off
  restores the per-currency view.
- **UI:** group settings → *Exchange rates* (`exchangeRatesTile`, summary
  `exchangeRatesSummary`) → `GroupRatesPage` (`/groups/:id/rates`,
  `groupRatesLocation`): intro, *Settle up in {base}* switch
  (`settleInBaseSwitch`), rows "1 CHF = 1,0797 EUR" (`rate-<code>`,
  `displayRate` = locale decimal, no grouping) with remove
  (`removeRate-<code>`), "used without a rate: …" (`ratesMissing`), FAB
  *Add rate* (`addRate` → currency picker → dialog). Base = the group
  currency when the first rate is added (kept if the group currency changes
  later). `RateDialog` (`rateField`, `rateSave`; `,` or `.` via
  `normalizeRateInput`). Writes: `GroupEditor.setExchangeRates` (new meta
  version, `nextLwwClock`, signed / `pendingSign` / link version, relayed;
  read-only for non-members). Balance page: "Settled in EUR …" note
  (`settledInBaseNote`, `openRatesFromBalance`) or, with several currencies
  and no conversion, *Set exchange rates* (`setExchangeRates`).
- **Fetch current rate** (`fetchRateButton`, `exchange_rate_fetcher.dart`):
  the only third-party request outside Matrix / Nostr, **only on tap**:
  `GET https://api.frankfurter.dev/v2/rate/<from>/<base>` (Frankfurter —
  open source, free, no key / account / cookies, ECB + central-bank
  reference rates, CORS ok; ~30 currencies, others → 404 / 422 →
  `RateUnavailableException` → "enter it yourself"). The request carries
  only the two codes (pinned by a `MockClient` test); the dialog names the
  host (`fetchRateSource`); the fetched value is only filled in (date shown)
  until *Save*. Test seam `exchangeRateFetcherProvider` (tests never hit the
  network). PRIVACY.md + `privacyRates*` (pinned equal), and the G43
  "only Matrix homeservers" texts (`privacyNoTrackingBody`,
  `privacyLocalBody`, summary table) name it as an exception.
- Mixed versions: a pre-G73 build refuses signed metas carrying rates (bad
  signature) until updated — `docs/open-points.md`. Tests:
  `test/core/exchange_rates_test.dart`, `exchange_rates_wire_test.dart`,
  `test/features/settle_currency_test.dart`,
  `test/integration/exchange_rates_sync_test.dart`,
  `test/database/schema_v17_migration_test.dart`,
  `test/g73_exchange_rates_test.dart`, G71 guidelines.

### Share, overview, groups order (G69)

- **Share "who pays whom" (U17):** balance page app bar → *Share*
  (`shareBalances`, hidden when the group has neither debts nor expenses).
  Pure `buildBalanceShareText` (`features/balance/balance_share.dart`):
  title "<group> – wer zahlt wem", one line per suggested payment
  "Ben → Anna: 42,10 €" (per currency a block "In CHF:" when there are
  several; never netted), no debts → "Alles ausgeglichen.", footer
  "Erstellt mit MoneyLedger" — no link, no tracking, **names only, never
  "you"** (the others read it). Sent via `textSharerProvider`
  (`core/platform/text_sharer.dart`, test seam) → `SharePlus.instance.share`
  (Android chooser / browser Web Share API); a throw (no Web Share API,
  e.g. desktop Firefox — share_plus's mailto fallback stays off) →
  `shareOrCopy` copies to the clipboard + snackbar `shareCopiedFallback`.
  Nothing new leaves the device except what the user sends (system sheet) —
  no PRIVACY.md change.
- **Overview (U19):** below the balances, per currency (`stats-<CUR>`):
  total spent + count, per person *paid* / *share* (under the name — fits
  360 dp at 200 % font), the 5 biggest categories as bars
  (`kStatsTopCategories`; the rest summed in one row; no category → "No
  category"). Pure `groupStats` (`features/balance/group_stats.dart`):
  live expenses only (payments are transfers), categories resolved like the
  ledger (`resolveCategory`), malformed splits skipped like the balances.
  A settled group with expenses shows `_SettledCard` + the overview (the
  full-page empty state only when there is nothing at all).
- **Groups list order (U20):** non-archived groups sorted by
  `groupActivityAt` = max(`GroupOverview.lastActivityAt` — newest record
  `created_at`, what the card shows —, the group's creation from its
  UUIDv7 id, `uuidV7Millis`), newest first; unknown last; ties by name.
  `sortGroupsByActivity` (`group_overview_provider.dart`). The archived
  section keeps its DB order.
- Tests: `test/features/g69_share_stats_sort_test.dart`,
  `test/g69_share_overview_test.dart` (EN + DE, 360 dp, 200 % font, groups
  order), `test/g71_accessibility_test.dart` (overview guidelines).

### Undo + read-only details (G67)

- **Undo (U13):** deletes keep their confirmation (Leo) and then show
  "Deleted …" / "Payment deleted" with *Undo* (8 s, `UndoSnack` in
  `features/expenses/record_actions.dart`); *Record payment*, adding /
  editing an expense and editing a payment show their confirmation with
  *Undo* too. `ExpenseAdder` writes return an `UndoableWrite`
  (`record_undo.dart`: the version written + the content before; null =
  created). `RecordUndoer.undo` re-reads the record, the pure `planUndo`
  checks the stored version is still **exactly** the one written (clock +
  G27 hash — someone else's newer change → `UndoOutcome.changedMeanwhile`,
  nothing written, snackbar `undoChangedMeanwhile`), then applies it through
  `GroupResetService.apply` (a one-record G48 reset: `nextLwwClock`, the
  creator's `origin` kept, signed by this device / `pendingSign` / unsigned
  in a link-only group, history source `revert`, relayed). Undoing a
  creation writes a tombstone.
- **Delete in the forms:** edit-expense app bar (`deleteExpenseButton`) and
  the edit-payment dialog (`paymentDelete` → `PaymentDeleteRequest`) — same
  confirm + undo (`deleteExpenseFlow` / `deleteSettlementFlow`).
- **Read-only details (U15):** in a group we were removed from, tapping an
  expense / payment opens a details sheet (`record_details_sheet.dart`:
  amount, payer, day, category, split per person, note, attribution).
  The removed / archived banners put their action below the text
  (`forceActionsBelow` — at 360 dp it overflowed).
- Tests: `test/integration/record_undo_sync_test.dart`,
  `test/features/record_undo_test.dart`, `test/core/action_errors_test.dart`,
  `test/g67_undo_errors_test.dart`.

### Review leftovers (G75)

- **Plain-language verification texts (U27):** *Only sync with verified
  devices* and *Devices & security* sit in their own settings section
  *Advanced (Matrix)* / *Erweitert (Matrix)*. The switch's subtitle is one
  or two short sentences (on: "only sends to devices you have verified — a
  new login of yours too. Other devices keep syncing with each other"); the
  confirmation (`_VerifiedOnlyConfirmContent`) says three sentences — only
  verified devices get this device's changes, unverified ones (someone's
  new phone, a new login of yours) get nothing until verified, it only
  limits what this device sends — and the rest (where to verify, a new
  login can't restore from here, inbound still accepted) is behind *Learn
  more* (`verifiedOnlyLearnMore` → `verifiedOnlyMoreBody`). Signature
  details avoid "signing device" / "signature": "Can't be checked — the
  device that wrote it may have signed out".
- **Web limits (U31):** on the web the groups page shows
  `WebLimitsBanner` (`features/web/web_limits.dart`) until *Got it* —
  device-wide flag `DevicePrefs.webNoticeSeen` (`web_notice_seen`, stored
  in this browser): syncs only while the tab is open (no background sync),
  no restore points, data only in this browser — back up now and then
  (*Back up* → `/backup`). Local mode: the text without the sync part
  (`webLimitsBodyLocal`). About → *MoneyLedger in the browser* shows it
  again (`WebLimitsAboutTile`, web only). Test seam: `isWebProvider`
  (`core/platform/is_web.dart`).
- **Duplicate expense:** row ⋮ → *Duplicate* (`duplicateExpenseMenuItem`)
  and the edit form's app-bar copy icon (`duplicateExpenseButton`; a
  changed form asks *Discard changes?* first, then the edit page is
  **replaced**) open `AddExpensePage(copyFrom:)` at
  `duplicateExpenseLocation(groupId)` (`/groups/:id/expenses/duplicate`,
  `extra` = the stored expense): description, amount, currency, payer,
  split, category, note prefilled, dated **today**, a new id on *Add* —
  nothing is written before. People who left are dropped from the copy
  (`duplicateSplit`: the amount spread equally over the rest; nobody left
  → the default equal split; a payer who left → me). Not offered in
  read-only groups (no row menu there).
- **Calculator (amount fields) — accepted when pasted, not advertised
  (G79, Leo 2026-10-17):** Gboard's decimal keypad (the amount fields keep
  `numberWithOptions(decimal: true)`) has only `-`, so the UI never mentions
  a calculator (no hint, helper or docs promise). A pasted / hardware-typed
  expression in the expense amount, the payment amount or an item amount
  is still read: `+ - * /` (also `× ÷ ·`), standard precedence, optional
  parentheses, one sign only at the start or after `(` — pure
  `parseAmountInput` (`core/l10n/formatting.dart`): every number read like
  `parseAmountCents` (locale `,` / `.` rules, `1.234` = 1234 in German),
  the **result** rounded once to the currency step (`10/3` → €3.33,
  `1000/3` JPY → ¥333); without an operator it is `parseAmountCents`
  itself. Malformed / division by zero → null (same invalid state as
  before); the live preview shows the result ("= 20,50 €"); the range check
  (1 cent … `kMaxAmountCents`) stays the caller's. The split editor's
  exact rows don't calculate. Tests: `test/core/amount_expression_test.dart`.
- **G64 leftovers:** renaming a person shows the duplicate-name hint live
  (`showTextPrompt(helperFor:)`, `duplicatePersonRenameHint`; other people
  incl. former ones, not the person itself). In local mode the delete
  confirmations say "will be deleted from this device"
  (`deleteExpenseBodyLocal` / `deleteSettlementBodyLocal`,
  `confirmDeleteExpense(localOnly:)`).
- **Try again (G67 leftover):** `ActionErrors.show(…, retry:)` makes
  *Try again* (`actionErrorRetry`) the snackbar action and moves *Details*
  into the content. Used where the action simply runs again: full / group
  backup export, CSV export, reading the picked backup / CSV file
  (restore, import). Not for writes that aren't idempotent or that need the
  user's input again (edit dialogs, sign-out, restore itself).
- Tests: `test/g75_polish_test.dart`, `test/verified_only_ui_test.dart`,
  `test/settings_page_test.dart`, `test/g64_people_test.dart` (rename
  hint), `test/core/device_prefs_test.dart`, `test/g71_accessibility_test.dart`
  (web notice, edit-form actions).

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
- **Former members on edit (G63 / U11):** the form lists the group's
  **active** participants plus — on edit only — every participant the
  expense itself references (payer + split keys) even if they left / were
  removed (`editorParticipants`, `add_expense_page.dart`; former ones last,
  marked *no longer in the group* — `formerMemberTag` — in the split row and the
  payer dropdown; never included by default). A new expense offers active
  ones only. An **untouched** split (no split interaction, same amount) is
  saved exactly as stored (same map incl. key order — re-resolving could
  move a remainder cent). Tests: `test/g63_former_member_edit_test.dart`.
- **Mode labels (G63 / U14):** *Equally / Amounts / Shares / %* (DE *Gleich
  / Beträge / Anteile / %*; "Gleichmäßig" doesn't fit four segments at
  360 dp); the "%" segment has the semantics label + tooltip *Percent* /
  *Prozent* (`splitPercent`). Pinned at 360 dp in `g61_split_names_test.dart`.
- **Smarter defaults (G59)** — pure helpers in `split_calculator.dart`:
  `distributeRest(total, fixed, open)` (rest spread equally, largest
  remainder; empty when rest ≤ 0 / nobody open), `rescaleProportionally`,
  `sharesFromWeights` (simplest whole shares: equal → 1 each, cents ÷ GCD —
  re-resolving gives the same cents; fractional weights via hundredths; G61:
  given the `total`, the smallest shares summing to ≤ `kMaxNiceShares` (20)
  that resolve to **exactly** the same cents win — 3.33 / 6.67 € → 1 / 2,
  not 333 / 667 — else the GCD form),
  `percentsFromWeights` (hundredths summing to exactly 100 %, e.g.
  33.34/33.33/33.33), `percentToHundredths` / `hundredthsToPercent`. Editor:
  - **Mode switch converts the current split** (Equal → Exact: the equal
    cents, excluded = `0`; → Shares; → Percent; Exact/Shares/% → Equal: the
    included set) — but only a **complete** split (Exact adding up, % at
    exactly 100, ≥ 1 weight/person); an incomplete one leaves the target's
    own inputs. A **peek** (switch away and back, no edit, same total)
    restores exactly what was there. No amount yet → Exact rows are blank.
    The edit flow converts the stored split the same way (it opens in Exact
    with the stored amounts as *typed* rows, others `0`).
  - **Exact / Percent: blank = open, `0` = not involved.** Rows the editor
    wrote itself (prefill, *Distribute*) stay "auto" (open) until the user
    types in them (`_autoExact` / `_autoPercent`). Status line: *Adds up* /
    "X left" / "X too much" (`splitLeft` / `splitTooMuch`) + one action —
    **Distribute** (total − typed rows spread over the open rows, when that
    rest is > 0) else **Rescale proportionally** (scales every value; the
    "total changed under typed amounts" case). Per-row ⊕ "Put the rest here"
    (visible while something is left, space reserved) adds the whole
    remainder to that row. Percent works in hundredths with the same
    actions. Hint line "Empty fields share the rest · 0 = not involved".
  - **Live remainder + more actions (G61 follow-up, Leo 2026-10-17: keep
    the *Distribute* button):** the "X left" / "X too much" label (key
    `splitRemaining`, error colour, `titleSmall`) sits in **one wrapping
    row** (`Wrap`) with the actions and updates on every keystroke.
    Exact, rows sum to more than the amount (or no amount yet but rows
    typed): **Set total to the sum** (`splitSetTotal`) next to *Rescale* —
    the editor calls `SplitEditor.onSetTotal(cents)` (only offered when the
    callback is given and the sum is 1 … `kMaxAmountCents`);
    `AddExpensePage` writes it into its amount field via
    `formatAmountInput` (locale format), so the split adds up.
  - **Shares:** −/+ steppers per row (min 0, − disabled at 0). **Fine-tune
    as amounts** (`splitFineTune`, shown with an amount and ≥ 1 share):
    switches to Exact via the normal complete-split conversion, forced even
    where a mode switch would be a "peek" (`_switchTo(convert: true)`) —
    4:1 on 5 € → 4.00 / 1.00, rows stay "auto" so *Distribute* re-balances
    after a tweak.
  - **Rows (G61):** names wrap onto up to two lines (MXID localparts share
    long prefixes — one ellipsized line made rows indistinguishable on a
    phone); Shares / Percent show the resolved amount under the name, not in
    a column. `test/g61_split_names_test.dart` (360 dp, EN+DE, also the payer
    dropdown + payment pickers, which already fit).
  - Equal/Shares/% follow a changed total automatically (resolve); Exact
    keeps its amounts and shows the mismatch. Tests:
    `test/features/split_editor_test.dart` (incl. the 5 € / 2.50 € example),
    `split_calculator_test.dart`.
- **Itemized split (G77):** *Split by items…* (`splitItemize`, a text
  button under the mode segments — a fifth segment doesn't fit 360 dp in
  German next to *Gleich / Beträge / Anteile / %*, and items are a way to
  *compute* amounts, not a mode of their own) opens `ItemSplitPage`
  (`item_split_page.dart`, pushed with `Navigator`, full screen). Items:
  optional name (`itemName-<i>`), amount (`itemAmount-<i>`,
  `parseAmountInput` — a pasted expression is read, G75/G79 — currency step G66), who shares it
  (`FilterChip`s of the **active** participants, *Everyone* chip; default
  everyone; nobody → *Select at least one person*, blocks). Pure
  `splitByItems(total, items, restMode:, step:)` (`split_calculator.dart`,
  `SplitItem(cents, people)`, `itemsSum`): each item split equally among its
  people (`splitEqually`, step); the rest (`total − items`, incl. items
  nobody shares) → `ItemRestMode.proportional` (default, by item subtotal,
  `distributeByWeights`) or `equal` (among everyone with an item); people at
  0 are absent; sums to the total exactly; null when total ≤ 0, items >
  total or nobody is in an item. Items over the total → "X too much" +
  *Set total to the sum* (`itemsSetTotal`; also with no amount yet), only
  when the editor has `onSetTotal`. *Use this split* (`itemsApply`) pops an
  `ItemizedSplit(total, split)` → the editor calls `onSetTotal` if the total
  changed and switches to **Exact** with the amounts as **typed** rows
  (others `0`, not "auto" — *Distribute* won't flatten them) → `_changed()`
  (G56 dirty, saved as the usual cents map). **Not stored** (no wire / DB
  change): an itemized expense reopens as Exact amounts like Shares / %; the
  items (`ItemSplitDraft`) live in the editor while the form is open (back
  without applying keeps them, no discard prompt). Tests:
  `test/g77_itemized_split_test.dart` (incl. 360 dp / 200 % EN+DE, save →
  stored split), `split_calculator_test.dart` (G77 group), G71 guideline
  test for the item page.
- **Out of scope:** per-item tax/tip lines, saving items, saving a default
  split per group; settlements remain split-free.

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
  Ausgabe, Zahlung, Saldo, Person / Personen, nicht mehr dabei,
  Synchronisiert*. **G64 (U6): people are "Personen" / "people" everywhere**
  — never *Mitglied(er)* / *member(s)* / *participant(s)* in user-visible
  text (ARB keys keep their old `member…` names); removed / left people are
  *nicht mehr dabei* / *no longer in the group*; "all members" → *alle in
  der Gruppe* / *everyone in the group*. *Person* is feminine ("die Person",
  "eine Person") — watch "ihr/ihre" references in German.
  `test/about_page_test.dart` checks both ARBs have the same keys/placeholders.
- **Pure helpers return structure, not text**, or take an `AppLocalizations`
  parameter (`describeAuthError` → `AuthErrorMessage.title(l)/hint(l)`,
  `unsettledWarning(debts, me, l)`, `deviceTrustSummary(devices, l)`,
  `registrationRequirementLabel(stage, l)`). Unit tests use `en`/`de` from
  `test/helpers/l10n.dart` (`lookupAppLocalizations`).
- **Amounts/dates:** `context.money(cents, currency)` (`€1,234.50` /
  `1.234,50 €`, `¥1,000` — the currency's display decimals, G66) and
  `context.date(ms)`; editable amount fields prefill with
  `formatAmountInput(…, currency:)` and parse with
  `parseAmountCents(…, currency:)`, which accepts `,` **and** `.` as decimal separator. G18 review: pass the UI
  `locale:` — a **lone** locale grouping separator followed by exactly 3
  digits is thousands (`de`: `1.234` = 1234; `en`: `1.234` stays 1.234,
  `1,234` = 1234); malformed grouping (`12,34.5`) is rejected. The amount
  fields show a live preview of the parsed value (`amountPreview`, "=
  1.234,00 €"), and only accept 1 cent … `kMaxAmountCents` (the expense
  form's *Add* and the payment dialog's *Record* stay disabled otherwise;
  `SplitPlan.resolve` is never valid for such a total). The **CSV stays machine
  format** (dot decimals, ISO dates, English headers) in every language.
- **Currencies (G66):** **storage stays hundredths for every currency** —
  the wire / DB integer is `major × 100` also for JPY (`100000` = ¥1,000);
  that was always so (JPY was offered since the first version) and real ISO
  minor units would change the meaning of existing signed records and
  between app versions (`docs/open-points.md`). Only display and input
  follow the currency (`lib/core/l10n/currencies.dart`):
  `currencyDecimals` = min(ISO, 2) — 0 for `kZeroDecimalCurrencies` (JPY,
  KRW, ISK, HUF, IDR, CLP, VND, …; our own list, independent of `intl`'s),
  else 2 (BHD / KWD / JOD / OMR / TND show 2 — a thousandth isn't
  storable); an unknown code (any string from a peer) → the code + 2
  decimals, never a crash. `currencyStep` (100 for 0 decimals) is what
  `parseAmountCents(currency:)` rounds to (`1000,5` JPY → ¥1,001) and what
  the split math hands out (`distributeByWeights(step:)`, `SplitPlan.step`:
  ¥1,000 / 3 → 334 / 333 / 333); a legacy total that isn't a whole step is
  split cent-exact and shown rounded, never refused, and a form's unchanged
  prefill keeps the stored amount (`formatAmountInput` keeps 2 decimals for
  it). `kMaxAmountCents` is unchanged (10^11 major units in any currency).
  Names: `currency_names.dart` (**generated** by
  `tool/currencies/make_currency_names.py` from Debian `iso-codes`,
  LGPL-2.1+, EN + DE, funds / metals / withdrawn codes left out; in-app
  license entry in `main.dart`). Pickers: `CurrencyField` +
  `showCurrencyPicker` (`core/widgets/currency_field.dart`; bottom sheet,
  search by code or a word of the EN / DE name, accent-insensitive; keys
  `currencySearch`, `currency-<code>`, `currencyNoMatch`) in create / edit
  group, the expense form and the payment dialog; order
  (`suggestedCurrencies`): selected, group currency, currencies used in the
  group by frequency (`groupCurrencySuggestions`), the region's, then
  `kCommonCurrencies`, then all others. **New group default** = the device
  region's currency (`deviceRegionProvider` — first system locale with a
  country; `defaultCurrencyFor`: CH → CHF, GB → GBP, DE → EUR, else EUR;
  tests override the provider). Tests: `test/core/currencies_test.dart`,
  `test/core/formatting_test.dart`, `test/g66_currency_picker_test.dart`.
- **Widget tests:** `testApp`/`testRouterApp` add the localization delegates
  (English by default, `locale: Locale('de')` for German tests); any other
  test `MaterialApp` needs `localizationsDelegates: testLocalizationsDelegates`.

### Design system (G17, "Paper & ink" since G42)

**Look (G42, chosen from three canvas directions):** paper background
(`#F6F2EA`), ink text + ink primary (filled buttons, FAB, selected segment —
`#1D1A16`), **one accent: rust** (`scheme.secondary`, *Settle up*, text
buttons), petrol for "you get money back". Summaries (groups-page totals,
group's *Your balance*) are **not cards**: a 2 px ink rule above
(`AppTheme.ledgerRule`), a hairline below, caps labels. Buttons / chips /
segments are pills; cards are flat sheets with a hairline border; group
badges are ink-ringed monograms. Dark mode = warm near-black with the same
roles. **No bundled font** — the platform's own (Roboto on Android); the web
serves the engine's Roboto itself + two fallback subsets (G43, see Building).

- **Tokens** live in `lib/core/theme/`: `app_theme.dart` (`AppTheme.light()` /
  `.dark()`, `ThemeMode.system`; component themes for cards, list tiles, FAB,
  inputs, buttons, segmented buttons, dialogs, sheets, snackbars; spacing
  `Insets`, radii `Radii`, `kContentMaxWidth` = 680, `kTabularFigures` for
  amounts; `AppTheme.cardColor`) and `app_colors.dart` (`BrandColors` — ink,
  paper, orange / rust accent, petrol, launch backgrounds — and the
  **`LedgerColors` ThemeExtension**, read via `context.ledgerColors`).
  **Never hard-code `Colors.*`** in widgets — use the scheme or LedgerColors.
- **Semantic money colours:** `positive` (petrol blue — "you are owed", "you
  lent", "gets back") and `negative` (rust — "you owe", "you borrowed"),
  plus `*Container` variants; light and dark values are pinned to WCAG-AA
  contrast by `test/core/design_system_test.dart`.
- **Font:** none bundled on Android (G42 removed Manrope) — Material's
  platform default (`Roboto` = the system font); the design test pins that,
  and that the web theme only adds `fontFamilyFallback: kWebFontFallback`
  (G43). Nothing is fetched from Google on the web (see Building).
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
  `NamesLine` (G33: a localized sentence with name placeholders — build the
  template with `NamesLine.sentinel(i)` in place of each name, e.g.
  settlement rows "A paid B", and the balance page's suggested payments "A
  pays B / You pay B / A pays you"; G18 review 2: it **wraps onto up to two
  lines**, and only if that isn't enough are the names shortened, each on
  its own to the same character cap (`capNames`), literals never cut; the
  ledger row keeps its amount on the first line).
- **Lists under an extended FAB** pad their bottom with
  `Insets.fabClearance(context)` (88 dp + the system navigation inset — a
  ListView with explicit padding doesn't add it itself), never a fixed number.
- **Ledger rows** (G33) are two independent lines — *title … amount* and
  *payer … you lent/borrowed* — so a long (German) note never squeezes the
  title. G79: the effect ("du schuldest 140,00 CHF") keeps its 70 % cap but
  wraps onto a second line (at the space before the amount) instead of
  cutting the amount.
- **360 dp truncation helpers (G79, `core/widgets/large_text.dart`):**
  `AppBarTitle` for every plain app-bar title (one line; too long → scaled
  down to ≥ 80 %; still too long → two lines at 80 %, one at a large font
  size); `SettingsSectionHeader` uses `WordSafeText` (wraps between words
  only; a single word wider than the line — "WIEDERHERSTELLUNGSPUNKTE" at
  200 % — shrinks the header until it fits); the split editor's exact cell
  drops its currency suffix when value + suffix don't fit its width
  (`_suffixFits`, cell never widened). `measureTextWidth` /
  `ScaledTextScaler` are the shared bits. Tests: the G79 group in
  `test/devi_large_font_test.dart`. The attribution footer ("Added by X · Last edited by Y") wraps
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
- **G56 UX follow-ups:** members page — a claimed member's subtitle is the
  muted `@localpart` (`memberAccountLine`, `member_model.dart`); the full
  MXID only when two participants share a name (case-insensitive) or a
  localpart; the full one is behind long-press / ⋮ → *Matrix ID*
  (`showMatrixIdDialog`, selectable + *Copy*). Groups page — *Devices &
  security* lives on the settings page (`devicesTile`), not the app bar.
  Group page — when I'm the only active member and the ledger has entries
  (the G46 empty-state CTA no longer shows), an `_AddPeopleCard` above the
  ledger offers *Add people*; dismissible per app session
  (`addPeopleHintDismissedProvider`), never in a read-only (removed) group
  or while searching. Add/edit expense — a `PopScope` asks *Discard
  changes?* (*Keep editing* / *Discard*) on ← / system back only when the
  form differs from how it opened (text fields, category, currency, payer,
  date, or any split-editor interaction — the editor's first plan push is
  the baseline); saving pops without asking. Tests: `test/g56_ux_test.dart`.
- **G71 accessibility + form flow (U30, U12):** every icon-only button
  needs a `tooltip` (= its screen-reader label); a non-tappable status icon
  is a `Tooltip` around the icon, never a disabled `IconButton` (the
  group page's sync cloud, `_StatusIcon`); meaningful icons without text
  next to them get a label (`CategoryIconTile(labelled: true)` in ledger
  rows, the row's "not synced yet" cloud `recordNotSyncedYet`) so a ledger
  row reads as one sentence; decorative ones (avatars, tiles next to their
  name) stay silent. Tap targets ≥ 48 dp — no `VisualDensity.compact` on
  icon buttons, dense inputs ≥ 48 dp high (split rows), the group title
  `minHeight: 48`. Section / day titles are `Semantics(header: true)`;
  caps labels carry a `semanticsLabel` in normal case; money is never
  colour-only (always a word: you lent / owe / gets back). Narrow fields
  must survive 200 % font (`CurrencyField` fades the code). Form flow:
  add expense autofocuses the description on a **new** expense, *Next* →
  amount (`TextInputAction.done`, decimal keyboard), the category picker
  sits after the date; the payment dialog autofocuses a blank amount and
  *Done* records a complete draft; create group: name *Next* → people
  field. Guideline tests (`androidTapTargetGuideline`,
  `labeledTapTargetGuideline`, `textContrastGuideline` with
  `AppTheme.light`, 360 dp, EN) for the main pages + focus tests:
  `test/g71_accessibility_test.dart` — add a page there when you add one.
  Device check (TalkBack, 200 % font): `docs/smoke-test.md` §11.
- **G65 settings pages (U22, U28, U21):** the settings **sheet** became a
  page, `SettingsPage` (`/settings`, `kSettingsLocation`, gear on the groups
  page — the app bar keeps only the gear and local mode's chip; *Import CSV*
  and *Sign out* moved in, the empty state keeps its own *Import CSV*).
  Sections (`SettingsSectionHeader`, `core/widgets/settings_section.dart`):
  *Account* (MXID `accountTile` + `signOutTile` → `confirmSignOut`; local
  mode: `LocalModeSettingsSection`), *Sync* (Matrix: sync
  text, `backgroundSyncSwitch`, `relaysTile`; local mode: `relaysTile` +
  the switch while a link group exists — G52 step 9),
  *Advanced (Matrix)* (G75 / U27, Matrix only: `VerifiedOnlySyncTile`,
  `devicesTile`), *Backup & restore* (`BackupSettingsSection` —
  since G70 one tile → `/backup`),
  *Data* (`importCsvTile`), *About* (`aboutTile`), *Debug* (debug builds +
  Android only). The group ⋮ menu keeps only *Add person*
  (`addPersonMenuItem`; G52's *Invite* goes here), *Archive / Unarchive*
  (`archiveMenuItem`) and *Group settings* (`groupSettingsMenuItem`); a tap
  on the group page's title opens the settings too. `GroupSettingsPage`
  (`/groups/:id/settings`, `groupSettingsLocation`): *Group* (`editGroupTile`
  name & currency, `categoriesTile`), *People* (`peopleTile` → members page;
  invite link later), *Data* (`backupGroupTile`, `exportCsvTile`,
  `resetGroupTile`), *On this device* (`archiveTile`), *Leave or delete*
  (`exitGroupTile`, error colour, last). Read-only (removed) group: edit and
  reset disabled, exit = *Delete*. The flows are shared top-level functions
  in `groups/group_actions.dart` (callers watch the auto-dispose notifiers).
  Both routes are ordinary "in" pages (signed out → login; connecting →
  login). Tests: `test/settings_page_test.dart`,
  `test/group_settings_page_test.dart`, router cases in
  `router_redirect_test.dart`.
- **Brand assets:** `tool/brand/render_icons.py` (cairosvg) renders the logo
  (G42: a split equals sign — paper bars on an ink squircle, one orange piece)
  from one geometry into `assets/brand/*.svg`, the in-app
  `logo_512.png`, Android launcher icons (adaptive + monochrome), the pre-12
  splash logo, web favicon / PWA (+ maskable) icons, the iOS set and the Play
  listing graphics `docs/store/icon_512.png` + `feature_graphic.png`
  (1024×500, German claim; `feature_graphic.svg` source). Launch
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

**Router pattern:** `routerProvider` is `keepAlive: true` and uses `refreshListenable` (a `ValueNotifier`, toggled) to rerun the redirect when `appSessionProvider`, `welcomeStatusProvider`, `connectingAccountProvider` **or** `onboardingGateProvider` changes (G39/G40: `routerRedirect({session, welcome, onboarding, connecting, location})` — prefs loading → `/splash`; signed out + welcome not seen → `/welcome` (+ public pages); signed out + seen → login / register / welcome / local setup / public; local mode = "in" like an account (own onboarding flag, no `/devices`); connecting → only login / register / public; `initialLocation` is `/splash`; tested in `test/core/router_redirect_test.dart` + the end-to-end flow in `router_provider_test.dart`). The rest of this paragraph describes the onboarding part. Do **not** make it non-keepAlive — that recreates the `GoRouter` on every auth state change, which crashes at the default initial location `/`. `routerRedirect(isLoggedIn, OnboardingStatus, location)` is the pure, unit-tested seam: signed-out users reach only `/login` + `/register`; signed in, the one-time **onboarding** flag (`onboarding_seen` in the per-account `AppSettings`) is tri-state (G25, `OnboardingGate` in `onboarding_provider.dart`): **unknown** (DB/flag still loading, incl. reloading after an account switch) → neutral `/splash`; **notSeen** → forced `/onboarding`; **seen** → off auth pages / `/` / `/splash` / `/onboarding` to `/groups`. If the flag hasn't loaded after `kOnboardingFlagTimeout` (8 s) or the stream errors, the gate logs and latches *seen* for that account (never strands the user on the splash; a late "not seen" doesn't yank them to onboarding). The wiring is tested end-to-end in `test/core/router_provider_test.dart` (listen to `routerProvider` in a container test — unlistened providers are paused; don't `pumpAndSettle` on the splash, its spinner never settles).

**Errors in user actions (G15, G67):** a user-initiated action that fails
must show it — never only `debugPrint`, and **never the raw exception text**
(G67, U25): capture `ActionErrors.of(context)` (`core/widgets/action_error.dart`)
**before the first await** and call `errors.show(error, what: l.exportFailedTitle)`
(`what` optional) → a friendly snackbar from the pure
`describeActionError(error, l)` (`core/errors/action_errors.dart`:
`classifyActionError` → interrupted (DB closed / account switched) ·
relayUnavailable · recordGone · tooLarge · linkOnly · file · storage ·
timeout · network · invalidData · unknown; by type, else by text) with the
raw text only behind *Details* (dialog, *Copy*). Inline (a failed list /
an error inside a dialog): `ActionErrorView(error:, what:)` (collapsed
*Details*). `failedWithError` / `errorWithDetail` are gone; CSV row errors
(`csvImportInvalidRow`) and `backupErrorMessage` stay as they are (already
friendly). Mutator notifiers expose the result
via `AsyncValue.guard` → read `.error` after awaiting, and only for the action
that actually ran. Background send failures go to `SyncHealth` (the
SyncEngine's repair / bootstrap answers use `_sendTracked`); malformed inbound
data is only logged (a peer must not flip our health). Never log SSO login
tokens (`redactSsoUri`). Text-prompt dialogs must own their
`TextEditingController` (`showTextPrompt`) — disposing it when `showDialog`
returns crashes the closing animation.

**Auth errors (G20):** login / SSO callback / register pages never show raw exception text. `MatrixAuthGateway` translates failures into plain port types (`auth_gateway.dart`): `AuthServerException(errcode, retryAfterMs)`, `AuthNetworkException(host)` (a transport error: **one** message "Can't reach <host>" whose hint covers "server down / wrong address / you're offline" — G43 removed the matrix.org probe that told them apart, it contacted a third party; an unwrapped raw network error → host-less `authUnreachableNoHostTitle`), `NotAHomeserverException` (`checkHomeserver` failed with a non-network error). The pure `describeAuthError(error, action:)` (`features/auth/auth_errors.dart`; falls back to matching the error text) maps them to `AuthErrorMessage{title, hint, detail}`, rendered by `AuthErrorCard` with the raw text behind a collapsed **Details**. All English strings live in `AuthErrorStrings` (one place, for G12). **Timeouts (G30):** `checkHomeserver` is capped at `kHomeserverCheckTimeout` (10 s), login/register requests at `kAuthRequestTimeout` (20 s) via the pure `withAuthTimeout` → `AuthTimeoutException` (a `TimeoutException`, wrapped as `AuthNetworkException`) → "The server took too long to respond". The SDK call isn't cancelled — a late success still signs in (**adopted**, G36). **Single flight (G36):** `AuthSingleFlight` (`auth_gateway.dart`) wraps each login / token login / registration (`operation`) and every raw homeserver request inside it (`track`) in `MatrixAuthGateway`; while an operation **or a timed-out request** is still running, a new attempt throws `AuthInProgressException` → "Still signing in…" (`AuthErrorKind.inProgress`) instead of starting a parallel `client.login` (two devices / session race). `FakeAuthGateway` uses the same guard (`pendingRequest`, `requestTimeout`, `requestsStarted`); tests: `test/features/auth_single_flight_test.dart`. Web sign-up fallback: `RegistrationRequiresWebException.signUpUrl` comes from the pure `resolveSignUpUrl` (`sign_up_url.dart`): OIDC auth metadata (MAS with `prompt=create` → `<issuer>register`, else `account_management_uri`) → `.well-known` `org.matrix.msc2965.authentication.account` → matrix.org: `app.element.io/#/register` → homeserver URL.

**Async work vs. account switch / dispose (G19):** on an account switch Riverpod 3 closes the old ledger DB **eagerly** (when `appDatabaseProvider` rebuilds), but dependents like `SyncEngine`/`LedgerSyncer` are only disposed on the next scheduler flush — so in-flight async work can outlive both its DB and its `Ref`. Rules: (1) capture the DB + DAOs (and transport/health notifier) **before the first await** — `SyncEngine`/`LedgerSyncer` read them in their constructor, `ExpenseAdder` (and the G48 `GroupResetService`) via `LedgerWriteContext`, the group mutators (`GroupCreator`/`MemberAdder`/`MemberRemover`/`GroupExiter`) via `_GroupWriteContext` (G23) — never re-read DAO providers after an await; (2) after **every** await check `_alive` (`!_disposed && !_db.isClosed`; `AppDatabase.isClosed` is set by `close()`) and bail silently; (3) in notifiers, only set `state` / use `ref` after an await when `ref.mounted`; (4) errors caught after the DB closed are expected — don't log them or report them to `SyncHealth` (its `report*` also no-op when unmounted). Regression tests: `test/integration/account_switch_sync_test.dart`, `test/features/group_mutators_lifecycle_test.dart`.

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
- **Minimal footprint (G45):** `buildMatrixClient` builds a `MoneyLedgerClient` (subclass of `Client`, used by the app **and** the background round) with `syncFilter` = `minimalSyncFilterJson()` (`core/matrix/sync_filter.dart`, matrix-free, pinned by `test/core/sync_filter_test.dart`): `room.rooms: []` (+ `types: []` on every room section), `presence.types: []`, `account_data.types: []` — no rooms (also none of the account's Element rooms / invites), presence or push rules / account data are fetched or cached. **to-device, `device_lists` and the one-time-key counts are not filterable** and the SDK's `_handleSync` handles them independently of rooms (verified on matrix.org with curl: a to-device message and an own-device `device_lists.changed` arrive with the filter). `syncPresence = offline` (`kSyncPresence`) → `/sync` sends `set_presence=offline`, never marks the user online. **Filter-id caching:** the SDK defines the filter once (`_checkSyncFilter`, only when `syncFilterId == null`) and keeps the id in its store (`sync_filter_id`) forever; Synapse dedupes identical filters. So `MoneyLedgerClient.syncFilterId` returns the stored id only when it equals the id recorded in a **device-local marker** (an SDK account-data-box entry `io.github.leostumpf.moneyledger.sync_filter` = `{filter_id, filter: <filter text>}`, written by the `defineFilter` override — never uploaded, wiped with the session) → a pre-G45 install (or a changed minimal filter) defines it again before its next `/sync`. Before that, `buildMatrixClient` runs `db.clearCache()` once (`syncCacheFromOtherFilter`) to drop rooms / members / presence / account data synced with the old default filter (Olm sessions, device keys, the session stay; `prev_batch` goes → the next `/sync` is an initial one, undelivered to-device messages still arrive). Kept on purpose: the device display name **"MoneyLedger"** and the automatic profile-name refresh (reads only). What the homeserver still keeps (PRIVACY.md + `privacyHomeserverBody`, pinned equal by the test): the account, its devices (named "MoneyLedger", last seen IP/time), device + one-time keys, undelivered encrypted to-device messages until fetched (or the device is removed), and the metadata who exchanges messages with whom / when / how much.
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
  "date": "2026-06-12",
  "origin": { "user": "@alice:matrix.org", "device": "AAAA", "key": "<b64 ed25519>", "sig": "<b64>" },
  "sig":    { "user": "@bob:matrix.org",   "device": "BBBB", "key": "<b64 ed25519>", "sig": "<b64>" }
}
```

`paid_by` and the `split` keys are **participant ids** (see Participant identity above), not necessarily MXIDs. `category` (a G16 wire id) and `note` are **optional** — omitted when unset, signed and hashed only when present (see "Categories, notes, search, archive (G16)"). So is `date` (G49): the ISO calendar day the expense happened, present only when it differs from `created_at`'s day (see "Expense date (G49)"). G76: `payers` (`{participantId: cents}`, optional) — only when several people paid, and then `paid_by` is `""` (see "Several payers (G76)").

**`com.moneyledger.settlement`** content: `{ "v", "id", "group", "amount", "currency", "from", "to", "created_at", "updated_at", "deleted", "date"?, "origin", "sig" }` (`from`/`to` are participant ids; `date` — G60, optional ISO `YYYY-MM-DD`, only when the payment is back-dated, signed and hashed only when present, exactly like the expense `date`).

**`com.moneyledger.member`** (participant) content: `{ "v", "group", "participant_id", "name", "matrix_id", "status", "updated_at", "sig" }` — `matrix_id` is null for a local participant. (`user` is the pre-virtual-users key, still read on the receiver for forward-compat.) **`com.moneyledger.group`** (meta): `{ "v", "group", "name", "currency", "updated_at", "categories"?, "link"?, "locked_at"?, "exchange_rates"?, "sig" }` — `categories` (G47, optional, only when the group has custom categories): `[{ "id": "c:<uuidv7>", "name": "Dog", "icon": "pets", "hidden": true? }]`, part of the signed body and the G27 hash only when present. `exchange_rates` (G73, optional): `{ "base": "EUR", "rates": { "CHF": "1.0797" }, "settle": true? }` — rates as canonical decimal strings, likewise only when set (see "Exchange rates (G73)").

**`com.moneyledger.digest`** (anti-entropy) — sent per group to all claimed members *including self*. Maps are `id → "<updated_at>:<hash8>"` (G27; a bare int = clock only), **tombstones included**; `meta_hash` is the meta's hash8; the `members` map (keyed by participant id) doubles as membership/identity gossip — each entry is the full **signed** member version (verified like a member payload). `rejected` (optional, G6) lists versions the sender refused (`{expenses: {id: T}, settlements: {…}, members: {pid: T}, meta: T}`) so peers don't re-send them; G18 review 2: the highest refused version per id — further ones ride in an optional `rejected_more` (`{expenses: {id: ["T:hash8", …]}, …, meta: [...]}`). A `reply: false` digest is answered once with `reply: true` (bounded two-message exchange):
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
