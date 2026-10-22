import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'daos/expenses_dao.dart' show backfillVersionHashes;
import 'daos/history_dao.dart' show backfillRecordHistory;

part 'app_database.g.dart';

class Groups extends Table {
  TextColumn get roomId => text()();
  TextColumn get name => text()();
  TextColumn get currency => text().withDefault(const Constant('EUR'))();
  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0))(); // ms epoch, LWW clock
  // G6: signature of this meta version (JSON, wire `sig`), NULL = legacy.
  TextColumn get sig => text().nullable()();
  // G6: written while the signer wasn't ready; signed before it's sent.
  BoolColumn get pendingSign => boolean().withDefault(const Constant(false))();
  // G47: the group's custom expense categories (JSON list, the wire
  // `categories` verbatim); NULL = none. Part of the signed meta when set.
  TextColumn get categoriesJson => text().nullable()();
  // G52: the writer's link-group participant (wire `by`) — see
  // Expenses.linkAuthor.
  TextColumn get linkAuthor => text().nullable()();
  // G53: the open invite link of a mixed group (wire `link: {epoch,
  // secret}`, signed meta only) — both NULL = no link. The secret is a
  // **secret**: never log it.
  IntColumn get linkEpoch => integer().nullable()();
  TextColumn get linkSecret => text().nullable()();
  // G53: when the group was locked (wire `locked_at`, ms); NULL = never.
  IntColumn get lockedAt => integer().nullable()();
  // G73: the fixed exchange rates (JSON, the wire `exchange_rates`
  // verbatim); NULL = none. Part of the signed meta when set.
  TextColumn get exchangeRatesJson => text().nullable()();
  // G57 (C1): the per-field clocks below `updated_at` (JSON object, the
  // wire `clocks` verbatim); NULL = none (every field at `updated_at`).
  TextColumn get fieldClocksJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {roomId};
}

class Expenses extends Table {
  TextColumn get id => text()(); // UUIDv7
  TextColumn get roomId => text()();
  TextColumn get matrixEventId => text().nullable()();
  TextColumn get description => text()();
  IntColumn get amountCents => integer()();
  TextColumn get currency => text()();
  TextColumn get paidBy => text()(); // Matrix user ID (@user:server)
  TextColumn get splitsJson => text()(); // JSON: {"@user:server": cents}
  IntColumn get createdAt => integer()(); // ms epoch
  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0))(); // ms epoch, LWW clock
  // Tombstone: deleted records are kept forever so anti-entropy can never
  // resurrect them on another device.
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  // G6: this version's signature + the creator's signed origin (JSON, the
  // wire `sig` / `origin` objects verbatim); NULL = legacy (pre-G6) row.
  TextColumn get sig => text().nullable()();
  TextColumn get origin => text().nullable()();
  BoolColumn get pendingSign => boolean().withDefault(const Constant(false))();
  // G16: optional category (stable wire id, `expense_category.dart`) and
  // free-text note; NULL = none. Part of the signed content when set.
  TextColumn get category => text().nullable()();
  TextColumn get note => text().nullable()();
  // G49: the day the expense happened (ISO `YYYY-MM-DD`, wire `date`);
  // NULL = the day of `created_at`. Part of the signed content when set.
  TextColumn get expenseDate => text().nullable()();
  // G37: cached G27 content hash (SHA-256 hex of the canonical content),
  // written by the DAO's LWW upsert; NULL = compute on demand.
  TextColumn get versionHash => text().nullable()();
  // G52: author hint of a version written in a link group — the writer's
  // `link_channels.my_participant_id` (wire `by`). Unsigned, display-only
  // ("Changed by Ben, via link"), **not** part of the signed body or the
  // G27 hash; NULL = none.
  TextColumn get linkAuthor => text().nullable()();
  // G76: who paid how much when several people paid (JSON, the wire
  // `payers` verbatim; `paid_by` is then ''); NULL = `paid_by` paid it
  // all. Part of the signed content when set.
  TextColumn get payersJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Settlements extends Table {
  TextColumn get id => text()(); // UUIDv7
  TextColumn get roomId => text()();
  TextColumn get matrixEventId => text().nullable()();
  IntColumn get amountCents => integer()();
  TextColumn get currency => text()();
  TextColumn get fromUser => text()();
  TextColumn get toUser => text()();
  IntColumn get createdAt => integer()(); // ms epoch
  IntColumn get updatedAt =>
      integer().withDefault(const Constant(0))(); // ms epoch, LWW clock
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  // G6 — see Expenses.
  TextColumn get sig => text().nullable()();
  TextColumn get origin => text().nullable()();
  BoolColumn get pendingSign => boolean().withDefault(const Constant(false))();
  // G60: the day the payment happened (ISO `YYYY-MM-DD`, wire `date`) —
  // see Expenses.expenseDate.
  TextColumn get settlementDate => text().nullable()();
  // G37 — see Expenses.versionHash.
  TextColumn get versionHash => text().nullable()();
  // G52 — see Expenses.linkAuthor.
  TextColumn get linkAuthor => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Group membership / participants, owned locally and replicated peer-to-peer
/// (Phase B roomless; virtual users in this phase). [groupId] is the local group
/// id (the Groups.roomId value). [status] is `active` or `removed`; [updatedAt]
/// is a logical clock used for last-writer-wins so concurrent add/remove of the
/// same participant resolves deterministically.
///
/// [userId] is the **stable participant id** — a per-group identity that is NOT
/// necessarily a Matrix ID. For participants migrated from before virtual users
/// (and for participants created from a real account) it equals the MXID; for a
/// Tricount-style local participant it is a fresh UUID. The Matrix account a
/// participant is "claimed" by, if any, lives in [matrixId] (null = pure-local).
/// Replication targets only participants with a non-null [matrixId].
class Members extends Table {
  TextColumn get groupId => text()();
  TextColumn get userId => text()(); // stable participant id (see class doc)
  TextColumn get displayName => text().withDefault(const Constant(''))();
  TextColumn get matrixId => text().nullable()(); // claimed account, or null
  TextColumn get status => text().withDefault(const Constant('active'))();
  IntColumn get updatedAt => integer()(); // ms epoch, LWW clock
  // G6 — see Groups.
  TextColumn get sig => text().nullable()();
  BoolColumn get pendingSign => boolean().withDefault(const Constant(false))();
  // G52 — see Expenses.linkAuthor.
  TextColumn get linkAuthor => text().nullable()();
  // G74: the participant's own payment details (JSON, the wire `payment`
  // verbatim); NULL = none. Part of the signed member version when set.
  TextColumn get paymentJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {groupId, userId};
}

/// G52: this device's **link channel** of a link group (no-login sharing
/// over Nostr relays, `docs/design/no-login-sharing.md` §7.1) — at most one
/// per group. Device-local, per ledger DB; never synced, never in a backup
/// file (the secret travels in the group meta, §7.2) and dropped with the
/// group ([AppDatabase.purgeGroup]).
///
/// **Secrets:** [secret] (the link secret = the group's read / write key)
/// and [nostrPriv] (this device's per-group Nostr signing key) live here,
/// protected like the Matrix session and the ledger itself (app-private
/// storage, Android backup off — G32). Never log them.
class LinkChannels extends Table {
  TextColumn get groupId => text()();

  /// Key epoch of [secret] (a *Reset invite link* starts a new one).
  IntColumn get epoch => integer()();

  /// The link secret (32 bytes, base64url without padding — the link's `k`):
  /// a cache of the meta's `link.secret` for [epoch].
  TextColumn get secret => text()();

  /// Who this device is in the group ("Which participant are you?"); NULL
  /// until picked. Device-local — never a synced claim (§6.1).
  TextColumn get myParticipantId => text().nullable()();

  /// This device's secp256k1 Nostr private key for this group (64 hex
  /// chars) — random per (device, group), not derived from [secret] (§3.1).
  TextColumn get nostrPriv => text()();

  /// Change detection: digest of the snapshot we last published (NULL =
  /// nothing published yet).
  TextColumn get lastPublishedHash => text().nullable()();

  /// When we last published (ms epoch, our clock; 0 = never) — drives the
  /// 10-day refresh.
  IntColumn get lastPublishedAt => integer().withDefault(const Constant(0))();

  /// The Nostr `created_at` (**seconds**) of our latest event — kept
  /// strictly increasing per (pubkey, d) (§4.5; 0 = none yet).
  IntColumn get lastCreatedAt => integer().withDefault(const Constant(0))();

  /// How many parts our last snapshot was sharded into (1, 2, 4 or 8, §5.4)
  /// — needed to retire parts when the count shrinks.
  IntColumn get parts => integer().withDefault(const Constant(1))();

  /// When this device opened / joined the channel (ms epoch).
  IntColumn get openedAt => integer()();

  @override
  Set<Column> get primaryKey => {groupId};
}

/// G52: every other publisher (Nostr pubkey) seen on a link group's channel
/// — dedup of processed events and the per-peer sync detail (§4.3, §5.3).
/// Device-local, dropped with the group / its channel.
class LinkPeers extends Table {
  TextColumn get groupId => text()();

  /// The publisher's Nostr pubkey (x-only, 64 hex chars).
  TextColumn get pubkey => text()();

  /// The participant the publisher's latest event names as its `me` — a
  /// hint only ("used on another phone"); NULL = none.
  TextColumn get me => text().nullable()();

  /// The id of the latest event processed **per part** (JSON object
  /// `{"<part index>": "<event id>"}`): a sharded snapshot is several
  /// events, each skipped before decrypting once seen.
  TextColumn get eventIdsJson => text().withDefault(const Constant('{}'))();

  /// Newest Nostr `created_at` (seconds) seen from this publisher (any part)
  /// — the base of the live subscription's `since`.
  IntColumn get lastCreatedAt => integer().withDefault(const Constant(0))();

  /// When this device last received an event of it (ms epoch, our clock) —
  /// "Ben's phone last published …".
  IntColumn get lastSeenAt => integer().withDefault(const Constant(0))();

  /// Digest of the publisher's snapshot as last merged (to compare with
  /// ours: "Ben has everything", §5.3); NULL = unknown.
  TextColumn get snapshotDigest => text().nullable()();

  /// G53 round 3 (Leo 2026-10-22, decision 6): when this device learned
  /// that the publisher deleted its copy of the group (its "left" header
  /// parts, ms epoch, our clock); NULL = still has it. The row is kept so
  /// the sync sheet says "Deleted the group" instead of dropping the
  /// person; a newer ordinary event of that publisher clears it.
  IntColumn get leftAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {groupId, pubkey};
}

/// G6: every (user, device) → Ed25519 key binding this device has seen —
/// **first-hand** from the homeserver's device list (`source = 'server'`,
/// incl. our own device) or vouched for by a trusted snapshot sender
/// (`source = 'attested'`, [attestedBy] = that sender's MXID). Kept after the
/// device signs out, so records it signed stay verifiable. Device-local trust,
/// per account; never synced and not purged with a group.
///
/// G18 review: an attestation is **scoped to the group** whose snapshot
/// carried it ([attestedGroup]) and only vouches for that group's records;
/// first-hand pins have `attested_group = ''` (valid everywhere).
class KnownDeviceKeys extends Table {
  TextColumn get userId => text()();
  TextColumn get deviceId => text()();
  TextColumn get ed25519Key => text()();
  TextColumn get source => text()(); // 'server' | 'attested'
  TextColumn get attestedBy => text().nullable()();
  IntColumn get firstSeenAt => integer()();
  TextColumn get attestedGroup => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {userId, deviceId, ed25519Key, attestedGroup};
}

/// G6: inbound record versions this device refused (bad / missing signature,
/// key conflict, changed origin, invalid content). [updatedAt] + [versionHash]
/// identify the refused **version** (G18 review: a refusal blocks exactly that
/// version, never other versions of the record). G18 review 2 (schema v10):
/// a small set per record — the version is part of the primary key and the
/// `kMaxRefusedVersionsPerRecord` highest refused versions are kept. Advertised in our digests (`rejected`) so peers stop re-sending
/// them (no repair loop). [kind] is `expense` / `settlement` / `member` /
/// `meta` ([recordId] = group id for meta).
class RejectedVersions extends Table {
  TextColumn get groupId => text()();
  TextColumn get kind => text()();
  TextColumn get recordId => text()();
  IntColumn get updatedAt => integer()();
  TextColumn get reason => text()();
  TextColumn get relayedBy => text()();
  TextColumn get claimedSigner => text().nullable()();
  IntColumn get rejectedAt => integer()();

  /// The G27 content hash of the refused version ('' = unknown: a refusal
  /// recorded before schema v9 — matches any version at [updatedAt]).
  TextColumn get versionHash => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {
    groupId,
    kind,
    recordId,
    updatedAt,
    versionHash,
  };
}

/// Per-peer sync bookkeeping for the anti-entropy digest exchange (Phase C).
/// [lastInSyncAt] is the last time a digest from [userId] matched our local
/// state exactly for [groupId]; it backs the sync-status UI.
class PeerSyncStates extends Table {
  TextColumn get groupId => text()();
  TextColumn get userId => text()(); // Matrix ID (@user:server)
  IntColumn get lastInSyncAt => integer().withDefault(const Constant(0))();
  IntColumn get lastDigestSentAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {groupId, userId};
}

/// G48: the device-local version history of every ledger record — each
/// version a DAO's LWW upsert actually **stored** (a new or different
/// version, local or inbound), with the full payload as stored (signatures
/// included). Backs "Reset group to an earlier state" (`group_reset.dart`).
/// Never synced, never in a backup / digest; pruned by
/// `HistoryDao.prune` (90 days + row cap, one base version per record is
/// always kept). [kind] is a `RecordKind.wire` (`expense` / `settlement` /
/// `member` / `meta`; [recordId] = participant id for a member, the group
/// id for meta). [source] is a `HistorySource.wire`. [recordedAt] = when
/// *this device* stored the version (its wall clock).
@DataClassName('HistoryRow')
@TableIndex(name: 'record_history_group', columns: {#groupId, #recordedAt})
@TableIndex(
  name: 'record_history_record',
  columns: {#groupId, #kind, #recordId},
)
class RecordHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get groupId => text()();
  TextColumn get kind => text()();
  TextColumn get recordId => text()();
  IntColumn get updatedAt => integer()();
  TextColumn get versionHash => text()();
  TextColumn get content => text()();
  TextColumn get source => text()();
  IntColumn get recordedAt => integer()();
}

/// Device-local key/value flags (e.g. whether onboarding has been seen). Purely
/// local — never replicated; only the ledger record types sync over to-device.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Groups,
    Expenses,
    Settlements,
    Members,
    PeerSyncStates,
    AppSettings,
    KnownDeviceKeys,
    RejectedVersions,
    RecordHistory,
    LinkChannels,
    LinkPeers,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the on-device database file/store called [name] (per-account ledger
  /// DBs are named via `accountDatabaseName` — see `account_database.dart`).
  /// [onOpen] runs once per open, after migrations, inside drift's
  /// `beforeOpen` (used to adopt the pre-per-account legacy ledger).
  ///
  /// [after] (G41): connect only once it completed — local mode's DB is
  /// reopened only after a deletion of its files has finished.
  AppDatabase.named(String name, {this.onOpen, Future<void>? after})
    : isSignedOutPlaceholder = false,
      super(
        after == null
            ? openNamedConnection(name)
            : LazyDatabase(() async {
                await after;
                return openNamedConnection(name);
              }),
      );

  /// Wraps an arbitrary executor (in-memory / temp-file DBs in tests).
  AppDatabase.forTesting(super.e, {this.onOpen})
    : isSignedOutPlaceholder = false;

  /// The storage-less placeholder behind `appDatabaseProvider` while signed
  /// out (executor: `SignedOutExecutor`).
  AppDatabase.signedOut(super.e) : onOpen = null, isSignedOutPlaceholder = true;

  /// True for the signed-out placeholder: there is no account, so sync
  /// components (SyncEngine / LedgerSyncer) must not start against it — an
  /// engine on the always-empty placeholder would e.g. send a spurious
  /// "new device" `resync_request` (G24).
  final bool isSignedOutPlaceholder;

  /// Hook run after migrations on every open — see [AppDatabase.named].
  final Future<void> Function(AppDatabase db)? onOpen;

  bool _closed = false;

  /// Whether [close] has been called. Long-running async work (SyncEngine,
  /// LedgerSyncer, replication) checks this after each await: on an account
  /// switch (G4) the previous account's DB is closed *before* the providers
  /// that captured it are disposed, and any further query on it would throw
  /// "Can't re-open a database after closing it".
  bool get isClosed => _closed;

  Future<void>? _closing;

  /// Idempotent: a second call (e.g. the provider's dispose after an explicit
  /// close before deleting local data, G40) waits for the first.
  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= super.close();
  }

  /// Deletes **every** row of this database (G40 "delete local data", and
  /// the local ledger once it was adopted into an account) in one
  /// transaction. The schema stays.
  Future<void> wipeAll() => transaction(() async {
    for (final table in allTables) {
      await delete(table).go();
    }
  });

  /// Removes every local row of [groupId] — group meta, participants,
  /// expenses, settlements (tombstones included), peer sync bookkeeping and
  /// (G52) its link channel + link peers —
  /// in one transaction (G9 leave / delete). Device-local: nothing is sent.
  Future<void> purgeGroup(String groupId) => transaction(() async {
    await (delete(groups)..where((t) => t.roomId.equals(groupId))).go();
    await (delete(members)..where((t) => t.groupId.equals(groupId))).go();
    await (delete(expenses)..where((t) => t.roomId.equals(groupId))).go();
    await (delete(settlements)..where((t) => t.roomId.equals(groupId))).go();
    await (delete(
      peerSyncStates,
    )..where((t) => t.groupId.equals(groupId))).go();
    await (delete(
      rejectedVersions,
    )..where((t) => t.groupId.equals(groupId))).go();
    // G48: a left / deleted group's version history goes with it.
    await (delete(recordHistory)..where((t) => t.groupId.equals(groupId))).go();
    // G52: and its link channel (incl. the secret + Nostr key) and peers.
    await (delete(linkChannels)..where((t) => t.groupId.equals(groupId))).go();
    await (delete(linkPeers)..where((t) => t.groupId.equals(groupId))).go();
    // G52 step 12 follow-up: and its "link replaced" notice.
    await (delete(
      appSettings,
    )..where((t) => t.key.equals('link_replaced:$groupId'))).go();
    // G53 round 3: and when its locks first arrived.
    await (delete(
      appSettings,
    )..where((t) => t.key.like('lock_seen:$groupId:%'))).go();
  });

  @override
  int get schemaVersion => 20;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // G49 (v13): `expenses.expense_date`. The v8 / v12 backfills below read
      // the expenses table with today's columns, so the column is added
      // before the first of them that runs (once).
      var expenseDateAdded = false;
      Future<void> addExpenseDate() async {
        if (expenseDateAdded) return;
        expenseDateAdded = true;
        await m.addColumn(expenses, expenses.expenseDate);
      }

      // G60 (v14): `settlements.settlement_date` — same reason (the v8 / v12
      // backfills read the settlements table with today's columns too).
      var settlementDateAdded = false;
      Future<void> addSettlementDate() async {
        if (settlementDateAdded) return;
        settlementDateAdded = true;
        await m.addColumn(settlements, settlements.settlementDate);
      }

      // G52 (v15): the `link_author` columns — same reason again (the v8
      // backfill reads expenses + settlements, the v12 one all four record
      // tables with today's columns). A DB older than v2 created `members`
      // in today's shape already.
      var linkAuthorsAdded = false;
      Future<void> addLinkAuthors() async {
        if (linkAuthorsAdded) return;
        linkAuthorsAdded = true;
        await m.addColumn(groups, groups.linkAuthor);
        await m.addColumn(expenses, expenses.linkAuthor);
        await m.addColumn(settlements, settlements.linkAuthor);
        if (from >= 2) await m.addColumn(members, members.linkAuthor);
      }

      // G53 (v16): the meta's link state — same reason (the v12 backfill
      // reads the groups table with today's columns).
      var groupLinkAdded = false;
      Future<void> addGroupLink() async {
        if (groupLinkAdded) return;
        groupLinkAdded = true;
        await m.addColumn(groups, groups.linkEpoch);
        await m.addColumn(groups, groups.linkSecret);
        await m.addColumn(groups, groups.lockedAt);
      }

      // G73 (v17): the meta's exchange rates — same reason (the v12
      // backfill reads the groups table with today's columns).
      var exchangeRatesAdded = false;
      Future<void> addExchangeRates() async {
        if (exchangeRatesAdded) return;
        exchangeRatesAdded = true;
        await m.addColumn(groups, groups.exchangeRatesJson);
      }

      // G76 (v18): `expenses.payers_json` — same reason (the v8 / v12
      // backfills read the expenses table with today's columns).
      var payersAdded = false;
      Future<void> addPayers() async {
        if (payersAdded) return;
        payersAdded = true;
        await m.addColumn(expenses, expenses.payersJson);
      }

      // G57 + G74 (v19): `groups.field_clocks_json` and
      // `members.payment_json` — same reason (the v12 backfill reads the
      // groups and members tables with today's columns). A DB older than v2
      // created `members` in today's shape already.
      var v19ColumnsAdded = false;
      Future<void> addV19Columns() async {
        if (v19ColumnsAdded) return;
        v19ColumnsAdded = true;
        await m.addColumn(groups, groups.fieldClocksJson);
        if (from >= 2) await m.addColumn(members, members.paymentJson);
      }

      // v2 (Phase B): add the local membership table. Existing
      // groups/expenses/settlements are left untouched (clean-slate move to
      // roomless — old room-based groups simply stop syncing).
      if (from < 2) {
        await m.createTable(members);
      }
      // v3 (Phase C): per-record LWW clocks + tombstones for edit/delete
      // and digest anti-entropy, plus per-peer sync bookkeeping.
      if (from < 3) {
        await m.addColumn(groups, groups.updatedAt);
        await m.addColumn(expenses, expenses.updatedAt);
        await m.addColumn(expenses, expenses.deleted);
        await m.addColumn(settlements, settlements.updatedAt);
        await m.addColumn(settlements, settlements.deleted);
        await m.createTable(peerSyncStates);
        await customStatement('UPDATE expenses SET updated_at = created_at');
        await customStatement('UPDATE settlements SET updated_at = created_at');
      }
      // v4 (virtual users): participants gain a display name and an optional
      // Matrix-account claim. Existing rows were created from real accounts,
      // so their userId already IS the MXID — backfill matrixId from it and
      // derive a display name from the localpart. Non-destructive: userId
      // (the participant id) is untouched, so all expense/settlement
      // references stay valid.
      if (from < 4) {
        await m.addColumn(members, members.displayName);
        await m.addColumn(members, members.matrixId);
        await customStatement('UPDATE members SET matrix_id = user_id');
        // localpart of @local:server → strip leading '@' up to the ':'
        await customStatement(
          "UPDATE members SET display_name = "
          "substr(user_id, 2, instr(user_id, ':') - 2) "
          "WHERE user_id LIKE '@%:%'",
        );
        await customStatement(
          "UPDATE members SET display_name = user_id "
          "WHERE user_id NOT LIKE '@%:%'",
        );
      }
      // v5 (Phase F): device-local settings (onboarding-seen flag).
      if (from < 5) {
        await m.createTable(appSettings);
      }
      // v6 (G6 signed records): per-version signatures (+ the creator's
      // origin), a pending-signature flag, the device-key history and the
      // refused versions. Existing rows keep `sig = NULL`: grandfathered as
      // legacy / unsigned (nobody can sign other people's history).
      if (from < 6) {
        await m.addColumn(groups, groups.sig);
        await m.addColumn(groups, groups.pendingSign);
        await m.addColumn(members, members.sig);
        await m.addColumn(members, members.pendingSign);
        await m.addColumn(expenses, expenses.sig);
        await m.addColumn(expenses, expenses.origin);
        await m.addColumn(expenses, expenses.pendingSign);
        await m.addColumn(settlements, settlements.sig);
        await m.addColumn(settlements, settlements.origin);
        await m.addColumn(settlements, settlements.pendingSign);
        await m.createTable(knownDeviceKeys);
        await m.createTable(rejectedVersions);
      }
      // v7 (G16): expense category + note (nullable — existing rows have
      // none, their signatures and hashes are unchanged). A pre-G16 build
      // can't verify a version that carries them (its signed body lacks the
      // fields) and refused it; forget those refusals so the next digest
      // exchange re-sends them and this build verifies them properly (a
      // genuinely bad version is simply refused again).
      if (from < 7) {
        await m.addColumn(expenses, expenses.category);
        await m.addColumn(expenses, expenses.note);
        if (from >= 6) {
          await customStatement(
            "DELETE FROM rejected_versions WHERE kind = 'expense'",
          );
        }
      }
      // v8 (G37): cache the G27 content hash per expense / settlement — a
      // digest of a 5k-record group took ~540 ms on a Pixel, mostly hashing.
      // Existing rows are hashed once here.
      if (from < 8) {
        await m.addColumn(expenses, expenses.versionHash);
        await m.addColumn(settlements, settlements.versionHash);
        await addExpenseDate();
        await addSettlementDate();
        await addLinkAuthors();
        await addPayers();
        await backfillVersionHashes(this);
      }
      // v9 (G18 review): device-key attestations are scoped to the group
      // whose snapshot carried them (new PK column `attested_group`), and a
      // refusal remembers the exact refused version (`version_hash`). The old
      // attestations were account-wide and can't be scoped after the fact —
      // they are dropped (records they vouched for show as unverified until a
      // snapshot of their group attests them again).
      // (A DB older than v6 created both tables in their current shape above.)
      if (from < 9 && from >= 6) {
        await customStatement(
          "DELETE FROM known_device_keys WHERE source = 'attested'",
        );
        await m.alterTable(
          TableMigration(
            knownDeviceKeys,
            newColumns: [knownDeviceKeys.attestedGroup],
          ),
        );
        await m.addColumn(rejectedVersions, rejectedVersions.versionHash);
      }
      // v10 (G18 review 2): a refusal set per record — the refused version
      // (clock + hash) joins the primary key; the existing rows are kept.
      if (from < 10 && from >= 6) {
        await m.alterTable(TableMigration(rejectedVersions));
      }
      // v11 (G47): per-group custom categories in the signed group meta
      // (nullable — existing metas have none; signatures and hashes are
      // unchanged). Like v7: a pre-G47 build refused signed metas carrying
      // them (its rebuilt body lacks the field) — forget meta refusals so
      // peers re-send and this build verifies them properly.
      if (from < 11) {
        await m.addColumn(groups, groups.categoriesJson);
        if (from >= 6) {
          await customStatement(
            "DELETE FROM rejected_versions WHERE kind = 'meta'",
          );
        }
      }
      // v12 (G48): the device-local version history. Every record stored so
      // far gets one `initial` entry (its current version) — the base a
      // later "reset group" goes back to; earlier states are unknown.
      if (from < 12) {
        await m.createTable(recordHistory);
        await m.createIndex(recordHistoryGroup);
        await m.createIndex(recordHistoryRecord);
        await addExpenseDate();
        await addSettlementDate();
        await addLinkAuthors();
        await addGroupLink();
        await addExchangeRates();
        await addPayers();
        await addV19Columns();
        await backfillRecordHistory(this);
      }
      // v13 (G49): the optional expense date (nullable — existing expenses
      // have none, their signatures and hashes are unchanged). Like v7: a
      // pre-G49 build refused signed expense versions carrying a `date` (its
      // rebuilt body lacks it) — forget expense refusals so peers re-send
      // and this build verifies them properly.
      if (from < 13) {
        await addExpenseDate();
        if (from >= 6) {
          await customStatement(
            "DELETE FROM rejected_versions WHERE kind = 'expense'",
          );
        }
      }
      // v14 (G60): the optional payment date — exactly like v13 for
      // expenses: a pre-G60 build refused signed settlement versions
      // carrying a `date`, so settlement refusals are forgotten.
      if (from < 14) {
        await addSettlementDate();
        if (from >= 6) {
          await customStatement(
            "DELETE FROM rejected_versions WHERE kind = 'settlement'",
          );
        }
      }
      // v15 (G52 no-login link groups): this device's link channels + the
      // publishers seen on them (both start empty), and the unsigned,
      // unhashed `link_author` hint per record version (NULL for every
      // existing row — signatures and G27 hashes are unchanged, so no
      // refusals need forgetting).
      if (from < 15) {
        await addLinkAuthors();
        await m.createTable(linkChannels);
        await m.createTable(linkPeers);
      }
      // v16 (G53 mixed groups + lock): the signed meta's optional `link`
      // and `locked_at` (NULL for every existing meta — signatures and
      // hashes unchanged). Like v11: a pre-G53 build refused signed metas
      // carrying them (its rebuilt body lacks the fields) — forget meta
      // refusals so peers re-send and this build verifies them properly.
      if (from < 16) {
        await addGroupLink();
        if (from >= 6) {
          await customStatement(
            "DELETE FROM rejected_versions WHERE kind = 'meta'",
          );
        }
      }
      // v17 (G73 exchange rates): the signed meta's optional
      // `exchange_rates` (NULL for every existing meta — signatures and
      // hashes unchanged). Like v11 / v16: a pre-G73 build refused signed
      // metas carrying them — forget meta refusals so peers re-send and
      // this build verifies them properly.
      if (from < 17) {
        await addExchangeRates();
        if (from >= 6) {
          await customStatement(
            "DELETE FROM rejected_versions WHERE kind = 'meta'",
          );
        }
      }
      // v18 (G76 multiple payers): the expense's optional `payers` (NULL
      // for every existing expense — signatures and hashes unchanged). A
      // pre-G76 build refused multi-payer versions (`paid_by` empty → "no
      // payer", `invalid_record`) — forget expense refusals so peers re-send
      // and this build accepts them.
      if (from < 18) {
        await addPayers();
        if (from >= 6) {
          await customStatement(
            "DELETE FROM rejected_versions WHERE kind = 'expense'",
          );
        }
      }
      // v19 (G57 C1 per-field meta clocks + G74 payment details): the
      // signed meta's optional `clocks` and the member's optional `payment`
      // (NULL for every existing row — signatures and hashes unchanged). A
      // pre-v19 build refused signed metas / member versions carrying them
      // (its rebuilt body lacks the field) — forget meta + member refusals
      // so peers re-send and this build verifies them properly.
      if (from < 19) {
        await addV19Columns();
        if (from >= 6) {
          await customStatement(
            "DELETE FROM rejected_versions WHERE kind IN ('meta', 'member')",
          );
        }
      }
      // v20 (G53 round 3, decision 6): `link_peers.left_at` — a publisher
      // that deleted its copy stays in the sync sheet as "Deleted the
      // group" (NULL for every existing row). A DB older than v15 created
      // `link_peers` in today's shape already.
      if (from < 20 && from >= 15) {
        await m.addColumn(linkPeers, linkPeers.leftAt);
      }
    },
    beforeOpen: (_) async {
      final hook = onOpen;
      if (hook != null) await hook(this);
    },
  );
}

/// The platform executor for the database called [name]: a `<name>.sqlite`
/// file in the app documents dir on native, OPFS/IndexedDB on web
/// (drift_flutter picks the best available web storage).
QueryExecutor openNamedConnection(String name) {
  return driftDatabase(
    name: name,
    web: kIsWeb
        ? DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          )
        : null,
  );
}
