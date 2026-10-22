/// G74 — **my payment details go to my groups.** The details from Settings
/// → Payment details (device-local, `AppSettings` `payment_details`) are
/// written as the optional signed `payment` field of **my participant** in
/// every group I'm active in — Matrix groups (signed, relayed to the
/// group's Matrix members) and link groups (unsigned link version, `by` =
/// me — the link sync engine republishes the snapshot; anyone with the
/// link can read them). Local mode's own groups get nothing (nobody to
/// read them; a local-mode adoption moves the settings, and the account
/// then publishes).
///
/// When ([paymentPublisherProvider]): on every ledger DB open, after the
/// settings change, and after my participants change (a group joined or
/// created, a claim, a stale editor's version) — debounced.
///
/// Where ([publishPaymentDetails]), per group with an active "me"
/// (`myParticipantIn`): a group with a link channel, or "me" claimed by
/// this device's Matrix account. A group whose stored value already equals
/// the target is left alone. Otherwise:
/// - the settings changed since this device last distributed them
///   (`payment_published`) → written;
/// - else written unless the stored version came from **my own other
///   device** (written by the participant itself and received — history
///   source `inbound`): two own devices with different device-local
///   settings must not overwrite each other forever; the newer explicit
///   change wins. A version of this device (creation, an edit before the
///   details existed), a restore, or another member's version that carried
///   none / an older value (accepted by `RecordGate` since the G74 review)
///   is replaced — the **re-publish**.
///
/// Every write is a new LWW version (`nextLwwClock`) through the normal
/// [LocalRecordSigner] (signed / `pendingSign` / link version); a group the
/// signer refuses (local mode in a locked / claimed mixed group) is skipped.
library;

import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/history_dao.dart';
import '../../core/database/daos/link_dao.dart';
import '../../core/database/daos/members_dao.dart';
import '../../core/database/daos/settings_dao.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import '../../core/session/app_session.dart';
import '../../core/sync/delivery_policy.dart';
import '../../core/sync/ledger_payloads.dart';
import '../../core/sync/record_signing.dart';
import '../../core/sync/record_validation.dart'
    show isValidMxid, paymentProblem;
import '../../models/member_model.dart';
import '../../models/payment_details.dart';
import '../expenses/expenses_provider.dart' show appDatabaseProvider;
import '../groups/group_provider.dart' show myParticipantIn;

/// The part of [d] that may go into a member record (`paymentProblem`):
/// the bank account only with its holder (BIC only next to an IBAN),
/// PayPal.me; null when nothing usable is left.
PaymentDetails? publishablePayment(PaymentDetails? d) {
  if (d == null) return null;
  final bank = d.hasBankAccount;
  final p = PaymentDetails(
    name: bank ? d.name : null,
    iban: bank ? d.iban : null,
    bic: bank ? d.bic : null,
    paypalMe: d.paypalMe,
  );
  if (p.isEmpty || paymentProblem(p) != null) return null;
  return p;
}

/// `payment_published` value for [p].
String publishedMarker(PaymentDetails? p) => p?.encode() ?? 'none';

/// One version [publishPaymentDetails] wrote.
class PublishedPayment {
  const PublishedPayment(this.groupId, this.member);
  final String groupId;
  final MemberModel member;
}

/// Whether participant version [m] was written by the participant itself
/// (as `RecordGate` decides it for the `payment` field).
bool writtenByParticipant(MemberModel m) {
  final sig = m.sig;
  if (sig != null) return m.matrixId != null && sig.user == m.matrixId;
  return m.linkAuthor != null && m.linkAuthor == m.userId;
}

/// Writes [details] into this device's participant of every eligible group
/// of [db] — see the library doc. [myId]: the ledger identity (MXID or
/// `local:self`). Returns what was written; records the distributed value
/// in `payment_published` once every group was handled.
Future<List<PublishedPayment>> publishPaymentDetails({
  required AppDatabase db,
  required String myId,
  required PaymentDetails? details,
  required LocalRecordSigner signer,
  bool Function()? isAlive,
  int Function()? clock,
}) async {
  bool alive() => !db.isClosed && (isAlive?.call() ?? true);
  final target = publishablePayment(details);
  final settings = SettingsDao(db);
  final marker = publishedMarker(target);
  final published = await settings.paymentPublishedRaw();
  final changed = (published ?? 'none') != marker;
  final groups = GroupsDao(db);
  final members = MembersDao(db);
  final link = LinkDao(db);
  final history = HistoryDao(db);
  final out = <PublishedPayment>[];
  for (final g in await groups.getAllGroups()) {
    if (!alive()) return out;
    final groupId = g.roomId;
    final me = await myParticipantIn(members, link, groupId, myId);
    if (me == null || !me.isActive || me.payment == target) continue;
    final linked = await link.getChannel(groupId) != null;
    if (!linked && !(isValidMxid(myId) && me.matrixId == myId)) continue;
    if (!changed && writtenByParticipant(me)) {
      final entries = await history.entriesForRecord(
        groupId,
        RecordKind.member,
        me.userId,
      );
      if (entries.isNotEmpty && entries.last.source == HistorySource.inbound) {
        continue; // my other device's choice
      }
    }
    final MemberModel written;
    try {
      written = await signer.member(
        MemberModel(
          groupId: groupId,
          userId: me.userId,
          displayName: me.displayName,
          matrixId: me.matrixId,
          status: me.status,
          updatedAt: nextLwwClock(me.updatedAt, now: clock?.call()),
          payment: target,
        ),
      );
    } on SignatureRequiredException {
      continue;
    }
    if (!alive()) return out;
    await members.upsertMemberLww(memberCompanion(written));
    out.add(PublishedPayment(groupId, written));
  }
  if (alive() && published != marker) {
    await settings.setPaymentPublishedRaw(marker);
  }
  return out;
}

/// Relays the signed versions of [written] to each group's active Matrix
/// members (self included — our other devices). Best-effort: the digest
/// repairs a lost one; unsigned versions (link / `pendingSign`) aren't sent.
Future<void> relayPublishedPayments(
  List<PublishedPayment> written, {
  required MembersDao members,
  required LedgerTransport transport,
  bool Function()? isAlive,
}) async {
  for (final w in written) {
    if (isAlive != null && !isAlive()) return;
    if (w.member.sig == null) continue;
    try {
      final targets = (await members.activeClaimedMatrixIds(w.groupId)).toSet();
      if (targets.isEmpty) continue;
      await transport.sendToUsers(
        targets,
        memberEventType,
        memberPayload(w.member),
      );
    } catch (e) {
      debugPrint('[payment] relaying to ${w.groupId} failed: $e');
    }
  }
}

/// How long [paymentPublisherProvider] waits after a trigger.
final paymentPublishDebounceProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 2),
);

/// G74: keeps my payment details in my groups (library doc). Watched
/// app-wide by `LedgerSyncHost`, rebuilt with the ledger DB; never throws.
final paymentPublisherProvider = Provider<void>((ref) {
  final myId = ref.watch(ledgerIdentityProvider);
  if (myId == null) return;
  final db = ref.watch(appDatabaseProvider);
  if (db.isSignedOutPlaceholder || db.isClosed) return;
  final settings = SettingsDao(db);
  final transport = withDeliveryPolicy(
    ref.read(ledgerTransportProvider.future),
    settings,
  )..ignore();
  final signer = LocalRecordSigner(transport, policy: LinkDao(db).policyOf);
  final debounce = ref.read(paymentPublishDebounceProvider);
  var disposed = false;
  bool alive() => !disposed && !db.isClosed;
  Timer? timer;
  var running = false;
  var again = false;

  Future<void> run() async {
    if (running) {
      again = true;
      return;
    }
    running = true;
    try {
      do {
        again = false;
        final details = PaymentDetails.decode(
          await settings.paymentDetailsRaw(),
        );
        if (!alive()) return;
        final written = await publishPaymentDetails(
          db: db,
          myId: myId,
          details: details,
          signer: signer,
          isAlive: alive,
        );
        if (written.isEmpty || !alive()) continue;
        debugPrint('[payment] details written into ${written.length} groups');
        await relayPublishedPayments(
          written,
          members: MembersDao(db),
          transport: await transport,
          isAlive: alive,
        );
      } while (again && alive());
    } catch (e) {
      if (alive()) debugPrint('[payment] distribution failed (retried): $e');
    } finally {
      running = false;
    }
  }

  void schedule() {
    if (!alive()) return;
    timer?.cancel();
    timer = Timer(debounce, () => unawaited(run()));
  }

  final subs = [
    // Distinct: every AppSettings write re-runs the query.
    settings.watchPaymentDetailsRaw().distinct().listen((_) => schedule()),
    db
        .tableUpdates(
          TableUpdateQuery.onAllTables([db.members, db.linkChannels]),
        )
        .listen((_) => schedule()),
  ];
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
    for (final s in subs) {
      unawaited(s.cancel());
    }
  });
  schedule();
});
