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

### G2. Android E2EE build depends on out-of-repo pub-cache patches ✅
`flutter_vodozemac` 0.5.0 needed two hand-patches in `~/.pub-cache` (Gradle 9
`Project.exec`, compileSdk 33 → 36).
- [x] Upstream 0.6.0 ships exactly both fixes (+ 16 KB page-size flags) → bumped
      `^0.5.0 → ^0.6.0` instead of vendoring; `rust/` + `lib/` byte-identical, so web
      `web/pkg` wasm is unaffected; `vodozemac` stays 0.5.0 (matrix 7.2.2)
- [x] Rust toolchain (stable + android targets) documented in README + CLAUDE.md
- [x] Verified: clean clone + empty `PUB_CACHE` → release APK builds; emulator launch
      without vodozemac init errors; web release build OK
- [x] compileSdk patch obsolete (0.6.0 + the G1 override); override still needed for
      file_picker 8.x (10.x would drop it — see G22)

### G3. Release signing uses the debug key 🔴
`android/app/build.gradle*` → `release { signingConfig = signingConfigs.getByName("debug") }`.
A Play-Store upload is rejected; a sideloaded debug-signed APK can't be upgraded
by a properly signed one later (users would have to reinstall → lose local data,
see G5).
- [x] Create an upload keystore (`~/moneyledger-upload-keystore.jks`, alias `upload`,
      RSA 4096; SHA-256 `99:24:17:F1:…:A8:61`), gitignored `android/key.properties`
- [x] Wire a `release` signingConfig that reads `key.properties` (debug-key fallback)
- [x] Document the signing setup (README "Release signing")
- [ ] **Leo:** back up the keystore + password from `key.properties` (password manager)
- [ ] Play Store: enroll Play App Signing with this key as upload key (G18)
- [x] Release notes: debug-signed installs must be uninstalled once (local data lost → export first)

### G4. Local ledger is shared across Matrix accounts on one device 🟠 (privacy)
The Drift DB is a single global file (`money_ledger_db`); `logout()` only calls
`client.logout()` and never touches Drift. `ledgerGroupsProvider` shows **all**
groups. If user A logs out and user B logs in on the same device/browser, B sees
all of A's groups, expenses and member list, and B's `SyncEngine` starts sending
digests for A's groups (dropped by peers' membership gate, but still leaks
metadata to A's peers and spams them).
- [x] Per-account DB `money_ledger_<FNV-64 hex of mxid>` (`account_database.dart`);
      logout non-destructive; signed-out = `SignedOutExecutor` (no DB opened)
- [x] `appDatabaseProvider` watches `accountUserIdProvider`; SyncEngine, LedgerSyncer,
      SyncHealth rebuild on account switch; onboarding flag is now per account
- [x] One-time legacy adoption of `money_ledger_db` (only by a plausible owner;
      INSERT OR IGNORE, marked on both sides; native + web)
- [x] Tests: 17 new (naming, adoption, A→B→A switch, SyncHealth reset) — 282 green
- [ ] Real-account switch on device → G7 smoke checklist
- [x] Later: delete the adopted legacy DB once adoption is confirmed (G18)

### G5. No recovery when the last device is lost 🟠 (data loss)
Ledger data exists only on members' devices. Recovery relies on *another device*
(own or a peer's) answering `resync_request`. A single-device user who uninstalls
or loses their phone **and** has no group peers online loses everything; even with
peers, only groups that have peers are recoverable — solo/local-only groups
(all participants virtual) are gone. CSV backup is manual and lossy (no
settlements/tombstones).
- [x] Onboarding / settings: explain "your data lives only on your devices"
      and recommend a second device or regular export
- [x] Full-fidelity backup format (JSON/zip: settlements, tombstones, stable
      participant ids) — export + import, reuse `bootstrap` codec
- [x] Optional: periodic "you haven't backed up in N days" nudge for groups
      with no claimed peer

### G6. Per-record cryptographic authorship 🟠 (trust model)
Membership gating authenticates the *relaying sender*, not the *author*: any
active member can create/edit/delete an expense or settlement "as" another
member (e.g. delete someone else's expense, record a fake settlement from them).
Digest membership gossip is likewise gated only by sender membership.
- [x] Design doc: sign each record (author MXID + device Ed25519 key, the
      vodozemac identity key is already there) over a canonical payload encoding;
      record `author` field; protocol `v: 2` with v1 read-compat
- [x] Policy: who may edit/delete what (author-only? any member + audit trail?)
- [x] Implement signing + verification in `ledger_payloads.dart` / `LedgerSyncer`
- [x] Key distribution/rotation: handle device changes, logged-out devices
- [x] Tests: forged record from another member is rejected; legit edit accepted

### G7. Never verified on real devices: SSO, registration, SAS, iOS 🟠
Covered only by unit/widget tests against fakes:
- SSO native deep link `moneyledger://sso-callback` (Android + iOS)
- Registration UIA on a real homeserver (dummy path + captcha/email/terms fallback)
- SAS emoji verification round-trip (needs two devices + olm)
- **iOS has never been built or run at all** (no vodozemac/Rust setup documented
  for iOS, `ios/Runner` is template-level)
- [x] Manual smoke checklist in `docs/smoke-test.md` (62 items, tagged emu/phone/2dev/Leo)
- [x] Run it on Android release build: ~45 pass, 2 bugs fixed (matrix.org registration
      → web fallback; re-adding a removed local person), 9 not run (Leo/SAS/web)
- [ ] Run it on web release build
- [x] iOS declared unsupported for v1 (no macOS) — README/CLAUDE.md/smoke-test
- [ ] Leo-only items: real SSO login, SAS verify (→ G11), web build run (→ G18)

---

## Phase G — Minor

### G8. Settlements can't be viewed, edited or undone in the UI 🟡
`addSettlement` is reachable from the balance page, but there is **no list of
settlements** anywhere and `ExpenseAdder.deleteSettlement` has **no caller**. A
mistyped settlement is permanent from the user's perspective.
- [x] Settlements merged into the expense list (newest first, handshake icon,
      "A paid B", date, amount)
- [x] Delete (tombstone) via `deleteSettlement` with confirmation; no edit —
      delete + re-record from the balance page is one tap
- [x] 4 widget tests + replication integration test (293 green)

### G9. No way to delete/leave/archive a group 🟡
`GroupsDao.deleteGroup` exists but is unused. Groups only accumulate.
- [x] "Leave group" = own participant `removed` (replicated) + `purgeGroup` + device-local
      `left_group:<id>` tombstone; stale digests/bootstraps can't resurrect it (SyncEngine
      rule 7 also re-sends our `removed` record to peers that missed it); re-add brings it back
- [x] "Delete group" for solo/local-only groups (or when we're no longer active)
- [x] Confirmation warns about unsettled balance + offers CSV export; ⋮ menu on expenses page
- [x] Archive for settled-up groups (G16, device-local, auto-unarchive on activity)

### G10. Group rename + default currency edit 🟡
Group meta is LWW-synced already (`meta_updated_at`), only the UI is missing.
- [x] "Edit group" in the ⋮ menu (name + default currency for new expenses);
      `GroupEditor` LWW upsert + `com.moneyledger.group` replication
- [x] Rename convergence (incl. concurrent) tested + verified on phone ↔ emulator

### G11. Device-verification enforcement (opt-in) 🟡
SAS exists for visibility only; replication still reaches unverified devices.
- [x] Per-user setting "only replicate to verified devices" (default off)
- [x] Warn in the members page when a peer has unverified devices

### G12. Polish & app identity 🟡
- [x] App name is `money_ledger` on Android (`android:label`) and web
      (`<title>`, `apple-mobile-web-app-title`, `manifest.json`) → "MoneyLedger"
- [x] Custom launcher icons + web favicon (G17)
- [x] Localization EN + DE (~250 ARB keys, informal "du"; EN fallback)
- [x] Amount/date formatting per locale (`formatting.dart`); input accepts `,` and `.`
- [x] About page (version, source link, AGPL, licenses) + PRIVACY.md / in-app policy
- [x] Manifest: `android:enableOnBackInvokedCallback="true"` (predictive back)
- [x] Launcher icons + favicon → G17

### G13. CSV backup limitations 🟡
Documented in CLAUDE.md: no settlements / tombstones, participant identity by
display name (collision merges, rename splits). Largely superseded by the
full-fidelity backup in G5 — keep CSV as the human-readable export only.
- [x] Add settlements as a second section or separate file (if G5 isn't done)
- [x] Warn on import when a name matches multiple/zero existing participants

### G14. Scalability limits 🟡 (not urgent)
- Digest is O(records/group) — fine to ~1,000 records, then hits to-device size
  limits. Needs sharding (hash-bucketed digests) using the `"v"` field.
- Wall-clock LWW: within the 5-min clamp a skewed clock can still win.
- [x] Add a test that measures digest size at 1k / 5k records to know the real ceiling
- [x] Bucketed digest design (only if real groups approach the limit)

### G15. Test & tooling debt 🟡
- [x] Test the `routerProvider` `refreshListenable` wiring (done in G25)
- [x] Offline demo mode `--dart-define=OFFLINE_DEMO=true` (override transport +
      auth gateway with seeded fakes) for screenshots / manual multi-user checks
- [x] CI (GitHub Actions): `./build.sh` on push — needs G2 first for Android
- [x] `first_login_recovery_test` "restoring falls back after the timeout" (40 ms
      timeouts) failed once under load → make deterministic (fake clock)
- [x] `dart format` the whole repo once (files are unformatted; agents avoid it to keep diffs small)
- [x] Regenerate stale `.g.dart` files (build_runner changes hashes in 4 untouched files)
- [x] Audit the ~30 `debugPrint` / swallowed `catch` sites in `lib/` — route
      user-relevant failures into `SyncHealth` or a snackbar

### G16. Nice-to-have features
- [x] Participant avatars (G17)
- [x] Expense categories / notes (receipt photos out of scope — no media over to-device)
- [x] "Simplify debts" toggle explanation + settle-up suggestions per currency
- [x] Search/filter in the expense list

---

### G19. Flaky integration tests under load 🟡
Found in G1: with the CPU busy (emulator running), `test/integration/anti_entropy_test.dart`
("a lost delete is repaired…") and `multi_device_test.dart` ("a second device populates
itself…") fail intermittently; `-j 2` is green. The suite also logs "Bad state: Can't
re-open a database after closing it" from the digest handler → async work outlives teardown.
- [x] `SyncEngine` uses its `Ref` after an await without a `mounted` check
      ("Cannot use the Ref of SyncEngine after it has been disposed" in
      `_sendDigest`) — with per-account DBs this can now happen in production on
      an account switch; guard every post-await `_ref` use
- [x] Make the sync tests deterministic: `FakeMatrixNetwork.settle()` waits for
      quiescence instead of fixed `pump()` sleeps
- [x] SyncEngine/LedgerSyncer capture DB+DAOs once and stop when `!_alive`
      (`AppDatabase.isClosed`); ExpenseAdder `_WriteContext`; SyncHealth ignores
      reports once unmounted; 4 account-switch regression tests
- [x] Full suite 6× at default concurrency with the emulator running — all green (286)

### G20. Raw exception text in login errors 🟡
`lib/features/auth/login_page.dart:186` shows e.g. "ClientException with SocketException: …"
or "M_FORBIDDEN: …" in the snackbar.
- [x] Sign-up link from OIDC auth metadata / MSC2965 → `account.matrix.org/register`
- [x] `describeAuthError` + inline `AuthErrorCard` (offline vs. unreachable server vs.
      not-a-homeserver, wrong password, rate limit, SSO token, username taken…)
- [x] Widget + unit tests; verified on a spare emulator

### G21. Licensing — matrix SDK + flutter_vodozemac are AGPL-3.0 🟠
Both `matrix` (Famedly) and `flutter_vodozemac` are **AGPL-3.0**; the repo has **no
LICENSE file**. Distributing the APK (Play Store) almost certainly requires the app
to be AGPL-compatible: publish the source, ship the license, list third-party
notices. **Decision for Leo.**
- [x] Leo decided (2026-10-15): license the app **AGPL-3.0**
- [x] `LICENSE` (FSF AGPL-3.0 text, "or later" notice), `THIRD_PARTY_NOTICES.md`
      (no incompatible deps), licenses page + source link in About
- [x] **Leo (2026-10-16):** AGPL-3.0-or-later confirmed; contact e-mail in
      PRIVACY.md stays leo.m.stumpf@gmail.com; GitHub repo made public (history
      scanned first: no keystores/key.properties/passwords/tokens in any commit)

### G22. Dependency upgrades (matrix 7 → 10+, file_picker 8 → 10) 🟡
`flutter_vodozemac` is pinned at 0.6.x by `matrix` 7.2.2 (`vodozemac ^0.5.0`); 0.7+/0.8
need matrix 10+/11+ and a rebuilt `web/pkg` wasm. file_picker 10.x compiles
against SDK 36 natively (the G1 gradle override could go).
- [x] Assess the matrix SDK major upgrade (API changes in to-device/encryption,
      DB init) — do it only if low-risk; rebuild web wasm
- [x] Upgrade file_picker to 10.x; drop the compileSdk override if no longer needed
- [x] CI: `actions/checkout@v4` runs on deprecated Node 20 → bump to a Node-24
      major (and check subosito/flutter-action); first CI run green (7 min)

### G23. Same ref-after-await pattern in group mutators 🟡
`lib/features/groups/group_provider.dart` (GroupCreator, MemberAdder, MemberRemover)
read `ref` after awaits and set `state` without a `ref.mounted` check (cf. the G19
`_WriteContext` fix in `expenses_provider.dart`).
- [x] Apply the same capture-before-await pattern (`_GroupWriteContext`) + test

### G24. Silent no-op sends + startup message loss 🟠
Found in G7a (real devices):
- `MatrixLedgerTransport.sendToUsers` returns success when the targets have no
  devices (`lib/core/matrix/matrix_ledger_transport.dart:41`), and the SDK's
  `sendToDeviceEncryptedChunked` returns quietly when encryption is off →
  SyncHealth reports success although nothing was sent.
- The SDK's to-device stream isn't buffered: events processed before the
  LedgerSyncer subscribes (app start, `client.init` → background sync) are lost
  until the next digest (≤10 min). Subscribe before the first sync, or buffer.
- Duplicate startup sends: resync_request ×3 within ~200 ms, digest ×2 at
  start (SyncEngine rebuilt during the per-account DB switch-over).
- [x] `TransportUnavailableException` (not logged in / encryption off) = failure;
      `SendResult.unreachableUsers` = peer without device → shown, not a failure
- [x] `MatrixLedgerTransport.forClient` subscribes before `client.init`;
      `BufferedInbox` (500, account-tagged) replays to late listeners
- [x] De-dup: engines don't start on the signed-out placeholder DB;
      `kGroupResyncCooldown` (30 s) — exactly one initial digest/resync per group
- [x] 24 new tests (317 green); verified on phone + emulator

### G25. Onboarding flag loads late → onboarding pops up minutes after login 🟡
G7a: on the emulator the groups page showed first and onboarding replaced it
~2–3 min later (flag defaults to "seen" until loaded; per-account DB opens late).
- [x] `OnboardingGate` (unknown/seen/notSeen) + `/splash`; 8 s timeout → seen
- [x] routerProvider refreshListenable wiring tested end-to-end (G15 item)

### G26. Member lifecycle gaps (found in G9) 🟠
- **Bug:** `MemberAdder.add(groupId, mxid)` for an MXID that already claimed a UUID
  participant creates a *second* participant with the same matrixId →
  `memberByMatrixId`'s `getSingleOrNull` then throws (e.g. re-adding someone who
  left after claiming a placeholder). Re-add must reactivate the existing participant.
- Members page hides removed participants → peers just see someone vanish; show
  "left"/"removed" (greyed) since they still appear in history.
- Leaving on one device leaves the group on the user's *other* devices (shown as
  removed, no digests). Consider propagating "left" to own devices (self-sync).
- Re-add detection compares the re-adder's clock with `left_at` (skew → ignored).
- [x] Re-add reactivates the existing participant; `claimedBy()` tolerates old duplicates
- [x] "Former members" section (greyed, Re-add)
- [x] Own leave propagates to own devices (purge + tombstone); removed by others →
      read-only history + banner + "Delete from this device"
- [x] `nextLwwClock = max(now, old+1)` for local edits (re-add beats a skewed `removed`)

### G27. LWW has no tie-break on equal `updated_at` 🟡
Two edits with the exact same ms clock stay divergent (digests see them as equal).
- [x] Deterministic tie-break (e.g. compare a content hash) in all LWW upserts + digest compare

### G28. Settling debts of local persons / payments received 🟠
`balance_page.dart:71` only lets the debtor tap their own row. A local person's
debt (no account) can never be settled, and a creditor can't record "X paid me".
Decision (conductor, Splitwise-style): **any active member may record a payment
between any two participants**; default from/to = the tapped debt row.
- [x] Settle any debt row (incl. local persons); "Record payment" with from/to pickers
- [x] Tests (widget + replication) — verified on devices (Carl's debt settled from the phone)

### G29. Expense-form gaps (G7) 🟡
- [x] Per-expense currency picker (also fixed: editing overwrote the expense currency)
- [x] Sign-out confirmation dialog
- [x] Sync status lag: reader side marks a peer in sync once convergence is proven
      from that peer's own records (`peer_convergence.dart`) — 22 s → immediate
- [x] SSO button label: the typed server name / IdP names
- [x] Writer side still pending ~27 s after own change (ack = digest after 5 s poke
      debounce + relay hop) → faster ack (shorter debounce or per-record ack)

### G30. Auth/first-login robustness (found in G20) 🟠
- A fresh login of A on a new emulator showed "No groups yet" although the phone
  has A's groups — check new-device recovery timing (resync_request scope all →
  own devices); was ~3 s in G7. Reproduce + fix or explain (show a "restoring…"
  state while the first resync is outstanding).
- `checkHomeserver` / `login` have no timeout → the button can spin ~20 s+.
- [x] Root cause: not a bug — the phone app wasn't running (no background sync);
      self-resync now retried at 5 s / 30 s / 2 min while the DB is empty
- [x] "Restoring your groups from your other devices…" state (3 min UI timeout;
      skipped when no other own device exists)
- [x] Timeouts: discovery 10 s, login/register 20 s → friendly "took too long"
- [x] A timed-out login still completes in the background (SDK call not cancelled)
      → a retry can create a second device; guard against concurrent logins
- [x] Queued retries are each answered later → bootstraps sent up to 4×; dedupe

### G31. Sync only happens while the app is open (no background sync) 🟠
To-device messages are queued on the homeserver and only fetched while
MoneyLedger runs. Peers/own devices that never open the app never answer
(digests, resync, bootstraps) — observed in G30. Options: Android periodic
background fetch (WorkManager: start client, one /sync, process to-device,
answer pending requests, stop), and/or Matrix push (pusher + push gateway → FCM;
needs a gateway, privacy trade-offs). Web: only while the tab is open.
- [x] Periodic background round on Android (`workmanager` 0.10, MIT): every 15 min,
      network + battery-not-low; one /sync, answer pending, digest if stale; 60 s cap
- [x] Process-wide guard (IsolateNameServer): app and round never share the stores;
      a round that finds the app alive delegates a oneShotSync to it
- [x] Per-account "Background sync" switch (Sync settings sheet); onboarding text
- [x] Verified: closed emulator app received a phone expense via a background round
- [x] Debug-only one-off trigger for manual testing (periodic jobs can't be forced)
- [ ] Push (Matrix pusher → FCM) — out of v1 scope

### G32. Android auto-backup includes ledger + Matrix crypto keys 🟠
No `allowBackup` setting → Google backup may contain the ledger DBs and the
Matrix session incl. Olm keys; a restore onto a new phone would resurrect a
stale crypto identity (broken sessions) and is a privacy concern.
- [x] `android:allowBackup="false"` + `dataExtractionRules`/`fullBackupContent`
      excluding everything (cf. ZoneCraft); update PRIVACY.md + in-app policy
      (pinned by `test/core/android_manifest_test.dart`)

### G17. Design pass — a polished, consistent look 🟡
- [x] Coherent Material 3 theme (teal seed, `LedgerColors`, bundled Manrope, dark mode; WCAG-AA tested)
- [x] Empty states, spacing, list/card styling for groups, expenses, balances
      (groups totals card + per-group balance, group summary + Settle up, date
      headers, lent/borrowed, per-person nets on the balance page)
- [x] Iterate against emulator screenshots of every main screen (EN/DE, light/dark)
- [x] Logo + launcher (adaptive, monochrome), Android 12 splash, favicon/PWA icons
- [x] Matrix profile display names (`LedgerTransport.profileName`) + initials avatars
- [x] Real-device findings (G7a): expenses title says only "Expenses" (truncated
      "Expe…") — show the group name; keyboard covers the "Add" button on the
      expense form; members shown by Matrix localpart (wraps) — prefer the
      Matrix display name; add-member dialog can't add a local person by name;
      long names wrap the settlement title over 4 lines; expense tiles show no date

### G33. Design follow-ups (found in G17) 🟡
- [x] Settlement row title with long names (MXID localparts) truncates to the
      payer only — keep both names visible ("A → B"), e.g. ellipsize each name
- [x] Expense row: the right column width (amount vs. "du schuldest 12,25 €")
      squeezes the title ("Taxi to a…") — lay out title+amount and
      payer+lent/borrowed as two independent rows so the title gets the space
- [x] The extended FAB covers the last list row's amount on the group and
      groups pages — add bottom padding (~88 dp) to the scroll views
- [x] G15 follow-ups: unit test for `_TrackingTransport.quiet` (background
      round); show an error when background-sync scheduling fails; clear banner
      when vodozemac init fails (E2EE off); German screenshots + web demo deploy
      for the README (screenshots in docs/screenshots/; web demo deploy skipped — repo private)
- [x] (won't do — profile path covered by tests) Test accounts' Matrix profile names equal their localparts, so devices
      still show `moneyledger-test-a-c725` — optionally set display names
      ("Anna"/"Ben") on the test accounts to exercise the profile-name path
- [x] Widget tests with a real in-memory DB must override `ledgerGroupsProvider`
      (Drift watch stream hangs under the widget-test clock) — document in
      CLAUDE.md testing notes / provide a helper

- [x] Balance page "You pay <long name>" could use `NamesLine` (wraps today)

### G34. Backup follow-ups (found in G5) 🟡
- [x] Nudge ignores a second device of the same account (would also protect
      solo groups) — needs the device list
- [x] Restore of a group where peers have us `removed` (newer) → read-only
      history again; manual two-device test
- [x] Saved-file snackbar shows the proposed name, not Android's actual one
      (`… (1).json`); leave dialog's backup snackbar shows behind the dialog
- [x] Optional per-group JSON backup in the group ⋮ menu
- [x] Optional: encrypted backup (passphrase) — file is plaintext JSON today

### G35. Signed-records follow-ups (found in G6) 🟡
See `docs/design/g6-signed-records.md` + `docs/open-points.md`.
- [x] (decided: no migration; recreate test groups before release — G18) Pre-G6 (legacy, unsigned) rows are refused when relayed, so an old group
      can't onboard a new member/device until its meta + member rows are
      re-saved. Unreleased app → only the test groups are affected; decide:
      re-create test groups before release, or a "re-sign legacy rows as
      migrated-by-this-device" step
- [x] (documented; cross-signing = future) Residual risks: invented device ids (flagged "unverified"; needs
      cross-signing — with G11), malicious inviter vouching fake keys,
      divergence by disagreement (not auto-resolved)
- [x] Restore is no longer one transaction per group (verification may hit
      the server mid-merge)
- [x] Footer wraps long MXIDs — fixed in G33 (NamesLine / per-part ellipsis)

### G36. Verification follow-ups (found in G11) 🟡
Decided by the conductor: inbound records from unverified devices stay
*flagged*, not quarantined (a permanent refusal wouldn't heal after a later
verification); the verified-device list stays device-local (not in backups —
trust is a per-device decision).
- [x] Translate the SAS emoji names (Matrix spec ships translations) — the SDK
      gives English names in the German UI
- [x] Matrix sync loop stalled after an emulator network switch until app
      restart (seen once on emulator-5556) — check reconnect/backoff
- [x] Verified-only only restricts what *this* device sends; document clearly
      in-app; a new own device can't restore while the setting is on elsewhere
      until verified
- [ ] SAS against Element sessions (Leo-only smoke 9.2/9.3)

### G37. Scale follow-ups (found in G14) 🟢 (not urgent)
Ceilings today: ~80 members per group (every bootstrap part / digest repeats
all members), ~30k records (2,048-bucket summary). See CLAUDE.md "Message size".
- [x] Store the G27 version hash in a DB column if digest hashing (~150 ms /
      5k records on desktop) is slow on phones — measure on the Pixel
- [x] (assessed, accepted for v1: only bucketed digests, ≤ 1 extra 3-message exchange per peer/cycle, pinned by a test) A refused version costs one extra 3-message bucket exchange per cycle
      (bounded); refusals are per clock (blocks other versions at the same ms)

### G40. Fully local mode — use the app without a Matrix account (Leo, 2026-10-16) 🟠
Never implemented so far (only local *participants* exist; the app user always
needs a Matrix login). Architecture already allows it (local-first Drift,
transport is a port; the offline demo runs without Matrix).
- [x] "Use without account" on the welcome/login: asks for your name, opens a
      device-local ledger DB (`money_ledger_local`), no Matrix client, no
      sync/background jobs; all groups local-only, other people = local
      participants; backup/CSV work as usual
- [x] Clear "local mode" indicator + explanation (nothing leaves this device;
      back up!) in groups page / settings; features needing Matrix (add by
      Matrix ID, devices, verification, sync status) hidden or explained
- [x] Upgrade path: "Connect a Matrix account" later → sign in, local data is
      adopted into that account's DB (reuse the G4 adoption mechanism), your
      local "me" participant becomes claimed by your MXID, groups can then
      invite Matrix members; local DB marked adopted
- [x] Sign out / switch back to local mode semantics defined + tested;
      EN + DE; tests; verified on a fresh install (emulator-5556); fresh-install recheck on phone/5554 in G38

### G39. First-open welcome before login (Leo, 2026-10-16) 🟠
Today the intro (`OnboardingPage`) only appears *after* login (per-account
flag). A first-time user lands on a bare Matrix login without knowing why.
- [x] Device-wide "welcome seen" flag (works signed out; native + web) and a
      short swipeable welcome before the login page: what MoneyLedger is
      (shared expense tracking, Splitwise/Tricount-style), free + open source
      (AGPL, link to the repo), no MoneyLedger server — data stays on your
      devices; what Matrix is (open, decentralized messaging network; you
      use an account on any homeserver, e.g. matrix.org — free sign-up);
      why log in (your Matrix ID is your identity + the encrypted relay to
      group members); what is shared with whom (members' devices get the
      group's records, E2EE; the homeserver sees only ciphertext + who talks
      to whom; nothing else); CTA "Sign in" / "Create account" / "Use
      without account" (G40)
- [x] Post-login onboarding slimmed to what's still new (backup tip etc.),
      no repetition; "How it works" reachable again from About
- [x] EN + DE, design system, tests; verified on a fresh install (emulator-5556); fresh-install recheck on phone/5554 in G38

### G41. Local-mode follow-ups (found in G40) 🟢
- [x] Restoring a backup made in local mode into a Matrix account: apply the
      same adoption step as *Connect a Matrix account* (re-claim `local:self`
      participant by the MXID, sign pending rows) instead of keeping rows
      unsigned + the `local:self` claim
- [x] Remove the empty `money_ledger_local` DB file after deletion / adoption
      (today it stays on disk, empty)

### G38. App id → `io.github.leostumpf.moneyledger` (Leo, 2026-10-16) 🟠
Leo's naming scheme (ZoneCraft, timeLoggBook): `io.github.leostumpf.<name>`.
Must happen before the first Play upload (the id is permanent there).
- [x] namespace + applicationId in `android/app/build.gradle.kts`, Kotlin
      package/path of `MainActivity`, background-sync references
      (`background_sync_native.dart`, `background_gate.dart`, jobscheduler
      command in CLAUDE.md / smoke-test), bench tool, docs
- [x] Devices (approved by Leo): sign out + uninstall the old app on the
      phone and emulator-5554, install the new id, log in test accounts A/B
      again, recreate the test groups (replaces the pre-G6 legacy groups, G35)
- [x] Re-verify on devices: login, sync both ways, SAS between A and B,
      background sync job id

### G18. Final release review 🟡
- [x] Code review over all of Phase G (sync/crypto/backup/math): 16 findings incl. 4 blockers → all fixed with regression tests
- [x] Second review pass over the G18 fixes (after G40/G39/G38): 3 major + 5 minor → all fixed with regression tests (schema v10)
- [x] (G38: devices reset, "Testgruppe A+B" + "Lokal-Test" recreated) Recreate the pre-G6 test groups ("G7a Test"/"G7a Probe") or document them
      as legacy-only (G35 decision)
- [x] Balance suggestion rows truncate long names to ~4 chars ("mone… zahlt an
      dich") — allow 2 lines instead of single-line NamesLine there
- [x] Delete the local emulator app-data safety copy
      (scratchpad `emu_appdata_backup.tgz`, contains test-account keys)
- [x] `./build.sh` green; release APK on emulator + phone
- [x] Docs in sync (CLAUDE.md, README, open-points); release notes (`docs/release-notes.md`)

## Phase H — Goals review follow-ups (Leo, 2026-10-16)

A review of the app against its seven goals (1 split bills with friends,
2 easy to use, 3 serverless / no server of ours, 4 usable without login,
5 Matrix only as transport — nothing stored on the homeserver, 6 AGPL,
7 local data, no ads, nothing reported anywhere). Result: 3, 4, 6 met;
1, 5 met with gaps; **7 is contradicted in practice** (web build loads
CanvasKit + fonts from Google, the login page queries matrix.org on open,
an offline probe hits matrix.org) and the privacy texts don't say so;
2 is good inside a group, but inviting friends (typed MXID, friend needs a
Matrix account) is the biggest gap. Product decision (Leo): a **no-login
"link group" synced over public Nostr relays becomes the default** for new
groups; Matrix stays as the optional "secure mode". Research notes:
ntfy.sh (4 KB msgs, 250/day/IP, 12 h cache) rejected in favour of Nostr
(addressable event per device + group holding the whole encrypted
snapshot; relays allow 128 KB–1 MB per event; NIP-40 expiration).

### G43. Privacy promises must be true (goal 7) 🔴
- [x] Web build without Google CDN: `--no-web-resources-cdn` in `build.sh` +
      CI (+ `tool/web/check_web_build.sh`); Roboto served locally at the
      engine's own path (web only), `fontFallbackBaseUrl: "fonts/"`, web-only
      subset fonts `SasEmoji` (64 SAS emoji) + `AppSymbols` (→, ⋮, …)
- [x] Remove the matrix.org offline probe (`matrix_auth_gateway.dart`);
      transport error → "Can't reach <host>" (server down / typo / offline)
- [x] Login page queries no server until the user acts (edit + debounce,
      "Check server", Matrix ID typed, Sign in / SSO)
- [x] PRIVACY.md + in-app `privacy*` / local-mode texts (EN+DE) match
      reality; CLAUDE.md, README, open-points updated
- [x] Headless Chrome (CDP): welcome, untouched login, local mode → zero
      requests outside the app's origin
- [x] Manual browser pass (network tab): local mode, untouched login, then
      "Check server" contacts only the entered server → `docs/smoke-test.md`

### G44. Small release fixes (goal 6/7) 🟠
- [x] About page shows `AGPL-3.0-or-later`
- [x] Android: `dependenciesInfo { includeInApk = false; includeInBundle = false }`
- [x] Release builds: silence `debugPrint` (logcat holds MXIDs / homeservers)

- [x] Follow-up: release APK signing block checked (2026-10-17): only the v2
      signature (0x7109871a) + verity padding — no dependency-info block
      (0x504b4453)
- [x] Optional opt-in "debug log" export — **decided 2026-10-17: no** (release
      builds stay silent; debug builds + logcat for diagnosis)

### G45. Minimal Matrix footprint (goal 5) 🟠
- [x] Minimal `syncFilter` (no rooms, presence, account data) +
      `syncPresence = offline` in `buildMatrixClient` (also used by the
      background round); to-device delivery must be unaffected
- [x] Decide device display name ("MoneyLedger") + whether the profile-name
      refresh should stay automatic; document what the homeserver still keeps
      (account, devices, keys, undelivered messages, who talks to whom)
- [x] Two-device smoke (sync, invite, SAS) + `docs/smoke-test.md` (DEV-H)

### G46. UX quick wins (goal 2) 🟠
- [x] "Which participant are you?" dialog: dismiss = cancel (not "I'm new")
- [x] After creating a group, open it; empty group shows "Add people" CTA
- [x] After *Delete local data* go to the welcome, not the login page
- [x] Hide signature/device details behind "Details" unless there is a real problem

### G47. Custom categories + dropdown picker 🟡
- [x] Category selection becomes a dropdown/selector (icon + name, "None",
      suggestion stays the preselection) instead of the chip row
- [x] Per-group custom categories in the signed group meta
      (`categories: [{id: "c:<uuid>", name, icon}]`, hashed only when set),
      create / rename / hide (⋮ → Categories page + "+ New category" in the
      dropdown); unknown id → "Other" (hidden ones still label old
      expenses); filter chips, search, CSV (`Category Name` column) aware;
      schema v11

### G48. Automatic restore points + revert (git-like) 🟡
- [x] `record_history` table: every version a DAO writes (local or inbound)
      is appended (group, kind, id, updated_at, hash, content, source);
      retention ~90 days / size cap
- [x] "Reset group to <date/time>": per record the newest version ≤ T,
      records created later → tombstones; written as **new** versions
      (`nextLwwClock`, signed) so peers adopt the revert; diff preview first
- [x] Rotating on-device full snapshots (`buildBackupJson`, daily if changed;
      keep 7 daily + 4 weekly), restore via the existing preview path
- [x] Settings: restore-point list, "Restore…" / "Reset group…"; EN+DE; tests

### G49. Expense date 🟡
- [x] Date picker on the add/edit form (expenses can be back-dated); decide
      whether `created_at` or a new optional signed `date` field carries it
      → new optional signed `date` (ISO `YYYY-MM-DD`, only when it differs
      from the creation day; `created_at` is in the `origin` creation
      statement and must never change); display date = `date ?? created_at`;
      list grouped/sorted by it; CSV `Date` = display day + `Created At`
      column; schema v13 (forgets expense refusals like v7); payments
      undated (open point)

### G50. No-login link groups — design doc 🟠 (signed off 2026-10-17)
- [x] `docs/design/no-login-sharing.md`: invite link / QR (group secret in
      the `#fragment`), key derivation, one addressable Nostr event per device
      and group with the gzip + AES-GCM snapshot (≤ 100 KB, NIP-40 expiry
      ~60 days), relay list (damus, primal, nos.lol) + custom relay, live
      WebSocket + Android background poll, LWW merge via the DAOs, identity
      without G6 signatures / membership gate (builds on `local:self`),
      dependency + license check (secp256k1 Schnorr), privacy texts, relay
      ToS grey zone, "Why Matrix instead of a link" section (identity +
      signatures, removal sticks, multi-device recovery, own homeserver,
      no third-party relays, scale), positioning "link = default"
- [x] **App key** (W5): group key = HKDF(link secret, salt = app key) so the
      link alone can't decrypt relay data (a hurdle, not security) —
      **decided 2026-10-17: public versioned salt `kLinkSaltV1`** (no secret
      key: AGPL Corresponding Source, F-Droid builds); key version in the link
- [x] Leo's sign-off of §14 (2026-10-17): kind 31847; damus + nos.lol +
      primal, no `r=` hints; `n=` name in the link; landing page in a
      **multi-app** `LeoStumpf.github.io` user-site repo (link
      `https://leostumpf.github.io/moneyledger/join#…`); no in-app scanner;
      link secret in backups (with warning); `by` hint; channel opens on the
      first invite; **Reset invite link in the first version**; web too;
      relay operators **not** contacted — but no grey zone: check each
      relay's terms first (G51); Matrix users' groups stay Matrix (+ mixed
      via link, G53); **expiry 30 days, refreshed after 10**

### G51. Nostr spike 🟡
- [x] **First:** read each default relay's published terms / policy (NIP-11
      `posting_policy`, linked terms); a relay excluding app data / encrypted
      blobs → propose a replacement to Leo (stop point)
      → done 2026-10-17 (design doc §9.4): nos.lol + nostr.mom ALLOWED (same
      operator), damus + primal GREY → Leo chose **option C: only nos.lol +
      nostr.mom** (custom relay = mitigation for the single operator)
- [x] Spike (2026-10-17, `tool/spike/nostr/`, design doc §16): **GO for
      G52**. Real cap 65 536 B event JSON (not the advertised 131 072 frame)
      → `kLinkContentBudget` 60 000 chars (~690 unsigned / ~1 200 signed
      records in 8 parts); replace + `replaced:` OK; live p50 ~140 ms;
      6 fresh keys no rate limit; native pack+sign 22 ms; both relays share
      one IP (separate DBs)
- [ ] Retention checks (`dart run bin/check_retention.dart` in
      `tool/spike/nostr/`, read-only): +1 d 2026-10-18, **+3 d 2026-10-20 =
      gate before G52 step 5 (sync engine)** → **passed** (checked
      2026-10-21, +105 h: 30-d probe served on nos.lol + nostr.mom), +7 d 2026-10-24 (§12
      criterion), +14 d 2026-10-31, +31 d 2026-11-17 (probe gone)
- [x] **Leo (2026-10-17): verify on native only, skip on the web.** Web signature verify misses the target (dart2js `bip340`
      4.9 s for 20 events) — proposal: verify on native only, web relies on
      the AES-GCM tag (§3.3 / §16); alternatives: verify only new events,
      faster secp256k1 lib
- [ ] Moved to the G52 device pass: two networks, Pixel, real Chrome
      timing, E9 headless Android

### G52. Link groups (implementation, incl. app key) 🟠
Sub-steps = design doc §13 (each a commit with tests; fakes first):
- [x] 1. Pure codec + crypto (`lib/core/link/`): link URI, HKDF (`kLinkSaltV1`), envelope (gzip + AES-GCM, AAD), sharding plan (`kLinkContentBudget` 60 000)
- [x] 2. Mini Nostr client (event id / BIP-340 — verify native only, Leo 2026-10-17; frames, `RelayConnection` + WebSocket adapter, `NostrRelayPool`, `replaced:` handling) + `test/helpers/fake_relay_network.dart`
- [x] 3. Schema v15 (`link_channels`, `link_peers`, `link_author`) + `LinkDao` + migration test
- [x] 4. Policy: `GroupPolicy`, `RecordGate` link path, engines skip link-only groups; local adoption (`adoptLocalLedger`) must keep / skip link groups (it doesn't copy `link_channels` / `link_peers` yet)
- [x] 5. `LinkSyncEngine` (gate: retention check passed 2026-10-21) — `lib/core/link/link_sync_engine.dart` (+ `link_channel.dart` open, `link_relay_policy.dart`, `nostr/nip09.dart`, `nostr/nip11.dart`); design doc §13 "As built (step 5)"
      — wire `link_author` into models / companions / payloads (a companion without it keeps the old value — set it explicitly, also null)
      — also: per-relay backoff/block policy after `rate-limited:` / `blocked:`, publish debounce, monotonic `created_at`, NIP-09 delete, NIP-11 (left out of step 2)
- [x] 6. Invite UI (sheet, QR, share, disclosure) — `lib/features/link/link_invite.dart`, `core/widgets/qr_code_view.dart` (`qr`, BSD-3); *Create group → Share with an invite link* on Matrix accounts; design doc §13 "As built (step 6)"
- [ ] 7. Join (intent filters + App Link, `/join`, `JoinLinkPage`) — store the channel **before** the first merge; refuse a link whose group id this device holds as a non-link group; invalidate `currentParticipant` after setting "me"
- [ ] 8. Background round link phase
- [ ] 9. Settings: relay list + status, peers sheet
- [ ] 10. Leave / delete unpublish; backup carries the secret (+ warning)
- [ ] 11. Docs, THIRD_PARTY_NOTICES (bip340, pointycastle, web_socket_channel, archive, posix), landing repo `LeoStumpf.github.io` (multi-app; assetlinks with the **upload-key** fingerprint for now — Leo 2026-10-17: Play App Signing not set up yet, add its fingerprint once enrolled), demo seed
- [ ] 12. Reset invite link
- [ ] 13. Device pass (Pixel + emulator + web)
- [x] (from step 5) **Creating a link group while signed in:** a Matrix
      device signs every write, so a group it created has a signed meta and
      `openLinkChannel` refuses it (`signedGroup` — it would turn `mixed`,
      G53). Step 6 must open the channel **before the first write** (e.g. a
      "share by link" choice in *Create group*, so the meta is written
      unsigned in `linkOnly`) — or this waits for G53. Decide in step 6.
      — **Done in step 6:** *Share with an invite link* switch in *Create
      group* (Matrix accounts only, default off = Matrix group, §14 Q13);
      the channel is stored before the first write. Existing Matrix groups
      show no link entry until G53.
- [ ] (from step 5) Wire the seams: ~~step 6 invite → `LinkSyncEngine.
      openChannel`~~ (done: `linkChannelOpenerProvider`); step 7 join → `putChannel` + `refresh(groupId:)` + set
      "me"; step 8 background round → `refresh()` + `publishAll()`; step 9
      icon / peers sheet → `linkGroupSyncStatusProvider`, `link_peers`,
      `relayPolicy.rejecting` + `link_relay_state:<url>`; step 10 leave →
      `unpublish(groupId)` before the purge
- [ ] (from step 5) The group page's sync cloud for a link-only group still
      comes from the Matrix `groupSyncStatusProvider` — switch it to the link
      status in step 9
- [ ] (from step 6) Disclosure: name the **configured** relays + "(one
      operator)" + "linked in Settings → Relays" / "add your own relay"
      once step 9 has the relay list; link *Why Matrix?* (G54) from it
- [ ] (from step 6) Invite sheet: the "Invite a Matrix user (secure)"
      section (§8.4) is left out — a link-only group refuses Matrix claims
      until G53; add it with G53's mixed groups
- [ ] (from step 6) §8.2: rename the local-mode chip "Local only" → "No
      account" and its sheet / onboarding texts (device-only vs. shared by
      link) — with step 11 or G54 (step 6 review: the chip sheet's
      "Nothing leaves this device" and the settings line already say
      "groups you don't share …"; welcome + onboarding texts still say
      "everything stays on this device")
- [ ] (from step 6) Leaving / deleting a link group uses `groupExitKind`
      (Matrix claims) — a link group of a signed-in user shows *Delete*;
      revisit with step 10 (unpublish)

### G53. Mixed groups + "lock group" 🟡
- [ ] Review (from G52 step 4): any link holder with a Matrix device can push a
      *signed* meta → group turns `mixed` → unsigned metas (renames by link-only
      members) are refused from then on; decide in G53 (meta `link` field)
- [ ] A Matrix group can open a link channel ("Invite by link"); Matrix
      devices bridge (publish + read the relay snapshot); link versions are
      unsigned and shown "via link, not verified" (per-group `RecordGate`
      allowance; never re-signed by a Matrix device)
- [ ] A link participant can sign in later and claim their participant
- [ ] "Lock group" once every active participant has a Matrix account: link
      channel closed, key dropped, unsigned versions refused from then on
      (signed group meta); reopening creates a new key + link

### G54. "Why Matrix?" info screen + welcome reorder 🟡
- [ ] Calm info page in the welcome style ("Hey, there's another mode — also
      free and it works even better, you just sign in"), from a link group's
      menu, "How it works" and once as a dismissible hint (no nagging); EN+DE
- [ ] Welcome/onboarding reordered for "link = default", Matrix as the upgrade

### G55. Web glyph coverage without Google (found in G43) 🟢
- [x] Emoji / CJK / Arabic typed by users render as boxes on web and cause
      local 404 retries — **decided 2026-10-17: accept + document** (no
      bundled Noto set; `docs/open-points.md`)
- [x] Flutter upgrades may move the engine's Roboto path (reminder only — — `check_web_build.sh`
      catches it; rerun `tool/fonts/make_web_fonts.py --roboto-path …`)
- [x] Optional copy: welcome / connect flow says nothing is contacted until
      you confirm your server — **no** (Leo 2026-10-17)

### G56. UX follow-ups (found in G46) 🟢
- [x] Members page: full MXID as subtitle — shorten / tuck away?
- [x] Groups app bar "Devices" icon → move into the settings sheet
- [x] "Add people" prompt also when I'm alone but the group already has expenses
- [x] Leaving a filled add-expense form with ← asks nothing (discard confirm?)

### G57. Custom-category follow-ups (found in G47) 🟢
- [ ] Concurrent category edits lose one (whole meta is LWW) — per-category
      merge if it matters; duplicate names only blocked in the dialog —
      **Leo 2026-10-17: later**, together with the link-group wire changes
- [x] Offline demo seed: add a custom category (screenshots)

### G58. Restore-point follow-ups (found in G48) 🟢
- [x] Snapshots also from Android background rounds (today: app start only)
- [ ] Device check: `[bg] round done: … snapshot: true` + new file in `snapshots/`
- [x] Offline demo seed: back-fill history so the reset page isn't empty
- [x] Snapshot restore **"exactly this state"** as an option (Leo
      2026-10-17: yes) — per group a reset to the snapshot's content (new
      versions, `nextLwwClock`, participants never reset); preview warns that
      newer changes of others are overwritten
- [ ] Device check: restore points with *Exactly this state* on, German, phone
      width (per-group count line wraps); snackbar wording counts groups +
      versions together
- [x] Decide: encrypt snapshot files — **no** (Leo 2026-10-17; private app
      dir like the DB, Android backup off)
- [x] Concurrent resets by two members converge per record (mix) — **LWW as
      today, no merge UI** (Leo 2026-10-17; `docs/open-points.md`)
- [x] A peer's live record within 30 s of a bootstrap is absorbed into the base
      batch (history doesn't record message type / relaying sender) —
      **accepted as a limit** (Leo 2026-10-17; `docs/open-points.md`)

### G59. Smarter split defaults (Leo, 2026-10-17) 🟡
Switching split modes or editing amounts today starts from blanks; make the
`SplitEditor` (`split_editor.dart`) do the obvious thing.
- [x] Switching mode prefills from the current split (Equal → Exact shows the
      equal amounts, → Shares 1 each, → Percent the matching percentages;
      on edit the stored split converts the same way)
- [x] Exact: an "auto / fill the rest" action — e.g. total 5 €, one person
      2.50 € → the remaining 2.50 € is spread over the people left blank
      (largest-remainder, `split_calculator.dart`); per-row "rest" button and
      a status line "2.50 € left — distribute"
- [x] Percent: same "rest" for the last open person; Shares: +/- steppers
- [x] Changing the total keeps the chosen proportions where it makes sense
      (Exact stays exact with a "doesn't add up" hint + one-tap rescale)
- [x] EN+DE, widget tests for each default / auto-fill path

### G60. Expense-date follow-ups (found in G49) 🟢
- [x] Payments (settlements) have no date yet
- [x] Offline demo seed: a back-dated example
- [x] Payments can't be edited — a wrong day means delete + re-record

### G61. Split follow-ups (found in G59) 🟢
- [x] Try live auto-fill of open rows (Tricount-style) instead of the button —
      **Leo 2026-10-17: keep the button**, add more actions instead (below)
- [x] Too much distributed → also **"Set total to the sum"** (next to the
      existing *Rescale proportionally*)
- [x] A clearly visible **live** "X left / X too much" next to *Distribute*
- [x] Shares mode: a **"Fine-tune as amounts"** action that switches to Exact
      (the existing conversion), e.g. 4:1 → 4/5 amounts to adjust
- [ ] Device check: *Set total to the sum* while the amount field is scrolled
      off-screen (feedback visible enough?)
- [x] Shares from very uneven amounts give big numbers (333/667) — round to nicer?
- [x] Check the new split rows at phone width (long names, Shares steppers)
- [x] Rows with long names sharing a prefix are indistinguishable
      ("moneyledger-test-…" twice) — ellipsize in the middle / 2 lines

### G62. Reset page empty after update / new group (found in DEV-H) 🟠
`changeBatches` (`group_history.dart`) chains entries < 10 min apart; a batch
is resettable only if the meta appeared in an *earlier* batch, so the first
batch (v12 `initial` backfill, group creation, bootstrap) plus every change
chained to it is never offered → "nothing to go back to".
- [x] Never merge `initial` / meta-creation entries with later changes (and/or
      split batches when the editor changes); regression test with the
      DEV-H repro (update → edits within 10 min → reset offered)

## Usability review 2026-10-17 (`docs/usability-review.md`, U1–U31)

Leo 2026-10-17: **no store hurry — finish everything first**; people are entered when creating a group + the UI says "Personen" throughout (G64); single deletes keep the confirm dialog **plus** an undo snackbar (G67); exchange rates manual **with a button to fetch the current rate** (any source; G73). Notifications (G72) **on by default**; payment details (IBAN / PayPal.me → GiroCode QR / link when settling) **optional, entered in the app settings** (new item G74).

### G63. Correctness + texts before release (U11, U5, U3, U29, U14) 🔴
- [x] **U11:** editing an expense that involves a former member drops them
      from the split (and empties the payer) → balances change silently;
      keep former participants of *this* expense selectable (like
      `settle_up.dart`) + regression test
- [x] Trim-validation of names / descriptions, stale homeserver hint,
      German polish, clearer split-mode labels (EN Equally / Amounts / Shares,
      DE Gleich / Beträge / Anteile — "Gleichmäßig" doesn't fit at 360 dp)

### G64. People when creating a group (U4, U9, U6, U10) 🟠
- [x] Add people while creating a group (chips, *Add & next*), duplicate-name
      hint, one term ("Personen"), balance warning when removing someone —
      **before G52 step 6/7** (join picker needs the people)
- [x] Left out: duplicate hint on *rename*; mode-dependent delete wording
      (local mode "will be deleted")
- [x] Device check (Pixel, DE, 360 dp): Enter keeps the keyboard + focus on
      the create page; *Add person* dialog's three buttons wrapping; payer
      dropdown tag "nicht mehr dabei"; read the reworded privacy texts

### G65. Group settings + settings page (U22, U28, U21) 🟠
- [x] Group settings page instead of the 9-entry ⋮ menu; `/settings` as a
      page with sections (CSV / sign-out moved) — **before G52 steps 6 + 9**
- [x] Device check: smoke step 3.11 (Pixel, DE, 360 dp)

### G66. Currencies (U16) 🟠
- [x] Full ISO-4217 list with search, minor units per currency (JPY 0),
      default from the device region — **storage stays hundredths for every
      currency** (JPY was always ×100; ISO minor units would be a wire change →
      G57 bundle if ever); display decimals = min(ISO, 2)

### G67. Undo + understandable errors (U13, U25, U15) 🟠
- [x] Undo snackbar for delete (confirm dialog stays — Leo) / record payment, *Delete* in the edit form,
      `describeActionError` instead of raw "Failed: …" (29 places), detail
      sheet in read-only groups
- [ ] Device check: undo snackbar (8 s, TalkBack), undone delete reaches the
      peer, details sheet + removed/archived banners at 360 dp / 200 % font,
      *Details* dialog from a snackbar
- [x] Not done: *Try again* button on error snackbars

### G68. Sync sheet per person (U24) 🟡
- [ ] Tappable cloud, status per person, *Sync now*; same sheet for Matrix and
      link groups — **with G52 step 9** (peers sheet)

### G69. Share + overview (U17, U20, U19) 🟡
- [x] "Who pays whom" as share text, group list sorted by activity, simple
      statistics on the balance page (`share_plus` added here; G52 step 6
      reuses `text_sharer.dart`)
- [x] `_PersonBalanceRow` (balance page) overflowed 12 px at 360 dp / 200 % font — fixed (Flexible + scaleDown, test)

### G70. Simplify backup / restore (U23) 🟡
- [x] One page, three blocks (file backup, restore points, reset group) with a
      decision aid — after G65, before G52 step 10 (`/backup`)
- [ ] Device check: smoke 8.16–8.18 (DE 360 dp, group picker → reset, local
      mode, nudge *Back up now*, snackbars)

### G71. Accessibility + form flow (U30, U12) 🟡
- [x] Semantics labels, 48 dp targets, autofocus / *Next* through the form;
      TalkBack / 200 % font check in the G52 step 13 device pass
- [ ] Device check: smoke §11 (11.1–11.8) in the G52 step 13 pass

### G72. Local notifications (U26) 🟢
- [ ] Notify from the background round about others' changes — **on by
      default** (Leo 2026-10-17), setting to turn off, privacy text; Android 13+
      needs `POST_NOTIFICATIONS` (today removed from the manifest, G31) +
      the runtime prompt at a sensible moment — after G52 step 8

### G73. Manual exchange rates (U18) 🟢
- [ ] Fixed rates per group in the signed meta, "settle in {currency}" — wire
      change → bundle with G57 after G52/G53
- [ ] *Fetch current rate* button (Leo 2026-10-17: any source): only on tap,
      never automatic; source named in the dialog + PRIVACY.md / in-app
      privacy text (a third-party request leaves the device — G43 promise
      wording must be adjusted); pick a keyless source without tracking

### G75. Usability polish (review leftovers) 🟡
- [x] U27: shorter, plain-language verification / device texts
- [x] U31: web limits shown once at first start (no background sync, no
      restore points, live only while the tab is open)
- [x] *Duplicate expense* (⋮ on a row / edit page) — cheap stand-in for
      recurring expenses
- [x] Calculator in amount fields ("12,50+8")
- [x] G64 leftovers: duplicate-name hint on rename; mode-dependent delete
      texts (local mode "will be deleted")
- [x] G67 leftover: *Try again* on error snackbars where the action is
      repeatable
- [ ] Device check: does the decimal keypad (Gboard) offer `+ - * /`? If not, the calculator is unreachable on Android → operator row or other keyboard type (smoke 5.18); web notice in a real web build (12.2); duplicate on two devices (5.17)
- [x] Ask Leo (2026-10-17): yes to multiple payers (G76), itemized split
      (G77), local-only receipt photo (G78); **no** quick-add shortcut / widget

### G74. Payment details + GiroCode (Leo 2026-10-17) 🟢
- [ ] Optional own IBAN / PayPal.me in the **app settings**; shown to others
      when they settle with me (GiroCode QR with amount / PayPal link) — needs
      a synced field → wire change, bundle with G57 / G73


### G76. Multiple payers per expense (Leo 2026-10-17) 🟢
- [ ] An expense paid by several people (`paid_by` → map of amounts) — wire
      change (signed body, G27 hash, CSV, backup, balance calc); older builds
      must not misread it → bundle with G57 / G73 / G74 wire changes

### G77. Itemized split (Leo 2026-10-17) 🟢
- [x] Split a receipt item by item (items → people, shared items, rest
      equally); result is a normal split map — no wire change (items not
      stored, like the split modes)
      → *Split by items…* action under the mode buttons (5 segments don't fit
      in DE at 360 dp), full-screen item editor, result opens as Amounts
- [x] Device check: smoke 5.19

### G78. Receipt photo, this device only (Leo 2026-10-17) 🟢
- [x] Attach a photo to an expense, stored only on this device (app dir, not
      synced, not in backups unless decided), clearly labelled so; deleted
      with the expense / group / local data; privacy text
      → Android only, not in backups (Leo); photos **move** with a local-mode
      adoption (expense ids unchanged); deleted expenses' photos go at the next
      app start (undo keeps them within the session)
- [x] Device check: smoke 5.20 (camera intent without permission prompt,
      photo picker, file size, cleanup, nothing reaches the peer)
- [ ] Later maybe: `retrieveLostData` (app killed while camera open); strip
      EXIF/GPS from stored photos


### G79. DEV-I findings (device pass 2026-10-17) 🟡
- [x] 200 % font at 360 dp: group cards, ledger rows, balance rows, split
      cells / mode labels, item editor, people page, currency field —
      fixed (`large_text.dart`, `test/devi_large_font_test.dart`)
- [x] **Calculator unreachable on Android:** Gboard's decimal keypad has
      only `-` → decide: operator row above the keyboard / text keyboard /
      drop the feature (Leo) → **dropped from the UI** (Leo 2026-10-17); a pasted
      expression still works
- [x] Normal font, 360 dp: ledger row "du schuldest 140,00 C…" (G33 70 %
      cap), long titles, Amounts cell "411,5CHF" (3-digit + suffix)
- [x] Section header "WIEDERHERSTELLUNGSPUNKTE" breaks mid-word at 200 %
- [x] Offline demo on Android shows web-only texts (no background sync /
      restore points "im Browser") — screenshots only
- [x] Fresh install builds the (empty) Matrix SDK store before a mode is
      chosen (`money_ledger_matrix.sqlite`, no network) — build it lazily
      only when Matrix is actually wanted
- [ ] Leo-only: TalkBack 11.1–11.4, 11.7, two-device checks (undo, duplicate,
      item split, photo never reaches peer), web notice 12.2, gallery pick,
      pinch zoom

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
- [x] G3 — release keystore
- [x] G2 — vodozemac build reproducible (upgrade to 0.6.0)
- [x] CP-accounts — test accounts `@moneyledger-test-{a,b}-c725:matrix.org` (`~/.config/moneyledger-test/accounts.env`)
- [x] G4 — per-account database
- [x] G19 — SyncEngine ref-after-dispose + flaky integration tests (pulled forward)
- [x] G7a — first real-device sync: phone (A) ↔ emulator (B) — all 10 steps pass after fixing app-wide sync host
- [x] G8 — settlements list + undo
- [x] G24 — silent no-op sends + startup message loss (pulled forward)
- [x] G9 — leave/delete group (+ G23 group mutators)
- [x] G10 — rename group / currency (+ G26 member lifecycle)
- [x] G7 — smoke checklist + device pass (iOS documented unsupported)
- [x] G28+G29 — settle any debt; currency picker, sign-out confirm, status lag, SSO label (pulled forward: features before i18n)
- [x] G20+G25 — friendly login errors, matrix.org sign-up link, late onboarding
- [x] G30 — first-login recovery + auth timeouts
- [x] G31 — background sync on Android (feature before i18n)
- [x] G12 — app identity, i18n EN+DE, privacy/about (+ G21 licensing)
- [x] G32+G17 — disable Android auto-backup; design pass (icons, theme, polish)
- [x] G15 — test/tooling debt, offline demo, CI
- [x] G5 — full-fidelity backup
- [x] G13 — CSV improvements (with G5)
- [x] G6 — signed records (any member may edit; every version signed by its editor)
- [x] G11 — verified-only replication (+ SAS emulator ↔ phone)
- [x] G14 — digest size measurement
- [x] G16 — nice-to-haves
- [x] G22 — dependency upgrades (matrix, file_picker)
- [x] G27 — LWW tie-break
- [x] G33 — design follow-ups (settlement title, test display names)
- [x] G34+G35 — backup + signed-records follow-ups
- [x] G36+ — verification follow-ups + robustness leftovers (G29/G30/G31/G33/G37)
- [x] G37 — scale follow-ups (optional)
- [ ] *(G32+ — newly discovered points)*
- [x] G40+G39 — fully local mode (no Matrix account) + first-open welcome
- [x] G41 — local-mode follow-ups (restore adoption, empty local DB file)
- [x] G38 — app id io.github.leostumpf.moneyledger + device reset (tests G39 on fresh installs)
- [x] G18 — final release review
- [x] G43 — privacy promises true (web CDN, matrix.org probes, privacy texts)
- [x] G44 — small release fixes (license label, AGP blob, release logging)
- [x] G45 — minimal Matrix footprint (sync filter, presence) — device smoke 7.12 moved to the end
- [x] G46 — UX quick wins
- [x] G47 — custom categories + dropdown
- [x] G48 — restore points + revert
- [x] G49 — expense date
- [x] G59 — smarter split defaults (prefill from current split, "fill the rest")
- [x] G62 — reset page empty after update / new group (found in DEV-H)
- [x] G50 — no-login link groups design doc (`docs/design/no-login-sharing.md`) — signed off by Leo 2026-10-17 (§14)
- [x] G51 — Nostr spike — GO (2026-10-17); retention checks + web-verify decision open
- [ ] G52 — link groups implementation
- [ ] G53 — mixed groups + lock group
- [ ] G54 — "Why Matrix?" info screen + welcome reorder
- [x] G55 — web glyph coverage without Google (found in G43) — accepted as is (Leo 2026-10-17); Flutter-upgrade reminder kept in G55
- [x] DEV-H — device/browser pass for Phase H: G45 smoke 7.12 (pre-G45 install updates, `[g45]` cache clear once, sync/invite/SAS ok, presence stays offline), G43 manual browser network check, G46 (Delete local data → welcome choices; Back from a new group → list), G47 smoke 5.13 + 5.14 on two devices, G48 smoke 8.13–8.15, G49 smoke 5.15, G59 split rows at phone width (use `pixel-lock` for the Pixel) — done 2026-10-17: all pass; found G62
- [ ] G58 — restore-point follow-ups (found in G48)
- [x] G60 — expense-date follow-ups (found in G49)
- [ ] G61 — split follow-ups (found in G59)
- [ ] G57 — custom-category follow-ups (found in G47)
- [x] G56 — UX follow-ups (found in G46)
- [x] G63 — correctness + texts before release (usability review U11 …)
- [x] G64 — people when creating a group (before G52 step 6/7)
- [x] G65 — group settings + settings page (before G52 step 6/9)
- [x] G66 — currencies
- [x] G67 — undo + understandable errors
- [ ] G68 — sync sheet per person (with G52 step 9)
- [x] G69 — share + overview
- [x] G70 — simplify backup / restore
- [x] G71 — accessibility + form flow
- [ ] G72 — local notifications (on by default)
- [ ] G73 — manual exchange rates + fetch button (with G57)
- [x] G75 — usability polish (review leftovers)
- [ ] G74 — payment details + GiroCode (with G57 / G73)
- [ ] G76 — multiple payers (wire, with G57 / G73 / G74)
- [ ] G79 — DEV-I findings (calculator keyboard, truncations, lazy Matrix store)
- [x] G77 — itemized split
- [x] G78 — receipt photo, this device only

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
