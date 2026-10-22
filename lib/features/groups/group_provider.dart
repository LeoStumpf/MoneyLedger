import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/expenses_dao.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/link_dao.dart';
import '../../core/link/link_channel.dart'
    show LinkChannelError, LinkChannelException, lastLinkEpoch, newLinkChannel;
import '../../core/link/link_keys.dart' show generateLinkSecret;
import '../../core/link/link_sync_engine.dart'
    show LinkUnpublisher, linkSyncEngineProvider, linkUnpublisherProvider;
import '../../core/link/link_uri.dart' show encodeLinkSecret;
import '../../models/exchange_rates.dart';
import '../../models/link_model.dart';
import '../../core/database/daos/members_dao.dart';
import '../../core/database/daos/settings_dao.dart';
import '../../core/database/daos/signing_dao.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import '../../core/session/app_session.dart';
import '../../core/sync/delivery_policy.dart';
import '../../core/sync/left_groups.dart';
import '../../core/sync/payload_budget.dart';
import '../../core/sync/ledger_payloads.dart';
import '../../core/sync/record_signing.dart';
import '../../core/sync/sync_health.dart';
import '../../core/sync/record_validation.dart'
    show groupMetaProblem, isValidMxid;
import '../../models/expense_category.dart';
import '../../models/group_model.dart';
import '../../models/member_model.dart';
import '../expenses/expenses_provider.dart';
import '../onboarding/onboarding_provider.dart';
import '../receipts/receipt_store.dart'
    show ReceiptStore, deleteReceiptsOf, receiptStoreProvider;

export '../../core/database/daos/members_dao.dart' show memberCompanion;

part 'group_provider.g.dart';

@riverpod
Stream<List<GroupModel>> ledgerGroups(Ref ref) {
  return ref.watch(groupsDaoProvider).watchAllGroups();
}

@riverpod
Stream<List<MemberModel>> groupMembers(Ref ref, String groupId) {
  return ref.watch(membersDaoProvider).watchMembers(groupId);
}

/// This device's own Matrix ID (empty until the transport/client is ready).
@riverpod
String currentUserId(Ref ref) =>
    ref.watch(ledgerTransportProvider).value?.userId ?? '';

/// The participant in [groupId] that this device's account has claimed, if any
/// — i.e. "who am I in this group". Its `userId` is the participant id to use
/// as `paid_by` / split key for the current user (equals the MXID for a
/// from-scratch user, a UUID once they've claimed a pre-existing local slot).
///
/// Re-evaluated whenever the group's members change (G26), so e.g. being
/// removed by another member is reflected live (read-only group, banner).
///
/// G52 (§6.1): with no participant claimed by this account (MXID or
/// `local:self`), a **link group**'s "me" is this device's
/// `link_channels.my_participant_id` — when that participant is active.
/// (Read once per members change; the join flow sets it together with the
/// participant.)
@riverpod
Future<MemberModel?> currentParticipant(Ref ref, String groupId) async {
  final myId = ref.watch(currentUserIdProvider);
  ref.watch(groupMembersProvider(groupId));
  final members = ref.watch(membersDaoProvider);
  final link = ref.watch(linkDaoProvider);
  if (myId.isNotEmpty) {
    final claimed = await members.memberByMatrixId(groupId, myId);
    if (claimed != null) return claimed;
  }
  final mine = (await link.getChannel(groupId))?.myParticipantId;
  if (mine == null) return null;
  for (final m in await members.getMembers(groupId)) {
    if (m.userId == mine && m.isActive) return m;
  }
  return null;
}

/// participant id → display label for [groupId]. Falls back to the Matrix
/// id's localpart (or the raw participant id, [MemberModel.label]) when a participant has no name yet, so the UI
/// never shows a blank. Watches the members stream, so renames/claims reflect
/// live.
@riverpod
Map<String, String> participantNames(Ref ref, String groupId) {
  final members =
      ref.watch(groupMembersProvider(groupId)).value ?? const <MemberModel>[];
  return {for (final m in members) m.userId: m.label};
}

/// Everything one group/member mutation needs, captured **before the first
/// await** (G23 — same pattern as `ExpenseAdder`'s `LedgerWriteContext`, G19): the
/// account DB + DAOs, the transport and this device's MXID. A mutation thus
/// always targets the account that was active when the user acted, and `ref`
/// is never touched after an await (the auto-dispose notifier may be disposed
/// mid-flight, e.g. when the page that triggered it is popped).
class _GroupWriteContext {
  _GroupWriteContext(Ref ref)
    : db = ref.read(appDatabaseProvider),
      groups = ref.read(groupsDaoProvider),
      members = ref.read(membersDaoProvider),
      expenses = ref.read(expensesDaoProvider),
      settings = ref.read(settingsDaoProvider),
      signing = ref.read(signingDaoProvider),
      receipts = ref.read(receiptStoreProvider),
      linkUnpublish = ref.read(linkUnpublisherProvider),
      budget = ref.read(payloadBudgetProvider),
      health = ref.read(syncHealthProvider.notifier),
      transport = withDeliveryPolicy(
        ref.read(ledgerTransportProvider.future),
        ref.read(settingsDaoProvider),
      ) {
    // Not every mutation awaits the transport (e.g. a solo-group delete);
    // don't let an unused transport failure surface as an unhandled error.
    transport.ignore();
    link = LinkDao(db);
    signer = LocalRecordSigner(transport, policy: link.policyOf);
  }

  /// G6: signs every version a mutation writes with this device's key —
  /// G52: in a link-only group it is stored unsigned instead (not
  /// `pendingSign`, `by` = this device's link participant); the relays
  /// below skip unsigned versions, so nothing reaches Matrix.
  late final LocalRecordSigner signer;

  /// G52: this ledger DB's link channels (group policy).
  late final LinkDao link;

  /// G52: Matrix-ID claims / Matrix bootstraps don't exist in a link-only
  /// group (§6.1: its member records carry no `matrix_id`; peers refuse
  /// claims there) — every Matrix membership mutation calls this first.
  Future<void> requireMatrixGroup(String groupId) async {
    if (await link.isLinkOnly(groupId)) throw const LinkOnlyGroupException();
  }

  final SigningDao signing;

  /// G78: this ledger's receipt photos (null where there are none).
  final ReceiptStore? receipts;

  /// G52 step 10: removes this device's copy of a link group from the
  /// relays before the group is purged (§7.3).
  final LinkUnpublisher linkUnpublish;

  /// G14: max JSON bytes per to-device message (bootstraps are chunked).
  final int budget;

  /// Sends the whole group to [to] as one or more self-contained bootstrap
  /// parts (G14, [buildBootstrapParts]).
  Future<void> sendBootstrap(String to, String groupId) async {
    if (await link.isLinkOnly(groupId)) return; // G52: never over Matrix
    final parts = await buildBootstrap(groupId);
    final t = await transport;
    for (final part in parts) {
      if (db.isClosed) return;
      await t.sendToUsers({to}, bootstrapEventType, part);
    }
  }

  /// Signs [m] and saves it (LWW). Returns the stored (signed or
  /// `pendingSign`) version.
  Future<MemberModel> saveMember(MemberModel m) async {
    final signed = await signer.member(m);
    if (!db.isClosed) await members.upsertMemberLww(memberCompanion(signed));
    return signed;
  }

  /// Sends a member payload — unless the version still waits for its
  /// signature (G6: peers refuse unsigned versions; anti-entropy delivers it
  /// once the sync engine has signed it).
  Future<void> sendMember(Set<String> targets, MemberModel m) async {
    if (m.sig == null || targets.isEmpty) return;
    await (await transport).sendToUsers(
      targets,
      memberEventType,
      memberPayload(m),
    );
  }

  final AppDatabase db;
  final GroupsDao groups;
  final MembersDao members;
  final ExpensesDao expenses;
  final SettingsDao settings;
  final SyncHealth health;
  final Future<LedgerTransport> transport;

  Future<String> myMxid() async => (await transport).userId;

  /// The name for a participant claimed by [matrixId] (G17): the account's
  /// Matrix profile display name, else its localpart.
  Future<String> profileNameOrLocalpart(String matrixId) async =>
      await (await transport).profileName(matrixId) ?? localpartOf(matrixId);

  /// Best-effort relay of [content] to the group's active claimed members
  /// (self included — our other devices). The change is already saved
  /// locally, so a transport failure doesn't fail the user action; it is
  /// reported to [SyncHealth] and anti-entropy repairs it later.
  Future<void> replicate(
    String groupId,
    String type,
    Map<String, dynamic> content,
  ) async {
    if (db.isClosed || content['sig'] == null) return;
    try {
      final targets = (await members.activeClaimedMatrixIds(groupId)).toSet();
      if (targets.isEmpty || db.isClosed) return;
      final result = await (await transport).sendToUsers(
        targets,
        type,
        content,
      );
      if (!db.isClosed) health.reportDelivery(targets, result);
    } catch (e) {
      if (!db.isClosed) health.reportFailure(e);
    }
  }

  Future<List<Map<String, dynamic>>> buildBootstrap(String groupId) async {
    final group = await groups.getGroup(groupId);
    final ms = await members.getMembers(groupId);
    // Tombstones included: the new member must learn about deletions too,
    // or they would re-gossip dead records via anti-entropy.
    final es = await expenses.getAllExpensesForGroup(groupId);
    final ss = await expenses.getAllSettlementsForGroup(groupId);
    return buildBootstrapParts(
      groupId,
      group,
      ms,
      es,
      ss,
      // G6: vouch for the signers' keys we saw first-hand.
      deviceKeys: await signing.attestationsFor(
        snapshotSigners(group, ms, es, ss),
      ),
      budget: budget,
    );
  }
}

/// G52: a Matrix membership change (add / invite / claim a Matrix ID) was
/// attempted in a link-only group — nothing was written.
class LinkOnlyGroupException implements Exception {
  const LinkOnlyGroupException();

  @override
  String toString() => 'LinkOnlyGroupException';
}

/// Runs [body] with a freshly captured [_GroupWriteContext]: loading → result,
/// where the final state is only set while the notifier is still mounted.
Future<void> _runGroupWrite(
  Ref ref,
  void Function(AsyncValue<void>) setState,
  Future<void> Function(_GroupWriteContext w) body,
) async {
  final w = _GroupWriteContext(ref);
  setState(const AsyncLoading());
  final result = await AsyncValue.guard(() => body(w));
  if (ref.mounted) setState(result);
}

@riverpod
class GroupCreator extends _$GroupCreator {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Creates a group locally (roomless): a fresh UUID id, with the creator as
  /// the first active member. Nothing is sent to Matrix — members are added (and
  /// the group replicated to them) via [MemberAdder].
  ///
  /// G64: [people] (names, from the create page's "Who's in?" chips) are
  /// added right away as local participants — exactly like *Add person*
  /// ([MemberAdder.addLocal]): a fresh UUIDv7 id, no Matrix ID, signed /
  /// `pendingSign` / unsigned per the group's policy by the same signer.
  /// Blank names are skipped; names are trimmed. Nothing is relayed: the
  /// group has no other claimed member yet (our own other devices learn it
  /// from the next digest, like the group itself).
  ///
  /// G52 step 6 — [viaLink] (*Create group → Share with a link*): the group
  /// is a **link group from its first write**. Its link channel is stored
  /// first (fresh secret + Nostr key, `my_participant_id` = the creator), so
  /// the group is `linkOnly` before anything is written: the meta and every
  /// participant are stored unsigned with `by` = the creator — also on a
  /// Matrix device, which would otherwise sign the meta and make the group
  /// a Matrix group (`openLinkChannel` refuses signed metas; mixed groups
  /// are G53). The creator is a participant **without** a claim and with a
  /// fresh UUIDv7 id (§6.1: link member records carry no `matrix_id`, and
  /// the MXID must not become a participant id the relays could see). All
  /// in one transaction; the link sync engine sees the new channel and
  /// publishes.
  ///
  /// Returns the new group's id once it is stored (G46: the create page opens
  /// it), or null when the write failed (see [state]) or the DB closed.
  Future<String?> create(
    String name,
    String currency, {
    List<String> people = const [],
    bool viaLink = false,
  }) async {
    String? created;
    await _runGroupWrite(ref, (s) => state = s, (w) async {
      final groupId = const Uuid().v7();
      final now = DateTime.now().millisecondsSinceEpoch;
      final me = await w.myMxid();
      final myName = await w.profileNameOrLocalpart(me);
      if (w.db.isClosed) return;
      if (viaLink) {
        await w.db.transaction(
          () => _createLinkGroup(w, groupId, name, currency, myName, people),
        );
        if (!w.db.isClosed) created = groupId;
        return;
      }
      final group = await w.signer.group(
        GroupModel(
          roomId: groupId,
          name: name,
          currency: currency,
          updatedAt: now,
        ),
      );
      if (w.db.isClosed) return;
      await w.groups.upsertGroupLww(groupCompanion(group));
      // The creator is the first participant, claimed by their own account
      // (participant id == their MXID, the invariant for from-scratch users).
      // G40 local mode: claimed by the local pseudo account, with a fresh
      // participant id (it keeps that id once a Matrix account adopts it).
      await w.saveMember(
        MemberModel(
          groupId: groupId,
          userId: isLocalAccountId(me) ? const Uuid().v7() : me,
          displayName: myName,
          matrixId: me,
          status: 'active',
          updatedAt: now,
        ),
      );
      for (final person in people) {
        final personName = person.trim();
        if (personName.isEmpty) continue;
        if (w.db.isClosed) return;
        await w.saveMember(
          MemberModel(
            groupId: groupId,
            userId: const Uuid().v7(),
            displayName: personName,
            matrixId: null,
            status: 'active',
            updatedAt: now,
          ),
        );
      }
      created = groupId;
    });
    return created;
  }

  static Future<void> _createLinkGroup(
    _GroupWriteContext w,
    String groupId,
    String name,
    String currency,
    String myName,
    List<String> people,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final myParticipant = const Uuid().v7();
    // The channel first: from here on the group is linkOnly, so the signer
    // stores every version below unsigned (`by` = myParticipant).
    await w.link.putChannel(
      newLinkChannel(groupId, myParticipantId: myParticipant, openedAt: now),
    );
    final group = await w.signer.group(
      GroupModel(
        roomId: groupId,
        name: name,
        currency: currency,
        updatedAt: now,
      ),
    );
    await w.groups.upsertGroupLww(groupCompanion(group));
    await w.saveMember(
      MemberModel(
        groupId: groupId,
        userId: myParticipant,
        displayName: myName,
        matrixId: null,
        status: 'active',
        updatedAt: now,
      ),
    );
    for (final person in people) {
      final personName = person.trim();
      if (personName.isEmpty) continue;
      await w.saveMember(
        MemberModel(
          groupId: groupId,
          userId: const Uuid().v7(),
          displayName: personName,
          matrixId: null,
          status: 'active',
          updatedAt: now,
        ),
      );
    }
  }
}

@riverpod
class MemberAdder extends _$MemberAdder {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> _run(Future<void> Function(_GroupWriteContext w) body) =>
      _runGroupWrite(ref, (s) => state = s, body);

  /// Adds [userId] (a Matrix ID) to the group: records them locally, sends them
  /// the whole group as a bootstrap payload ("send my friend the database"), and
  /// notifies existing members of the new member.
  Future<void> add(String groupId, String userId, {String? displayName}) =>
      _run((w) => _applyAdd(w, groupId, userId, displayName: displayName));

  static Future<void> _applyAdd(
    _GroupWriteContext w,
    String groupId,
    String userId, {
    String? displayName,
  }) async {
    await w.requireMatrixGroup(groupId);
    // G26: if this account already claims a participant here (e.g. it left
    // after claiming a placeholder, or was removed), **reactivate** that
    // participant — same id + name, so history stays attributed — instead of
    // inserting a second participant with the same matrixId. Its clock is
    // strictly newer than the `removed` record (whoever stamped it), so the
    // re-add wins LWW everywhere and the re-added device's tombstone check
    // (`updated_at > left_at`) passes even if our clock lags theirs.
    final existing = claimedBy(await w.members.getMembers(groupId), userId);
    // A new participant is named by the caller, else by the account's Matrix
    // profile display name (G17), else by the MXID's localpart.
    final name = existing != null
        ? existing.displayName
        : (displayName != null && displayName.isNotEmpty)
        ? displayName
        : await w.profileNameOrLocalpart(userId);
    if (w.db.isClosed) return;
    final member = existing != null
        ? MemberModel(
            groupId: groupId,
            userId: existing.userId,
            displayName: existing.displayName,
            matrixId: userId,
            status: 'active',
            updatedAt: nextLwwClock(existing.updatedAt),
          )
        // Added by Matrix ID → a claimed participant (id == MXID for now;
        // G40: local mode's pseudo account gets a fresh id instead).
        : MemberModel(
            groupId: groupId,
            userId: isLocalAccountId(userId) ? const Uuid().v7() : userId,
            displayName: name,
            matrixId: userId,
            status: 'active',
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
    final saved = await w.saveMember(member);

    // 1) Bootstrap the new member with the full group state + ledger.
    await w.sendBootstrap(userId, groupId);

    // 2) Tell the existing active members about the new member.
    final others = (await w.members.activeClaimedMatrixIds(
      groupId,
    )).where((m) => m != userId).toSet();
    await w.sendMember(others, saved);
  }

  /// Invites a Matrix account into the group **as a participant chosen by
  /// the inviter** (G18 review): [participantId] = an existing (typically
  /// local, unclaimed) participant the account becomes ([claim] — history
  /// kept), else a new participant for it ([add]). Either way an active
  /// member assigns the slot, the account receives the bootstrap and is an
  /// active member right away. (Peers refuse membership changes a
  /// non-member makes about itself — so the invitee can no longer pick its
  /// own slot after a slot-less invite.)
  Future<void> invite(
    String groupId,
    String matrixId, {
    String? participantId,
  }) => _run((w) async {
    final members = await w.members.getMembers(groupId);
    // An account that already claims a participant here is re-added as that
    // participant (G26), never linked to a second one.
    if (participantId == null || claimedBy(members, matrixId) != null) {
      await _applyAdd(w, groupId, matrixId);
    } else {
      await _applyClaim(w, groupId, participantId, matrixId);
    }
  });

  /// Adds a Tricount-style local participant: a named person with no Matrix
  /// account (a fresh UUID participant id, `matrixId == null`). They are pure
  /// ledger data — relayed to the claimed members so everyone sees them, but
  /// never a sync target until someone claims the slot.
  Future<void> addLocal(String groupId, String name) => _run((w) async {
    final member = MemberModel(
      groupId: groupId,
      userId: const Uuid().v7(),
      displayName: name,
      matrixId: null,
      status: 'active',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _relayToClaimed(w, groupId, await w.saveMember(member));
  });

  /// Re-adds a removed **local** participant (G7): reactivates the same
  /// participant id + name so their history stays attributed — re-adding via
  /// "Add person" would mint a second, unrelated participant of the same name.
  /// (A claimed former member is re-added through [add], which also
  /// bootstraps their account.)
  Future<void> reactivate(String groupId, String participantId) =>
      _editParticipant(
        groupId,
        participantId,
        (m) => _copyWith(m, status: 'active'),
      );

  /// Renames a participant (LWW edit), then replicates.
  Future<void> rename(String groupId, String participantId, String name) =>
      _editParticipant(
        groupId,
        participantId,
        (m) => _copyWith(m, displayName: name),
      );

  /// Claims a (typically local) participant for the Matrix account [matrixId]:
  /// links the account to the existing ledger identity, keeping all history.
  /// Bootstraps that account with the whole group (they may not have it yet).
  Future<void> claim(String groupId, String participantId, String matrixId) =>
      _run((w) => _applyClaim(w, groupId, participantId, matrixId));

  static Future<void> _applyClaim(
    _GroupWriteContext w,
    String groupId,
    String participantId,
    String matrixId,
  ) async {
    await w.requireMatrixGroup(groupId);
    final current = _find(await w.members.getMembers(groupId), participantId);
    if (current == null) return;
    final updated = await w.saveMember(_copyWith(current, matrixId: matrixId));
    await w.sendBootstrap(matrixId, groupId);
    final targets = (await w.members.activeClaimedMatrixIds(groupId)).toSet();
    await w.sendMember(targets, updated);
  }

  /// Claims an existing participant as **this device's own account** — for a
  /// group this device holds without being a participant of it (e.g. one
  /// created by a CSV import). Peers only accept it from an active member
  /// (G18 review): an account that isn't a participant yet must be invited
  /// into a slot by a member instead ([invite]).
  Future<void> selfClaim(String groupId, String participantId) => _run(
    (w) async => _applyClaim(w, groupId, participantId, await w.myMxid()),
  );

  /// Joins a group this device holds as a brand-new participant (you are not
  /// any of the existing local people) — creates a self-participant and tells
  /// the others (who only accept it from an active member, see [selfClaim]).
  Future<void> joinAsNew(String groupId, String name) => _run(
    (w) async => _applyAdd(w, groupId, await w.myMxid(), displayName: name),
  );

  /// Detaches the Matrix account from a participant (the "remove account" of
  /// open-points #7) — the participant and their history stay; only the claim
  /// is cleared. Relays to the remaining members and to the detached account's
  /// own device so it learns it is no longer linked.
  Future<void> unclaim(String groupId, String participantId) => _run((w) async {
    final current = _find(await w.members.getMembers(groupId), participantId);
    if (current == null || current.matrixId == null) return;
    final detached = current.matrixId!;
    final updated = await w.saveMember(_copyWith(current, matrixId: null));
    final targets = (await w.members.activeClaimedMatrixIds(groupId)).toSet()
      ..add(detached);
    await w.sendMember(targets, updated);
  });

  Future<void> _editParticipant(
    String groupId,
    String participantId,
    MemberModel Function(MemberModel) edit,
  ) => _run((w) async {
    final current = _find(await w.members.getMembers(groupId), participantId);
    if (current == null) return;
    final updated = await w.saveMember(edit(current));
    await _relayToClaimed(w, groupId, updated);
  });

  static Future<void> _relayToClaimed(
    _GroupWriteContext w,
    String groupId,
    MemberModel member,
  ) async {
    final targets = (await w.members.activeClaimedMatrixIds(groupId)).toSet();
    await w.sendMember(targets, member);
  }

  static MemberModel? _find(List<MemberModel> members, String participantId) {
    for (final m in members) {
      if (m.userId == participantId) return m;
    }
    return null;
  }

  static MemberModel _copyWith(
    MemberModel m, {
    String? displayName,
    Object? matrixId = _unset,
    String? status,
  }) => MemberModel(
    groupId: m.groupId,
    userId: m.userId,
    displayName: displayName ?? m.displayName,
    matrixId: identical(matrixId, _unset) ? m.matrixId : matrixId as String?,
    status: status ?? m.status,
    updatedAt: nextLwwClock(m.updatedAt),
  );
}

/// Sentinel for [_copyWith] so `matrixId: null` (unclaim) is distinguishable
/// from "leave unchanged".
const Object _unset = Object();

/// The participant [members] has as `removed` for [userId], with a fresh LWW
/// clock — identity (name + claim) kept, so history stays attributed and the
/// relay doesn't wipe peers' copies. Null if [userId] isn't a participant.
MemberModel? _removedCopy(List<MemberModel> members, String userId, int now) {
  for (final m in members) {
    if (m.userId == userId) {
      return MemberModel(
        groupId: m.groupId,
        userId: m.userId,
        displayName: m.displayName,
        matrixId: m.matrixId,
        status: 'removed',
        updatedAt: nextLwwClock(m.updatedAt, now: now),
      );
    }
  }
  return null;
}

@riverpod
class MemberRemover extends _$MemberRemover {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Marks [userId] removed (last-writer-wins) and relays the change. Their
  /// expense history stays in Drift, so balances are preserved — only their
  /// membership status changes. The removed user is included in the relay so
  /// their own device updates too.
  Future<void> remove(String groupId, String userId) =>
      _runGroupWrite(ref, (s) => state = s, (w) async {
        final members = await w.members.getMembers(groupId);
        final updated = _removedCopy(
          members,
          userId,
          DateTime.now().millisecondsSinceEpoch,
        );
        if (updated == null) return;
        final saved = await w.saveMember(updated);
        // Relay to every claimed account, including the removed member's own
        // device so it learns of the removal.
        final targets = members
            .map((m) => m.matrixId)
            .whereType<String>()
            .toSet();
        await w.sendMember(targets, saved);
      });
}

/// One-off name upgrade (G17): participants whose stored name is just their
/// account's MXID localpart — the default before profile names were fetched —
/// are renamed to that account's Matrix profile display name, if it has a
/// different one. Runs once per signed-in account (keepAlive; rebuilt on an
/// account switch with the DB), only in groups where this account is an
/// active participant (others would reject our edits), and only for active
/// claimed participants. Each rename is an ordinary LWW edit relayed to the
/// group like a manual rename. Returns the number of renamed participants.
///
/// G19: everything is captured before the first await; it bails silently
/// once the DB closed (account switch / sign-out).
@Riverpod(keepAlive: true)
Future<int> profileNameRefresh(Ref ref) async {
  final db = ref.watch(appDatabaseProvider);
  if (db.isSignedOutPlaceholder) return 0;
  final w = _GroupWriteContext(ref);
  try {
    final transport = await w.transport;
    final me = transport.userId;
    // G40: local mode has no Matrix profiles to look up.
    if (me.isEmpty || isLocalAccountId(me) || db.isClosed) return 0;
    final names = <String, String?>{}; // MXID → profile name (one lookup each)
    var renamed = 0;
    for (final group in await w.groups.getAllGroups()) {
      if (db.isClosed) return renamed;
      final members = await w.members.getMembers(group.roomId);
      if (!(claimedBy(members, me)?.isActive ?? false)) continue;
      for (final m in members) {
        final mxid = m.matrixId;
        if (mxid == null || !m.isActive) continue;
        if (m.displayName.isNotEmpty && m.displayName != localpartOf(mxid)) {
          continue; // a chosen name — never overwrite it
        }
        final name = names.containsKey(mxid)
            ? names[mxid]
            : (names[mxid] = await transport.profileName(mxid));
        if (db.isClosed) return renamed;
        if (name == null || name == m.displayName) continue;
        final updated = await w.saveMember(
          MemberModel(
            groupId: m.groupId,
            userId: m.userId,
            displayName: name,
            matrixId: m.matrixId,
            status: m.status,
            updatedAt: nextLwwClock(m.updatedAt),
          ),
        );
        await w.replicate(
          group.roomId,
          memberEventType,
          memberPayload(updated),
        );
        renamed++;
      }
    }
    return renamed;
  } catch (e) {
    // Best effort: a failed lookup / closed DB just leaves the names as they
    // are until the next start.
    return 0;
  }
}

/// What the group menu offers for a group (G9) — see [groupExitKind].
enum GroupExitKind {
  /// We are an active participant and other claimed accounts are active:
  /// mark ourselves removed for everyone, then drop the group locally.
  leave,

  /// Nobody else could be affected (solo / local-only group, or we're no
  /// longer an active participant anyway): drop the group from this device.
  delete,
}

/// Pure decision behind the group menu entry: **Leave** when this account is
/// an active participant and at least one *other* claimed account is active
/// (they must learn we left); otherwise **Delete** (purely local).
GroupExitKind groupExitKind(List<MemberModel> members, String myMxid) {
  final meActive = members.any((m) => m.isActive && m.matrixId == myMxid);
  final othersClaimed = members.any(
    (m) => m.isActive && m.matrixId != null && m.matrixId != myMxid,
  );
  return meActive && othersClaimed ? GroupExitKind.leave : GroupExitKind.delete;
}

/// Leave / delete a group (G9). Both end with the group **purged** from the
/// local DB and a device-local [LeftGroupTombstone], so a late digest or
/// bootstrap from a peer (or our own other devices) can't resurrect it — only
/// being re-added (a newer `active` member record for our MXID) brings it back.
@riverpod
class GroupExiter extends _$GroupExiter {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Leaves [groupId]: our participant is marked `removed` (LWW) and relayed
  /// to every claimed account — peers see "X left", and our own other devices
  /// learn it too — then the group is purged locally. The relay is
  /// best-effort: if it fails (offline), the tombstone keeps our removal
  /// notice and re-sends it to any peer whose digest still lists us as active
  /// (SyncEngine rule 7), so the leave still reaches everyone eventually.
  Future<void> leave(String groupId) =>
      _runGroupWrite(ref, (s) => state = s, (w) async {
        final me = await w.myMxid();
        final members = await w.members.getMembers(groupId);
        final now = DateTime.now().millisecondsSinceEpoch;
        final self = claimedBy(members, me);
        final unsigned = self == null
            ? null
            : _removedCopy(members, self.userId, now);
        final removed = unsigned == null ? null : await w.saveMember(unsigned);
        if (removed != null && removed.sig != null) {
          final targets = members
              .map((m) => m.matrixId)
              .whereType<String>()
              .toSet();
          try {
            final result = await (await w.transport).sendToUsers(
              targets,
              memberEventType,
              memberPayload(removed),
            );
            if (!w.db.isClosed) w.health.reportDelivery(targets, result);
          } catch (e) {
            if (!w.db.isClosed) w.health.reportFailure(e);
          }
        }
        await _purge(
          w,
          groupId,
          LeftGroupTombstone(
            leftAt: removed?.updatedAt ?? now,
            removalNotice: removed == null ? null : memberPayload(removed),
          ),
        );
      });

  /// Deletes [groupId] from this device only — nothing is sent. Meant for
  /// solo / local-only groups (see [groupExitKind]).
  Future<void> delete(String groupId) =>
      _runGroupWrite(ref, (s) => state = s, (w) async {
        await _purge(
          w,
          groupId,
          LeftGroupTombstone(leftAt: DateTime.now().millisecondsSinceEpoch),
        );
      });

  static Future<void> _purge(
    _GroupWriteContext w,
    String groupId,
    LeftGroupTombstone t,
  ) async {
    if (w.db.isClosed) return; // account switched meanwhile — not ours to touch
    // G52 step 10 (§7.3): a link group's own events leave the relays first
    // (header-only parts expiring after a day + a NIP-09 deletion) —
    // best-effort and bounded; the peers keep their copies. The purge then
    // drops the channel (secret + Nostr key) with the group.
    if (await w.link.getChannel(groupId) != null) {
      if (w.db.isClosed) return;
      final ok = await w.linkUnpublish(groupId);
      debugPrint('[link] $groupId unpublished before the purge: $ok');
      if (w.db.isClosed) return;
    }
    // G78: the group's receipt photos go with it (ids read before the purge).
    final expenseIds = w.receipts == null
        ? const <String>[]
        : [
            for (final e in await w.expenses.getAllExpensesForGroup(groupId))
              e.id,
          ];
    if (w.db.isClosed) return;
    await w.settings.purgeGroupAsLeft(groupId, t);
    await deleteReceiptsOf(w.receipts, expenseIds);
  }
}

/// Edits a group's meta — name and default currency (G10). Any active member
/// may edit. Persisted as an LWW meta upsert with a fresh clock and relayed
/// as a `group` meta payload to the active claimed members (anti-entropy's
/// `meta_updated_at` repairs a lost relay). The default currency only applies
/// to **new** expenses — existing ones keep theirs (balances are per currency).
@riverpod
class GroupEditor extends _$GroupEditor {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> edit(
    String groupId, {
    required String name,
    required String currency,
  }) => _runGroupWrite(ref, (s) => state = s, (w) async {
    final current = await w.groups.getGroup(groupId);
    if (current == null) return;
    if (current.name == name && current.currency == currency) return;
    await _write(
      w,
      // G47: categories kept; G53: the link state (open link / lock) too.
      current.nextVersion(
        updatedAt: nextLwwClock(current.updatedAt),
        name: name,
        currency: currency,
      ),
    );
  });

  /// G47: adds a custom category ([name] trimmed, [icon] a key of
  /// [kCustomCategoryIcons]) to [groupId]'s meta — a new signed meta version
  /// relayed like [edit]. Returns its id (`c:<uuidv7>`), or null when the
  /// write failed (see [state]), the group is unknown or full.
  Future<String?> addCategory(
    String groupId, {
    required String name,
    required String icon,
  }) async {
    String? id;
    await _runGroupWrite(ref, (s) => state = s, (w) async {
      final current = await w.groups.getGroup(groupId);
      if (current == null ||
          current.categories.length >= kMaxCustomCategories) {
        return;
      }
      final category = CustomCategory(
        id: '$kCustomCategoryPrefix${const Uuid().v7()}',
        name: name.trim(),
        icon: icon,
      );
      if (await _writeCategories(w, current, [
        ...current.categories,
        category,
      ])) {
        id = category.id;
      }
    });
    return id;
  }

  /// G47: replaces the custom category [updated] (same id) — rename, new
  /// icon, hide / show. Unknown id or no change → nothing is written.
  Future<void> updateCategory(String groupId, CustomCategory updated) =>
      _runGroupWrite(ref, (s) => state = s, (w) async {
        final current = await w.groups.getGroup(groupId);
        if (current == null) return;
        final i = current.categories.indexWhere((c) => c.id == updated.id);
        if (i < 0 || current.categories[i] == updated) return;
        await _writeCategories(w, current, [
          for (final c in current.categories) c.id == updated.id ? updated : c,
        ]);
      });

  /// G73: replaces [groupId]'s fixed exchange rates ([fx] null = none) — a
  /// new meta version (name, currency, categories, link state kept),
  /// signed and relayed like [edit]. No change → nothing is written; rates
  /// breaking the content rules throw (nothing written).
  Future<void> setExchangeRates(String groupId, ExchangeRates? fx) =>
      _runGroupWrite(ref, (s) => state = s, (w) async {
        final current = await w.groups.getGroup(groupId);
        if (current == null || current.exchangeRates == fx) return;
        final next = current.nextVersion(
          updatedAt: nextLwwClock(current.updatedAt),
          exchangeRates: fx,
        );
        final problem = groupMetaProblem(next);
        if (problem != null) throw ArgumentError(problem);
        await _write(w, next);
      });

  /// Writes [current] with [categories] as a new meta version; false when
  /// they break the content rules (nothing written) or the DB closed.
  static Future<bool> _writeCategories(
    _GroupWriteContext w,
    GroupModel current,
    List<CustomCategory> categories,
  ) async {
    final next = current.nextVersion(
      updatedAt: nextLwwClock(current.updatedAt),
      categories: categories,
    );
    final problem = groupMetaProblem(next);
    if (problem != null) throw ArgumentError(problem);
    return _write(w, next);
  }

  /// Signs, stores and relays [g] (a new meta version).
  static Future<bool> _write(_GroupWriteContext w, GroupModel g) async {
    if (w.db.isClosed) return false;
    final updated = await w.signer.group(g);
    if (w.db.isClosed) return false;
    await w.groups.upsertGroupLww(groupCompanion(updated));
    await w.replicate(g.roomId, groupMetaEventType, groupMetaPayload(updated));
    return true;
  }
}

/// G53 step 2 (§10.1 "Matrix → link"): *Invite by link* in a Matrix group /
/// *Reset invite link* in a mixed one, on a Matrix device — returns this
/// device's channel of the group once it follows the new link.
typedef MixedLinkAction = Future<LinkChannelModel> Function(String groupId);

/// *Invite by link* in a **Matrix group**: this account (an active
/// participant) writes a **signed** meta with `link: {epoch, secret}` — a
/// fresh 32-byte secret, the next epoch ([lastLinkEpoch] + 1) — relays it to
/// the group's Matrix members (they bridge on receipt) and lets the link
/// sync engine bridge this device ([LinkSyncEngine.ensureBridged]: a channel
/// with the meta's secret, "me" = our participant). A group whose meta
/// already opens a link is only bridged. The group is `mixed` from the
/// meta write on.
final mixedLinkOpenerProvider = Provider<MixedLinkAction>(
  (ref) =>
      (groupId) => _mixedLink(ref, groupId, reset: false),
);

/// *Reset invite link* in a **mixed** group (G52 step 12 + §10.1): like the
/// opener with a new secret and the next epoch even though a link is open —
/// every Matrix member's device follows the new signed meta (unpublishing
/// its copy from the old topic), people without an account need the new
/// link sent directly.
final mixedLinkResetterProvider = Provider<MixedLinkAction>(
  (ref) =>
      (groupId) => _mixedLink(ref, groupId, reset: true),
);

Future<LinkChannelModel> _mixedLink(
  Ref ref,
  String groupId, {
  required bool reset,
}) async {
  final w = _GroupWriteContext(ref);
  final engine = ref.read(linkSyncEngineProvider);
  await writeMixedLinkMeta(
    w.db,
    groupId,
    me: await w.myMxid(),
    reset: reset,
    sign: w.signer.group,
    relay: (signed) =>
        w.replicate(groupId, groupMetaEventType, groupMetaPayload(signed)),
  );
  final channel = await engine.ensureBridged(groupId);
  if (channel == null) {
    throw const LinkChannelException(LinkChannelError.noChannel);
  }
  return channel;
}

/// G53 step 2: writes the signed meta that opens (or, [reset], replaces)
/// [groupId]'s invite link — see [mixedLinkOpenerProvider]. [me] = this
/// device's MXID (an active participant, else
/// [LinkChannelError.notParticipant]); [sign] must return a **signed**
/// version (a `pendingSign` one → [TransportUnavailableException], nothing
/// stored: an unsigned meta can't carry a link); [relay] sends it to the
/// Matrix members. A meta that already opens a link and no [reset] → nothing
/// is written. Returns the stored meta.
Future<GroupModel> writeMixedLinkMeta(
  AppDatabase db,
  String groupId, {
  required String me,
  required bool reset,
  required Future<GroupModel> Function(GroupModel) sign,
  required Future<void> Function(GroupModel signed) relay,
  int Function()? clock,
}) async {
  if (!me.startsWith('@')) throw const SignatureRequiredException();
  final groups = GroupsDao(db);
  final meta = await groups.getGroup(groupId);
  if (meta == null) throw const LinkChannelException(LinkChannelError.noGroup);
  final mine = claimedBy(await MembersDao(db).getMembers(groupId), me);
  if (mine == null || !mine.isActive) {
    throw const LinkChannelException(LinkChannelError.notParticipant);
  }
  if (!reset && meta.link != null && meta.sig != null) return meta;
  final epoch = await lastLinkEpoch(db, groupId) + 1;
  final next = meta.nextVersion(
    updatedAt: nextLwwClock(meta.updatedAt, now: clock?.call()),
    link: GroupLink(
      epoch: epoch,
      secret: encodeLinkSecret(generateLinkSecret()),
    ),
    lockedAt: null,
  );
  final signed = await sign(next);
  if (signed.sig == null) {
    throw const TransportUnavailableException('signing key not ready');
  }
  if (db.isClosed) return signed;
  await groups.upsertGroupLww(groupCompanion(signed));
  await relay(signed);
  return signed;
}

/// G53 step 4 (§10.1 Lock): the active participants that keep a group from
/// being locked — everyone active must be claimed by a Matrix account
/// (a valid MXID). Empty = it can be locked. Pure.
List<MemberModel> lockBlockers(Iterable<MemberModel> members) => [
  for (final m in members)
    if (m.isActive && !isValidMxid(m.matrixId)) m,
];

/// G53: *Make group secure* was asked for a group that can't be locked —
/// [blockers] still need to sign in with Matrix (or be removed). Nothing
/// was written.
class LockNotEligibleException implements Exception {
  final List<MemberModel> blockers;
  const LockNotEligibleException(this.blockers);

  @override
  String toString() => 'LockNotEligibleException(${blockers.length})';
}

/// Locks a group (G53 step 4).
typedef GroupLocker = Future<void> Function(String groupId);

/// G53 step 4 — **Make group secure** (§10.1): on a Matrix device of an
/// active participant, in a group whose every active participant is
/// claimed by a Matrix account ([lockBlockers], else
/// [LockNotEligibleException]): a **signed** meta without `link` and with
/// `locked_at` = its clock — stored by the link sync engine together with
/// the final `locked: true` event and the channel drop
/// ([LinkSyncEngine.lockLink]) — then relayed over Matrix (the members'
/// devices drop their channels on receipt). From then on unsigned versions
/// newer than `locked_at` are refused everywhere. Reopening is *Invite by
/// link* again (a new secret + epoch).
final groupLockerProvider = Provider<GroupLocker>(
  (ref) => (groupId) async {
    final w = _GroupWriteContext(ref);
    final engine = ref.read(linkSyncEngineProvider);
    final me = await w.myMxid();
    if (!me.startsWith('@')) throw const SignatureRequiredException();
    final meta = await w.groups.getGroup(groupId);
    if (meta == null) {
      throw const LinkChannelException(LinkChannelError.noGroup);
    }
    final people = await w.members.getMembers(groupId);
    final mine = claimedBy(people, me);
    if (mine == null || !mine.isActive) {
      throw const LinkChannelException(LinkChannelError.notParticipant);
    }
    final blockers = lockBlockers(people);
    if (blockers.isNotEmpty) throw LockNotEligibleException(blockers);
    final at = nextLwwClock(meta.updatedAt);
    final signed = await w.signer.group(
      meta.nextVersion(updatedAt: at, link: null, lockedAt: at),
    );
    if (signed.sig == null) {
      throw const TransportUnavailableException('signing key not ready');
    }
    if (w.db.isClosed) return;
    await engine.lockLink(groupId, signed);
    await w.replicate(groupId, groupMetaEventType, groupMetaPayload(signed));
  },
);
