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
- [ ] Release notes: debug-signed installs must be uninstalled once (local data lost → export first)

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
- [ ] Later: delete the adopted legacy DB once adoption is confirmed (G18)

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
- [ ] Archive for settled-up groups — not done (future, low priority)

### G10. Group rename + default currency edit 🟡
Group meta is LWW-synced already (`meta_updated_at`), only the UI is missing.
- [x] "Edit group" in the ⋮ menu (name + default currency for new expenses);
      `GroupEditor` LWW upsert + `com.moneyledger.group` replication
- [x] Rename convergence (incl. concurrent) tested + verified on phone ↔ emulator

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
- [ ] Manifest: `android:enableOnBackInvokedCallback="true"` (predictive back; logcat warning)

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
- [x] Test the `routerProvider` `refreshListenable` wiring (done in G25)
- [ ] Offline demo mode `--dart-define=OFFLINE_DEMO=true` (override transport +
      auth gateway with seeded fakes) for screenshots / manual multi-user checks
- [ ] CI (GitHub Actions): `./build.sh` on push — needs G2 first for Android
- [ ] `dart format` the whole repo once (files are unformatted; agents avoid it to keep diffs small)
- [ ] Regenerate stale `.g.dart` files (build_runner changes hashes in 4 untouched files)
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
- [ ] Add `LICENSE`, `THIRD_PARTY_NOTICES.md` (cf. ZoneCraft/PositioningInfo), in-app
      licenses page (`showLicensePage`) + source link in About (G12)

### G22. Dependency upgrades (matrix 7 → 10+, file_picker 8 → 10) 🟡
`flutter_vodozemac` is pinned at 0.6.x by `matrix` 7.2.2 (`vodozemac ^0.5.0`); 0.7+/0.8
need matrix 10+/11+ and a rebuilt `web/pkg` wasm. file_picker 10.x compiles
against SDK 36 natively (the G1 gradle override could go).
- [ ] Assess the matrix SDK major upgrade (API changes in to-device/encryption,
      DB init) — do it only if low-risk; rebuild web wasm
- [ ] Upgrade file_picker to 10.x; drop the compileSdk override if no longer needed

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
- [ ] Deterministic tie-break (e.g. compare a content hash) in all LWW upserts + digest compare

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
- [ ] Writer side still pending ~27 s after own change (ack = digest after 5 s poke
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
- [ ] A timed-out login still completes in the background (SDK call not cancelled)
      → a retry can create a second device; guard against concurrent logins
- [ ] Queued retries are each answered later → bootstraps sent up to 4×; dedupe

### G31. Sync only happens while the app is open (no background sync) 🟠
To-device messages are queued on the homeserver and only fetched while
MoneyLedger runs. Peers/own devices that never open the app never answer
(digests, resync, bootstraps) — observed in G30. Options: Android periodic
background fetch (WorkManager: start client, one /sync, process to-device,
answer pending requests, stop), and/or Matrix push (pusher + push gateway → FCM;
needs a gateway, privacy trade-offs). Web: only while the tab is open.
- [ ] Evaluate + implement a periodic background sync on Android (battery-friendly,
      e.g. every 15 min, network-constrained)
- [ ] Explain in onboarding/help that devices sync when the app runs
- [ ] Decide on push (later, likely out of v1 scope)

### G17. Design pass — a polished, consistent look 🟡
- [ ] Coherent Material 3 theme (seeded color scheme, typography, dark mode)
- [ ] Empty states, spacing, list/card styling for groups, expenses, balances
- [ ] Iterate against emulator screenshots of every main screen
- [ ] Real-device findings (G7a): expenses title says only "Expenses" (truncated
      "Expe…") — show the group name; keyboard covers the "Add" button on the
      expense form; members shown by Matrix localpart (wraps) — prefer the
      Matrix display name; add-member dialog can't add a local person by name;
      long names wrap the settlement title over 4 lines; expense tiles show no date

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
- [ ] G31 — background sync on Android
- [~] G12 — app identity, i18n EN+DE, privacy/about (+ G21 licensing)
- [ ] G17 — design pass
- [ ] G15 — test/tooling debt, offline demo, CI
- [ ] G5 — full-fidelity backup
- [ ] G13 — CSV improvements
- [ ] G6 — signed records (any member may edit; every version signed by its editor)
- [ ] G11 — verified-only replication (+ SAS emulator ↔ phone)
- [ ] G14 — digest size measurement
- [ ] G16 — nice-to-haves
- [ ] G22 — dependency upgrades (matrix, file_picker)
- [ ] G27 — LWW tie-break
- [ ] *(G32+ — newly discovered points)*
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
