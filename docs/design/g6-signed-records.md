# G6 — Signed records (per-version cryptographic authorship)

Status: **implemented** (M1–M5; M6 device check — see the report / smoke
test). Scope: plan.md G6. Policy (product owner): any active member may
create, edit or delete any expense or settlement, but **every version is
signed by the device that wrote it**. Forging a version "as" another member
must be impossible. The UI shows "added by X" / "edited by X". Protocol `v: 2`.

**Review outcome (simplification).** The app is unreleased — the only
installs are two test devices that both get the new build. So there is **no
mixed-version period**: strict mode, the per-peer protocol column and every
v1-compatibility path below are **dropped**. v2 is mandatory: an inbound
version **without** a signature is refused like a forged one (recorded in
`rejected_versions` / the digest `rejected` map, so repair loops terminate).
Rows already in the local DB before the migration are **grandfathered** as
legacy/unsigned (subtle UI note) and keep working locally; an unsigned relay of
a legacy row we already hold at the same clock is a no-op (an inbound version
is only looked at when it is newer than ours). The "signed beats unsigned at
equal clock" rule is no longer needed and was dropped. Cross-signing stays a
documented residual risk / future item. "Vouched" renders like "verified" in
the footer; the details dialog tells "verified on receipt" from "vouched by
<sender>". Sections 9 and 12 are superseded accordingly (kept short below).

## 0. Decisions at a glance

| # | Question | Decision |
|---|----------|----------|
| 1 | What is signed | Every **version** of `expense`, `settlement`, `member` and `group meta`, tombstones included. The signed body is built from the **parsed model** in Matrix canonical JSON (`canonical_json`), with a type tag, the `group`, all record fields and the signer. `v`, `sig` and other transport fields are excluded. Expenses and settlements also carry an immutable **`origin`** (a creation statement signed by the creator), which backs "added by". Digests and resync requests are not signed. |
| 2 | Which key | The editing device's **Matrix Ed25519 fingerprint key** (the vodozemac olm account), via `client.encryption!.olmManager.signString`. No app-level key. On the wire: `sig: {user, device, key, sig}`. In Drift: JSON columns (schema **v6**). |
| 3 | Verify after a device logs out | **Pinned device-key history** (`KnownDeviceKeys`). Each device records every member device key it ever sees **first-hand** from the homeserver (`updateUserDeviceKeys`, self-signed `DeviceKeys`). It pins proactively on every send, so keys are captured before devices log out. A record whose signer key is pinned or listed now is **verified**. A record whose key is unknown is **accepted but flagged unverified**. A record whose key **contradicts** a pinned key is **rejected**. TOFU snapshots (a new group's bootstrap, our own devices, backup restore) may carry **key attestations**, shown as "vouched". Cross-signing chains are a later upgrade (§5.4). |
| 4 | Reject vs. flag | Rejected (recorded): unsigned, bad signature, bad or changed `origin`, key conflict, wrong signer (non-member self-claim). Transient drop: clock more than 5 min in the future. Flagged: unverified key. Local pre-G6 rows: legacy. Rejected versions go into `RejectedVersions` and are advertised in the digest `rejected` map, so peers stop repairing them (no loop). |
| 5 | LWW | Verification runs **before** the upsert and only for versions **newer** than the stored one (equal clock = no-op). A rejected version never touches the row. Verification status is receiver-relative, so it **never** influences LWW order. |
| 6 | Ports and tests | As built: `RecordCrypto` (sign + verify) and `DeviceKeyDirectory` (current server device keys) are ports exposed on `LedgerTransport` (`crypto`, `deviceKeys`), so every transport fake / the background session / the demo get them for free. Real adapters use matrix and vodozemac. Fakes use HMAC-SHA256 per fake device, so they are deterministic and unforgeable without the device secret. Canonicalisation, hashing and the verdict logic are pure Dart. New direct deps: `canonical_json` (Apache-2.0) and `crypto` (BSD-3). Both are already transitive in `pubspec.lock`, so nothing new is downloaded. |
| 7 | UI | Edit-expense page footer: "Added by X · Last edited by Y". Settlement dialog: "Recorded by X". Small "unverified" or "unsigned" hints. A notice when a newer version was rejected. EN and DE. |
| 8 | Rollout | v2 mandatory (unreleased app, both test devices updated). Unsigned inbound = refused. Pre-G6 local rows grandfathered as legacy. No strict mode / protocol tracking. |
| 9 | Milestones | M1 codec, ports and fakes · M2 Drift v6 and real adapters · M3 syncer, digest and bootstrap integration · M4 UI · M5 docs (strict mode dropped) · M6 on-device check (emulator ↔ phone). |

## 1. Threat model

- **Attacker:** an active member M, or any device holding M's account. M can send any to-device payload, relay any record, and run a modified client.
- **Goal to prevent:** a version accepted by honest v2 devices that **claims an editor (or creator) other than M** and is shown as verified. M may still edit anything under M's own name, because the policy allows it. Signing gives attribution, not permission.
- **Out of scope** (inherited from the Matrix trust model, see G11):
  - X's homeserver injecting a fake device for X.
  - A compromised device of X.
  - Old v1 clients, which verify nothing.
- **Not signed:** digests and resync requests. They are hints that only trigger re-sending signed records. Digest member gossip moves to signed member entries (§6.3).

## 2. What is signed

### 2.1 Signed bodies

`lib/core/sync/record_signing.dart` (pure Dart) builds every body. The body is built **from the model after parsing and defaulting**, never from the raw inbound map. Two reasons:

- The receiver's view is exactly what a relayer will rebuild from Drift later (`expensePayload(model)`).
- Defaults such as `description ?? ''` can't make a relayed record fail to verify.

Unknown future fields are therefore not covered. A v3 would add them to the body.

```
expense:    {t:"com.moneyledger.expense", id, group, description, amount, currency,
             paid_by, split:{pid:cents}, created_at, updated_at, deleted,
             origin:<origin object incl. its sig>, signer:{user, device, key}}
settlement: {t:"com.moneyledger.settlement", id, group, amount, currency, from, to,
             created_at, updated_at, deleted, origin, signer}
member:     {t:"com.moneyledger.member", group, participant_id, name, matrix_id,
             status, updated_at, signer}
group meta: {t:"com.moneyledger.group", group, name, currency, updated_at, signer}
origin:     {t:"com.moneyledger.expense#origin" | "...settlement#origin",
             id, group, created_at, signer}
```

- **`t` (type tag):** domain separation. An expense signature can't be replayed as a settlement.
- **`group` and `id`:** bind the signature to one record in one group. It can't be replayed into another group.
- **`signer` (including `key`):** inside the body, so a relayer can't swap the claimed signer or key.
- **`origin` (inside an edited version's body):** the editor vouches for which creation it continues.
- **Tombstones:** an ordinary version with `deleted: true`, signed by the deleter. "Deleted by Y" is therefore attributable.

### 2.2 Encoding and the message that is signed

```
canon   = canonicalJson.encode(body)            // package:canonical_json (Matrix canonical JSON:
                                                 //   sorted keys, no whitespace, ints only, NFC strings)
message = "mlsig1:" + base64Url(sha256(canon)) // ASCII only, 50 chars, sha256 from package:crypto
```

Why a hash and not the canonical bytes:

- The SDK signs `String.fromCharCodes(canonicalBytes)` (`olm_manager.dart:signJson`), which double-encodes non-ASCII through vodozemac's `String` API.
- An ASCII-only message makes real vodozemac signing, the pure-Dart fake and any future implementation agree byte for byte, whatever the description text is.

All amounts are already integer cents, so there are no floats, which `canonical_json` rejects.

## 3. Keys and wire format (protocol v2)

**Signing.** The real adapter does `client.encryption!.olmManager.signString(message)`. This is the device's Ed25519 identity, `client.fingerprintKey` / `olmManager.fingerprintKey` (`matrix-7.2.2/lib/encryption/olm_manager.dart:35,104`).

- It is the key that the device's own uploaded `device_keys` self-signature already uses. So every Matrix client can bind (user, device) to this key.
- It works on web too, through the vodozemac wasm in `web/pkg/` (same `vodozemac` Dart API).
- An app-level key (vodozemac `PkSigning`) was rejected. It would need its own distribution and attestation by the device key anyway.

**Verification.** `vod.Ed25519PublicKey.fromBase64(key).verify(message:, signature: vod.Ed25519Signature.fromBase64(sig))` throws on mismatch (`vodozemac-0.5.0/lib/src/api.dart:78-102`). This is the same call `checkJsonSignature` uses. The adapter needs `vodozemac` as a direct dependency. It is already transitive and AGPL-3.0 (listed in `THIRD_PARTY_NOTICES.md`).

**Wire.** Additive. Every v1 key stays as it is, and `v` becomes 2:

```json
{ "v": 2, "id": "…", "group": "…", "description": "Dinner", "amount": 4200, "currency": "EUR",
  "paid_by": "p1", "split": {"p1": 2100, "p2": 2100},
  "created_at": 1760000000000, "updated_at": 1760000050000, "deleted": false,
  "origin": {"user": "@alice:x.org", "device": "AAAA", "key": "<b64 ed25519>",
             "created_at": 1760000000000, "sig": "<b64>"},
  "sig":    {"user": "@bob:y.org",   "device": "BBBB", "key": "<b64 ed25519>", "sig": "<b64>"} }
```

- **Member payloads** gain `sig`.
- **Group meta payloads** gain `sig`.
- **Bootstrap** gains:
  - `meta`: the full signed group-meta payload. The top-level `name`/`currency`/`updated_at` stay for v1 readers.
  - `device_keys`: attestations, `{user: {device: key}}`, limited to the signers referenced in the snapshot.
- **Digest:**
  - `members` entries gain `sig`. Each entry already holds every member field, so it can be verified.
  - New optional `rejected: {expenses:{id:T}, settlements:{id:T}, members:{pid:T}, meta:T}`.
- **Size:** roughly 300 bytes more per expense or settlement and about 150 bytes per member. This doubles a typical record and makes the single-message bootstrap ceiling tighter. Flag it for **G14**, which may need to chunk bootstraps.

## 4. Storage — Drift schema v6

`AppDatabase.schemaVersion` goes 5 → 6. `onUpgrade` gets `if (from < 6)`:

| Table | Change |
|-------|--------|
| `expenses`, `settlements` | `sig TEXT NULL` (wire `sig` object as JSON, relayed verbatim), `origin TEXT NULL`, `pending_sign BOOL DEFAULT 0` |
| `members`, `groups` | `sig TEXT NULL`, `pending_sign BOOL DEFAULT 0` |
| **new** `known_device_keys` | PK `(user_id, device_id, ed25519_key)`; `source` (`server` \| `attested`), `attested_by TEXT NULL`, `first_seen_at`, `last_seen_at` |
| **new** `rejected_versions` | PK `(group_id, kind, record_id)`; `updated_at` (highest rejected clock), `reason`, `relayed_by`, `claimed_signer`, `rejected_at` (v9: + `version_hash`; v10: PK `(group_id, kind, record_id, updated_at, version_hash)`, ≤ 4 per record — see the second G18 review below) |

- `purgeGroup` also clears `rejected_versions`.
- `known_device_keys` is per account and survives a group purge. It is device-local trust and is never synced.
- Existing rows keep `sig = NULL`, so they are legacy and unsigned. There is no backfill: we can't sign other people's history.
- Models (`ExpenseModel`, `SettlementModel`, `MemberModel`, `GroupModel`) gain `RecordSignature? sig`, `RecordOrigin? origin` and `bool pendingSign`. The payload builders emit the stored `sig`/`origin` verbatim.
- `_copyAll` (legacy adoption) also copies the new tables.

**Migration test.** Create a raw v5 SQLite file with the current `CREATE TABLE`s and `PRAGMA user_version = 5`, insert rows, then open it with `AppDatabase.forTesting(NativeDatabase(file))`. Assert:

- the new columns and tables exist;
- rows are intact with `sig IS NULL`;
- a v6 round-trip works.

Optionally start `drift_dev schema dump` snapshots (`drift_schemas/`) from v6 on.

## 5. Verification and key binding

### 5.1 Two questions per signature

1. **Is the signature valid for the embedded key?** This is objective. Every honest device gets the same answer.
2. **Is that key really (user, device)'s?** This depends on what the receiver knows.

Question 1 failing means **reject**. Question 2 produces a key status:

| Status | Meaning |
|--------|---------|
| `verified` | `(user, device, key)` is in `known_device_keys` with `source = server`, or is in the current server list after a refresh. Our own device counts as `server`. |
| `vouched` | Only an `attested` pin matches. |
| `unverified` | `(user, device)` is unknown to us and to the server (logged out before we ever saw it, or fabricated). |
| `conflict` | `(user, device)` has a pinned `server` key, and neither that key nor the device's current server key equals the claimed key. This means **reject**. |

**Key status is derived at display time** by joining the stored `sig` with `known_device_keys`, instead of being stored per record. So pinning a key later upgrades old records automatically. The one exception: a later pin that contradicts an accepted record makes it show as `conflict` ("signature doesn't match X's device"). The record is not reverted, because we don't keep its predecessor.

### 5.2 Getting keys first-hand

`DeviceKeyDirectory.currentDevices(Set<String> users)`:

- **Real adapter:** `await client.updateUserDeviceKeys(additionalUsers: users)`, then reads `client.userDeviceKeys[u]!.deviceKeys` and keeps only `isValid && !blocked` (self-signed) entries with their `ed25519Key`.
- **Proactive pinning:** `MatrixLedgerTransport.sendToUsers` already refreshes the targets' device lists before every send. After each send, the sync layer pins all current devices of the targets. Every online peer sends digests every 10 min, so in practice every member device is pinned by every active peer **while it exists**. That is before a sign-out (`client.logout()` deletes the device server-side) can remove it.
- **On-demand pinning:** when verifying, if the claimed `(user, device)` isn't pinned, refresh those users once. Batch per inbound message or bootstrap, at most once per user per 60 s. Pin what comes back.

### 5.3 Relays long after a logout (options weighed)

| Option | Security | Robustness | Verdict |
|--------|----------|------------|---------|
| (a) Server device list only | Matrix-level | Breaks on every sign-out. Old history becomes unverifiable, and every sign-out creates a new device. | Not enough on its own |
| (b) Embed key + cross-signing chain (SSK signs the device keys; the master key persists after logout) | Best | Needs cross-signing set up. MoneyLedger never bootstraps it (no `bootstrapCrossSigning` in `lib/`), so in-app accounts have none. Adds ~600 bytes per record or a key bundle. | Later upgrade (§5.4) |
| (c) "Verified at receipt" flag passed along by relayers | None: a relayer can lie | Good | Rejected |
| **(d) Pinned key history + TOFU attestations in snapshots** | Matrix-level for keys we observed. TOFU only where the model already trusts TOFU. | Good | **Chosen** |

**Attestations.** A bootstrap or backup includes `device_keys` with the sender's `server`-source pins for the snapshot's signers. Pins learned by attestation are never re-attested, so there is no laundering. The receiver stores them as `source = attested`, `attested_by = sender`, but **only** in three cases:

- the snapshot creates an **unknown group** (the existing TOFU bootstrap: the inviter defines the group for the new member anyway);
- the sender is **our own MXID** (our own devices, as in new-device recovery);
- a **backup restore** the user started.

Attestations relayed by another member for a known group are ignored. A `server` pin always overrides an `attested` one for the same `(user, device)`, and a mismatch then flags the dependent records as `conflict`.

### 5.4 Residual risk (explicit)

1. **Fabricated device.** M signs a version as X using an invented device ID D′ and M's own key. Receivers who have never seen D′, and can't find it on X's server list, can't tell it apart from a device X logged out of before they pinned it. It is **accepted as "unverified"** and shown as such.
   - **Mitigation:** X's own devices flag any record claiming X with a device that is neither pinned nor currently X's. They show "not from one of your devices", and X can react, for example by re-editing.
   - G11 doesn't close it: such a version is still accepted (inbound isn't refused under verified-only); the details dialog shows the device as not verified by you.
   - **Closing it fully** needs cross-signing (b). Add it later: if X has a master key and the record's device is SSK-signed (`DeviceKeys.crossVerified` / `hasValidSignatureChain`), treat it as `verified`. If X has cross-signing and an unknown device is not SSK-signed, a strict client could reject it.
2. **Malicious inviter.** For a new member, the inviter can attest fake keys, so those records show as "vouched". This is no worse than today, where the inviter's bootstrap is TOFU-accepted wholesale.
3. **Homeserver.** It can add devices for its own users. *G11 (opt-in):* "Only sync with verified devices" sends nothing to a device we never emoji-verified, and the details dialog says whether the signing device was verified by us; inbound records are still accepted (not refused).
4. **Mixed mode.** v1 peers verify nothing and strip signatures when they relay (§9).
5. **Disagreement between honest devices.** An honest device that accepted M's fabricated-device version as "unverified", while another device that knew a conflicting pin rejected it, can end up holding different versions. The `rejected` digest map stops the repair loop and both sides surface it in the UI. Divergence beats accepting a provable forgery. It is **not auto-resolved** — it lasts until the record is edited again (a newer verifiable version wins everywhere).
6. **Legacy (pre-G6) rows can't be relayed** (G35, decided: no migration). Unsigned rows stay readable locally but are refused by every peer, so an old group can't onboard a new member or a new device (unsigned meta → whole snapshot refused; unsigned records → the group arrives incomplete). The app is unreleased and only the test groups have such rows, so there is no "re-sign as migrated" step; the test groups are recreated before the release. The receiver logs `[g6] refused unsigned …` and the groups page shows a dismissible hint naming the group and the sender (`RecordGate.onRefused` → `SyncHealth.reportLegacyRefused`).

**G18 security review (pre-release) — changes to the above.**

- **Attestations are group-scoped.** `known_device_keys` gained
  `attested_group` (schema v9, part of the PK): a snapshot's `device_keys`
  vouch only for records of **that** snapshot's group. Before, a stranger's
  throwaway TOFU bootstrap could pin an invented device of X account-wide and
  make a forged version in another group show as "vouched". Also, a peer's
  attestation never vouches for a device of an account whose first-hand
  device list we hold without that device (`attestationVouches`); an account
  vouching for its **own** device (our own devices' bootstraps, our own
  backup) still counts. Residual risk 2 (malicious inviter) is therefore
  limited to the inviter's own group and to accounts we have no first-hand
  device list for. The pre-v9 (account-wide) attestations were dropped by the
  migration.
- **Snapshots only touch their own group.** Every nested entry of a
  bootstrap / restored group must name the snapshot's group
  (`snapshotEntries`); the sender gate only ever checked the outer group.
- **Signer rule (defence in depth).** The signer of an expense / payment /
  meta version must claim a participant of the record's group (removed: only
  versions not newer than the removal) or be the relaying account —
  otherwise the version is dropped (`signer_not_member`, transient). Known
  limitation: after **unclaiming** (detaching) an account, versions it signed
  are only accepted from that account itself — a device that never held them
  (a new member) doesn't get them via others' relays (documented in
  `docs/open-points.md`).
- **Refusals are exact.** A refusal blocks exactly the refused version
  (clock + G27 hash, `rejected_versions.version_hash`); the digest `rejected`
  map carries `"<ms>:<hash8>"`. A far-future clock is checked before
  anything else and never recorded. §6.1/§6.3 "refused at or above the clock"
  is superseded.
- **Content validation.** Invalid expenses / payments (split / amount rules,
  `record_validation.dart`) are refused as `invalid_record` (recorded).
- **Membership.** A non-member can no longer self-claim, join as new or
  rejoin (§6.1 `member_self_claim` is moot): an active member assigns the
  slot (invite / claim).

**Second G18 review (2026-10-16).**

- **Refusal sets.** `rejected_versions` keeps up to 4 refused versions per
  record (the version is part of the primary key, schema v10). The digest's
  `rejected` map still carries the highest one per record (compatible); the
  others go into an optional `rejected_more` (`{expenses: {id: ["T:hash8",
  …]}, settlements, members, meta: [...]}`) that older peers ignore.
- **`matrix_id` validation.** A member version whose `matrix_id` is set but
  isn't a syntactically valid MXID (`@localpart:server`) — including local
  mode's `local:self` — is refused as `invalid_record` (live, gossip,
  snapshot, restore). Only a restore of local mode's own backup (a truly
  local group) may store `local:self` claims. Send targets are filtered to
  valid MXIDs (`activeClaimedMatrixIds`, digest targets, the transport).
- **Record ids are bound to their group.** An expense / payment version whose
  id is stored for another group is refused as `invalid_record` (it would
  move / overwrite that record); the CSV import aborts on such a row and the
  DAO's LWW upsert never moves a row between groups.
- **Restored unsigned rows.** A backup file is unauthenticated: an unsigned
  restored version carries **no** `origin` (attribution must never vouch for
  unsigned content) and is never marked `pending_sign`. This device
  signs restored rows only for a **truly local** group of a local-mode
  backup (no Matrix-claimed participant in the file or the DB, nothing
  signed in the file), and adopting a local ledger signs only the rows local
  mode wrote (`pending_sign`). A Matrix backup restored in local mode hands
  over only a participant claim the backup account signed.

**Status (G35 review).** Risks 1–3 and 5 are accepted for v1 and listed in `docs/open-points.md`. 1 and 2 **need cross-signing** (future item: set up cross-signing for in-app accounts, then treat SSK-signed devices as verified and, optionally, refuse unknown devices of accounts that have it); G11's opt-in verified-only sync narrows 3 for outbound data only.

## 6. Reception policy

### 6.1 Order in `LedgerSyncer._onMessage`

1. Left-group check (G9, unchanged).
2. **Membership gate on the relaying sender** (`isSenderAuthorized`, unchanged). It still applies to every relayed record.
3. For each record (each one individually for a bootstrap, so one bad record doesn't sink the snapshot):
   - Parse it into a model.
   - Load the stored row. If `incoming.updated_at < stored.updated_at`, it's a no-op: **skip verification** (cheap path for repeated relays).
   - Otherwise call `RecordVerifier.check(...)`, which returns a `Verdict`.
   - Act on the verdict: **accept** → LWW upsert with `sig`/`origin`; **flag** → upsert, since the flag is derived later; **reject** → log, and record it in `rejected_versions` only for the reject classes marked "recorded" below.

**Rejected (recorded):**

- `bad_signature`: `sig` doesn't verify for its embedded key, or it is malformed.
- `bad_origin`: `origin` is present and doesn't verify, or its `id`/`group`/`created_at` don't match the record.
- `origin_changed`: we hold a signed origin for this ID and the incoming origin differs. Origin is immutable. A creation version (no stored row) must have `origin.signer == sig.signer`.
- `key_conflict`: §5.1.
- `member_self_claim`: a **non-member's** self-claim or join `member` payload must be signed by the claimant (`sig.user == senderId == matrix_id`). This keeps the existing gate rule meaningful once records can be relayed.

- `unsigned` (as built, after review): no `sig` at all.

**Dropped, not recorded (transient):**

- `future_clock`: a signed `updated_at` more than 5 min in the future. A signed version can't be stored clamped without breaking its signature. It is re-offered by repair and accepted once the clock is in range, the same convergence as today's clamp.

**Accepted, flagged:**

- A valid signature with a key status of `unverified` or `vouched`.
- (Backup restore only: unsigned rows of the user's own file are restored as legacy.)

**Backup restore (G35).** A restore verifies like any snapshot, but the homeserver lookups come **first** (`RecordVerifier.prefetch` for every signer in the file, one call); each group is then applied inside **one DB transaction** with no network round-trips, so a group is restored completely or not at all (a failure rolls it back, including the cleared left-group tombstone; other groups of the file are independent).

**Signer policy.**

- The signer doesn't have to be the relaying sender, because relays are the whole point of anti-entropy.
- The signer doesn't have to be an active member now: removed members' history stays valid.
- A version is **accepted on its own signature**. The gate already makes sure that only members inject records into a group.

`isOwnLeaveFromOtherDevice` additionally requires `sig.user == myMxid` with a `verified` key.

### 6.2 LWW interaction

As built: `RecordGate` only considers inbound versions with `updated_at >` the
stored clock (and above any version we already refused); everything else is a
no-op. The DAO upserts are unchanged.

- Two *different* signed versions with the same clock remain G27's tie-break problem. Until then, the first one stored wins.
- A forged high clock can't win, because the version is rejected before the upsert.
- Verification status never enters LWW. It is receiver-relative and would break convergence.
- **G57 (C1, schema v19):** the group **meta** is the exception — it merges field by field (per-field `clocks` in the signed body); an inbound meta that isn't newer is still verified when it holds a newer field, and a merge that equals neither version is written and **signed by the merging device** as its own new version (`meta_merge.dart`, `docs/design/g57-category-merge.md` "As built"). Its "last edited by" names that device.
- **G74:** a member version may carry the participant's `payment` details only from the participant itself (signed by the claiming account); another member's version must carry them over (`payment_not_own`, transient otherwise) — it may also hold none or a value the participant itself published earlier under the same claim (an editor that missed a change; the participant's device re-publishes).

### 6.3 Digests without repair loops

- **Rule 1 (repair).** Unchanged for v1 senders. For a v2 sender, don't re-send record `id` when `remote.rejected[id] >= stored.updated_at`: the peer has seen that version and refused it.
- **Rule 4 (identical).** An ID counts as matching when `remote == stored`, **or** when `local rejected[id] == remote > stored` (we refused exactly what they hold), **or** when `remote.rejected[id] == stored` (they refused ours). "Agree to disagree" shows as synced. The disagreement is visible on the record instead (§8).
- **Our digest** always advertises **stored** clocks; `rejected` is an extra map.
- **Rule 2 (member gossip).** Entries are verified like member payloads (unsigned → refused).
- **Rule 8 (new, regression-tested):** a digest from a sender that is **not a participant at all** is ignored (no gossip, repair or reply). Before, `_onDigest` only stopped removed senders (rule 6) and `senderRec == null` fell through to rules 1–3.

## 7. Interactions

- **Local writes** (`ExpenseAdder`, `GroupCreator`, `MemberAdder`, `MemberRemover`, `GroupExiter`, `GroupEditor`):
  - `_WriteContext` / `_GroupWriteContext` capture `RecordSigner` before the first await (G19).
  - The model is signed (`origin` on create) **before** the local upsert.
  - If the signer isn't ready (encryption not up), the record is stored with `pending_sign = 1` and the write still succeeds (local-first).
  - `SyncEngine` signs pending rows of its own account before `broadcastDigests`, and `replicate` signs them before sending. A `pending_sign` row is never sent unsigned: rule 1 skips it until it is signed.
  - Editing keeps the stored `origin`. Editing a legacy unsigned record leaves `origin = null`, so "added by" stays unknown.
- **`clampInboundClock`:** unsigned records only. Signed records use `future_clock` (§6.1).
- **Backup and restore (G5):**
  - The file is bootstrap-shaped, so records carry `sig`/`origin`, and `device_keys` attestations are added per group.
  - `BackupService.restore` goes through the same verifying `processBootstrap(…, verifier)`. Attestations are accepted because the user started the restore.
  - **Backup `version` stays 1.** The additions are optional keys, and the parser in `ledger_backup.dart` ignores unknown keys, so older apps can still restore (unsigned).
- **CSV import:** the CSV has no signatures. A row that **wins** LWW against local state becomes a new version signed by the importing device (`origin` too, for rows that create a record). Rows that don't win are not re-signed: no equal-clock re-signing of someone else's version.
- **Background round (G31):**
  - `BackgroundSession` gains `RecordSigner signer` and `DeviceKeyDirectory deviceKeys`, built over the session's client. It uses the same olm account and therefore the same key.
  - The round's `ProviderContainer` overrides `recordSignerProvider` / `deviceKeyDirectoryProvider` in the same way it overrides the account and DB providers.
  - Key refreshes count toward the 60 s budget: batched, and at most one `updateUserDeviceKeys` per round.
- **Web:**
  - Signing and verifying both run in vodozemac wasm, the same API as native.
  - `canonical_json` and `crypto` are pure Dart.
  - No platform split is needed.
  - Cost: one Ed25519 verify per *winning* inbound version, plus `origin`. A 1,000-record bootstrap is at most about 2,000 verifies. That's fine natively; measure it on web in M6.
- **Offline demo (`OFFLINE_DEMO`):** uses the fake signer and directory.

## 8. UI

The editor name comes from `sig.user` → `claimedBy(members, mxid)?.displayName`, then the MXID, with "you" for our own account. Key status comes from a `deviceKeyStatusProvider` that streams `known_device_keys` into memory, since the table is small.

- **Edit-expense page** (`add_expense_page.dart`, edit mode only): a muted `bodySmall` footer:
  - "Added by Alex · 12 Oct" (from `origin`);
  - "Last edited by Sam · 14 Oct" (from `sig`, shown when the signers differ or the version is newer than `created_at`).
  - A trailing ⓘ opens the details: device ID and verified / vouched-by-Y / unverified.
- **Settlement tap dialog** (`_confirmDeleteSettlement`): "Recorded by X" (origin), plus "edited by" if different.
- **Expense list:** no new text, to keep it calm. Only `conflict` or *own-identity impersonation* adds a small `Icons.gpp_maybe_outlined` (error colour) to the tile.
- **Unverified / unsigned:** subtle text in the footer only. No list noise.
- **Rejected newer version** (`rejected_versions` has the ID): a notice on the edit page: "A newer version relayed by M was refused: it claims to be from X but isn't signed by X's device."

New ARB keys, with EN and DE in both files, ICU placeholders, informal "du":

| key | EN | DE |
|-----|----|----|
| `recordAddedBy` | Added by {name} · {date} | Hinzugefügt von {name} · {date} |
| `recordEditedBy` | Last edited by {name} · {date} | Zuletzt bearbeitet von {name} · {date} |
| `recordRecordedBy` | Recorded by {name} | Erfasst von {name} |
| `recordYou` | you | dir |
| `recordSigUnverified` | Signature not verifiable — the signing device may have signed out | Signatur nicht überprüfbar – das signierende Gerät wurde evtl. abgemeldet |
| `recordSigVouched` | Device confirmed by {name} | Gerät bestätigt von {name} |
| `recordUnsigned` | Saved by an older app version (unsigned) | Von einer älteren App-Version gespeichert (unsigniert) |
| `recordSigConflict` | Signature doesn't match {name}'s device | Signatur passt nicht zum Gerät von {name} |
| `recordNotYourDevice` | Claims to be from you, but not from one of your devices | Gibt vor, von dir zu sein – aber nicht von einem deiner Geräte |
| `recordVersionRejected` | A newer version relayed by {relay} was refused: it claims to be from {name} but isn't signed by their device. | Eine neuere Version (weitergeleitet von {relay}) wurde abgelehnt: Sie gibt vor, von {name} zu sein, ist aber nicht von dessen Gerät signiert. |
| `recordSignedByDevice` | Signed by device {device} | Signiert von Gerät {device} |

## 9. Rollout (superseded by the review)

The original plan here (strict mode per group, v1 peers stripping signatures,
equal-clock upgrades) is dropped: the app is unreleased and both test devices
run v2. v2 is mandatory; pre-G6 local rows are grandfathered as legacy. Note
for the record: v1 code never read `content['v']`, so a v2 payload would have
been applied by a v1 peer without checks.

## 10. Ports, fakes and tests

```dart
// lib/core/sync/record_signing.dart (pure)
class SignerId { final String user, device, key; }
abstract interface class RecordSigner { SignerId? get identity; Future<String> sign(String message); }
abstract interface class DeviceKeyDirectory {
  Future<Map<String, Map<String, String>>> currentDevices(Set<String> users); // user → device → ed25519
}
typedef Ed25519Verify = bool Function(String key, String message, String sig);
Map<String, Object?> signedBody(String type, Object model, SignerId s, {RecordOrigin? origin});
String signingMessage(Map<String, Object?> body);          // "mlsig1:" + b64url(sha256(canon))
Future<Verdict> checkVersion(...);                          // pure policy, §6.1
```

- **Real adapters:**
  - `lib/core/matrix/matrix_record_signer.dart`: `olmManager.signString`, `client.deviceID`, `client.fingerprintKey`.
  - `matrix_device_key_directory.dart`.
  - `vodozemacVerify`.
  - They are imported only from providers, the same way `MatrixLedgerTransport` is. Tests never import `package:matrix`.
- **Fakes** (`test/helpers/fake_record_signing.dart`):
  - Each fake device has a random secret. `key = "fake-ed25519:" + hex(sha256(secret))`, and `sig = b64(HMAC-SHA256(secret, message))`.
  - The fake verifier resolves `key` to its secret through a registry that only the fake network holds.
  - A test "attacker" holds only its own device's secret, so forging is impossible unless the test hands over the secret on purpose. That models Ed25519 faithfully enough for the protocol.
  - `FakeMatrixNetwork` gets a `FakeDeviceKeyDirectory`, and `removeDevice()` = logout: the device disappears from the directory.
- **Why no real Ed25519 in tests:** there is no pure-Dart Ed25519 in the lockfile (`ed25519_edwards` is in the pub cache but isn't a dependency), and vodozemac needs the native or wasm library. Real signing is covered in M6 on devices.

**Test plan** (all offline):

1. **Codec:** golden canonical bytes and messages, including non-ASCII and NFC descriptions; sign → verify round-trip for each type; any changed field breaks verification; type and group replay are rejected.
2. **Forgery:** M sends an expense signed with M's key but `sig.user = X` (existing device of X) → `key_conflict`, rejected, row unchanged, `rejected_versions` written. With a fabricated device → accepted as `unverified`, X's devices show "not your device". A bad signature → rejected.
3. **Legitimate edit:** Y edits X's expense → accepted everywhere. "Added by X · edited by Y". `origin_changed` is rejected.
4. **Delete:** a tombstone signed by Y → "deleted by Y" is recorded and replicated.
5. **Relay after logout:** X edits, Z pins X's device by receiving it, X's device is removed, then a new member W bootstraps from Z (attested → `vouched`) and from Z's digest repair (no attestation → `unverified`). Y, who already pinned the device, shows it `verified`.
6. **Loop:** a forged version held by a fooled v2 peer → after one exchange, no further re-sends (fake `sent` log), and the peers show as in sync.
7. **Unsigned / legacy:** an unsigned inbound version is refused and recorded; an unsigned relay of a legacy row we hold at the same clock is a no-op; the v5 → v6 migration keeps rows as legacy.
8. **Restore:** a backup with sigs and attestations, restored on a fresh account DB → statuses as expected. A tampered field in the file → that record is rejected and the rest restore.
9. **CSV:** an imported winning row is signed by the importer. A non-winning row is not re-signed.
10. **Lifecycle (G19):** signer captured before the first await. `pending_sign` is signed on the next digest broadcast. Account switch mid-verify → silent bail.
11. **Migration:** v5 → v6 (§4).
12. **Background round:** fake session signer and directory; a verified inbound record is applied.
13. **UI:** widget tests for footer EN and DE, unverified/unsigned hints, the rejected notice. The ARB key-parity test.

## 11. Milestones

- **M1 — codec and policy (pure).** `record_signing.dart` (bodies, canonical form, message), `Verdict` / `checkVersion`, fake signer, verifier and directory. Promote `canonical_json` and `crypto` to direct dependencies and update `THIRD_PARTY_NOTICES.md`. Tests 1–2 at unit level.
- **M2 — storage and adapters.** Drift v6 (columns, `known_device_keys`, `rejected_versions`, `protocol_version`) plus migration test 11. Models and payload builders emit `sig`/`origin`/`v: 2`. Real `MatrixRecordSigner` and `MatrixDeviceKeyDirectory`, `vodozemacVerify` (+ `vodozemac` direct dependency). Providers, including the background-session and demo overrides.
- **M3 — sync integration.**
  - Signing in every local writer, plus `pending_sign` sweeps.
  - Verification in `LedgerSyncer` (records and per-record bootstrap) and digest member gossip.
  - Proactive pinning after sends, and attestations in bootstrap and backup.
  - Equal-clock DAO rule, the `rejected` digest map and rules 1/4, the non-member gossip fix.
  - Backup restore and CSV import paths.
  - Tests 2–10, 12, with integration tests in the style of `test/integration/` using `FakeMatrixNetwork`.
- **M4 — UI.** Footer, dialog line, hints, rejected notice, own-identity warning, ARB EN and DE, test 13.
- **M5 — docs.** (Strict mode dropped by the review.) CLAUDE.md (protocol v2, schema v6, reception rules, backup/CSV), `docs/open-points.md` (residual risks from §5.4).
- **M6 — real devices** (emulator ↔ phone, with G11):
  - sign on Android and verify on web, and the reverse;
  - sign out on one device, then a fresh device bootstraps and shows `vouched` / `unverified` as expected;
  - verify throughput on a large group on web;
  - add the steps to `docs/smoke-test.md`.

## 12. Review answers

1. Cross-signing: deferred (the app never sets it up) — residual risk + future item.
2. Vouched renders like verified in the footer; the details dialog distinguishes "verified on receipt" from "vouched by <sender>".
3. "Unverified" shows on the edit page only; the list flags key conflicts and impersonation of you.
4. Strict mode dropped (unreleased app).
5. `origin` kept — it stayed small (one extra column + one extra signature).

## 13. As built (file map)

- `lib/models/record_signature.dart` — `RecordSignature` (wire / column JSON).
- `lib/core/matrix/record_crypto.dart` — ports `RecordCrypto`, `DeviceKeyDirectory`, `SignerId`; on `LedgerTransport` as `crypto` / `deviceKeys`.
- `lib/core/matrix/matrix_ledger_transport.dart` — `MatrixRecordCrypto` (`olmManager.signString`, `vod.Ed25519PublicKey.verify`), `MatrixDeviceKeyDirectory` (`updateUserDeviceKeys` + valid, unblocked `DeviceKeys`).
- `lib/core/matrix/hmac_record_crypto.dart` — HMAC stand-in keys + directory (tests, offline demo).
- `lib/core/sync/record_signing.dart` — bodies, `signingMessage`, `sign*`, `LocalRecordSigner`.
- `lib/core/sync/record_verifier.dart` — `RecordVerifier`, `RejectReason`, `signatureStatus`.
- `lib/core/sync/record_gate.dart` — `RecordGate` (live records, snapshots, digest gossip, restore).
- `lib/core/database/daos/signing_dao.dart` — `known_device_keys`, `rejected_versions`; schema v6.
- `lib/features/expenses/record_attribution.dart` — footer / dialog / list flag.
- Tests: `test/core/record_signing_test.dart`, `record_verifier_test.dart`, `digest_rejected_test.dart`, `test/integration/signed_records_test.dart`, `test/database/schema_v6_migration_test.dart`, `test/record_attribution_test.dart`, plus G6 cases in `backup_service_test.dart` / `csv_import_test.dart`.
