# MoneyLedger — Implementation Plan

Active phase: **Phase D — CSV export/import**. The virtual-users phase (M1–M6)
is **done** and committed (`afbd1dc` → `3492b1f`); detail is in git history and
`docs/open-points.md`.

Status legend: `[ ]` open · `[x]` done. Update this file as milestones land.
Workflow: commit + push after each milestone (tests green first).

---

## Roadmap

1. ~~Phase C — sync reliability + edit/delete~~ ✅
2. ~~Virtual users~~ ✅
3. **Phase D — CSV export/import** ← this plan
4. Custom splits — per-person amounts/shares
5. Public-release hardening — registration, onboarding, device-verification UX,
   membership check on inbound records, surfacing sync failures
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

### M4 — Docs

- [ ] `CLAUDE.md`: backup feature + CSV format/columns + limitations.
- [ ] `docs/open-points.md`: Phase D done; note settlements/identity-by-name
      limitations.

---

## Verification

`flutter test --reporter compact` green per milestone; `./build.sh` green at
phase end. Manual smoke: export a group on web, re-import the file → no
duplicates; edit a share in a spreadsheet, re-import → LWW applies.
