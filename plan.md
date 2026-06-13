# MoneyLedger — Implementation Plan

Active phase: **Virtual users** (Tricount-style participants). Phase C
(record-digest anti-entropy + expense edit/delete) is **done** and committed
(`3feecf7`); its milestone detail lives in git history and `docs/open-points.md`.

Status legend: `[ ]` open · `[x]` done. Update this file as milestones land.

---

## Roadmap (recommended order)

1. ~~Phase C — sync reliability + expense edit/delete~~ ✅ done
2. **Virtual users** (open-points #7) ← this plan
3. Phase D — CSV export/import (backup + migration path)
4. Custom splits — per-person amounts/shares
5. Public-release hardening — in-app registration, onboarding, device
   verification UX, membership check on inbound records, surfacing sync failures
6. Nice-to-haves: offline demo mode (#9), group rename/currency edit, avatars

---

## Virtual users — design

**Problem.** Identity is keyed on the raw MXID everywhere: `Members.userId`,
`Expenses.paidBy` + `split` keys, `Settlements.from/to`, sync routing, and the
UI all use `@user:server`. That blocks Tricount-style local participants (a
named person with no Matrix account) and makes removed members show as raw
MXIDs (#8).

**Decision (locked).** A participant is a **stable per-group entity** with its
own participant id (UUID), a `displayName`, and an **optional** `matrixId`
(the "claim"). Records reference the participant id, never the MXID — so
attaching or detaching a Matrix account never rewrites ledger history.

> Implementation note: the participant id is physically the existing
> `Members.userId` column (kept under that name to make the migration
> non-destructive and keep every milestone compiling). It is documented as "the
> stable participant id, not necessarily a Matrix ID"; the Matrix account, if
> any, lives in the new `matrixId` column. A cosmetic field rename can follow
> later if desired.

- **Routing.** Replication / digest / bootstrap target the `matrixId` of
  participants that are `active` **and claimed** (`matrixId != null`).
  Nameless-local participants are data-only — carried in the members map and
  bootstraps, but nobody sends them to-device messages.
- **Claim** = set `matrixId`. **Unclaim / "remove account"** = clear `matrixId`,
  keeping the participant and all history. `status` (`active`/`removed`) still
  hides a participant from the active roster; rows (and history) are never
  deleted.
- **Self.** `currentParticipant(groupId)` = the participant whose `matrixId`
  equals this device's MXID. The group creator seeds a self-participant.
- **Migration (v4, non-destructive).** Each existing `Members` row becomes a
  participant whose `participantId` **is the existing MXID string** — so every
  existing `paid_by` / `split` / `from` / `to` reference stays valid with zero
  record rewrites — with `matrixId` = that MXID and `displayName` = its
  localpart. New participants always get fresh UUIDs.
- **Protocol.** The member object in payloads/digests gains `name` + `matrix_id`
  and is keyed by `participantId`. Additive; stays `v: 1` (pre-release, all
  peers upgrade together).
- **PeerSyncStates** stays keyed by MXID — it tracks real peer *accounts*, not
  participants.

---

## Milestones

Each milestone is one commit: code + tests, `flutter test --reporter compact`
green, `dart run build_runner build` after any annotated-file change.

### M1 — Schema v4: participant identity on the Members table ✅

- [x] `lib/core/database/app_database.dart`: `Members` += `displayName` (text,
      default '') and `matrixId` (text, nullable); `userId` re-documented as the
      stable participant id. `schemaVersion => 4`; `onUpgrade` `if (from < 4)`:
      `addColumn` ×2, then backfill `matrixId = userId` and
      `displayName = localpart(userId)` for existing (already-claimed) rows.
- [x] `lib/models/member_model.dart`: `MemberModel` += `displayName`,
      `matrixId`; `isClaimed => matrixId != null`. `userId` doc'd as participant
      id.
- [x] `lib/core/database/daos/members_dao.dart`: + `memberByMatrixId`,
      `activeClaimedMatrixIds` (status active && matrixId != null);
      `_toModel`/upsert carry the new fields.
- [x] codegen
- [x] tests (`test/database/members_dao_test.dart`): backfill SQL (matrixId /
      localpart); `activeClaimedMatrixIds` excludes local + removed;
      `memberByMatrixId`; LWW still ignores stale. Full suite green (149).

### M2 — Wire protocol: participant identity over the relay ✅

- [x] `lib/core/sync/ledger_payloads.dart`: `memberPayload` carries
      `participant_id`, `name`, `matrix_id`, `status`, `updated_at`; digest
      `members` map values gain `name`/`matrix_id` (sync_engine).
- [x] `lib/features/expenses/ledger_syncer.dart`: `processMember` reads
      `participant_id` (fallback `user`) + `name` + `matrix_id`, LWW upsert.
- [x] `lib/core/sync/sync_engine.dart`: `buildDigestContent` members map +
      digest gossip-apply carry `name`/`matrix_id` (no longer wipe them);
      `compareDigest` unchanged (updatedAt is the LWW source of truth).
- [x] writers (`group_provider.dart`): create/add/remove set `displayName` +
      `matrixId` and relay the full participant payload (`memberCompanion`).
- [x] tests: `processMember` reads the new shape; claim via LWW; digest content
      shape; full suite green (151).

### M3 — Sync routing + self identity ✅

- [x] route `_replicate` (expenses_provider) + digest/bootstrap targets +
      add/remove relays to `activeClaimedMatrixIds`; engine resolves self/sender
      by `matrixId` (`_claimedBy`).
- [x] `currentParticipant(groupId)` provider (matrixId == my MXID);
      `currentUserId` stays the device MXID.
- [x] `GroupCreator.create`: seeds a self-participant claimed by the creator
      (id == MXID for from-scratch users; displayName = localpart).
- [x] `sync_status_provider`: active peers = active **claimed** participants'
      matrixIds, self excluded.
- [x] tests (`group_provider_test`): self-participant seeded + currentParticipant;
      local participants never become sync targets. Full suite green (153).

### M4 — UI: participants (names, add local/real, claim/unclaim, payer)

- [ ] participant name resolver (participantId → displayName, per group).
- [ ] `group_provider`: `ParticipantAdder.add(name, {matrixId})`,
      `claim(id, matrixId)`, `unclaim(id)`, `rename(id, name)`, `remove(id)`.
- [ ] `group_members_page`: displayName title, MXID-or-“Local” badge, “You”
      chip; add dialog (name + optional MXID); per-row edit (rename / attach /
      detach MXID); remove keeps history.
- [ ] `add_expense_page`: payer dropdown + splits over participants, by name
      (payer is hard-coded to self today).
- [ ] `expenses_page` tiles + `balance_page`: resolve participantId → name.
- [ ] tests: widget (add local participant, claim/unclaim, payer pick) +
      resolver unit.

### M5 — Removed/unclaimed display (#8) + docs

- [ ] removed / unclaimed participants still render by name in balances + history.
- [ ] `CLAUDE.md` + `docs/open-points.md`: mark #7 done and #8 resolved; update
      the data-model + protocol sections for participant identity.

### M6 — (later) Auto self-claim on join

- [ ] new device whose MXID matches no participant in a freshly bootstrapped
      group → prompt to pick an unclaimed participant → set matrixId = self,
      replicate the claim. (Deferred — manual claim covers the gap until then.)

---

## Correctness notes

- Migration is non-destructive (participantId = MXID keeps all existing record
  references valid); old room-era groups already stopped syncing at v2.
- Claim/unclaim is a normal LWW field edit on the participant row — converges
  like every other record; concurrent claim of the same slot resolves by clock.
- A participant with no `matrixId` is pure ledger data; it is never a transport
  target, so routing must filter on `matrixId != null` everywhere.
- Verification: `flutter test --reporter compact` green per milestone;
  `./build.sh` green at phase end; manual two-device smoke (add a local
  participant on web, claim it from Android).
