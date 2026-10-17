# G50 — No-login link groups (Nostr relays)

Status: **signed off by Leo on 2026-10-17** (plan.md G50; decisions in §14). This is the spec
for G51 (spike), G52 (link groups), G53 (mixed groups + lock) and G54 ("Why
Matrix?" + welcome reorder). It contains no code. Product decisions by Leo
(2026-10-16) are taken as given. Where this doc decides something new, it
says so, and the decision is repeated in §14 "Open questions for Leo".
G51 (spike, 2026-10-17): default relays decided (nos.lol + nostr.mom, §9.4),
results and the G52 go / no-go in §16.

## 0. Decisions at a glance

| # | Question | Proposal |
|---|----------|----------|
| 1 | Default invite | **Link group**: an invite link / QR code shared over WhatsApp & co. Friends install the app, open the link and pick their participant. No account. Matrix stays as the optional **secure mode**. |
| 2 | When the link channel starts | A new group stays **device-only** until the first *Invite*. Inviting opens the link channel: the secret is created and publishing starts. A solo group never talks to a relay. |
| 3 | Transport | **Public Nostr relays.** Each device publishes **one addressable event per group** (custom kind in 30000–39999, proposal `31847`). The event holds that device's **whole group snapshot**: bootstrap JSON → gzip → AES-256-GCM → base64. Readers fetch every event with the group's `d` tag and LWW-merge them through the existing `RecordGate` and DAOs. |
| 4 | Relays | Defaults **`nos.lol` and `nostr.mom`** only (decided by Leo 2026-10-17, §9.4 option C: the only free relays whose published terms allow this use; damus + primal dropped as grey zone). Every event goes to both. **Both have one operator and one host** (§16), so the user can add a custom relay as the mitigation. NIP-40 `expiration` 30 days, refreshed while the group is in use (decided 2026-10-17). |
| 5 | Keys | `link secret` (32 random bytes, in the URL `#fragment`) → HKDF-SHA256 → **topic** (`d` tag), **encryption key**. A random **secp256k1 key per (device, group)** signs the Nostr events. Nothing is reused across groups. |
| 6 | App key (W5) | **Recommendation: no secret app key.** Use a public, versioned HKDF salt that lives in the source. A secret `--dart-define` key would very likely have to be published as part of the AGPL Corresponding Source. It also breaks F-Droid / self-build interoperability, and anyone can pull it out of the APK (§4.4). |
| 7 | Size | Budget: ≤ **60 000** base64 chars of `content` per event (G51: both relays advertise a 131 072-byte frame but refuse any **event over 65 536 bytes** with `invalid: event too large`; §16). The usage profile (~200 unsigned records) is ~17 KB of content. A bigger group is **sharded into up to 8 addressable parts**. LWW makes the parts order- and generation-independent. |
| 8 | Identity | No accounts and no signatures in link groups. "Who am I" is **device-local**: `link_channels.my_participant_id`. Member records in a pure link group carry **no claim** on the wire. Each event's header names the publisher's participant, only as a hint for the "taken" marks in the picker. |
| 9 | Gate | Per-group policy in `RecordGate`. In a **link group** (unsigned meta), unsigned versions are accepted. Content validation, wrong-group checks, the future-clock drop and LWW still apply. The Matrix membership gate doesn't apply. Matrix replication never targets link groups. |
| 10 | Mixed + lock (G53) | The **signed meta** carries `link: {epoch, secret}` while a link is open. Unsigned versions are accepted only while it is open and are shown "via link, not verified". **Lock** = a signed meta without `link`: the channel is closed and any later unsigned version is refused. |
| 11 | Backups | The secret travels in the group meta, so backups contain it and a restore can rejoin. The device's Nostr key and "who am I" stay device-local. CSV unchanged. |
| 12 | Deps | `bip340` (MIT) + `pointycastle` (MIT) for Schnorr. `web_socket_channel` (BSD-3) is already transitive; `archive` (MIT, gzip on web) is a direct dependency since G52 step 1. `qr` (BSD-3) renders the QR code and `share_plus` (BSD-3) opens the share sheet. **Our own ~400-line Nostr client**, no Nostr SDK (§11). |

## 1. Goals, non-goals, positioning

**Goals**
- Inviting friends takes three taps: *Invite* → share link → friend opens it → "Which one are you?". Nobody needs an account, a Matrix ID or a homeserver.
- Near-real-time sync while the app is open. While closed, the same Android background round as today (~15 min).
- Still **no server of ours** (goal 3). Relay data is encrypted with a key that only the link carries.
- Keep working with what exists: the local ledger, LWW, the DAOs, G48 history, backups, local mode.

**Non-goals**
- Security against people who hold the link. Anyone with the link can read, write and delete. That is the documented trade-off; Matrix is the answer for it.
- Forward secrecy, per-member revocation, push notifications, iOS.
- Large groups. The target is ≤ ~10 people and a few hundred records. ~2–5k records still fit (§5.4).

**Positioning.** Link = the default and the easy path. Matrix = "secure mode", offered calmly (§10, G54), never as a nag.

**Relation to local mode (G40).** The main user of link groups is a **local-mode user** (`local:self`, no Matrix at all). Today local mode means nothing leaves the device. With G52 it becomes "no account": device-only groups stay device-only, and link groups talk to Nostr relays. The UI's "Local only" chip is renamed (§8.3). Link groups don't use `local:self` claims, because "me" is device-local per link group (§6). G40 adoption (*Connect a Matrix account*) moves link groups into the account DB unchanged: they stay link groups and keep their channel row, and none of their rows are signed (Leo: "never re-signed").

## 2. Invite link and QR code

### 2.1 Format

```
https://leostumpf.github.io/moneyledger/join#v=1&k=<secret>&n=<name>
moneyledger://join#v=1&k=<secret>&n=<name>
```

| Field | Meaning |
|-------|---------|
| `v` | Link / key-derivation version (`1`). An unknown version leads to "Please update the app". |
| `k` | Link secret: 32 random bytes, base64url without padding (43 chars). |
| `n` | **Optional** group name hint (URL-encoded, ≤ 40 chars). Used for "Join *Trip to Rome*?" before anything is fetched. It is visible to whoever sees the link, and those people can read the group anyway. Switch: §14 Q4. |

- **Why the `#fragment`.** Browsers never send the fragment to a server. GitHub Pages therefore never sees the secret, and WhatsApp's link preview fetch doesn't send it either (the preview requests the URL without the fragment).
- **What the link does not carry.** There's no group id or relay list. The group id comes from the decrypted snapshot, and the joiner uses its own relay list (defaults + custom). A group on a custom-only relay isn't found by a joiner with defaults; §14 Q3 covers adding `r=` relay hints.
- The **QR code** encodes the https link (`qr` package, rendered in the invite sheet). The phone's camera app opens it like a tapped link. There's no in-app scanner in v1 (§14 Q6).

### 2.2 Opening it

| Situation | Behaviour |
|-----------|-----------|
| App installed, Android | An intent filter for `moneyledger://join` (like the SSO callback). For the https form, an **App Link** with `autoVerify="true"` on `leostumpf.github.io` with `pathPrefix /moneyledger/join`. Verification needs `https://leostumpf.github.io/.well-known/assetlinks.json` at the **domain root**: a `LeoStumpf.github.io` user-site repo with `.nojekyll` (decided 2026-10-17: **shared by all of Leo's apps** — `assetlinks.json` is a list of statements, one per package, and each app gets its own path prefix `/<appname>/`; the root page lists the apps), holding the release + upload key fingerprints (public certificate fingerprints only; the Play App Signing fingerprint is added once known). Without verification, Android asks "Open with" or opens the browser, which then shows the landing page. |
| App not installed | The landing page `join.html` (GitHub Pages, static, no analytics, no external requests) says "Open in MoneyLedger" (a `moneyledger://join#…` button built **in JS from `location.hash`**) and links to Play / F-Droid / the web app. After installing, the user taps the link again. The welcome page also has **"Join with an invite link" → Paste**. |
| Deferred deep link through the Play install referrer | **Rejected.** It would hand the secret to Google Play. |
| Web app | The web build uses the hash URL strategy, so the link becomes `https://<web>/#/join?v=1&k=…`. The secret is still inside the fragment. |

`/join` is a public route in `routerRedirect`. It is reachable signed out, before the welcome has been seen, and in local mode (§8.2).

## 3. Keys and crypto

### 3.1 Derivation

```
secret   = 32 random bytes (Random.secure)
salt     = kLinkSaltV1   (public 32-byte constant in the source, §4.4)
prk      = HKDF-Extract(salt, secret)                         (SHA-256)
topic    = HKDF-Expand(prk, "moneyledger-link-v1 topic", 32)  → hex, 64 chars = `d` tag
encKey   = HKDF-Expand(prk, "moneyledger-link-v1 enc",   32)  → AES-256-GCM key
```

`cryptography` 2.9 already provides `Hkdf(hmac: Hmac.sha256())` and `AesGcm.with256bits()`, using the pure-Dart implementations as in G34.

**Nostr event key.** Each device generates a random secp256k1 key **per group** (`link_channels.nostr_priv`). It is not derived from the secret: if it were, every device would publish under the same pubkey and overwrite the others' snapshots. A per-group key also means relays can't link one device's groups by pubkey (IP and timing still can, §9).

### 3.2 Envelope

```
plain   = utf8(json(snapshot))              // §5.1
packed  = gzip(plain)                       // `archive` GZipEncoder (pure Dart, web too)
nonce   = 12 random bytes                   // fresh per event
aad     = "moneyledger-link-v1|31847|<d>|<pubkey hex>"
ct      = AES-256-GCM(encKey, nonce, packed, aad)   // ct ‖ 16-byte tag
content = "1:" + base64(nonce ‖ ct)
```

- `base64` is the standard alphabet with padding. The gzip header's MTIME is zeroed (the web encoder would stamp the current time), so packing is deterministic per platform; native and web deflate still differ, so change detection compares plaintext (G52 step 1: `lib/core/link/link_envelope.dart`).
- **Random 96-bit nonce per event.** A group sees at most a few thousand encryptions under one key, far below the ~2³² random-nonce bound.
- **The AAD** binds the ciphertext to its kind, topic and publishing pubkey. Another key holder can't re-publish a device's snapshot under their own pubkey to make it look like it came from that device. This is cheap integrity among key holders, not authentication of people.
- **Decrypt failure** (wrong app salt, tampering, a foreign event on our `d`) → the event is ignored and logged, never shown.

### 3.3 Event signature

NIP-01 requires a BIP-340 Schnorr signature over `sha256([0,pubkey,created_at,kind,tags,content])`. We sign with the per-group key. On receive we verify the signature, which is cheap and catches broken relays, though relays (strfry) verify too. **G51 (§16):** verifying is cheap natively (12 ms) but not on the web (≈ 160–170 ms per event in dart2js), and it adds no security on top of the AEAD (§3.2: the AAD already binds the content to the pubkey; anyone with the link can make a valid key anyway). **Decided by Leo (2026-10-17):** verify on native only; on the web skip the check and rely on the AEAD + the relays' own verification (§16 open point 2).

*G52 step 2 (`lib/core/link/nostr/`):* the policy is `kVerifyNostrSignatures` (= `!kIsWeb`), injected into `NostrRelayPool(verifySignatures:)`. The **event id** (one SHA-256) is checked on every platform: it is cheap and stops a relay from passing off other content under a known id (dedup is by id). Signing runs everywhere.

### 3.4 App key (W5) — AGPL analysis and recommendation

**Leo's idea:** `salt` = a secret app key, injected into release builds via `--dart-define=LINK_APP_KEY=…` from a gitignored file. Self-builds would use a public default, so a link alone can't decrypt relay data without the official app.

**License text** (repo `LICENSE`, GPLv3 terms incorporated by AGPLv3):

- §1: *"The 'Corresponding Source' for a work in object code form means all the source code needed to generate, install, and (for an executable work) run the object code and to modify the work, including scripts to control those activities."*
- §6 / "Installation Information": *"…any methods, procedures, authorization keys, or other information required to install and execute modified versions of a covered work in that User Product…"*. This applies only when object code is conveyed *"in, or with, or specifically for use in, a User Product"* as part of a transaction that transfers possession of that product (for example, selling a phone with the app). It also only covers what is needed to **install and run** modified versions. Distributing through Play or F-Droid doesn't transfer a device, and a modified build installs and runs fine without our key. So the Installation-Information clause is **not** the relevant one.

**§1 is the relevant clause.** The key is compiled into the release binary. Without it, nobody can regenerate that object code or produce a modified version that behaves the same, which here means reading and writing release-made groups. The key is "needed to generate … and run the object code" in the sense that matters for interoperability. It isn't a credential for a third-party service (the usual argument for leaving API keys out of GPL sources). It is a protocol constant of this program, so it should be counted as part of the Corresponding Source.

Leo owns his own code, but the binary combines AGPL code he doesn't own: the `matrix` SDK, `flutter_vodozemac` and `vodozemac`. Conveying it means honouring the AGPL for the whole work (§5c), so "it's my code" doesn't settle the question. This is a reasoned reading, not legal advice, but there is a real risk of non-compliance.

**Practical arguments, independent of the license:**
1. **F-Droid** builds from source with public inputs. F-Droid users would get the public default and couldn't join groups made by Play users. That splits the user base in two, invisibly.
2. **Reproducible builds** become impossible to verify.
3. The key sits as plain bytes in `libapp.so`, and `strings` / `blutter` recover it in minutes. As a hurdle it stops nobody who writes their own client, and casual link holders simply install the app.
4. The threat it addresses (relay data plus a leaked link, but no app) gains almost nothing, because the leaked link plus the free app reads everything anyway.

**Recommendation:** drop the secret app key.
- Keep a **public, versioned salt** `kLinkSaltV1` (= SHA-256("moneyledger-link-v1 salt")) in the source. It gives domain separation and lets us change derivation through `v=2` later.
- Document honestly: "the link is the key".
- If Leo still wants a hurdle, the only AGPL-clean form is a key that **is** published in the repo. That adds nothing over the salt.

## 4. Nostr specifics

### 4.1 Kind and semantics

- **Addressable range.** NIP-01 defines `30000 <= n < 40000` as addressable: "for each combination of `kind`, `pubkey` and the `d` tag value, only the latest event MUST be stored by relays, older versions MAY be discarded." Ties on `created_at` keep the **lowest id**, which is why we keep `created_at` strictly increasing per (pubkey, d) (§4.5).
- **Proposed kind: `31847`.** It is unregistered (checked against the NIPs README kind table on 2026-10-17). Check again before release; registering it with a NIPs PR is optional.
- **Why not NIP-78 kind 30078.** NIP-78 ("arbitrary custom app data") says relays *should require NIP-42 AUTH and serve these events only to the author's pubkey*. That makes them author-private: a friend (a different pubkey) couldn't read our snapshot on a NIP-78-conforming relay. Our model needs exactly **cross-author reads by `d` tag**, so 30078 is the wrong kind.
- **Unknown kinds.** Both default relays run **strfry** 1.1.3, which stores any valid event; the policy plugins decide. nos.lol says "accepts notes, except spammy ones". **Measured in G51 (§16):** kind 31847 is accepted, stored and served by both; events are capped at **65 536 bytes** of event JSON (not the advertised 131 072-byte frame).
- **Don't use NIP-70 `["-"]`.** Relays MUST reject protected events unless the author AUTHs (NIP-42), which is extra complexity. It is listed as a later option to make third-party re-broadcasting harder.

### 4.2 Event

```json
{ "kind": 31847, "pubkey": "<per-group device key>", "created_at": 1792000000,
  "tags": [ ["d", "<topic hex>"],
            ["expiration", "1797184000"],
            ["alt", "MoneyLedger encrypted group data"] ],
  "content": "1:<base64>", "id": "…", "sig": "…" }
```

- `alt` (NIP-31) tells generic clients what the event is.
- There is no `p`, `t` or client tag, to avoid extra metadata.
- `expiration` (NIP-40) = now + 30 days. NIP-40 says relays **SHOULD** delete expired events but **MAY persist them indefinitely**, and that expiration is **not a security feature**. We treat it as hygiene, not as privacy.

### 4.3 Subscriptions and fetch

- **Filter.** `{"kinds":[31847], "#d":[<topics of all my link groups and their parts>]}`, one `REQ` per relay. Single-letter tags are indexed by relays (NIP-01). Relay limits: `max_subscriptions` 20 (nos.lol), 50 (nostr.mom); `max_limit` 500 per filter.
- **Live, app in the foreground.** One WebSocket per relay and one subscription covering all groups. `since` is set to the newest `created_at` seen minus 60 s. The subscription is re-issued when the group set changes, closed 30 s after the app is paused and reopened on resume. Reconnects back off: 2 s → 4 → … → 5 min, plus jitter.
- **Full fetch** (on join, on app start, on "pull to refresh"): `REQ` without `since`, wait for `EOSE` (timeout 10 s per relay), then `CLOSE`. (G52 step 2: the 10 s include connecting; a publish waits up to 10 s per relay for its `OK`, connecting included.)
- **Dedup.** `link_peers` stores the last event id per (group, pubkey, part). An event already processed is skipped before decrypting.
- **Own events.** Skip our own pubkey; re-reading it only confirms that a relay holds it, which `link_relay_state` records.

### 4.4 Publishing

- **Trigger:** any change to the group's stored state. That means a local write *or* an inbound merge that changed a row (`snapshotDigest` ≠ `last_published_hash`).
- **Debounce:** 3 s; at most 1 publish per group per 5 s per relay.
- **Inbound merges.** Republishing after an inbound merge makes every device's event a full, merged copy, so one surviving phone is enough to bring a new joiner up to date. It converges: a merge that changes nothing publishes nothing.
- **Refresh:** republish an unchanged snapshot when the last publish is > 10 days old, so `expiration` keeps moving while anyone opens the group.
- **Relay replies:** `OK true` → record success per relay. `OK false` with a NIP-01 prefix (`rate-limited:`, `invalid:`, `blocked:`, `restricted:`, `pow:`, `error:`) → back off that relay (rate-limited: 1 min doubling to 1 h; blocked / restricted / invalid: mark it "rejects our events" in settings and stop retrying until the next app start). `duplicate:` counts as success. **`replaced: have newer event`** (an `OK false` strfry sends when it already holds a newer — or same-second lower-id — event for that address, G51 E2) is **not** a relay failure: it means our `created_at` wasn't ahead (§4.5) → bump `last_created_at` past the relay's event and republish once. `invalid: event too large: <n>` means the sharding budget was exceeded (a bug, §5.4), not "rejects our events".
- **Sync health.** A group counts as **delivered** when ≥ 1 relay said `OK true`. 0 of N for 2 consecutive attempts → `SyncHealth` failing for link groups (same threshold as G24).

### 4.5 Clock

Nostr `created_at` is in **seconds**. Use `created_at = max(nowSec, lastCreatedAt + 1)`, stored in `link_channels.last_created_at`. Relays may reject far-future timestamps (NIP-11 `created_at_upper_limit`), so the value must never run more than a few seconds ahead. With the 3 s debounce that holds in practice. The ledger's LWW clocks are inside the encrypted payload and never depend on `created_at`.

### 4.6 NIP-11 discovery

On adding or first using a relay, `GET https://<relay>` with `Accept: application/nostr+json`:
- read `limitation.max_message_length` (frame bytes), `max_content_length`, `max_subscriptions`, `auth_required`, `payment_required`, `restricted_writes` and `supported_nips` (40 must be present);
- cache the result for 7 days;
- refuse a custom relay with `auth_required` / `payment_required` ("this relay needs an account").

- **NIP-11 doesn't tell the event size limit.** Both defaults advertise only `max_message_length` 131 072, but refuse events over 65 536 bytes (strfry's `maxEventSize`, G51). G52 therefore uses the fixed `kLinkContentBudget` (§5.4) for every relay and treats a smaller advertised `max_message_length` / `max_content_length` of a custom relay as a lower budget for it.

Measured on 2026-10-17 (defaults decided by Leo the same day, §9.4):

| Relay | max_message_length | event size limit (G51) | max_subscriptions | NIPs (relevant) | Software | Status |
|-------|-------------------|------------------------|-------------------|-----------------|----------|--------|
| nos.lol | 131 072 | **65 536** | 20 | 1, 9, 11, 40, 70 (ToS link) | strfry 1.1.3 | **default** |
| nostr.mom | 131 072 | **65 536** | 50 | 1, 9, 11, 40, 70 (ToS link) | strfry 1.1.3 | **default** |
| relay.damus.io | 1 000 000 | — | 200 | 1, 11, 40, 59, 70 | strfry | dropped (grey zone, §9.4) |
| relay.primal.net | 1 000 000 | — | 20 | 1, 11, 40, 70 | strfry | dropped (grey zone, §9.4) |

## 5. Snapshot and merge semantics

### 5.1 Snapshot payload (inside the encryption)

```json
{ "format": "moneyledger-link", "v": 1,
  "group": "<groupId>", "me": "<participant id of the publisher>",
  "part": 0, "parts": 1, "app": "1.4.0",
  ...buildBootstrapContent(group)          // meta, members, expenses, settlements, tombstones, device_keys
}
```

- The header keys **replace** the bootstrap's own: `v` here is the link snapshot version (1), not the bootstrap's protocol version (2) — every record inside keeps its own `"v": 2` (as the G51 spike; G52 step 1: `buildLinkSnapshotPart`, `lib/core/link/link_snapshot.dart`). `part` is 0-based (unlike G14's informational 1-based bootstrap parts).
- This is the **same bootstrap content** the Matrix path and the backup file use. Categories (G47 meta), expense dates (G49), notes and tombstones are all included.
- `pending_sign` rows are included in link groups. They are never `pending_sign` there anyway (§6.3).
- In **mixed** groups the signatures travel along. Attestations (`device_keys`) are included but never trusted from the link path.

### 5.2 Merge

Every decrypted event → `RecordGate.snapshot(content, relayedBy: "nostr:<pubkey>", trustAttestations: false)` with the group's **link policy** (§6.4). This means:
- whole-record LWW per id with the G27 hash tie-break;
- tombstones win when newer;
- the history source is `inbound` (G48);
- rejected versions are recorded the same way (§6.4).

**Clock skew.** Versions with `updated_at` > now + 5 min are **dropped transiently**, not clamped. Clamping would mint a different version on each device. Because the event stays on the relay, the version is accepted once our clock catches up. This matches the G6 verifier's `futureClock` rule.

**Group binding.**
- `snapshot.group` must equal `link_channels.group_id`. On join, it is the group id of the first event that decrypts. Events that disagree are ignored and logged.
- `snapshotEntries` already drops nested entries of other groups.
- An expense id stored for another group is refused (`invalid_record`, as today).

**Stale publishers.** A phone that was uninstalled or that left keeps its last event until expiry. Under LWW its old versions lose to newer ones, so this is harmless. It still supplies older records to new joiners, which is a feature.

**Deletion.** Through tombstones, like everywhere else. A tombstone lives in every publisher's snapshot, so no device can resurrect the record (LWW).

### 5.3 Sync status in link groups

There are no digests. The cloud icon for a link group:
- **synced** — our latest snapshot was acknowledged by ≥ 1 relay, and every peer event we hold decrypted and merged;
- **pending** — a publish is waiting or in flight;
- **failing** — §4.4.

A per-peer detail sheet lists each known publisher (participant from `me`, "last update 3 min ago") from `link_peers`. "Has Ben seen my change" is shown honestly as "Ben's phone last published at …". A link snapshot can't prove that it covers our change without per-record comparison, so this is the only signal available. Optionally the sheet can compare Ben's snapshot digest with ours and show "Ben has everything" when they match. That is the cheap G29 analogue and is proposed for G52.

### 5.4 Size

- **Measured (G51 E8, §16).** 200 unsigned records ≈ 98.6 KB JSON → gzip + AES-GCM + base64 = **17 330 chars** of content (≈ 87 chars / record; 500 records → 41 100, 1 000 → 80 600).
- **Mixed groups.** Signatures (`origin` + `sig`, random base64) don't compress: 200 signed records = **76 458 chars**, i.e. **2 parts** already at 200 records (≈ 380 chars / record).
- **Budget.** `kLinkContentBudget` = **60 000 chars** of `content` per event. Both default relays advertise a 131 072-byte frame (`max_message_length`), but refuse every **event** whose JSON exceeds **65 536 bytes** (`OK false "invalid: event too large: <n>"`, G51 E1: 65 519 B accepted, 65 551 B refused on both). Our envelope (id, pubkey, sig, `created_at`, `kind`, the `d` / `expiration` / `alt` tags) is ≈ 490 bytes, so 60 000 chars of content give an event of ≈ 60 500 bytes and an `EVENT` frame of ≈ 60 510 bytes: ~5 KB headroom for a part suffix on `d`, a later tag, or a relay that counts slightly differently. (The frame limit itself is then never close: 60 510 of 131 072.)
- **Sharding.** Over budget → `parts` = 2, 4 or 8. Records are assigned by `fnv1a(id) % parts`. Part `i` is published under `d = topic` (i = 0) or `d = topic + "." + i`. Every part carries meta + all members + its slice, like G14's self-contained bootstrap parts.
- **Readers** always subscribe to the topic and `.1`–`.7`, which is cheap.
- **Shrinking.** When `parts` drops, the publisher replaces the now-unused parts with a header-only part (meta + members, no records; its `part` = the old index ≥ the new `parts`, which marks it retired) with `expiration` = now + 1 day. LWW makes mixed generations harmless: an old part only offers older versions.
- **Ceiling** ≈ 8 × 60 000 chars ≈ **5 000 unsigned records** (≈ 690 per part minus the per-part header), but only ≈ **1 200 signed records** in a mixed group. Beyond that: "This group is too big for link sharing — use Matrix" (§10).

## 6. Identity and participants

### 6.1 Who am I

`link_channels.my_participant_id` is set when the user creates the link channel (their participant) or joins ("Which participant are you?"). `currentParticipant(group)` changes to:

1. the participant claimed by `ledgerIdentity` (MXID or `local:self`), as today; else
2. the link channel's `my_participant_id` when that participant is active.

Everything built on top (balances "you", `expenseEffectFor`, filters, exit kind) works unchanged.

**Why not a synced claim like `nostr:<pubkey>` in `Members.matrixId`:**
- Claims would have to be rewritten per device: two phones of one person, or a reinstall, give two pubkeys.
- Unsigned claims would fight under LWW.
- `isValidMxid` / `memberProblem` would need another exception.
- Every "replication target" path would need to skip them.

Keeping "me" device-local avoids all of that. The `me` field in each event header (§5.1) is a **hint only**: the join picker marks participants other phones already use ("used on another phone"). It is not exclusive, because a person's second phone may pick the same participant.

**Opening a link in a group that has a `local:self` claim** (a local-mode group): the own participant is rewritten **without** the claim (`nextLwwClock`), and `my_participant_id` is set to it. This happens once, before the first publish, so no `local:self` ever leaves the device. Member records in a pure link group must have `matrix_id: null`. Inbound member versions with a claim are refused (`invalid_record`) unless the group is mixed (§10).

### 6.2 Joining

1. Open the link → `JoinLinkPage`. On the very first link use on this device, show the first-use disclosure (§9.2).
2. Full fetch from all relays (10 s) → decrypt → merge into the current ledger DB:
   - local mode → the local DB;
   - signed in → the account DB;
   - neither (fresh install, welcome not done) → join **creates a local profile implicitly** (name from the picker), marks the welcome seen and continues in local mode.
3. Show "Which participant are you?". The G46 dialog is reused: it lists active participants with "used on another phone" hints, plus "I'm new" → name → a new participant. Dismiss = cancel the join: nothing is published, but the group remains unless the user cancels the whole join, in which case it is purged.
4. Save `link_channels` → publish our snapshot (now containing our new participant if one was created) → open the group.

**Nothing found** after 10 s: "Couldn't find this group yet. The person who invited you needs to open MoneyLedger once (or check your relays)." The page offers *Retry* and keeps the pending link for 7 days, so live sync picks the group up later.

### 6.3 Writes and signatures

- **Local mode in a link group:** versions are stored **unsigned and not `pending_sign`** (new flag `link_unsigned`, or simply `sig = null` + group policy). G40 adoption and `signPendingRows` skip link groups, so link-written versions are never re-signed (Leo).
- **A Matrix device** (signed in) **signs every version it writes, in every group.** In a link group that gives correct "added by" for mixed groups later. Link peers can't verify it, which is fine: they show "via link".
  - *G52 step 4:* until G53 this holds for `matrix` and `mixed` groups only. In a **`linkOnly`** group a signed-in device writes unsigned like local mode (`LocalRecordSigner` with the group policy): a signed meta would turn the group `mixed` (§6.4), and a signed version's signer claims no participant there, so link peers would drop it (rule 5). G53's signed self-claim lifts this.
- **Author hint.** Every version written in a link group carries an optional, **unsigned, unhashed** `by: <participant id>` = the writer's `my_participant_id`. It is stored in a new nullable `link_author` column and is display-only: "Changed by Ben (via link, not verified)". It is excluded from the G27 content hash, so it never splits versions (§14 Q8).

### 6.4 Gate rules per group

The group policy is derived from the stored **meta**:

| Policy | When | Matrix (to-device) path | Link path |
|--------|------|-------------------------|-----------|
| `matrix` | signed meta, no `link` field | unchanged (G6 / G18) | not subscribed |
| `linkOnly` | meta unsigned (created in local mode / via link) | dropped: Matrix sends never target it, and inbound for it is dropped | unsigned accepted, signed verified |
| `mixed` | signed meta with `link: {epoch, secret}` | unchanged, **plus** unsigned versions accepted (§10) | unsigned accepted, signed verified |

**Link path rules** (in `RecordGate`, behind `policy.allowsUnsigned`):
- **Still enforced:**
  - `record_validation` (split sums, amount bounds, payer, no self-payment, member rules);
  - wrong-group id;
  - future clock (> now + 5 min, transient drop);
  - LWW / G27;
  - an exactly refused version is dropped;
  - a **signed** version is verified as usual — a bad signature or key conflict is refused, because a forged signature is never acceptable even where unsigned is.
- **Bypassed for unsigned versions:**
  - the "unsigned → refused" verdict;
  - the signer-membership rule (rule 5);
  - origin checks (unsigned versions carry no `origin`, as with restored legacy rows — attribution never lies).
- **Not applicable:** `LedgerSyncer.isSenderAuthorized` (there is no authenticated sender). The topic + AEAD only prove "holds the link".
- **`linkOnly` meta** may itself be replaced by an unsigned version (rename, currency, categories). The **first signed meta** turns the group `mixed` (G53).

**Attribution UI** (`record_attribution.dart`):
- unsigned version in a link/mixed group → "Via link · not verified" (+ "Changed by Ben" from `link_author`);
- signed versions → as today.

**`SyncEngine` / `LedgerSyncer`:** skip `linkOnly` groups entirely (no digests, no bootstraps, no resync answers). `activeClaimedMatrixIds` is empty there anyway.

**As built (G52 step 4, `lib/core/link/group_policy.dart`, `LinkDao.policyOf`, `RecordGate(linkPolicy:)`):**
- The policy needs **this device's `link_channels` row** — no channel → `matrix`, whatever the meta says (legacy unsigned Matrix groups and local-mode groups stay `matrix`). Channel + unsigned / not-yet-stored meta → `linkOnly`; channel + signed meta → `mixed` (until G53 adds the meta `link` field). The channel is device-local and only created by the user's own open / join, so **inbound data can never downgrade a Matrix group**. The join flow (step 7) therefore stores the channel before the first merge, and must refuse a link whose group id this device already holds as a non-link group.
- Unsigned versions are accepted only by a gate built for the link path; the Matrix path keeps G6 (also for `mixed` until G53).
- A link-path **unsigned meta** is accepted only in `linkOnly` — never over the signed meta of a `mixed` group (that would turn it `linkOnly`). An **unsigned** Matrix-ID claim is refused in `mixed` too.
- `by` is kept only for link-path (and restored) versions; the Matrix path drops it.
- Local writes in `linkOnly` groups are stored unsigned, not `pending_sign`, without `origin`, `by` = `my_participant_id`; Matrix claims / invites there throw `LinkOnlyGroupException`.
- G40 adoption copies `link_channels` / `link_peers` with the group (an existing channel of the account DB wins); a `linkOnly` group is neither re-claimed nor signed, and a leftover `local:self` claim is rewritten without it and becomes `my_participant_id`.

## 7. Data model, backups, deletion

### 7.1 Schema v15

(Drafted as "v14"; G60 took v14, so the link schema is **v15** — G52 step 3, `lib/core/database/app_database.dart` + `LinkDao`.)

```
link_channels (group_id PK, epoch INT, secret TEXT /*base64url*/,
               my_participant_id TEXT NULL, nostr_priv TEXT /*hex*/,
               last_published_hash TEXT NULL, last_published_at INT DEFAULT 0,
               last_created_at INT DEFAULT 0 /*seconds*/, parts INT DEFAULT 1,
               opened_at INT)
link_peers    (group_id, pubkey, PK(group_id,pubkey), me TEXT NULL,
               event_ids_json TEXT DEFAULT '{}' /*{"<part>": "<event id>"}*/,
               last_created_at INT DEFAULT 0 /*seconds*/,
               last_seen_at INT DEFAULT 0, snapshot_digest TEXT NULL)
groups.link_author / expenses.link_author / settlements.link_author /
members.link_author  TEXT NULL
```

- **Step 3 refinements.** `link_peers.last_event_id` became a per-part map (`event_ids_json`): a sharded snapshot is up to 8 events per publisher, each deduped on its own (§4.3). `me` / `snapshot_digest` follow the publisher's newest event; `last_created_at` / `last_seen_at` only move forward. `groups.link_author` was added too, since a meta version written in a link group also carries `by` (§6.3). All `link_author` values are NULL after the migration; the column is outside the signed body and the G27 hash.
- `link_channels.last_created_at` is advanced by `LinkDao.nextCreatedAt` (`max(nowSec, last + 1)`, stored before use, §4.5) and `bumpCreatedAt` (after `replaced:`, §4.4).
- Both tables are device-local: never synced, never in a backup file, dropped by `purgeGroup` (and `wipeAll`). `secret` and `nostr_priv` are secrets in the per-account DB (same protection as the Matrix session; Android backup off, G32) and are never logged (`LinkChannelModel.toString` omits them).

- Relay list: `AppSettings` `link_relays` (JSON list; defaults when absent), per ledger DB.
- Per-relay status: `AppSettings` `link_relay_state:<url>` with NIP-11 cache, last OK and last rejection.
- **Where the secret lives.** It is part of the group **meta** (`link: {epoch, secret}`, §10), so `link_channels.secret` is a cache of the meta field for the current epoch. For `linkOnly` groups the meta is unsigned and carries the same field. A peer can't use that to "steal" anything, since it already has the secret.

### 7.2 Backups and CSV

- **JSON backup:** the meta carries the secret, so a restore on a new phone shows the group, and *Rejoin link* creates a new `link_channels` row with a fresh Nostr key, then asks "Which one are you?" again.
- The backup preview warns: "This file contains the invite key of N link groups. Anyone with the file can read and change them." That is one more reason to set the G34 passphrase.
- The device-local `nostr_priv` and `my_participant_id` are **not** backed up. A new phone is a new device.
- **CSV:** unchanged. No link data.

### 7.3 Leaving, deleting, "Delete local data"

- **Leave / delete a link group:**
  1. Publish a **header-only** snapshot with `expiration` = now + 1 day (our copy disappears from relays; peers keep theirs).
  2. Send a NIP-09 deletion (`kind 5`, `["a","31847:<pubkey>:<d>"]`) for every part.
  3. Purge as today and drop `link_channels`.
- In a link group, *Leave* = *Delete from this device*. Our participant stays in the ledger (debts are history). There is no "X left" record.
- **Delete local data** (local mode) does the same per link group, best-effort with a 5 s timeout, before `wipeAll()`. The confirmation lists "N shared groups — the others keep their copies".
- **Removing a person** in a link group only marks the participant `removed`; it doesn't revoke the key. The UI says so: "They can still open the group with the link. To lock them out, create a new invite link." A **Reset invite link** action (new epoch + secret: publish under the new topic, empty the old) ships in the first version (G52, §14 Q10). The remaining people get the new link **directly** (share sheet / QR — the default); a pointer to the new topic on the old channel would be readable by the removed person too, so it is only used for one's own further devices, if at all (G52 evaluates both).

## 8. App integration

### 8.1 Transport layer

A new port, `LinkTransport` (`lib/core/link/`), separate from `LedgerTransport` because its semantics differ (snapshot pub/sub, not messages):

```
abstract class RelayConnection {            // one WebSocket
  Stream<RelayMessage> get messages;        // EVENT / EOSE / OK / CLOSED / NOTICE
  Future<void> send(List<Object?> frame);
  Future<void> close();
}
class NostrRelayPool { publish(event) → Future<Map<relay, OkResult>>;
                       subscribe(filter) → Stream<NostrEvent>; fetchOnce(filter, timeout) }
class LinkSyncEngine  // per ledger DB, like SyncEngine: watches link_channels + group changes,
                      // debounced publish, live subscription, merge via RecordGate
```

- `linkSyncEngineProvider` `ref.watch`es `appDatabaseProvider` and captures the DAOs before its first await (G19 rules).
- It starts for MXID **and** `local:self` identities, but never on the signed-out placeholder or in the offline demo.
- `LedgerSyncHost` keeps it alive.
- In tests the `FakeRelayNetwork` stands in. It implements addressable replacement and the tie-break, `#d` filters, `since`, EOSE, OK prefixes, `max_message_length`, injected rate limits / outages, and `settle()`.

### 8.2 Router and onboarding

- `/join` is public.
- Local mode's "nothing leaves the device" changes to "No account". The chip reads **"No account"**, and its sheet explains device-only vs. shared-by-link groups.
- `LocalOnlyTransport` stays as it is. Link groups go through `LinkTransport`, not `LedgerTransport`.

### 8.3 Background (G31)

`runBackgroundRound` gains a **link phase**. It runs whenever the DB has a link channel, in local mode too: today local mode cancels background sync, and that changes to "schedule when ≥ 1 link group exists".

The link phase is one `fetchOnce` over all topics on all relays (EOSE or 10 s) → merge → publish what changed → close, inside the existing 60 s bound. The Matrix phase only runs when there is a Matrix session. The same concurrency gate applies (the round and the app must not both write the DB).

Web has no background sync; it relies on live sync while the tab is open.

### 8.4 Invite UI

The group ⋮ / members page / empty-group CTA → **Invite** sheet:
- the QR code;
- *Share link* (share sheet);
- *Copy*;
- the line "Anyone with this link can see and change this group";
- for Matrix users, a second section "Invite a Matrix user (secure)".

The first *Invite* in a group shows the disclosure (§9.2) and then opens the channel.

## 9. Privacy

### 9.1 What relays see

| Visible to relays (and anyone reading them) | Not visible |
|---|---|
| The device's **IP address** and connection times | Group name, people, amounts, notes (encrypted) |
| Per (device, group) **pubkey** — random, not linked across groups | The link secret |
| **`d` tag**: links all devices of one group (count of publishers = rough group size) | Which participant a device is |
| `created_at` of each publish (activity timing), event **size** | — |
| That the client speaks kind 31847 ("MoneyLedger") | — |

- **Archived history.** Relays may keep, mirror and archive events regardless of `expiration` (NIP-40). A link leaked later decrypts **every archived snapshot**, because there's no forward secrecy.
- **Comparison with Matrix mode:** there, the user's own homeserver sees "who talks to whom" (§G45) and nobody else does.

### 9.2 Texts

- **First-use disclosure** (before the first invite or join on a device; one screen, EN+DE, explicit *Continue*):
  > "Shared groups sync through two public Nostr relays, nos.lol and nostr.mom (one operator). They are independent services with their own terms (linked in Settings → Relays). They store your group encrypted — only people with the link can read it. The relays see your IP address and when you sync, and may keep data longer than the 30 days we ask for. Anyone with the link can see and change the group. You can add your own relay in Settings. Want accounts and verified devices? Use Matrix (secure mode)."
  It links to "Why Matrix?" (§10.2).
- **PRIVACY.md + the in-app `privacy*` keys:**
  - a new section "Shared (link) groups" covering the above, the relay operators as independent third parties with their own terms, the 30-day expiry request (not a guarantee), and the backup containing the link key;
  - the "local mode sends nothing" passages changed to "groups you don't share send nothing".
- Settings shows the relay list with "Add relay…" / remove / restore defaults.

### 9.3 Relay terms (grey zone)

Public relays exist for social notes. Some operators may not want opaque app blobs. NIP-78 shows that app data is an accepted pattern, but it is author-private there.

**Mitigations:**
- tiny volume (one replaceable event per device and group, so storage doesn't grow with edits);
- `expiration` set;
- an `alt` tag that says what it is;
- user-configurable relays;
- the defaults are only relays whose published terms allow this use (§9.4); they share one operator, so the custom relay setting is the fallback;
- back off on `rate-limited` / `blocked`;
- a short project page "For relay operators" (what we publish, how to block: kind 31847).

**Decided (2026-10-17, §14 Q12):** operators are **not** contacted. Condition: no grey zone — G51 first reads each default relay's published policy / terms (NIP-11 `posting_policy`, nos.lol's linked terms, damus / primal pages). A relay whose terms exclude app data or opaque encrypted blobs is dropped from the defaults and replaced by one that explicitly allows it (Leo is asked before the replacement). Fallback if relays become a problem: a self-hosted relay entered as the custom relay (Nostr is an open network, any relay works). The in-app disclosure (§9.2) and the "For relay operators" page stay.

### 9.4 Relay terms check (G51, 2026-10-17)

Read-only check, nothing was published. For each relay: the NIP-11 document
(`curl -s -H 'Accept: application/nostr+json' https://<host>`), every
`terms_of_service` / `posting_policy` / `privacy_policy` link in it, the relay's
own HTML page, and the operator's public terms pages. **No relay checked has a
NIP-11 `posting_policy` or `retention` field**, and none declares
`restricted_writes`, `auth_required` or `relay_countries` (except the paid ones).

**Classes** (bar from §14 Q12, "no grey zone"):
- **ALLOWED** = the operator publishes terms / a policy for this relay, and nothing
  in it restricts app data, encrypted content or non-social kinds, and we stay
  inside its stated limits.
- **GREY** = no published terms for the relay, social-only framing, or terms whose
  scope over the relay is unclear.
- **EXCLUDED** = the terms forbid our use, or the relay needs payment / auth /
  a whitelist, or it is technically unfit (no storage, frame too small).

| Relay | Class | Terms source | Limits (NIP-11) | Notes |
|---|---|---|---|---|
| **relay.damus.io** (former default, dropped) | **GREY** | none — NIP-11 has no terms field; `damus.io/terms`, `/privacy`, `/eula` → 404 | frame 1 000 000, subs 200, NIP-40 ✓ | Only the Damus *app* EULA exists, scoped to "our mobile application Damus" |
| **nos.lol** (default) | **ALLOWED** | NIP-11 `terms_of_service` → wikifreedia.xyz/nos.lol | frame **131 072**, subs 20, NIP-40 ✓ | No kind / content restriction; rate limits by pubkey and fresh keys |
| **relay.primal.net** (former default, dropped) | **GREY** (leans allowed) | none in NIP-11; company ToS primal.net/terms (Primal Systems Inc.) | frame 1 000 000, subs 20, NIP-40 ✓ | ToS covers "Services, including but not limited to" the apps; the relay isn't named. If it applies, it only forbids illegal / harmful content |
| **nostr.mom** (default since option C) | **ALLOWED** | NIP-11 `terms_of_service` → wikifreedia.xyz/nostr.mom | frame 131 072, subs 50, NIP-40 ✓ | **Same operator as nos.lol** (same NIP-11 pubkey `c5fadeb5…`, same wiki author); "stricter" spam + nudity filter |
| relay.nostr.net | GREY | none (description only, contact nostr.net = a link list) | frame 262 144, subs 100, `max_limit` 100, NIP-40 ✓ | "public relay operated by aljaz@nostr.si" |
| offchain.pub | GREY | none (description only) | frame 131 072, subs 20, NIP-40 ✓ | "public nostr relay running strfry"; same NIP-11 pubkey as nostr.bitcoiner.social |
| nostr.oxtr.dev | GREY | none (description is a motto) | frame 131 072, subs 40, NIP-40 ✓ | — |
| relay.nos.social | GREY | relay page only | frame 262 144, NIP-40 ✓ | "supports both reading and writing of notes … It is FREE to use" — social framing |
| relay.nostr.place | GREY | NIP-11 description only | frame 131 072, NIP-40 ✓ | "Public strfry instance, don't be a dick." — a one-liner, not terms |
| relay.snort.social | EXCLUDED (technical) | none | frame 524 288, `idle_timeout` 10, NIPs 1/9/11 only | "High-performance **in-memory** Nostr relay" (memlay): no NIP-40, no persistence promise |
| relay.nostr.band | EXCLUDED (unreachable) | — | — | No HTTP / NIP-11 answer on 2026-10-17 |
| nostr-pub.wellorder.net | EXCLUDED | NIP-11 description | — | "Relay for the (**NIP-05 verified**) Nostr community" — our keys are anonymous |
| relay.nostrcheck.me | EXCLUDED (limits) | ToS link (didn't load) | **`max_content_length` 8 196** | Content limit far below our snapshots |
| nostr.wine | EXCLUDED | nostr.wine/terms | `payment_required`, `restricted_writes` | Paid ("admission" 18 888 sats) |
| nostr.land | EXCLUDED | nostr.land/terms | `payment_required`, frame 65 535 | Paid; terms forbid "Storage of large non-Nostr blobs" |
| nostr21.com, theforest.nostr1.com | EXCLUDED | `#policy` | `payment_required` | Paid / community relay |

**Verbatim quotes**

- **relay.damus.io** — NIP-11 (https://relay.damus.io): `"description":"Damus strfry relay"`, `"contact":"jb55@jb55.com"`; no `terms_of_service`, `posting_policy` or `privacy_policy`. The relay's HTML page only says "Please use a Nostr client to connect." The only legal text found is the iOS app's EULA (https://github.com/damus-io/damus/blob/master/damus/Features/Onboarding/Views/EULAView.swift): *"This End User License Agreement ("EULA") is a legal agreement between you and Damus Nostr Inc. for the use of our mobile application Damus."* Its prohibited-content list ("discriminatory or promotes hate speech" …) is about the app and doesn't mention relays, kinds or encryption. → Terms are **silent** about the relay: GREY.
- **nos.lol** — NIP-11 (https://nos.lol): `"description":"Generally accepts notes, except spammy ones."`, `"terms_of_service":"https://wikifreedia.xyz/nos.lol/"`. The linked entry (https://wikifreedia.xyz/nos.lol/npub1nlk894teh248w2heuu0x8z6jjg2hyxkwdc8cxgrjtm9lnamlskcsghjm9c, published 2026-09-01, the only entry on that topic):
  > "Intended for end user and also high quality proxies, aggregators and blasters. It does rate limiting based on public key (npub). Counts the number of notes sent by a public key and if this number gets too high, first it will say it needs proof of work to accept the notes (practically rejecting). Then if the user continues to send events, it will silently reject. It doesn't like spammy, repetitive text. It will tell the user to slow down first and then after some point will stop responding. Does not currently do filtering of notes based on content. It doesn't like URLs and pictures from fresh public keys because these are main points of spam or NSFW. […] If a user or relay sends events with fresh public keys, it may switch to rate limiting based on IP. […] Only recent logs are kept on the server (A few gigabytes). Administration is done by a human and AI agents. If you worry about your IP leaking to AI companies, use a VPN. Please keep the relay clean, use ethically and responsibly."

  → No kind, content or encryption restriction; the rules are about volume and spam. We comply: a few replaceable events per hour per group, no URLs / pictures, content not repetitive text. **Caveats:** (1) every (device, group) key is a *fresh* public key, which the policy says may switch the relay to **IP-based rate limiting** — G51 E6 must measure it with several groups from one IP; (2) "notes" is used loosely for events (the text says "send events" in the same paragraph); (3) the terms are a wiki entry that the author can change at any time.
- **relay.primal.net** — NIP-11 (https://relay.primal.net): `"description":"Primal Public Relay"`, `"contact":"primal.net"`; no terms field. Company ToS (https://primal.net/terms, "LAST UPDATED FEBRUARY 19, 2024"; the page is client-rendered, text read from its bundle `assets/Terms-*.js`):
  > "This Agreement is between you and Primal Systems Inc., an Ontario corporation […], pertaining to your use of Primal's applications and services, including but not limited to the Primal web app, Primal iOS app, Primal Android app, Primal browser extension, Primal Premium Service, or Primal Hosted Wallet Service (collectively referred to as "Services")."

  > "Prohibited content: You agree not to use our Services to create, upload, post, send, store, or share any content that is illegal, infringing, fraudulent, harmful, threatening, abusive, hateful, harassing, defamatory, obscene, or invasive of another's privacy. […]"

  > "Content ownership: You retain all your ownership rights to the content you create. However, by submitting content to Primal, you hereby grant Primal Systems Inc. a worldwide, non-exclusive, royalty-free, sublicensable and transferable license to use, reproduce, distribute […] the content in connection with our Services […]"

  The Privacy Policy (https://primal.net/privacy, 2024-02-21) also scopes itself to "any Primal products and services, including but not limited to" the apps; it says nothing about the relay. → If the ToS covers the relay, nothing in it restricts encrypted app data. But it never names the relay and the relay's NIP-11 doesn't link it, so whether it applies is **ambiguous**: GREY (the mildest kind).
- **nostr.mom** — NIP-11 (https://nostr.mom): `"description":"Spam and nudity filtering. Stricter and more experimental than nos.lol."`, `"terms_of_service":"https://wikifreedia.xyz/nostr.mom/"`. Linked entry (same author as nos.lol): *"Most filtering and operation is similar to nos.lol. Filtering is a bit stricter. Read nos.lol wiki entry to learn more."* → ALLOWED on the same terms as nos.lol, with the same caveats. "Experimental" means acceptance can change more often.
- **relay.nos.social** — https://relay.nos.social: *"Relay.nos.social is a unique relay within the Nostr ecosystem that supports both reading and writing of notes as well as the functionality of the Tagr-bot. At a baseline all the users who subscribe to the wss://relay.nos.social can write to and read content from the relay. It is FREE to use."* → describes social notes and content moderation; silent on app data: GREY.
- **nostr.land** — https://nostr.land/terms: *"You may not use the Nostr.land services to store or disseminate following content: […] Storage of large non-Nostr blobs"*; NIP-11 `"payment_required":true`. → EXCLUDED (paid; also, an encrypted snapshot could be read as a "non-Nostr blob").
- **nostr.wine** — https://nostr.wine/terms: *"That some services, such as but not limited to the privilege to publish content may require payment(s)"*; NIP-11 `"payment_required":true,"restricted_writes":true`. → EXCLUDED (paid).
- **nostr-pub.wellorder.net** — NIP-11: `"description": "Relay for the (NIP-05 verified) Nostr community."` → EXCLUDED.

**Limits that matter for the budget (§5.4).** Of the ALLOWED relays, nos.lol and nostr.mom both advertise a **131 072-byte** frame. G51 E1 then measured the real cap: both refuse any **event over 65 536 bytes** (`invalid: event too large`), well below the frame. The budget is therefore **60 000 chars of `content`** (≈ 44 KB of gzip'd ciphertext; event ≈ 60 500 B, frame ≈ 60 510 B — §5.4, §16). Typical 200-record events (≈ 17 KB) are far below it. Every checked relay supports NIP-40. None publishes a retention period: nos.lol only says "Only recent logs are kept", which is about logs, not events. So retention stays a G51 E7 measurement.

**Result: the "no grey zone" condition failed for two of the three former defaults.** relay.damus.io has no published terms for the relay at all. relay.primal.net has only a company-wide ToS that doesn't name the relay. This was a stop point for Leo (§14 Q3/Q12), **resolved the same day with option C** (below). Only nos.lol and nostr.mom are ALLOWED, and they share **one operator**: one policy change or outage hits both. No free, independent third public relay was found whose terms allow (or even address) this use. The free relays either publish nothing or describe themselves for social "notes". The relays with real terms are paid or forbid blobs. **Three independent ALLOWED free relays are not available today.**

**Decided by Leo (2026-10-17): option C — defaults = nos.lol + nostr.mom only.** Both are ALLOWED; damus and primal are dropped as grey zone; there is no relay of our own. Users can add a custom relay (Settings → Relays), which is also the answer to the **single-operator risk**: both defaults have one operator, one terms page author and — measured in G51 — **one host** (both names resolve to 142.132.206.70, nginx in front of two separate strfry databases, §16). One policy change, ban or outage on that machine stops every link group that hasn't got a custom relay. Mitigations in G52: the relay settings show per-relay status ("rejects our events" / unreachable) and the group's sync cloud turns failing when 0 of N relays accept (§4.4), so the user sees it; a custom relay entered by any member keeps that member's devices syncing (others need it too — the link carries no relay hints, §14 Q3); and the default list can change with an app update (re-run this check then). A self-hosted relay (option A) stays the fallback if the operator ever objects.

The options as they were put to Leo (for the record):
- **Option A — strict (recommended if "no grey zone" is literal):** defaults = **nos.lol + nostr.mom + a relay Leo runs himself** (strfry, on his own server or a small VPS), with a published one-page policy that explicitly allows kind 31847 and states its limits and retention. The custom-relay setting stays. Costs: one more service to run and pay for, plus a legal / privacy role as operator (the relay sees IPs, so PRIVACY.md must name Leo as relay operator). It also weakens the "no MoneyLedger server" claim (welcome page 2, G39), so the wording must change to "an optional relay run by the developer, one of three". Damus and Primal are dropped.
- **Option B — no own server:** defaults = **nos.lol + nostr.mom + relay.primal.net**, if Leo accepts the reading that Primal's company ToS ("services, including but not limited to …") covers its "Primal Public Relay". Read that way, the ToS restricts only illegal / harmful content, and our use is allowed. Damus is dropped either way (it has no terms at all). The risk is that two of the three defaults have one operator, so G52's "rejects our events" status must cope with losing both at once.
- **Not recommended:** keeping damus (silent terms), any description-only relay (relay.nostr.net, offchain.pub, nostr.oxtr.dev, relay.nostr.place), or paid relays (users are anonymous, there is no payment flow).
- Whichever option is chosen: re-run this check before release and on every change to the default list. G52's NIP-11 discovery (§4.6) should store each relay's `terms_of_service` URL and show it in the relay settings.

- **Option C — chosen:** nos.lol + nostr.mom only, custom relay as the mitigation (above).

**Disclosure text (§9.2) with the chosen set (option C)** — see §9.2 for the final wording ("…two public Nostr relays, nos.lol and nostr.mom (one operator)…"). PRIVACY.md lists each default relay with its operator and terms URL: wikifreedia.xyz/nos.lol, wikifreedia.xyz/nostr.mom, and says that both run on one server of one operator. The "For relay operators" page stays: kind 31847, the `alt` tag, volume, and how to block.

## 10. Mixed groups, lock, and "Why Matrix" (G53, G54)

### 10.1 Mixed groups and lock (G53)

**Matrix → link ("Invite by link" in a Matrix group):**
1. Any active member writes a **signed meta** with `link: {epoch: n+1, secret}`. It replicates over Matrix (E2EE) and is published on the relay (encrypted).
2. Every Matrix device of the group that holds the meta creates `link_channels` (own Nostr key, `my_participant_id` = its claimed participant) and **bridges**: it publishes its snapshot and reads peers.
3. Unsigned versions are accepted (link path *and* Matrix relays of them) while `link` is set. They are stored unsigned, **never re-signed**, and shown "Via link · not verified".

**Matrix peers accepting relayed unsigned versions.** In a `mixed` group, `RecordGate` accepts an unsigned version relayed over Matrix by an active member. That relaxes "unsigned → refused" only while `link` is open.

**Link participant joins Matrix.** On *Connect a Matrix account* (G40 adoption) or sign-in, each mixed / link group gets a **signed claim** on `my_participant_id` (member version with `matrix_id` = MXID, `nextLwwClock`), published on both channels.

Peers accept it while the link is open under a narrowly scoped exception to "a non-member can never claim": the claimed participant must be unclaimed, the version must be signed by that MXID, and `link` must be set. From then on that user is a normal Matrix member: they receive replication and their device signs.

**Link → Matrix.** In a `linkOnly` group, the first signed member claim **plus a signed meta** (`link` kept) written by that Matrix device turns the group `mixed`. Policy is derived from the meta (§6.4).

**Lock** (⋮ → *Make group secure*). Enabled only when every **active** participant is claimed by a valid MXID; otherwise the menu lists who still needs to sign in. The device writing the lock:
1. writes a signed meta **without** `link` (with `locked_at` = its clock);
2. publishes a final header-only event `{locked: true}` with a short `expiration` + NIP-09 deletion;
3. drops `link_channels`.

After the lock:
- Every device that receives the signed meta drops its channel the same way.
- `RecordGate` refuses unsigned versions with `updated_at > locked_at` (`unsigned`, recorded, so there's no repair loop).
- Older unsigned versions stay as history ("via link").

**Link-only devices** see the `{locked}` event (or the signed meta in a snapshot): the group turns **read-only** with the banner "This group is now secure-only — sign in with Matrix to keep using it" and a *Connect account* button.

**Reopen** = a new epoch + a new secret, so the old link is useless. The flow is the same as "Invite by link".

**Leo's directions, both covered:** link → add Matrix → lock; Matrix → open link → lock again.

### 10.2 "Why Matrix instead of a link" (content of the G54 screen)

| | Link group | Matrix (secure mode) |
|---|---|---|
| Who can read / change | **Anyone who has the link** — forwarded, screenshotted, leaked | Only members you added; every change **signed** by the device that made it |
| Removing someone | Marks them removed, but they keep access until you **reset the link** and re-invite everyone | **Removal sticks**; their messages are ignored |
| "Added by / edited by" | A hint, not verified | Verified signatures (G6) |
| New phone / lost phone | Identity is the phone; needs the link (or a backup) again | Sign in → your other devices restore everything |
| Infrastructure | Public relays run by volunteers, no guarantees, terms not meant for this | A homeserver you choose (or run), with clear terms; Matrix is an open standard |
| Who sees metadata | Every relay: your IP, timing, group size | Only your own homeserver (who talks to whom) |
| Old data | A link leaked later decrypts archived copies | End-to-end encrypted to-device messages; the server keeps nothing |
| Size | ~5 000 records (~1 200 in a mixed group) | ~30k records, ~80 members |

**The cost:** an account at a Matrix homeserver (free, e.g. matrix.org) and a sign-in. For us there are also **two sync worlds** to maintain: twice the code paths and twice the test matrix. That is the honest reason the doc keeps Matrix as the "better" mode and doesn't build link groups into a second secure system.

### 10.3 The G54 screen and welcome reorder

**"Why Matrix?" page.** Welcome style: `_Hero` with the BrandLogo, 3 swipe pages. Tone: "There's another mode — also free, and it works even better. You just sign in."
- Page 1: "Links are easy" — what a link group does well.
- Page 2: the comparison above in plain sentences (who can read; removal; new phone; relays).
- Page 3: "Ready when you are" — *Connect a Matrix account* / *Not now*.

**Entry points:**
- ⋮ *Why Matrix?* in link groups;
- *How it works*;
- the first-use disclosure;
- **once** a dismissible card on the groups page after the first link group has ≥ 10 records (`AppSettings` `why_matrix_hint_dismissed`).

No other nudges.

**Welcome reorder.**
- **Choices:**
  1. **Start without an account** (primary; the G40 local setup, renamed);
  2. **Join with an invite link** (paste field; also auto-filled when the app was opened by a link);
  3. **Sign in with Matrix** / **Create a Matrix account** under a "Secure mode" subheading.
- **Explanation pages:** 1 what it does · 2 free + open source, no server of ours · 3 **"Share a group with a link"** (relays, encrypted, anyone with the link) · 4 "Want more security? Matrix" (short; links the G54 page). The current "What is Matrix" and "Who sees what" pages are merged into 3 and 4.
- **Onboarding** for local mode: "invite with a link" replaces "share later".

## 11. Dependencies

| Need | Package | License | Web | Notes |
|---|---|---|---|---|
| BIP-340 Schnorr sign / verify | **`bip340` 0.3.1** (fiatjaf) | MIT | yes | Tiny, depends on `pointycastle` + `crypto`. BigInt arithmetic, not constant-time — acceptable for per-group throwaway keys. G51: sign 18 ms / verify 12 ms native, **232 / 172 ms in dart2js** (Dart BigInt in JS) — see §16 for the consequence. |
| secp256k1 curve, key generation | **`pointycastle` 4.0.0** (Bouncy Castle) | MIT | yes | Widely used. Pubkey = x-only of `G·d`. |
| WebSocket | **`web_socket_channel` 3.0.3** (dart.dev) | BSD-3 | yes | Already transitive (matrix SDK). Becomes a direct dependency. |
| gzip on web | **`archive` 4.x** | MIT | yes | Direct dependency since G52 step 1 (was transitive). `dart:io` `gzip` on native would also work, but one code path is simpler. |
| HKDF, AES-GCM | `cryptography` 2.9 | Apache-2.0 | yes | Already direct (G34). |
| QR code | **`qr` 4.0.0** (+ our own painter) or `qr_flutter` 4.1.0 | BSD-3 | yes | `qr_flutter` is from 2023 → prefer `qr` plus a 30-line `CustomPainter`. |
| Share sheet | `share_plus` | BSD-3 | yes | Optional: *Copy* + QR work without it. |

**Rejected:**
- `nostr` 2.0 (LGPL-3.0: compatible, but it brings `elliptic`, `bech32` and `http` we don't need);
- `dart_nostr` 10.x (MIT, **no web platform tag**, BIP-39/32 deps);
- `ndk` 0.10 (MIT, large: sembast, rxdart, a Rust toolchain via `native_toolchain_rust`, CBOR);
- `nostr_core_dart` (LGPL, unmaintained since 2023).

NIP-01 client-side is ~400 lines (event serialization, id, sign / verify, frames), which is less risk than a framework.

All recommended licenses (MIT, BSD-3, Apache-2.0) are AGPL-3.0-or-later-compatible. Add them to `THIRD_PARTY_NOTICES.md`.

## 12. G51 — Spike plan

A separate Dart package `tool/spike/nostr/` (like `tool/bench/`, never part of the app) using exactly the recommended deps. It runs as two processes on two networks (laptop + Pixel via `dart compile exe`, or Termux) against the default relays — after Leo's 2026-10-17 decision only **nos.lol and nostr.mom** (§9.4 option C). A Flutter web build of the same code checks browser WebSockets and the BIP-340 speed of dart2js. (As run in G51: laptop only, two processes on one network; the Pixel, the second network, browser WebSockets and E9 moved to the G52 device pass — §16.)

| # | Experiment | Pass criterion |
|---|---|---|
| E1 | Publish kind 31847 events with random content of 10 / 50 / 100 / ~125 KB **frames** (only up to the advertised 131 072-byte limit; expiration +10 min, then a NIP-09 deletion); record `OK` + message per relay | both relays accept **100 KB** custom-kind events; rejections come with a readable `OK false` prefix |
| E2 | Addressable semantics: v1 then v2 (same d, +1 s); same-second v2; a REQ returns only the newest | Only the newest returned on every accepting relay |
| E3 | Cross-author `#d` filter: 3 pubkeys, same d | All 3 returned, nothing else |
| E4 | Live latency: B subscribed, A publishes 50× (every 10 s) | p50 < 1.5 s, p95 < 5 s on ≥ 2 relays |
| E5 | Full fetch: connect → EOSE time for 1 topic with 5 events | < 3 s p95 |
| E6 | ~~Rate limit: 30 publishes in 60 s~~ (no hammering, Leo's condition): 6 events from 6 fresh keys (= 6 groups from one IP) at our pace, ≥ 5 s apart | No `rate-limited` at our pace; note any |
| E7 | Retention: events with `expiration` +30 d fetched at 1 h, 1 d, 3 d, 7 d, 14 d; one with +10 min | 30-d event present at 7 d on ≥ 2 relays; the 10-min one gone (or at least not served) |
| E8 | Crypto cost: HKDF + gzip + AES-GCM + base64 for a 200-record snapshot; BIP-340 sign + verify; on the Pixel (AOT) and in Chrome (dart2js) | Pack + sign ≤ 100 ms native, ≤ 500 ms web; verify 20 events ≤ 1 s web |
| E9 | Background: an Android WorkManager one-off with one WebSocket fetch + publish (the G36 debug trigger) | Works headless within 20 s |
| E10 | NIP-11 of the default relays (+ alternates) | Recorded in §9.4 / §4.6 |

**Output:** a short report with numbers, chosen budget, chosen default relays, and a go / no-go for G52 — **§16**.

**No-go triggers:**
- < 2 relays accept 100 KB → lower the budget, or shard by default at 40 KB;
- custom kinds blocked;
- retention < 3 days.

## 13. Implementation breakdown

Each step is a commit with tests. The fakes come first.

**G52 — link groups**
1. **Pure codec + crypto** (`lib/core/link/`): link URI build / parse (versions, bad input), HKDF derivation (fixed test vectors), envelope pack / unpack (AAD binding, tamper → error), sharding plan. Unit tests.
2. **Mini Nostr client:** event serialize / id / sign / verify (BIP-340 test vectors + NIP-01 id vectors), frame codec, `RelayConnection` port + WebSocket adapter, `NostrRelayPool` (publish → per-relay OK, subscribe, fetchOnce, backoff). `test/helpers/fake_relay_network.dart` with addressable semantics, limits, injected failures, `settle()`.
3. **Schema v15** (`link_channels`, `link_peers`, `link_author` columns) + `LinkDao` + migration test.
4. **Policy:** `GroupPolicy` derived from meta; `RecordGate` link path (§6.4); `currentParticipant` fallback; `SyncEngine` / `LedgerSyncer` skip `linkOnly`; `signPendingRows` / adoption skip link groups. Unit tests for each rule (accept unsigned, refuse bad signature, invalid content, wrong group, future clock, claim refused in `linkOnly`).
5. **`LinkSyncEngine`:** open channel (rewrite the `local:self` claim), debounced publish, monotonic `created_at`, change detection, refresh, live subscription, merge, `link_peers`, sync status. Integration tests with 2–3 fake devices: concurrent edits, tombstones, an offline device catching up, a stale publisher, sharding up and down, one relay rejecting / rate-limiting, a G19 account switch mid-publish.
6. **Invite UI:** sheet, QR, share / copy, first-use disclosure, empty-group CTA. Widget tests (EN+DE).
7. **Join:** intent filters + App Link, `/join` route, paste field, `JoinLinkPage` (fetch, picker, implicit local profile, nothing-found), router tests.
8. **Background round:** link phase; schedule in local mode when link groups exist. `background_round_test` with the fake relay.
9. **Settings:** relay list (+ NIP-11 check), status; link group sync icon + peers sheet.
10. **Leave / delete / Delete local data** unpublish; backup carries the secret + preview warning; *Rejoin link* after a restore.
11. **Docs:** PRIVACY.md + `privacy*` keys, CLAUDE.md architecture section, THIRD_PARTY_NOTICES, README, `docs/smoke-test.md` (two-device link pass), landing page `join.html` + `assetlinks.json` (user-site repo), offline demo seed with one link group (`FakeRelayNetwork`-backed demo transport).
12. **Reset invite link** (new secret + epoch, empty the old topic; the new link is shared directly with the remaining people — §7.3, §14 Q10).
13. **Device pass** (Pixel + emulator + web): create → invite via QR → join → edit both sides → background round → leave.

**G53 — mixed + lock**
1. Meta `link` field (signed, hashed only when set) + policy `mixed`; Matrix path accepts unsigned versions in mixed groups; attribution "via link".
2. *Invite by link* in Matrix groups; Matrix devices bridge (channel per device from meta).
3. Signed self-claim of a link participant (scoped exception) + adoption hook for link groups.
4. Lock: eligibility, signed meta, final event, channel drop, refusal of later unsigned versions, read-only banner on link-only devices; reopen. Integration test across a fake relay + `FakeMatrixNetwork` (link → Matrix → lock, Matrix → link → lock → reopen).
5. Docs + smoke test.

**G54 — "Why Matrix?" + welcome**
1. `WhyMatrixPage` (3 pages, EN+DE) + entry points + the one-time hint.
2. Welcome choices + pages reordered, paste-link choice, onboarding texts; router tests; screenshots updated.

## 14. Risks and open questions for Leo

**Risks**
- **Relay policy can change at any time.** Custom kinds or blobs may get blocked. Mitigations: custom relay, NIP-11 checks, clear "rejects our events" status. **Single operator:** both defaults (nos.lol, nostr.mom) have one operator and run on one host (§9.4, §16), so one decision or outage blocks both at once; a new default list then needs an app update, and until then only groups whose members added a custom relay keep syncing.
- **Leaked links.** People will forward them. The UI must say what a link means at the point of sharing.
- **Two sync worlds:** more code, more tests, more support. Mixed groups (G53) are the most complex part. Its scoped exceptions in the gate need a security review like G18.
- **"Pure link groups can't go wrong" isn't true.** A malicious link holder can wipe the group (tombstones). G48 restore points and *Reset group* are the recovery path, and the doc should say so in the invite sheet's help.
- **Battery / data** for live WebSockets is small (idle sockets) but needs a check in the device pass.

**Open questions — decided by Leo on 2026-10-17**
1. **App key (W5):** → **Public salt** `kLinkSaltV1` (no secret key; §3.4).
2. **Event kind:** → **`31847`**; registering it in the NIPs repo is optional, later.
3. **Default relays:** → originally damus, nos.lol, primal. **G51 terms check (§9.4): damus and primal are GREY → Leo decided option C on 2026-10-17: defaults = `nos.lol` + `nostr.mom` only**, every event to both; **no** `r=` relay hints in v1; a custom relay is an expert setting and the mitigation for the single-operator risk. Size consequence: `kLinkContentBudget` = 60 000 chars (both refuse events > 65 536 B, §5.4 / §16).
4. **Group name hint `n=`:** → **Yes.**
5. **Landing page + App Links:** → **Yes**, as a `LeoStumpf.github.io` user-site repo **shared by all of Leo's apps** (per-app path `/moneyledger/…`, one `assetlinks.json` with a statement per package). Created in G52 once the link handler exists.
6. **In-app QR scanner:** → **No**; the system camera opens the link.
7. **Secret in backups:** → **Yes**, with the preview warning.
8. **`by` author hint:** → **Yes.**
9. **Channel opens only on the first invite:** → **Yes.**
10. **Reset invite link:** → **In the first version (G52)**, new link shared directly with the remaining people (§7.3).
11. **Web app:** → **Yes**, same code, live only while the tab is open.
12. **Ask relay operators:** → **No.** Disclosure in the app + the "For relay operators" page; **condition: no grey zone** — G51 checks each relay's terms first (§9.3), a relay that excludes this use is replaced; self-hosted relay as the fallback. **Result: see §9.4** (only nos.lol + nostr.mom, one operator, are ALLOWED).
13. **Matrix users' new groups:** → stay `matrix` groups; *Invite by link* opens a mixed channel (G53).
14. **Expiry:** → **30 days, refreshed after 10 days of age** (changed from the proposed 60 / 20).

## 15. Sources

- NIP-01 (kinds ranges, addressable semantics, tie-break, `#d` filters, OK prefixes): https://github.com/nostr-protocol/nips/blob/master/01.md
- NIP-11 (relay information document, `limitation` fields): https://github.com/nostr-protocol/nips/blob/master/11.md
- NIP-40 (expiration; "SHOULD delete", "MAY persist", not a security feature): https://github.com/nostr-protocol/nips/blob/master/40.md
- NIP-78 (app-specific data, kind 30078, author-only via NIP-42): https://github.com/nostr-protocol/nips/blob/master/78.md
- NIP-31 (`alt` tag), NIP-70 (protected events), NIP-09 (deletion), kind registry: https://github.com/nostr-protocol/nips (README kinds table, read 2026-10-17)
- Relay NIP-11 documents fetched 2026-10-17: `https://relay.damus.io`, `https://nos.lol`, `https://relay.primal.net`, `https://nostr.mom` (`Accept: application/nostr+json`)
- G51 spike code + raw results: `tool/spike/nostr/` (`results/*.jsonl`, `retention_ids.json`)
- BIP-340: https://github.com/bitcoin/bips/blob/master/bip-0340.mediawiki
- pub.dev API (versions, licenses, platforms, 2026-10-17): `bip340`, `pointycastle`, `web_socket_channel`, `archive`, `qr`, `qr_flutter`, `nostr`, `dart_nostr`, `ndk`, `nostr_core_dart`, `mobile_scanner`
- GPLv3 §1 / §6 text: repo `LICENSE` (AGPL-3.0)

## 16. G51 spike results (2026-10-17)

**Setup.** `tool/spike/nostr/` — a standalone Dart package (own `pubspec.yaml`, never imported by the app) with the §11 deps: `bip340` 0.3.1 (MIT), `pointycastle` 4.0.0 (MIT), `cryptography` 2.9.0 (Apache-2.0), `web_socket_channel` 3.0.3 (BSD-3), `archive` 4.5.2 (MIT; pulls in `posix` 6.5.2, MIT), `crypto` 3.0.7 (BSD-3) — all AGPL-compatible. `lib/link_crypto.dart` (pure Dart, also compiles with dart2js): HKDF topic / key with the public `kLinkSaltV1` (§3.1), gzip + AES-256-GCM envelope with the §3.2 AAD, NIP-01 id + BIP-340 sign / verify (BIP-340 test vector 0 passes), NIP-09 deletion; `lib/relay.dart`: one WebSocket per relay, `EVENT`/`OK`, `REQ`/`EOSE`/`CLOSE`, live subscriptions. `bin/selftest.dart` checks the crypto offline. Raw results: `results/*.jsonl`, `results/e8_*.json`.

**Politeness (Leo's condition).** Only nos.lol and nostr.mom; synthetic data encrypted under throwaway secrets, never real data; every test event carried `expiration` = now + 10 min (except one E7 probe, +30 d); E1–E4 published NIP-09 deletions afterwards (`OK true`, the deleted ids weren't served any more 2 s later); ≥ 5 s between publishes per key; no burst / rate-limit hammering. Total ≈ 55 events from ≈ 13 keys per relay over ~15 minutes, < 1 MB per relay.

**Network facts.** nos.lol and nostr.mom resolve to the **same IP (142.132.206.70)**, nginx in front, both strfry 1.1.3 — but they are **separate databases**: an event published only to nos.lol was not served by nostr.mom 10 s later (E6). So the two defaults give storage redundancy but **no host / operator redundancy** (§9.4).

### Results

| # | Experiment (as run) | nos.lol | nostr.mom | Criterion |
|---|---|---|---|---|
| E1 | kind 31847, frames 10 000 / 50 000 / 65 529 / 65 561 / 100 001 / 125 001 / 130 001 B | 10 k, 50 k, 65 529 ✓ (`OK true`, stored + served); ≥ 65 561 ✗ `invalid: event too large: <event bytes>` | same | **fails "100 KB"** → budget lowered (below) |
| E1 | effective limit | event JSON ≤ **65 536 B** (65 519 ✓, 65 551 ✗) — NIP-11 says only `max_message_length` 131 072 | same | readable prefix ✓ |
| E2 | addressable replace: v1 → v2 (+1 s); same-second pairs in both orders; older `created_at` after newer | only newest served ✓; same second → **lowest id** kept ✓ (the higher id gets `OK false "replaced: have newer event"`); an older event → same `replaced:` | same | ✓ |
| E3 | 3 fresh keys, one `d`, `#d` filter | 3 events, 3 authors, all verify + decrypt, nothing else ✓ | same | ✓ |
| E4 | live: subscriber + publisher (2 processes, laptop), 20 publishes every 10 s (one address, replaced each time), ~1.2 KB frames | delivery p50 **137 ms**, p95 **193 ms** (max 223); `OK` p50 47 ms | p50 **145 ms**, p95 **182 ms** (max 221); `OK` p50 45 ms | p50 < 1.5 s, p95 < 5 s ✓ |
| E5 | fresh connection → `REQ` 2 topics (4 events) → `EOSE`, 10 runs | connect 105–119 ms, REQ→EOSE 35–95 ms, total p50 147 / max 206 ms | connect 105–110 ms, REQ→EOSE 35–38 ms, total p50 144 / max 148 ms | < 3 s p95 ✓ |
| E6 | 6 fresh keys (= 6 groups from one IP), one 4.8 KB event each, 6 s apart, both relays | 6/6 `OK true`, no `rate-limited`, no NOTICE | 6/6 `OK true`, no `rate-limited` | ✓ (at our pace; the whole spike — ≈ 55 events from ≈ 13 fresh keys per relay in 15 min — never triggered a limit) |
| E7 | retention probes published 08:42:44 UTC (+30 d and +10 min), see below | +0 h both served; **+15 min and +1 h: 30-d served, 10-min probe gone** (NIP-40 honoured) | same | 30-d probe at 7 d — **pending** |
| E8 | crypto, 200-record snapshot (synthetic bootstrap shape, unsigned, 98 553 B JSON) | see next table | | |
| E9 | Android headless round | **skipped — covered by the G52 device pass** | | |
| E10 | NIP-11 | §4.6 / §9.4 | | ✓ |

**E8 — crypto cost** (median of 15 after a warm-up; laptop i7-8550U; native = `dart compile exe`, web = `dart compile js -O2` run in node 20 / V8 — Chrome's engine, but not a browser):

| Step | native (AOT) | dart2js (node) | Criterion |
|---|---|---|---|
| HKDF (topic + key) | 0.06 ms | 1 ms | |
| JSON encode | 1.5 ms | 3 ms | |
| pack: gzip + AES-GCM + base64 | 2.5 ms | 15 ms | |
| NIP-01 id + BIP-340 sign | 18 ms | 228–232 ms | |
| **pack + sign** | **22 ms** | **246–250 ms** | ≤ 100 ms native ✓, ≤ 500 ms web ✓ |
| verify 1 event | 12 ms | 159–172 ms | |
| **verify 20 events** | 245 ms | **4.9 s** | ≤ 1 s web **✗** |
| unpack: base64 + GCM + gunzip + JSON | 2.2 ms | 7 ms | |
| content size, 200 unsigned records | 17 330 chars | 17 822 chars (pure-Dart deflate) | |
| content size, 200 signed records (mixed) | 76 458 chars | 76 978 chars | |
| content size, 500 / 1 000 unsigned | 41 098 / 80 570 chars | 42 386 / 83 198 chars | |

The web cost is all BIP-340: `bip340` does its curve math with Dart `BigInt`, which dart2js implements in Dart rather than with JS `BigInt`. Everything else is fast enough everywhere.

### Chosen content budget

**`kLinkContentBudget` = 60 000 chars of `content`** (was 100 000). The binding limit is not the advertised 131 072-byte frame but strfry's **65 536-byte event** cap (event JSON = frame − 10 bytes for `["EVENT",…]`). Our envelope is ≈ 490 B, so a 60 000-char event is ≈ 60 500 B (frame ≈ 60 510 B): ~5 KB headroom. Consequences (§5.4): 200 unsigned records = 17 K (one part, 29 % of the budget); a part holds ≈ 690 unsigned records → ceiling ≈ 5 000 with 8 parts; a **mixed** group needs 2 parts already at 200 signed records and tops out at ≈ 1 200 signed records.

### Go / no-go for G52 (§12 triggers)

- *< 2 relays accept 100 KB* → **triggered** (both cap at 65 536 B). §12's own remedy applies: lower the budget (60 000) and shard; the typical group is 3× below it. Not a blocker.
- *Custom kinds blocked* → **not triggered** (31847 accepted, stored, served, replaced and deleted as specified on both).
- *Retention < 3 days* → **open** until the E7 check at +3 d (2026-10-20).

**Verdict: GO for G52** — with the 60 000-char budget, `replaced:` handled as in §4.4, and the web signature-verify decision below. **Condition:** the E7 check on 2026-10-20 (+3 d) must show the 30-day probe still served on both relays; if it's gone on both, stop before G52's sync engine (step 5) and revisit (shorter refresh interval than 10 days, or a self-hosted relay). The 7-d / 14-d checks only tune the refresh interval.

### E7 follow-up

Probes (one throwaway key `8083fed6…`, two `d` tags, same events on both relays) are listed in `tool/spike/nostr/retention_ids.json`. Check (read-only, nothing is published; appends to `results/retention.jsonl`):

```
cd tool/spike/nostr && dart run bin/check_retention.dart
```

| When | Date (UTC) | Expect |
|---|---|---|
| +1 h | 2026-10-17 ≥ 09:43 | 30-d served; 10-min probe gone (expired 08:52:44) — **done: as expected on both** (also at +15 min) |
| +1 d | 2026-10-18 ≥ 08:43 | 30-d served |
| **+3 d (gate)** | **2026-10-20 ≥ 08:43** | 30-d served on both → retention criterion passed |
| +7 d | 2026-10-24 ≥ 08:43 | 30-d served on ≥ 1 relay (§12 E7 criterion: on both) |
| +14 d | 2026-10-31 ≥ 08:43 | informational (the 10-day refresh keeps real groups fresh) |
| +31 d | 2026-11-17 | 30-d probe gone (NIP-40 honoured) |

### Open points

1. **Two networks / Pixel / browser.** E4 ran with both processes on this laptop (one IP, one network); E8 web ran in node, not Chrome; E9 (headless Android) was skipped. All three move to the **G52 device pass** (§13 step 13): Pixel ↔ emulator/laptop over different networks, the web build in Chrome (browser WebSockets, real dart2js timing), and a WorkManager round with one fetch + publish.
2. **Signature verify on the web** (E8 ✗): 160–170 ms per event. **Decided by Leo (2026-10-17):** G52 verifies BIP-340 **on native only**; on the web it skips the check and relies on the AES-GCM AAD (binds content to kind / topic / pubkey — a forger needs the link secret, and then could just sign with its own key) plus the relays' own verification. Alternatives if Leo wants verify everywhere: verify only new events (dedup via `link_peers` first — a normal fetch then has 0–3 new events), or a faster secp256k1 on web (JS-`BigInt` implementation / WebCrypto doesn't do secp256k1). Signing (≈ 230 ms per publish, debounced) is acceptable as is.
3. **`replaced: have newer event`** is an `OK false` that isn't a failure (E2) — added to §4.4; G52's `FakeRelayNetwork` must emit it for the same-second-higher-id and older-`created_at` cases.
4. **NIP-11 doesn't advertise the 65 536-byte event cap.** For custom relays G52 can't learn it either; it uses the same 60 000 budget and drops to the custom relay's advertised `max_message_length` / `max_content_length` when smaller.
5. **Single host.** nos.lol and nostr.mom are one machine (separate databases). The custom-relay setting is the only mitigation in v1; re-check the defaults before release (§9.4).
6. **Third-party notices.** Not changed in G51: the spike isn't shipped. G52 adds `bip340`, `pointycastle`, `web_socket_channel`, `archive` (+ its `posix`) to `THIRD_PARTY_NOTICES.md` when they become app dependencies (`cryptography` is already listed).
