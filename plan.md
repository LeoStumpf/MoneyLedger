# MoneyLedger — Implementation Plan

Active phase: **Phase E — Custom splits** (see design + milestones at the
bottom). Phase D (CSV export/import, M1–M4) and virtual users (M1–M6) are done;
detail is in git history, `docs/open-points.md`, and `CLAUDE.md`.

Status legend: `[ ]` open · `[x]` done. Update this file as milestones land.
Workflow: commit + push after each milestone (tests green first).

---

## Roadmap

1. ~~Phase C — sync reliability + edit/delete~~ ✅
2. ~~Virtual users~~ ✅
3. ~~Phase D — CSV export/import~~ ✅
4. **Phase E — Custom splits — per-person amounts/shares** ← this plan
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

### M1 — Split math (pure Dart)

- [ ] `lib/features/expenses/split_calculator.dart` (pure Dart, no Flutter/DB):
      `splitEqually(total, ids)`, `splitByShares(total, {id: weight})`,
      `splitByPercent(total, {id: percent})` → `{id: cents}` summing **exactly**
      to total via a shared largest-remainder helper; `isEqualSplit(map)` for
      edit-mode inference; `remainingForExact(total, {id: cents})`.
- [ ] tests (`test/features/split_calculator_test.dart`): sum-equals-total
      invariant incl. the 100¢÷3 remainder case; shares proportionality;
      percent→cents; deterministic remainder assignment; single participant;
      empty/zero-weight guarded; `isEqualSplit` true/false.

### M2 — Split editor UI + wire into add/edit

- [ ] `lib/features/expenses/split_editor.dart`: a `SplitEditor` widget — mode
      selector (`SegmentedButton`) + per-participant rows (checkbox / amount /
      weight / percent per mode), live per-person preview and a running
      total/remainder; surfaces a validated `{id: cents}` map (or null = invalid)
      via callback.
- [ ] `add_expense_page.dart`: replace the hardcoded equal split with
      `SplitEditor`; disable Add/Save while the split is invalid; on edit, seed
      the included set + mode from the stored map (`isEqualSplit`).
- [ ] widget tests (`test/add_expense_page_test.dart` / `split_editor_test.dart`):
      each mode yields the expected map; sum-mismatch / empty selection disables
      submit; editing an unequal expense prefills Exact mode with stored cents.

### M3 — Round-trip + docs

- [ ] confirm an unequal split round-trips through CSV export/import (blank
      column = excluded) and through replication/edit; add a CSV test for an
      unequal split if not already covered.
- [ ] `CLAUDE.md`: "Custom splits" notes (four modes, cents-only persistence,
      largest-remainder rounding, edit-mode inference, excluded = absent) +
      `split_calculator.dart`/`split_editor.dart` in the structure tree.
- [ ] `docs/open-points.md`: custom-splits item done; note settlements still
      split-free and that mode/raw-inputs aren't persisted.

## Verification (Phase E)

`flutter test --reporter compact` green per milestone; `./build.sh` green at
phase end. Manual smoke: add an expense, switch modes, confirm the live preview
sums to the total; save an unequal split → balances reflect it; edit it →
reopens prefilled; export → re-import → unchanged.
