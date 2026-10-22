/// G72: which background-round changes become a notification, and their
/// EN / DE texts (pure).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/history_dao.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart' show RecordKind;
import 'package:money_ledger/features/notifications/change_notices.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/member_model.dart';
import 'package:money_ledger/models/record_signature.dart';

import '../helpers/l10n.dart';

const me = '@me:x.org';
const anna = '@anna:x.org';
const g = 'g1';

RecordSignature sig(String user) =>
    RecordSignature(user: user, device: 'D', key: 'k', sig: 's');

var _id = 0;

HistoryEntry expenseEntry(
  String id, {
  String? signer,
  String? by,
  bool deleted = false,
  String description = 'Dinner',
  HistorySource source = HistorySource.inbound,
  String group = g,
}) {
  final e = ExpenseModel(
    id: id,
    roomId: group,
    description: description,
    amountCents: 4210,
    currency: 'EUR',
    paidBy: 'p-anna',
    splitsJson: '{"p-anna":2105,"p-me":2105}',
    createdAt: 1,
    updatedAt: 2,
    deleted: deleted,
    sig: signer == null ? null : sig(signer),
    linkAuthor: by,
  );
  return HistoryEntry(
    id: ++_id,
    groupId: group,
    kind: RecordKind.expense,
    recordId: id,
    updatedAt: 2,
    versionHash: 'h',
    content: expensePayload(e),
    source: source,
    recordedAt: 3,
  );
}

HistoryEntry paymentEntry(String id, {String? signer}) {
  final s = SettlementModel(
    id: id,
    roomId: g,
    amountCents: 2000,
    currency: 'EUR',
    fromUser: 'p-me',
    toUser: 'p-anna',
    createdAt: 1,
    updatedAt: 2,
    sig: signer == null ? null : sig(signer),
  );
  return HistoryEntry(
    id: ++_id,
    groupId: g,
    kind: RecordKind.settlement,
    recordId: id,
    updatedAt: 2,
    versionHash: 'h',
    content: settlementPayload(s),
    source: HistorySource.inbound,
    recordedAt: 3,
  );
}

const members = [
  MemberModel(
    groupId: g,
    userId: 'p-anna',
    displayName: 'Anna',
    matrixId: anna,
    status: 'active',
    updatedAt: 1,
  ),
  MemberModel(
    groupId: g,
    userId: 'p-me',
    displayName: 'Me',
    matrixId: me,
    status: 'active',
    updatedAt: 1,
  ),
  MemberModel(
    groupId: g,
    userId: 'p-ben',
    displayName: 'Ben',
    status: 'active',
    updatedAt: 1,
  ),
];

List<ChangeNotice> plan(
  List<HistoryEntry> entries, {
  Set<String> recordsBefore = const {},
  Set<String> groupsBefore = const {g},
  String? myParticipantId,
}) => planChangeNotices(
  entries: entries,
  groupsBefore: groupsBefore,
  recordsBefore: recordsBefore,
  groups: {
    g: NoticeGroup(
      name: 'Trip',
      members: members,
      myParticipantId: myParticipantId,
    ),
  },
  identity: me,
);

void main() {
  test('an expense someone else added → one notice with name, '
      'description and amount', () {
    final n = plan([expenseEntry('e1', signer: anna)]);
    expect(n, hasLength(1));
    expect(n.single.groupName, 'Trip');
    expect(n.single.newGroup, isFalse);
    final c = n.single.changes.single;
    expect(c.action, NoticeAction.added);
    expect(c.author, 'Anna');
    expect(noticeText(n.single, en).body, 'Anna added Dinner · €42.10');
    expect(
      noticeText(n.single, de).body,
      'Anna hat Dinner eingetragen · 42,10\u00a0€',
    );
    expect(noticeText(n.single, en).lines, isEmpty);
  });

  test('own versions (another own device / "me" in a link group) and '
      'non-inbound sources are left out', () {
    expect(plan([expenseEntry('e1', signer: me)]), isEmpty);
    expect(
      plan([expenseEntry('e1', by: 'p-link-me')], myParticipantId: 'p-link-me'),
      isEmpty,
    );
    // The participant this account claims counts as "me" too.
    expect(plan([expenseEntry('e1', by: 'p-me')]), isEmpty);
    for (final s in [
      HistorySource.local,
      HistorySource.restore,
      HistorySource.csvImport,
      HistorySource.revert,
      HistorySource.initial,
    ]) {
      expect(plan([expenseEntry('e1', signer: anna, source: s)]), isEmpty);
    }
  });

  test('edited / deleted need the record held before; added + deleted in '
      'one round is skipped', () {
    final edited = plan(
      [expenseEntry('e1', signer: anna)],
      recordsBefore: {'expense:e1'},
    );
    expect(edited.single.changes.single.action, NoticeAction.edited);
    expect(noticeText(edited.single, en).body, 'Anna changed Dinner');

    final deleted = plan(
      [expenseEntry('e1', signer: anna, deleted: true)],
      recordsBefore: {'expense:e1'},
    );
    expect(deleted.single.changes.single.action, NoticeAction.deleted);
    expect(noticeText(deleted.single, de).body, 'Anna hat Dinner gelöscht');

    expect(
      plan([
        expenseEntry('e1', signer: anna),
        expenseEntry('e1', signer: anna, deleted: true),
      ]),
      isEmpty,
    );
  });

  test('only the newest version of a record counts', () {
    final n = plan([
      expenseEntry('e1', signer: anna, description: 'Old'),
      expenseEntry('e1', signer: anna, description: 'New'),
    ]);
    expect(n.single.changes.single.description, 'New');
  });

  test('a link-group version names its author by participant; unknown '
      'authors are "Someone"', () {
    final n = plan([
      expenseEntry('e1', by: 'p-ben'),
      expenseEntry('e2'),
    ], myParticipantId: 'p-me');
    expect([for (final c in n.single.changes) c.author], ['Ben', null]);
    final t = noticeText(n.single, en);
    expect(t.body, '2 changes by Ben, Someone');
    expect(t.lines, [
      'Ben added Dinner · €42.10',
      'Someone added Dinner · €42.10',
    ]);
    expect(noticeText(n.single, de).body, '2 Änderungen von Ben, Jemand');
  });

  test('payments name both sides', () {
    final n = plan([paymentEntry('s1', signer: anna)]);
    expect(
      noticeText(n.single, en).body,
      'Anna recorded a payment: Me → Anna · €20.00',
    );
    expect(
      noticeText(n.single, de).body,
      'Anna hat eine Zahlung eingetragen: Me → Anna · 20,00\u00a0€',
    );
  });

  test('a group new in this round → "you were added" when someone else '
      'wrote it', () {
    final n = plan([expenseEntry('e1', signer: anna)], groupsBefore: {});
    expect(n.single.newGroup, isTrue);
    expect(
      noticeText(n.single, en).body,
      'You were added to this group — 1 entry.',
    );
    expect(
      noticeText(n.single, de).body,
      'Du wurdest zu dieser Gruppe hinzugefügt – 1 Eintrag.',
    );
    // Our own groups restored from another own device: nothing.
    expect(plan([expenseEntry('e1', signer: me)], groupsBefore: {}), isEmpty);
  });

  test('long lists are cut, many authors summarised', () {
    final n = plan([
      for (var i = 0; i < 8; i++) expenseEntry('e$i', signer: anna),
    ]);
    final t = noticeText(n.single, en);
    expect(t.lines, hasLength(kNoticeMaxLines));
    expect(t.lines.last, '…');
    expect(t.body, '8 changes by Anna');
  });

  test('stable, positive notification ids per group', () {
    expect(noticeIdFor('g1'), noticeIdFor('g1'));
    expect(noticeIdFor('g1'), isNot(noticeIdFor('g2')));
    expect(noticeIdFor('0190f1e2-aaaa-7bbb-8ccc-1234567890ab'), greaterThan(0));
  });
}
