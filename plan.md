# MoneyLedger — Implementation Plan

Active phase: **Phase F — Public-release hardening** (see design + milestones at
the bottom). Phases C/D/E and virtual users are done; detail is in git history,
`docs/open-points.md`, and `CLAUDE.md`.

Status legend: `[ ]` open · `[x]` done. Update this file as milestones land.
Workflow: commit + push after each milestone (tests green first).

---

## Roadmap

1. ~~Phase C — sync reliability + edit/delete~~ ✅
2. ~~Virtual users~~ ✅
3. ~~Phase D — CSV export/import~~ ✅
4. ~~Phase E — Custom splits — per-person amounts/shares~~ ✅
5. **Phase F — Public-release hardening** — membership-gated records, surfacing
   sync failures, registration + onboarding, device-verification UX ← this plan
6. Nice-to-haves: offline demo mode, group rename/currency edit, avatars

---

## Phase D — design

**Goal.** Export a group to a spreadsheet-friendly CSV (backup / sharing /
migrating old room-era groups) and import one back. Decisions (locked):

- **Human-readable expenses sheet** — one CSV per group, one row per (non-deleted)
  expense, with a share column per participant. Readable columns first, machine
  columns appended so it still round-trips.
- **Import merges by id (LWW)** — idempotent: re-importing a backup never
  duplicates; a group id not present locally is created.

### Reconciliation (the two choices partly conflict — how we square them)

A purely human-readable sheet has no ids/clocks; id-based LWW merge needs them.
So the CSV is readable **and** carries trailing machine columns:

```
Date, Description, Currency, Amount, Paid By, <Participant A>, <Participant B>, …, Expense ID, Group, Group ID, Updated At
2026-06-13T…, Dinner, EUR, 42.00, Alex, 21.00, 21.00, …, <uuid>, Trip, <gid>, 1760000050000
```

- Leading columns are the spreadsheet view; share columns are decimals per
  participant (header = display name); trailing columns drive the merge.
- **Participants are matched by display name** within the target group (created
  as local participants if unknown) — the sheet carries names, not participant
  ids, so identity is by name (acceptable for a human-readable backup).
- **Merge:** ensure the group by `Group ID` (LWW-upsert meta, create if absent),
  resolve/create participants by name, then **LWW-upsert each expense by
  `Expense ID`** using `Updated At` as the clock → idempotent re-import.
- **Out of scope (documented limitation):** settlements and tombstones are not
  in the sheet; balances reconstruct from expenses only. Participant identity is
  by name, not stable id. A future full-fidelity backup format could add these.

---

## Milestones

Each milestone is one commit: code + tests, `flutter test --reporter compact`
green; `dart run build_runner build` after any annotated-file change.

### M1 — CSV codec (pure Dart) ✅

- [x] `lib/features/backup/ledger_csv.dart`: RFC4180 encode/decode;
      `buildGroupCsv(group, members, expenses)` (non-deleted, share column per
      participant); `parseGroupCsv` → `ParsedCsv` / `ParsedExpenseRow`.
- [x] tests (`test/features/ledger_csv_test.dart`, 7): round-trip; quoting
      (comma/quote/newline in description + names); decimal↔cents; share columns
      map to the right people; deleted excluded; empty group.

### M2 — Import service (DB merge) ✅

- [x] `lib/features/backup/csv_import.dart` (`CsvImporter`): ensure group (LWW
      meta, create if absent) → resolve participants by name (existing else new
      local) → LWW-upsert expenses by id (shares remapped name→participant id).
- [x] tests (`test/features/csv_import_test.dart`, 4): import into empty creates
      group + participants + expenses; idempotent re-import; LWW merge (newer
      wins, stale ignored); unknown names → local participants. Suite green (175).

### M3 — Export/import UI + platform glue ✅

- [x] export action on the expenses screen → `buildGroupCsvForExport` →
      `saveCsvFile` (web download / native save via `file_picker`).
- [x] import action on the groups screen → `pickCsvText` → `CsvImporter`;
      snackbar success/error feedback.
- [x] `lib/features/backup/csv_export.dart` (DB→CSV seam + `csvFileName`) and
      `csv_files.dart` (file_picker glue, manual-smoke only).
- [x] tests (`test/features/csv_export_test.dart`, 3): export round-trips back
      to expenses; missing group → empty; file-name sanitising. Import seam
      covered in M2; file pick/share is manual-smoke only (like SSO deep-link).

### M4 — Docs ✅

- [x] `CLAUDE.md`: "Backup (CSV export/import — Phase D)" section (format,
      columns, merge semantics, limitations) + `backup/` in the structure tree.
- [x] `docs/open-points.md`: item #16 (Phase D done; settlements/tombstones not
      in sheet, identity-by-name limitation); roadmap/footer updated.

---

## Verification

`flutter test --reporter compact` green per milestone; `./build.sh` green at
phase end. Manual smoke: export a group on web, re-import the file → no
duplicates; edit a share in a spreadsheet, re-import → LWW applies.

---

# Phase E — Custom splits

**Goal.** Let an expense be divided **unequally** — not just split equally among
everyone. The add/edit form gets a split editor with four modes; the resolved
`{participantId: cents}` map is unchanged elsewhere.

## Phase E — design

**Key fact:** the split is already a `{participantId: cents}` map *everywhere* —
DB (`splitsJson`), wire (`split`), balance calc, CSV (one share column per
participant). Nothing assumes equality **except the add/edit UI**
(`add_expense_page.dart`, `amountCents / members.length` for every member). So
custom splits is a **UI + split-math feature, not a protocol change.**

Decisions (locked):

- **Four split modes** in the editor: **Equal + pick who** (checkboxes; not
  always everyone), **Exact amounts** (per-person cents, must sum to total),
  **Shares/weights** (integer weights → proportional), **Percentages** (% per
  person, must total 100%).
- **Cents-only persistence** — store only the resolved cents map (no new wire/DB
  fields, fully forward/backward compatible). The split *mode* and raw inputs
  (weights/percents) are **not** persisted. On **edit**, infer the opening mode:
  all included shares equal → **Equal**, otherwise → **Exact** (prefilled with
  the stored cents). Re-opening a shares/percent expense shows it as exact
  amounts — same result, just not the original knobs.
- **Excluded participants are absent from the map** (not stored as `0`). Balance
  calc already skips them; CSV shows a blank share column; on edit, the included
  set = the map's keys.
- **Largest-remainder rounding** — every computed mode (equal/shares/percent)
  distributes `total` by flooring each share, then handing the leftover cents
  one-by-one to the largest fractional remainders (deterministic, stable order).
  Guarantees the shares **sum to the total exactly** — this also fixes a latent
  bug in today's equal split (`round()` per person can lose/gain a cent, e.g.
  100¢ ÷ 3 = 33¢×3 = 99¢).
- **Out of scope:** itemised receipts, per-item assignment, tax/tip lines,
  saving a default split per group. (Future.)

## Milestones

Each milestone is one commit: code + tests, `flutter test --reporter compact`
green; `dart run build_runner build` after any annotated-file change.

### M1 — Split math (pure Dart) ✅

- [x] `lib/features/expenses/split_calculator.dart` (pure Dart, no Flutter/DB):
      `splitEqually(total, ids)`, `splitByShares(total, {id: weight})`,
      `splitByPercent(total, {id: percent})` → `{id: cents}` summing **exactly**
      to total via the shared `distributeByWeights` largest-remainder helper;
      `isEqualSplit(map)` for edit-mode inference; `remainingForExact`.
- [x] tests (`test/features/split_calculator_test.dart`, 21): sum-equals-total
      invariant incl. the 100¢÷3 remainder case + a brute-force sweep; shares
      proportionality; percent→cents; deterministic remainder assignment; single
      participant; empty/zero-weight guarded; `isEqualSplit` true/false (incl.
      the canonical 34/33/33 and the wrong-cent-position negative). Suite 199.

### M2 — Split editor UI + wire into add/edit ✅

- [x] `lib/features/expenses/split_editor.dart`: a `SplitEditor` widget — mode
      selector (`SegmentedButton`: Equal/Exact/Shares/%) + per-participant rows
      (checkbox / amount / weight / percent) with a live per-person preview and a
      status line (remaining / total weight / 100%). Surfaces an immutable
      `SplitPlan` (mode + raw inputs) via `onPlanChanged`; the **parent resolves
      it against the live amount** so changing the amount never strands a stale
      split (no didUpdateWidget round-trip).
- [x] `add_expense_page.dart`: replaced the hardcoded equal split with
      `SplitEditor`; Add/Save disabled unless `_plan.resolve(amount).isValid`; on
      edit, seeds included set + mode from the stored map (`isEqualSplit` →
      Equal, else Exact prefilled).
- [x] widget tests (`test/add_expense_page_test.dart`, +5): exact relays typed
      amounts; shares relays a proportional split; deselecting in Equal excludes;
      an unbalanced exact split disables Add (shows Remaining); editing an
      unequal expense opens Exact prefilled. Suite 204.

### M3 — Round-trip + docs ✅

- [x] confirmed an unequal split round-trips through CSV export/import (blank
      column = excluded participant): new `csv_import_test` case covers an
      unequal both-present split and an excluded participant. Replication/edit
      need no change — the wire `split` map was already arbitrary.
- [x] `CLAUDE.md`: "Custom splits (Phase E)" section (four modes, cents-only
      persistence, largest-remainder rounding, edit-mode inference, excluded =
      absent) + `split_calculator.dart`/`split_editor.dart` in the structure tree.
- [x] `docs/open-points.md`: item #17 (settlements still split-free;
      mode/raw-inputs not persisted); roadmap/footer updated.

## Verification (Phase E)

`flutter test --reporter compact` green per milestone; `./build.sh` green at
phase end. Manual smoke: add an expense, switch modes, confirm the live preview
sums to the total; save an unequal split → balances reflect it; edit it →
reopens prefilled; export → re-import → unchanged.

---

# Phase F — Public-release hardening

**Goal.** Close the gaps that stand between "works for the developer" and "safe
to hand to strangers": a sender can't forge another group's ledger, sync
failures are visible instead of silent, new users can create an account and
get oriented, and E2EE between devices can be verified rather than blind-trusted.

## Phase F — design

The four areas are independent and ship in order of value/risk: security and
reliability first, then the product/onboarding surface, then the heaviest
(device verification) last. Decisions (locked):

### 1. Membership-gated inbound records (the trust model)

Today `LedgerSyncer._onMessage` applies every inbound `expense` / `settlement` /
`member` / `bootstrap` with **no sender check** — any Matrix user who knows your
MXID can forge a record. To-device messages are **E2EE**, so `msg.senderId` is
already cryptographically authenticated; the only missing step is checking that
the authenticated sender is a **member of the group they're writing to**.
`SyncEngine` already does this for `resync_request` (`_claimedBy` + rule 5/6);
`LedgerSyncer` will do the analogous check.

- **Expense / settlement:** apply only if `senderId` ∈ the group's **active
  claimed** members. Group/members unknown → drop (a digest/bootstrap will
  establish membership first, then repair).
- **Bootstrap:** first contact for an **unknown** group is **TOFU-accepted** (the
  inviter/own-device defines the group + its membership). A bootstrap for a group
  we **already know** is honoured only from an active member — a stranger can't
  rewrite an existing group wholesale.
- **Member (claim/membership) gossip:** apply if `senderId` ∈ active members,
  **or** it is a **self-claim** — `payload.matrix_id == senderId` for a
  `participant_id` that already exists in the group (this is how an invited
  account legitimately joins; it can only claim itself onto an existing local
  participant, never invent membership). Removing/unclaiming *another*
  participant requires being an active member.
- **Clock clamp:** clamp inbound `updated_at` to `min(updated_at, now + 5min)`
  before LWW, so a skewed/hostile clock can't future-date a record and win every
  merge forever.
- The check is a **pure function** (`isSenderAuthorized(type, senderId, content,
  members, groupKnown)`) for unit-testing; `_onMessage` becomes async, fetches
  the group's members from Drift, and only calls the (still-pure) processor when
  authorized. **Out of scope:** per-record cryptographic signatures (a future
  phase) — membership gating over E2EE-authenticated senders is the MVP.

### 2. Surface sync / transport failures

Replication and digest errors are currently swallowed into `debugPrint`, so a
user can silently diverge. Add a `SyncHealth` Riverpod notifier the transport /
sync layer reports success/failure to (last error + timestamp, consecutive-fail
count). Drive a **third app-bar state** (`cloud_off` / error colour) beside the
existing `cloud_done` / `cloud_queue`, tappable to show "last synced … / last
error …" with a **manual retry** (re-run `broadcastDigests` + re-replicate).
Keep the health model a pure/testable seam; the icon + sheet are thin UI.

### 3. In-app registration + onboarding

- **Registration:** support **password registration** against homeservers whose
  UIA offers `m.login.dummy` (no captcha). Servers requiring reCAPTCHA / email /
  terms get a clear message pointing to web registration (don't reimplement
  every UIA stage). Parsing the flows / building the request is a pure,
  unit-tested function (mirrors `sso_url.dart` / `sso_callback.dart`).
- **Onboarding:** a first-run flow (shown once, gated by a local flag) explaining
  the decentralized model — your data is local, groups sync peer-to-peer, no
  central server — and the basics of adding members/expenses.

### 4. Device-verification UX

Heaviest, Matrix-SDK-specific, last. **MVP = visibility + manual verification,
not enforcement:** list a user's own + members' devices with verified/unverified
status, allow **SAS (emoji) verification**, and bootstrap cross-signing. A
verified-only replication toggle is **off by default / out of scope for MVP**
(it can strand legitimate unverified devices). Much of this is manual-smoke on a
real homeserver (like the SSO deep link); unit-test whatever is pure.

## Milestones

Each milestone is one commit: code + tests, `flutter test --reporter compact`
green; `dart run build_runner build` after any annotated-file change.

### F-M1 — Inbound membership gate + clock clamp ✅

- [x] `LedgerSyncer.isSenderAuthorized(...)` pure function (expense/settlement/
      group-meta → active member; bootstrap → unknown-group TOFU else member;
      member → self-claim/join for own MXID, no hijack of another's participant)
      + `clampInboundClock` helper.
- [x] wired into `LedgerSyncer._onMessage` (now async: fetches the group's
      members + existence from Drift, drops unauthorized with a debug log);
      clamp applied in every processor's `updated_at`.
- [x] tests: `inbound_authorization_test` (14 — every rule incl. removed sender,
      hijack, forge-other, clamp) + `integration/membership_gate_test` (2 —
      forged non-member expense dropped, real member's expense applied). All
      existing replication/self-claim/join flows still green. Suite 221.
- [x] `CLAUDE.md` (Data Flow membership-gate note) + `docs/open-points.md`
      (trust-model limitation → membership-gated; residual = per-record
      cryptographic authorship).

### F-M2 — Surface sync / transport failures ✅

- [x] `SyncHealth` notifier (`lib/core/sync/sync_health.dart`, `keepAlive`):
      `SyncHealthState` (consecutive-fail count + last error/ts + last-success
      ts); `failing` only after `kSyncFailureThreshold` (2) consecutive failures
      so a single offline blip doesn't alarm. Reported from `_replicate`
      (`expenses_provider`) and `_sendDigest` (`sync_engine`).
- [x] app-bar error cloud (tappable) → sheet with last-synced / last-error +
      **Retry now** (`broadcastDigests()`); replaces the silent `debugPrint`.
- [x] tests: `core/sync_health_test` (6 — transitions + notifier on/off) and a
      page widget test (error cloud shown + retry sheet). Also made the
      add-expense form scrollable (`SingleChildScrollView`) so the taller
      split-editor form can't push the payer dropdown off-screen. Suite 228.

### F-M3 — Auth edge cases (#10 / #11) ✅

- [x] verified via the fake auth gateway (no production change needed — the
      `authProvider → loginStateProvider → isLoggedInProvider` chain already
      handles both): `re-login after logout` round-trip flips `isLoggedIn` back
      to true; `simulateRemoteLogout()` (an external `loginStateChanges` event)
      flips it to false without the app calling `logout()`.
- [x] `auth_gateway_test` +2; `FakeAuthGateway.simulateRemoteLogout` helper.
      Resolves open-points #10/#11 (real-`Client` SDK round-trip after logout
      remains a device smoke-test caveat). Suite 230.

### F-M4 — In-app registration ✅

- [x] pure `classifyRegistrationFlows` (`register_flows.dart`): a `m.login.dummy`
      flow → in-app; captcha/email/phone/terms/token → web fallback with friendly
      labels (easiest flow reported). `AuthGateway.register` + the real adapter's
      UIA dummy-completion dance + `RegistrationRequiresWebException`.
- [x] `RegisterPage` (homeserver/username/password; success → `/groups`;
      requires-web → fallback card with "Open homeserver website"); `/register`
      route + redirect allowance; "Create an account" link on the login page.
- [x] tests: `register_flows_test` (8), `register_page_test` (4 — render,
      success-navigates, web-fallback, short-password guard), `auth_gateway_test`
      (+2 register paths), `router_redirect_test` (+2 `/register`). Suite 246.

### F-M5 — First-run onboarding

- [ ] one-time onboarding flow gated by a local flag (intro to the decentralized
      model + add members/expenses); entry from first launch / post-register.
- [ ] tests: shows on first run, suppressed thereafter (flag persisted).

### F-M6 — Device-verification UX

- [ ] device list with verified/unverified status; SAS (emoji) verification;
      cross-signing bootstrap. Verified-only replication stays off by default.
- [ ] unit-test the pure bits; the SDK round-trip is manual-smoke on a real
      homeserver (documented like the SSO caveat).

## Verification (Phase F)

`flutter test --reporter compact` green per milestone; `./build.sh` green at
phase end. Manual smoke: forge a record from a non-member device → it's ignored;
kill connectivity mid-write → the error surfaces and retry recovers; register a
new account on a dummy-UIA homeserver; complete onboarding once; verify a second
device by emoji.
