# MoneyLedger — Implementation Plan

Overall picture and the Phase C implementation plan (sync reliability + expense
edit/delete). Decisions behind this plan: **reliability first**, expenses must be
**editable and deletable**, target is a **public release**.

Status legend: `[ ]` open · `[x]` done. Update this file as milestones land.

---

## 1. Where the project stands (2026-06-12)

The hard architectural work is done and validated (Phases A/B, commits
`a1a0e5e` → `ad1c757`):

- **Roomless local-first sync** — groups live only in local Drift; Matrix is
  purely an encrypted to-device relay; the homeserver retains no ledger data.
- Clean port architecture: `LedgerTransport` + `AuthGateway` seams, fakes for
  both, ~2,100 lines of tests, no `package:matrix` outside the adapters.
- Core happy path works: login (password + SSO), groups, members (add/remove
  with LWW), expenses, settlements, multi-currency balances.

**Biggest gap:** replication is fire-and-forget. A lost to-device message, a
new device, or a reinstall makes a peer's ledger silently diverge **forever**.
For a money app this is the #1 risk. Expenses are also immutable (no
edit/delete), and edit semantics interact with the sync protocol — so both are
one phase.

Stale docs: `docs/open-points.md` (items #2, #12) and the Architecture/Data
Model sections of `CLAUDE.md` still describe the pre-Phase-B room-based design.
Fixed in M8.

## 2. Roadmap (recommended order)

1. **Phase C — sync reliability + expense edit/delete** ← this plan, detailed below
2. **Virtual users** (open-points #7) — Tricount-style participants (name +
   optional MXID, claimable on join); do before more features pile onto raw
   MXIDs; also fixes removed-member display (#8)
3. **Phase D — CSV export/import** — backup + migration path for old
   room-based groups
4. **Custom splits** — per-person amounts/shares (pure UI/model work once edit exists)
5. **Public-release hardening** — in-app registration, onboarding,
   device-verification UX (currently TOFU), auth edge cases (#10/#11),
   surfacing sync failures, store builds, Android vodozemac build robustness
6. Nice-to-haves: offline demo mode (#9), group rename/currency edit, avatars

---

## 3. Phase C design: record-digest anti-entropy

**No sequence numbers, no outbox — the Drift DB is the replication log.**

Every record (expense, settlement, member, group meta) gets a per-record
`updatedAt` LWW clock and a `deleted` tombstone flag — extending the proven
pattern of `upsertMemberLww` (`lib/core/database/daos/members_dao.dart:30`).
Peers periodically exchange **digests** (`{recordId: updatedAt}` per group);
comparing digests tells each side exactly which records to (re)send, and a
re-send is just the normal payload rebuilt from the DB row.

Why digests instead of per-sender sequence numbers:

- Reinstall / new device recovery falls out for free: an empty digest gets repaired.
- An edit is the same record with a higher `updatedAt` — no seq/edit ambiguity.
- No per-peer bookkeeping, no seq-reset epochs.
- Cost: digest is O(records in group), fine to ~1,000 records/group under
  to-device size limits — the same ceiling the existing `bootstrap` payload
  already accepts. `"v"` (protocol version) on every payload allows sharding later.

### 3.1 Payload formats (protocol v1 — every payload gains `"v": 1`)

**`com.moneyledger.expense`** (settlement analogous) — extended:

```json
{
  "v": 1,
  "id": "<uuidv7>",
  "group": "<groupId>",
  "description": "Dinner",
  "amount": 4200,
  "currency": "EUR",
  "paid_by": "@alice:matrix.org",
  "split": {"@alice:matrix.org": 2100, "@bob:matrix.org": 2100},
  "created_at": 1760000000000,
  "updated_at": 1760000050000,
  "deleted": false
}
```

Edit = full re-send with `updated_at = now`. Delete = same with
`deleted: true`. Receivers apply **whole-record LWW** on `updated_at`.

**`com.moneyledger.digest`** (new) — sent per group to all active members
*including self* (reaches own other devices, same convention as `_replicate`):

```json
{
  "v": 1,
  "group": "<groupId>",
  "reply": false,
  "meta_updated_at": 1760000000000,
  "members": {
    "@alice:x.org": {"status": "active",  "updated_at": 1759990000000},
    "@bob:y.org":   {"status": "removed", "updated_at": 1760000010000}
  },
  "expenses":    {"<uuid>": 1760000050000},
  "settlements": {"<uuid>": 1759995000000}
}
```

Maps are `id → updated_at`, **tombstones included**. The `members` map doubles
as membership gossip (fixes the orphan case where the introducer bootstraps a
new member and then goes offline before telling the others).

Digest **receiver rules**:

1. For each record where the local copy is newer or the sender lacks it →
   re-send the normal record payload to the sender (targeted repair).
2. Apply the `members` map via LWW (`processMember`).
3. If the sender has newer/unknown records and `reply == false` → send own
   digest back with `reply: true`. A reply **never** triggers another reply
   (bounded two-message exchange; residual divergence is caught next cycle).
4. Exact match → record `lastInSyncAt = now` for `(group, sender)`; if
   `reply == false`, still send the matching reply so the sender learns it too.
5. Digest for an **unknown group** → send `resync_request` for it.
6. Digest from a sender who is locally `removed` in that group → reply only
   with their member-tombstone record (their device learns of the removal).

**`com.moneyledger.resync_request`** (new):

```json
{"v": 1, "scope": "group", "group": "<groupId>"}
```

or `{"v": 1, "scope": "all"}`. Handler responds with bootstrap payload(s) —
only if the requester is an active member of that group, or is the responder's
own MXID (`scope: all` honored only for self).

**`com.moneyledger.bootstrap`** — extended with `v` and per-record
`updated_at`/`deleted`, **tombstones included** (otherwise a stale device
receiving a bootstrap could keep a live copy of a deleted expense and
re-gossip it).

**Digest send triggers:** engine start (per group) · periodic timer (~10 min,
injectable for tests) · debounced after receiving any ledger payload (acts as
an ack) · `pokeGroup(groupId)` ~5 s after a local write (fast checkmarks).

---

## 4. Milestones

Each milestone is one commit: code + tests, `flutter test --reporter compact`
green, `dart run build_runner build` after any annotated-file change.

### M1 — Schema v3: LWW clocks, tombstones, peer sync state

- [x] `lib/core/database/app_database.dart`:
  - [x] `Groups` += `updatedAt` (int, default 0) — group meta currently has no
        clock; concurrent renames flip-flop today
  - [x] `Expenses` += `updatedAt` (int, default 0), `deleted` (bool, default false)
  - [x] `Settlements` += same two columns
  - [x] new table `PeerSyncStates`: `groupId`, `userId`, `lastInSyncAt`
        (int, default 0), `lastDigestSentAt` (int, default 0), PK `(groupId, userId)`
  - [x] `schemaVersion => 3`; `onUpgrade` `if (from < 3)`: `addColumn` ×5,
        `createTable(peerSyncStates)`, backfill
        `UPDATE expenses SET updated_at = created_at` (and settlements)
- [x] `lib/core/database/daos/expenses_dao.dart`:
  - [x] `watchExpensesForRoom` / `watchSettlementsForRoom` /
        `getExpensesForRoom` / `getSettlementsForRoom` filter
        `deleted == false` (BalancePage/balance_provider stay correct unchanged)
  - [x] new `getAllExpensesForGroup` / `getAllSettlementsForGroup`
        (tombstones included — for digest/bootstrap building)
  - [x] replace `insertOnConflictUpdate` with `upsertExpenseLww` /
        `upsertSettlementLww` — copy the `DoUpdate(..., where: old.updatedAt
        .isSmallerOrEqualValue(...))` pattern from `members_dao.dart:30`
- [x] new `lib/core/database/daos/sync_states_dao.dart` (upsert + watch)
- [x] `lib/core/database/daos/groups_dao.dart`: LWW upsert for group meta
- [x] `lib/models/expense_model.dart`: `ExpenseModel`/`SettlementModel` +=
      `updatedAt`, `deleted`; writers set `updatedAt = createdAt` on create
- [x] codegen
- [x] tests (`test/database/expenses_dao_test.dart`): stale LWW upsert ignored;
      deleted rows hidden from `watch*`, returned by `getAll*`

### M2 — Protocol fields + shared payload codec + LWW processors

- [x] new `lib/core/sync/ledger_payloads.dart` (plain Dart, models only):
  - [x] `const protocolVersion = 1`
  - [x] `expensePayload(ExpenseModel)`, `settlementPayload(...)`,
        `memberPayload(...)`
  - [x] `buildBootstrapContent(group, members, expenses, settlements)` — move
        `_buildBootstrap` out of `MemberAdder`
        (`lib/features/groups/group_provider.dart`) for reuse by repair/resync
- [x] `lib/features/expenses/ledger_syncer.dart`:
  - [x] `processExpense`/`processSettlement` parse `updated_at` (fallback
        `created_at`) + `deleted`, call LWW upserts
  - [x] `processGroupMeta` becomes LWW
  - [x] `processBootstrap` nested processors tombstone-aware
- [x] `lib/features/expenses/expenses_provider.dart`: `_replicate` payloads
      built via the codec (now carry `v`, `updated_at`, `deleted: false`)
- [x] tests (`test/features/ledger_syncer_test.dart`): stale edit payload
      doesn't overwrite newer row; tombstone not resurrected by an older live
      payload; bootstrap containing a tombstone deletes the local live copy

### M3 — Edit & delete (data layer + replication)

- [x] `ExpenseAdder` (`lib/features/expenses/expenses_provider.dart`):
  - [x] `updateExpense({id, roomId, description, amount, currency, paidBy,
        splits})` — LWW upsert with `updatedAt = now`, then `_replicate`
  - [x] `deleteExpense(id, roomId)` — `deleted: true`, `updatedAt = now`, replicate
  - [x] `deleteSettlement(id, roomId)` — same (settlement *edit* omitted:
        delete + re-create covers it)
- [x] tests: extend `test/features/local_first_write_test.dart` (edit/delete
      persist offline, replicate when online); new integration test —
      concurrent edit of the same expense on Alice and Bob converges to the
      same winner on both; delete on one device disappears from the other

### M4 — Edit/delete UI

- [x] `lib/features/expenses/add_expense_page.dart`: optional
      `ExpenseModel initial` → prefill, submit calls `updateExpense` with
      the existing id
- [x] `lib/core/router.dart`: edit route
      (e.g. `/groups/:id/expenses/edit/:expenseId`)
- [x] `lib/features/expenses/expenses_page.dart`: tap tile → edit; trailing
      menu (or long-press) → delete with confirmation dialog
- [x] tests: extend `test/expenses_page_test.dart`,
      `test/add_expense_page_test.dart`

### M5 — Anti-entropy SyncEngine (digest exchange + repair)

- [x] `lib/core/matrix/ledger_transport.dart`: + `digestEventType =
      'com.moneyledger.digest'`, `resyncRequestEventType =
      'com.moneyledger.resync_request'` (no interface change — `onMessage` is
      broadcast, `sendToUsers` suffices)
- [x] new `lib/core/sync/sync_engine.dart` + `syncEngineProvider` (mirror the
      `ledgerSyncerProvider` pattern, `ledger_syncer.dart:16`; watch from
      `ExpensesPage`/`GroupsPage` alongside the syncer):
  - [x] own `onMessage` subscription handling `digest` + `resync_request` per
        the receiver rules in §3.1 (LedgerSyncer stays a pure state-mirror)
  - [x] periodic timer (injectable interval) + `pokeGroup(groupId)` debounce
  - [x] `@visibleForTesting` pure core: `buildDigestContent(...)` and
        `compareDigest(localRecords, remoteDigest) → DigestDiff{idsToResend,
        senderHasNewer}`
  - [x] update `PeerSyncStates.lastInSyncAt` on matching digests
  - [x] `resync_request` handler: membership check → `buildBootstrapContent`
- [x] `test/helpers/fake_ledger_network.dart`: message-loss injection
      (drop predicate / partitioned users)
- [x] tests: `compareDigest` units (missing / stale / tombstone / identical);
      integration — dropped expense repaired by digest cycle; deleted expense
      never resurrected by a stale peer; removed member's device learns its
      removal; digest exchange terminates (no ping-pong)

### M6 — New-device / reinstall recovery

- [x] `test/helpers/fake_ledger_network.dart`: multi-device — key transports
      by `(userId, deviceId)`, `clientFor(userId, {device = 'D1'})`; deliver
      to all of the target's devices except the exact sending transport
      (matches homeserver semantics; existing tests stay green)
- [x] `lib/core/sync/sync_engine.dart`: on start with empty `Groups` table →
      `resync_request{scope: all}` to own MXID; handler honors `scope: all`
      for self-senders only, replies with one bootstrap per group
      (the M5 unknown-group-digest rule covers organic repair)
- [x] tests: second device of Alice logs in empty and receives all groups
      from device 1; reinstall recovered purely via Bob's periodic digest

### M7 — Sync-status UI

- [x] new `groupSyncStatusProvider(groupId)` (in `lib/core/sync/`): combine
      active members + `PeerSyncStates` — `synced` iff every active peer's
      `lastInSyncAt >=` the group's max record `updatedAt`; per-expense:
      pending unless `expense.updatedAt <= min(lastInSyncAt over active
      peers)` (sound: a matching digest at time T proves the peer had all
      records existing at T). Also wired `syncEngineProvider` into
      Groups/Expenses pages (M5 left it unwatched) and added tombstone-aware
      `watchAllExpenses/SettlementsForGroup` streams.
- [x] `lib/features/expenses/expenses_page.dart`: app-bar cloud icon
      (`cloud_done` / `cloud_queue`) with tooltip ("Synced with all members" /
      "Waiting for @bob…"); small per-tile pending indicator
- [x] tests: provider unit test (`test/features/sync_status_test.dart`:
      `computeSyncStatus` cases + reactive provider pending→synced); widget
      tests (synced vs pending cloud + per-tile indicator)

### M8 — Documentation refresh

- [x] `CLAUDE.md`: rewrite Architecture + Data Model sections for roomless
      design; protocol v1 table including digest/resync payloads (also refreshed
      the project-structure tree and the room-era Matrix SDK API notes →
      to-device)
- [x] `docs/open-points.md`: mark stale room-era items (#2, #12), record
      Phase C as done, add known limitations:
  - trust model unchanged — any sender can forge state (TOFU, no membership
    check on inbound records); deferred to release hardening
  - ~1,000 records/group digest ceiling (`v` field enables sharding later)
  - wall-clock LWW (skewed clock wins edits; whole-record granularity)

---

## 5. Correctness risks (handled by design)

1. **Tombstone resurrection** — tombstones are permanent rows, included in
   digests and bootstraps; all merges are LWW. Edit-vs-delete race: latest
   timestamp wins deterministically (a later edit deliberately un-deletes).
2. **Reinstall / seq reset** — designed out: no sequences; an empty digest
   gets repaired.
3. **Digest loops** — `reply: true` never triggers a reply; repairs are
   idempotent LWW upserts; residual divergence caught next periodic cycle.
4. **Clock skew / LWW ties** — accepted, consistent with the existing Members
   pattern (`<=` tie-break by arrival); optional: clamp inbound `updated_at`
   to `now + 5 min`.
5. **Trust model** — unchanged from Phase B; only resync gets a membership
   check. Documented in M8, fixed in release hardening.

## 6. Verification

- `flutter test --reporter compact` green after every milestone;
  `./build.sh` green at the end of the phase.
- Integration tests in `test/integration/` drive multiple users/devices
  through `FakeLedgerNetwork` with loss injection — the core proof that
  divergence gets repaired.
- Manual smoke at end of phase: two real devices (web + Android), kill the
  network mid-add, confirm repair after reconnect; fresh login on a second
  device pulls all groups via self-resync.
