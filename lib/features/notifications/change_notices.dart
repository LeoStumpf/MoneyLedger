/// G72: what a background round tells the user about **others' changes** —
/// pure planning (which history entries are worth a notification) and the
/// localized texts. No platform code; the Android glue is
/// `notification_platform_native.dart`.
///
/// Source of truth is the G48 version history: a round notes the newest
/// `record_history` id before it syncs ([collectChangeNotices]); every
/// expense / payment version stored after that with source `inbound` is a
/// candidate. Left out: versions written by this account (another own
/// device — the signer is our MXID) or by "me" in a link group (`by` = my
/// participant), restores, CSV imports, resets, member / name changes.
library;

import '../../core/database/app_database.dart';
import '../../core/database/daos/groups_dao.dart';
import '../../core/database/daos/history_dao.dart';
import '../../core/database/daos/link_dao.dart';
import '../../core/database/daos/members_dao.dart';
import '../../core/l10n/formatting.dart';
import '../../core/sync/record_signing.dart' show RecordKind;
import '../../l10n/app_localizations.dart';
import '../../models/member_model.dart';
import '../../models/record_signature.dart';

/// Which record changed.
enum NoticeRecord { expense, payment }

/// What happened to it.
enum NoticeAction { added, edited, deleted }

/// One change by someone else.
class NoticeChange {
  const NoticeChange({
    required this.record,
    required this.action,
    required this.author,
    required this.amountCents,
    required this.currency,
    this.description,
    this.from,
    this.to,
  });

  final NoticeRecord record;
  final NoticeAction action;

  /// The author's name in the group; null = unknown (an unsigned version).
  final String? author;
  final int amountCents;
  final String currency;

  /// Expense description.
  final String? description;

  /// Payment sides (names).
  final String? from;
  final String? to;

  @override
  String toString() =>
      'NoticeChange(${record.name} ${action.name} by $author: '
      '${description ?? '$from→$to'} $amountCents $currency)';
}

/// The changes of one group in one round — one notification.
class ChangeNotice {
  const ChangeNotice({
    required this.groupId,
    required this.groupName,
    required this.changes,
    this.newGroup = false,
  });

  final String groupId;
  final String groupName;

  /// The group arrived in this round (someone added us).
  final bool newGroup;
  final List<NoticeChange> changes;

  @override
  String toString() =>
      'ChangeNotice($groupName, new: $newGroup, ${changes.length} changes)';
}

/// What a group looks like for [planChangeNotices].
class NoticeGroup {
  const NoticeGroup({
    required this.name,
    required this.members,
    this.myParticipantId,
  });

  final String name;
  final List<MemberModel> members;

  /// "Me" of a link group (`link_channels.my_participant_id`).
  final String? myParticipantId;
}

/// Who wrote a version: [mine] = this account / "me"; else [name] (null =
/// unknown).
typedef _Author = ({bool mine, String? name});

_Author _authorOf(
  Map<String, dynamic> content,
  NoticeGroup g,
  String identity,
  String? myClaimed,
) {
  final signer = RecordSignature.fromJson(content['sig'])?.user;
  if (signer != null && signer.isNotEmpty) {
    if (signer == identity) return (mine: true, name: null);
    final m = claimedBy(g.members, signer);
    return (mine: false, name: m?.label ?? localpartOf(signer));
  }
  final by = content['by'];
  if (by is String && by.isNotEmpty) {
    if (by == g.myParticipantId || by == myClaimed) {
      return (mine: true, name: null);
    }
    return (mine: false, name: _nameOf(g, by));
  }
  return (mine: false, name: null);
}

String? _nameOf(NoticeGroup g, String participantId) {
  for (final m in g.members) {
    if (m.userId == participantId) return m.label;
  }
  return null;
}

/// Plans the notifications of one round (pure).
///
/// [entries]: the history entries stored during the round (append order);
/// [groupsBefore]: groups with history before the round; [recordsBefore]:
/// `"<kind>:<id>"` of records with history before it; [groups]: the
/// groups' names / people; [identity]: this ledger's account (MXID, or
/// `local:self`).
///
/// Per record only its newest inbound version counts: not held before →
/// *added* (a record added and deleted within the round is skipped), held
/// and now a tombstone → *deleted*, else *edited*. A group new in this
/// round becomes one "you were added" notice when someone else wrote any of
/// it. Groups sorted by name.
List<ChangeNotice> planChangeNotices({
  required List<HistoryEntry> entries,
  required Set<String> groupsBefore,
  required Set<String> recordsBefore,
  required Map<String, NoticeGroup> groups,
  required String identity,
}) {
  // Newest inbound version per record, per group (insertion = append order).
  final latest = <String, Map<String, HistoryEntry>>{};
  final othersWrote = <String>{};
  for (final e in entries) {
    if (e.source != HistorySource.inbound) continue;
    final g = groups[e.groupId];
    if (g == null) continue;
    final myClaimed = claimedBy(g.members, identity)?.userId;
    final author = _authorOf(e.content, g, identity, myClaimed);
    if (!author.mine) othersWrote.add(e.groupId);
    if (e.kind != RecordKind.expense && e.kind != RecordKind.settlement) {
      continue;
    }
    final perGroup = latest.putIfAbsent(e.groupId, () => {});
    final key = '${e.kind.wire}:${e.recordId}';
    perGroup.remove(key); // keep the map in order of the newest version
    perGroup[key] = e;
  }

  final notices = <ChangeNotice>[];
  final groupIds = {...latest.keys, ...othersWrote};
  for (final gid in groupIds) {
    final g = groups[gid]!;
    final myClaimed = claimedBy(g.members, identity)?.userId;
    final changes = <NoticeChange>[];
    for (final MapEntry(key: key, value: e) in (latest[gid] ?? {}).entries) {
      final author = _authorOf(e.content, g, identity, myClaimed);
      if (author.mine) continue;
      final before = recordsBefore.contains(key);
      final NoticeAction action;
      if (e.deleted) {
        if (!before) continue;
        action = NoticeAction.deleted;
      } else {
        action = before ? NoticeAction.edited : NoticeAction.added;
      }
      final expense = e.expense;
      final settlement = e.settlement;
      if (expense != null) {
        changes.add(
          NoticeChange(
            record: NoticeRecord.expense,
            action: action,
            author: author.name,
            amountCents: expense.amountCents,
            currency: expense.currency,
            description: expense.description.trim().isEmpty
                ? null
                : expense.description.trim(),
          ),
        );
      } else if (settlement != null) {
        changes.add(
          NoticeChange(
            record: NoticeRecord.payment,
            action: action,
            author: author.name,
            amountCents: settlement.amountCents,
            currency: settlement.currency,
            from: _nameOf(g, settlement.fromUser),
            to: _nameOf(g, settlement.toUser),
          ),
        );
      }
    }
    final isNew = !groupsBefore.contains(gid);
    if (isNew ? !othersWrote.contains(gid) : changes.isEmpty) continue;
    notices.add(
      ChangeNotice(
        groupId: gid,
        groupName: g.name,
        newGroup: isNew,
        changes: changes,
      ),
    );
  }
  notices.sort(
    (a, b) => a.groupName.toLowerCase().compareTo(b.groupName.toLowerCase()),
  );
  return notices;
}

/// Reads what [planChangeNotices] needs from the ledger DB: the history
/// stored after [afterHistoryId] and the groups it touched.
Future<List<ChangeNotice>> collectChangeNotices(
  AppDatabase db, {
  required int afterHistoryId,
  required String identity,
}) async {
  final history = HistoryDao(db);
  final entries = (await history.entriesAfter(
    afterHistoryId,
  )).where((e) => e.source == HistorySource.inbound).toList();
  if (entries.isEmpty) return const [];
  final groupsBefore = await history.groupsWithEntriesUpTo(afterHistoryId);
  final recordsBefore = await history.recordsWithEntriesUpTo(afterHistoryId, {
    for (final e in entries) e.recordId,
  });
  final groups = <String, NoticeGroup>{};
  for (final gid in {for (final e in entries) e.groupId}) {
    final meta = await GroupsDao(db).getGroup(gid);
    if (meta == null) continue; // left / purged meanwhile
    groups[gid] = NoticeGroup(
      name: meta.name,
      members: await MembersDao(db).getMembers(gid),
      myParticipantId: (await LinkDao(db).getChannel(gid))?.myParticipantId,
    );
  }
  return planChangeNotices(
    entries: entries,
    groupsBefore: groupsBefore,
    recordsBefore: recordsBefore,
    groups: groups,
    identity: identity,
  );
}

/// The localized text of one notification: [lines] (one per change, at
/// most [kNoticeMaxLines]) for the expanded view when there are several.
typedef NoticeText = ({String title, String body, List<String> lines});

/// Lines shown in an expanded notification.
const kNoticeMaxLines = 6;

/// Builds the text of [n] in [l] (amounts formatted for [l]'s locale).
NoticeText noticeText(ChangeNotice n, AppLocalizations l) {
  final lines = [for (final c in n.changes) _line(c, l)];
  final String body;
  if (n.newGroup) {
    body = l.notifyAddedToGroup(n.changes.length);
  } else if (lines.length == 1) {
    body = lines.single;
  } else {
    final names = <String>[];
    for (final c in n.changes) {
      final name = c.author ?? l.notifySomeone;
      if (!names.contains(name)) names.add(name);
    }
    final shown = names.length > 3
        ? '${names.take(3).join(', ')} +${names.length - 3}'
        : names.join(', ');
    body = l.notifySeveralChanges(n.changes.length, shown);
  }
  final shownLines = lines.length > kNoticeMaxLines
      ? [...lines.take(kNoticeMaxLines - 1), '…']
      : lines;
  return (
    title: n.groupName,
    body: body,
    lines: lines.length > 1 || n.newGroup ? shownLines : const [],
  );
}

String _line(NoticeChange c, AppLocalizations l) {
  final who = c.author ?? l.notifySomeone;
  final amount = formatMoney(c.amountCents, c.currency, l.localeName);
  switch (c.record) {
    case NoticeRecord.expense:
      final what = c.description ?? l.notifyAnExpense;
      return switch (c.action) {
        NoticeAction.added => l.notifyExpenseAdded(who, what, amount),
        NoticeAction.edited => l.notifyExpenseEdited(who, what),
        NoticeAction.deleted => l.notifyExpenseDeleted(who, what),
      };
    case NoticeRecord.payment:
      final from = c.from ?? l.notifySomeone;
      final to = c.to ?? l.notifySomeone;
      return switch (c.action) {
        NoticeAction.added => l.notifyPaymentAdded(who, from, to, amount),
        NoticeAction.edited => l.notifyPaymentEdited(who, from, to),
        NoticeAction.deleted => l.notifyPaymentDeleted(who, from, to),
      };
  }
}

/// A stable notification id per group (FNV-1a, 31 bits): a later round
/// replaces the group's earlier notification instead of stacking up.
int noticeIdFor(String groupId) {
  var h = 0x811c9dc5;
  for (final c in groupId.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}
