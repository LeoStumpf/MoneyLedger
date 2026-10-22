# G57 — Concurrent custom-category edits (design note)

Status: **decided by Leo 2026-10-22 — C1** (answers below); built in the
wire bundle, see "As built (C1)" at the end. Leo 2026-10-17: "later, together with the link-group wire changes" —
this note is the input for that bundle (G57 / G73 / G74 / G76).

## Problem

Custom categories (G47) live in the **signed group meta**
(`com.moneyledger.group`, optional `categories` list). The meta is one LWW
record `(updated_at, G27 hash)`, so any two concurrent meta writes lose one:

- A adds "Dog", B adds "Fuel" at the same time → only the newer meta
  survives; the other category vanishes on every device (also on its
  author's). Expenses already tagged with the lost `c:` id show as *Other*
  (the id is kept, so a later definition brings the label back).
- A renames the group while B adds a category (or changes an icon / hides
  one) → one of the two changes is lost.
- Since G53 the meta also carries `link` / `locked_at`; a concurrent
  category edit and *Invite with a link* / *Make secure* race the same way
  (the link state losing is the worse case — today it is mitigated only by
  the rarity of the race).
- Duplicate names: the add dialog refuses a case-insensitive duplicate, but
  two peers can create "Dog" concurrently (different ids). `groupMetaProblem`
  must **not** refuse duplicate names (that would freeze the group); today
  both survive only if neither meta is lost — usually one is.

No user report so far; it needs two people editing categories / the group
within the same relay round trip (seconds on Matrix, longer on Nostr link
groups where devices sync less often — more likely there).

## Options

### A. Keep whole-meta LWW (status quo) — documented limit
Cost: nothing. `docs/open-points.md` already lists it.

### B. Receiver-side union, no wire change ("re-add what I lost")
When a device's stored meta is replaced by an inbound winner and the loser
held category ids the winner lacks, that device writes a new meta version
(`nextLwwClock`) = winner + the missing categories, signed / relayed.
- **Problem 1:** categories are never deleted by the UI, but a **G48 reset**
  (and G58 *Exactly this state*) intentionally rewrites the meta and can drop
  categories added after the restore point → peers would immediately undo
  that part of the reset. Would need "a reset meta is authoritative" — not
  expressible without a wire flag.
- **Problem 2:** a rename / icon / hide conflict on the *same* category still
  loses one side (no per-category clock).
- **Problem 3:** extra meta versions on every conflict, from every device
  that held the losing version (they converge — union is commutative — but
  each writes once). In link-only groups the merge would be unsigned and
  anyone with the link could already rewrite the meta anyway.
- Not recommended alone; it changes sync semantics without a wire signal.

### C. Per-category versions inside the meta (wire change) — recommended
Each category entry gets its own clock: `{id, name, icon, hidden?,
updated_at}`. Merge rule on every meta apply (and in `RecordGate`, DAO
`upsertGroupLww`, digests unchanged): the stored category set is the **union
by id** of all meta versions seen, each id resolved by its own
`(updated_at, entry hash)` LWW; name / currency / link / `locked_at` stay
whole-meta LWW. A reset writes the target entries with fresh clocks; a
category that must disappear after a reset becomes `hidden: true` (no delete
— old expenses keep their label), so union never resurrects anything
visible.
- Signed body + G27 hash change for metas with categories → a pre-change
  build refuses them (same pattern as G16 / G47 / G49: a schema-step forgets
  refused meta versions after the update). Unreleased app → acceptable, but
  should ship in one bundle with the other meta changes (G73 exchange rates
  are also meta fields — ideally per-field clocks for them too).
- The "stored meta" is then a merge of several signed versions: the
  attribution ("last edited by") and G48 history must store / show per
  version, and a **digest** must reflect the merged state — the meta hash
  would be over the merged content, and the repair path must re-send the
  versions whose entries we hold (or a merged meta re-signed by us). This is
  the part that needs the most design: either (C1) every device re-signs the
  merged meta as its own new version after a merge (simple, more versions,
  "last edited by" = the merging device), or (C2) categories move out of the
  meta into their own record kind (below).

### D. Categories as their own record kind (wire change, cleanest)
`com.moneyledger.category` records `{group, id, name, icon, hidden,
updated_at, sig}` — signed, LWW per record, digested / bootstrapped /
backed up / reset like expenses (new digest map `categories`, new
`record_history` kind, CSV unchanged). The meta keeps name / currency /
link only. Concurrent adds never conflict; a rename conflict is per category.
- Most code (new DAO table + schema step, digest section, bootstrap parts,
  `RecordGate.category`, link-path rules: who may write categories in a
  mixed group — today only Matrix members may change the meta, §G53).
- Migration: existing meta `categories` are converted locally on upgrade;
  peers on the old build ignore the new type (and keep seeing the meta list
  until everyone has updated — a transition period with both written).

### Duplicate names (any option)
Never refuse on the wire. Display-only fix possible without a wire change:
when two visible categories share a name (case-insensitive), the picker /
categories page could show them disambiguated (e.g. with the icon and
"(2)") and offer *merge* = hide one + retag its expenses (new expense
versions). That's a UX decision too (retagging writes many versions).

## Questions for Leo (answered 2026-10-22)

1. Fix it at all before the release, or keep A (documented limit)?
2. If yes: C1 (per-entry clocks in the meta, merged meta re-signed by the
   merging device) or D (own record kind)? D is cleaner and also fits G73
   (exchange rates as per-currency records?) — decide together with G73 /
   G74 / G76.
3. Should a concurrent **link / lock** meta race (G53) be protected the same
   way (per-field clocks for `link` / `locked_at`)?
4. Duplicate names after a concurrent add: leave as is, disambiguate in the
   UI, or offer a merge?

**Answers (Leo 2026-10-22):**
1. Fix it **before the release**.
2. **C1**: per-field clocks inside the signed group meta — name, currency,
   each custom category, exchange rates (G73), link / `locked_at` (G53) —
   and the merging device re-signs the merged meta.
3. Yes — `link` / `locked_at` get their own field clock (one field: the
   link state).
4. Not decided separately — duplicates stay possible after a concurrent add
   (never refused on the wire); both survive now (union by id).
