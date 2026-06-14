# MoneyLedger — Implementation Plan

**No active plan.** All planned phases through public-release hardening have
shipped. This file is the home for the *next* implementation plan; the
architecture and design decisions live in [`CLAUDE.md`](CLAUDE.md), and known
gaps in [`docs/open-points.md`](docs/open-points.md).

When starting new work, add a `## Phase …` section here with `[ ]`/`[x]`
checkbox milestones, and tick them off as they land. Convention: one milestone =
one commit (tests green first), then commit + push.

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

---

## Open ground (no active plan)

Candidate next work, roughly by value — see `docs/open-points.md` for detail:

- **Per-record cryptographic authorship** — the residual trust-model gap: a
  group member can still forge *another member's* record (membership gating only
  authenticates the relaying sender, not the authoring participant).
- **Device-verification enforcement** — an opt-in "replicate only to verified
  devices" mode (deliberately out of the M6 MVP).
- **Offline demo mode** (`--dart-define=OFFLINE_DEMO=true`) — drive the real UI
  off pre-seeded fakes for screenshots / manual multi-user inspection.
- **Real-device smoke tests** — SSO deep link, registration UIA, and the SAS
  verification round-trip can only be verified on a real device + homeserver.
- Smaller / nice-to-have: group rename + currency edit, avatars, the `router`
  provider's `refreshListenable` wiring test.
