# MoneyLedger — Implementation Plan

**Active plan: Phase G — release readiness.** A full audit of open points
(2026-10-15), sorted **major → minor**. Each item states *what's wrong*, *why it
matters*, and commit-sized `[ ]` substeps. Architecture and design decisions live
in [`CLAUDE.md`](CLAUDE.md); durable limitations in
[`docs/open-points.md`](docs/open-points.md).

Convention: one milestone = one commit (tests green first), then commit + push.
Tick boxes as milestones land.

Severity legend:
- **Major** — blocks a public release, loses/leaks data, or breaks a platform.
- **Minor** — UX gaps, polish, test/tooling debt; ship-able without them.

---

## Phase G — Major

### G1. Android release build has no network access 🔴 (blocker)
`android/app/src/main/AndroidManifest.xml` has **no**
`<uses-permission android:name="android.permission.INTERNET"/>` — Flutter only
adds it in the `debug/` and `profile/` manifests. Every device test so far ran a
debug build, so this never surfaced; a `flutter build apk --release` cannot reach
any homeserver (login + sync dead).
- [x] Add the INTERNET permission to `src/main/AndroidManifest.xml`
- [x] Release APK on emulator: homeserver resolves, sign-in gets a real server reply
      (full login + sync round-trip moves to G7, needs test accounts)
- [x] Release build was also broken by file_picker 8.x (compileSdk 34 vs. 36 required):
      `android/build.gradle.kts` now raises library plugins to compileSdk 36

### G2. Android E2EE build depends on out-of-repo pub-cache patches 🔴
`flutter_vodozemac` 0.5.0 only builds on Android with two hand-patches in
`~/.pub-cache` (`cargokit/gradle/plugin.gradle`: `Project.exec` → injected
`ExecOperations` for Gradle 9; `android/build.gradle`: `compileSdkVersion 33 → 36`).
A `pub cache repair`, version bump, fresh clone or CI machine loses them →
Android stops building. Not reproducible by anyone but this machine.
- [ ] Vendor `flutter_vodozemac` into the repo (e.g. `third_party/flutter_vodozemac/`)
      as a `path:` dependency with both patches committed
- [ ] Document the Rust toolchain requirement (nightly? targets
      aarch64/armv7/x86_64/i686-linux-android) in README + CLAUDE.md
- [ ] Verify a clean clone builds an APK after `flutter pub cache clean`
- [ ] Check upstream for a release that fixes Gradle 9 / compileSdk — drop the
      vendored copy if so
- [ ] The G1 compileSdk override in `android/build.gradle.kts` may already make the
      `compileSdkVersion 33 → 36` patch unnecessary — verify; consider upgrading file_picker

### G3. Release signing uses the debug key 🔴
`android/app/build.gradle*` → `release { signingConfig = signingConfigs.getByName("debug") }`.
A Play-Store upload is rejected; a sideloaded debug-signed APK can't be upgraded
by a properly signed one later (users would have to reinstall → lose local data,
see G5).
- [ ] Create an upload keystore (outside the repo), `key.properties` + gitignore
- [ ] Wire a `release` signingConfig that reads `key.properties`
- [ ] Document the signing setup (where the keystore lives, backup!)

### G4. Local ledger is shared across Matrix accounts on one device 🟠 (privacy)
The Drift DB is a single global file (`money_ledger_db`); `logout()` only calls
`client.logout()` and never touches Drift. `ledgerGroupsProvider` shows **all**
groups. If user A logs out and user B logs in on the same device/browser, B sees
all of A's groups, expenses and member list, and B's `SyncEngine` starts sending
digests for A's groups (dropped by peers' membership gate, but still leaks
metadata to A's peers and spams them).
- [ ] Decide: per-account DB file (`money_ledger_db_<hash(mxid)>`) **or** wipe
      on logout with a "export CSV first?" warning. Recommendation: per-account DB
      (logout stays non-destructive; re-login restores instantly)
- [ ] Implement + make `appDatabaseProvider` depend on the logged-in MXID
- [ ] Test: two accounts on one device never see each other's groups

### G5. No recovery when the last device is lost 🟠 (data loss)
Ledger data exists only on members' devices. Recovery relies on *another device*
(own or a peer's) answering `resync_request`. A single-device user who uninstalls
or loses their phone **and** has no group peers online loses everything; even with
peers, only groups that have peers are recoverable — solo/local-only groups
(all participants virtual) are gone. CSV backup is manual and lossy (no
settlements/tombstones).
- [ ] Onboarding / settings: explain "your data lives only on your devices"
      and recommend a second device or regular export
- [ ] Full-fidelity backup format (JSON/zip: settlements, tombstones, stable
      participant ids) — export + import, reuse `bootstrap` codec
- [ ] Optional: periodic "you haven't backed up in N days" nudge for groups
      with no claimed peer

### G6. Per-record cryptographic authorship 🟠 (trust model)
Membership gating authenticates the *relaying sender*, not the *author*: any
active member can create/edit/delete an expense or settlement "as" another
member (e.g. delete someone else's expense, record a fake settlement from them).
Digest membership gossip is likewise gated only by sender membership.
- [ ] Design doc: sign each record (author MXID + device Ed25519 key, the
      vodozemac identity key is already there) over a canonical payload encoding;
      record `author` field; protocol `v: 2` with v1 read-compat
- [ ] Policy: who may edit/delete what (author-only? any member + audit trail?)
- [ ] Implement signing + verification in `ledger_payloads.dart` / `LedgerSyncer`
- [ ] Key distribution/rotation: handle device changes, logged-out devices
- [ ] Tests: forged record from another member is rejected; legit edit accepted

### G7. Never verified on real devices: SSO, registration, SAS, iOS 🟠
Covered only by unit/widget tests against fakes:
- SSO native deep link `moneyledger://sso-callback` (Android + iOS)
- Registration UIA on a real homeserver (dummy path + captcha/email/terms fallback)
- SAS emoji verification round-trip (needs two devices + olm)
- **iOS has never been built or run at all** (no vodozemac/Rust setup documented
  for iOS, `ios/Runner` is template-level)
- [ ] Manual smoke checklist in `docs/smoke-test.md` (steps + expected result)
- [ ] Run it on Android release build (after G1–G3)
- [ ] Run it on web release build
- [ ] iOS: build vodozemac for iOS, run on simulator/device, record findings
      (or explicitly declare iOS unsupported for v1)

---

## Phase G — Minor

### G8. Settlements can't be viewed, edited or undone in the UI 🟡
`addSettlement` is reachable from the balance page, but there is **no list of
settlements** anywhere and `ExpenseAdder.deleteSettlement` has **no caller**. A
mistyped settlement is permanent from the user's perspective.
- [ ] Show settlements in the expenses list (or a "Payments" section) with
      date / from → to / amount
- [ ] Delete (tombstone) via the existing `deleteSettlement`; optional edit
- [ ] Widget test

### G9. No way to delete/leave/archive a group 🟡
`GroupsDao.deleteGroup` exists but is unused. Groups only accumulate.
- [ ] "Leave group" = mark own participant `removed` + stop syncing + hide locally
- [ ] "Delete locally" for groups that are only on this device
- [ ] Decide archive vs. delete semantics for settled-up groups

### G10. Group rename + default currency edit 🟡
Group meta is LWW-synced already (`meta_updated_at`), only the UI is missing.
- [ ] Edit dialog on the expenses screen; replicate meta update
- [ ] Test convergence of a rename across two devices

### G11. Device-verification enforcement (opt-in) 🟡
SAS exists for visibility only; replication still reaches unverified devices.
- [ ] Per-user setting "only replicate to verified devices" (default off)
- [ ] Warn in the members page when a peer has unverified devices

### G12. Polish & app identity 🟡
- [ ] App name is `money_ledger` on Android (`android:label`) and web
      (`<title>`, `apple-mobile-web-app-title`, `manifest.json`) → "MoneyLedger"
- [ ] Custom launcher icons + web favicon (currently Flutter defaults)
- [ ] Localization: all UI strings are hard-coded English `Text('…')` — add
      `flutter_localizations` + ARB files (at least EN + DE)
- [ ] Amount/date formatting per locale (`intl`), currency symbols
- [ ] Privacy policy / about page (needed for store listing)

### G13. CSV backup limitations 🟡
Documented in CLAUDE.md: no settlements / tombstones, participant identity by
display name (collision merges, rename splits). Largely superseded by the
full-fidelity backup in G5 — keep CSV as the human-readable export only.
- [ ] Add settlements as a second section or separate file (if G5 isn't done)
- [ ] Warn on import when a name matches multiple/zero existing participants

### G14. Scalability limits 🟡 (not urgent)
- Digest is O(records/group) — fine to ~1,000 records, then hits to-device size
  limits. Needs sharding (hash-bucketed digests) using the `"v"` field.
- Wall-clock LWW: within the 5-min clamp a skewed clock can still win.
- [ ] Add a test that measures digest size at 1k / 5k records to know the real ceiling
- [ ] Bucketed digest design (only if real groups approach the limit)

### G15. Test & tooling debt 🟡
- [ ] Test the `routerProvider` `refreshListenable` wiring (login + onboarding
      flag changes actually re-run the redirect)
- [ ] Offline demo mode `--dart-define=OFFLINE_DEMO=true` (override transport +
      auth gateway with seeded fakes) for screenshots / manual multi-user checks
- [ ] CI (GitHub Actions): `./build.sh` on push — needs G2 first for Android
- [ ] Audit the ~30 `debugPrint` / swallowed `catch` sites in `lib/` — route
      user-relevant failures into `SyncHealth` or a snackbar

### G16. Nice-to-have features
- [ ] Participant avatars
- [ ] Expense categories / notes / receipt photo
- [ ] "Simplify debts" toggle explanation + settle-up suggestions per currency
- [ ] Search/filter in the expense list

---

### G19. Flaky integration tests under load 🟡
Found in G1: with the CPU busy (emulator running), `test/integration/anti_entropy_test.dart`
("a lost delete is repaired…") and `multi_device_test.dart` ("a second device populates
itself…") fail intermittently; `-j 2` is green. The suite also logs "Bad state: Can't
re-open a database after closing it" from the digest handler → async work outlives teardown.
- [ ] Make the sync tests deterministic (await/flush instead of timing; cancel
      timers/subscriptions before closing the DB)
- [ ] Run the full suite 5× at default concurrency with the emulator running — all green

### G20. Raw exception text in login errors 🟡
`lib/features/auth/login_page.dart:186` shows e.g. "ClientException with SocketException: …"
or "M_FORBIDDEN: …" in the snackbar.
- [ ] Map common failures (network, wrong password, unknown server, rate limit) to
      friendly, localized messages; keep details expandable
- [ ] Widget tests

### G17. Design pass — a polished, consistent look 🟡
- [ ] Coherent Material 3 theme (seeded color scheme, typography, dark mode)
- [ ] Empty states, spacing, list/card styling for groups, expenses, balances
- [ ] Iterate against emulator screenshots of every main screen

### G18. Final release review 🟡
- [ ] `/code-review` over all of Phase G; fix findings
- [ ] `./build.sh` green; release APK on emulator + phone
- [ ] Docs in sync (CLAUDE.md, README, open-points); release notes

---

## Execution queue (conductor process)

One task at a time: the conductor session hands a task to a single subagent,
reviews the diff + tests + emulator screenshots, ticks boxes, commits + pushes to
`main`, then starts the next. **Newly discovered points are appended as `G19+`
before G18.** If a step needs Leo (accounts, phone), only that step moves to the
end and work continues. Resume after an interrupted session with
"mach weiter mit plan.md".

Status: `[ ]` open · `[~]` in progress · `[x]` done

- [x] G1 — INTERNET permission
- [~] G3 — release keystore
- [ ] G2 — vendor flutter_vodozemac
- [ ] CP-accounts — create test accounts A/B with Leo (`~/.config/moneyledger-test/accounts.env`)
- [ ] G4 — per-account database
- [ ] G8 — settlements list + undo
- [ ] G9 — leave/delete group
- [ ] G10 — rename group / currency
- [ ] G7 — smoke checklist + emulator pass (iOS: document unsupported — no macOS)
- [ ] G12 — app identity, i18n EN+DE, privacy/about
- [ ] G17 — design pass
- [ ] G15 — test/tooling debt, offline demo, CI
- [ ] G5 — full-fidelity backup
- [ ] G13 — CSV improvements
- [ ] G6 — signed records (any member may edit; every version signed by its editor)
- [ ] G11 — verified-only replication (+ SAS emulator ↔ phone)
- [ ] G14 — digest size measurement
- [ ] G16 — nice-to-haves
- [ ] G19 — flaky integration tests
- [ ] G20 — friendly login error messages
- [ ] *(G21+ — newly discovered points)*
- [ ] G18 — final release review

---

## Shipped (newest first)

Design rationale for each lives in `CLAUDE.md`; full detail is in git history.

| Phase | What shipped |
|-------|--------------|
| **F — Public-release hardening** | Membership-gated inbound records + LWW clock clamp (closes the forge-any-record hole); `SyncHealth` surfacing of replication/digest failures with a retry; auth edge-case coverage (re-login, remote logout); in-app registration (dummy-UIA, web fallback for captcha/email/terms); first-run onboarding (device-local `AppSettings` flag); device-verification UX (SAS emoji, visibility + manual, not enforced). |
| **E — Custom splits** | `SplitEditor` with four modes (Equal+pick / Exact / Shares / Percent); pure `split_calculator.dart` with largest-remainder rounding (always sums to total; fixed the equal-split cent loss); cents-only persistence (no protocol change). |
| **D — CSV export/import** | Human-readable per-group CSV (spreadsheet columns + trailing machine columns) with idempotent LWW merge-by-id; `file_picker` glue. |
| **Virtual users** | Participant identity decoupled from the Matrix account: local participants (name, no account), claim/unclaim, self-claim on join. |
| **C — Sync reliability + edit/delete** | Digest-based anti-entropy; per-record LWW clocks + tombstones; edit/delete; new-device/reinstall recovery; sync-status UI. |
| **B — Roomless local-first** | Dropped ledger rooms; Matrix is an encrypted to-device relay; Drift is the local source of truth. |
