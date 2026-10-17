/// G58: the restore preview's "Exactly this state" option — off by default
/// (the merge), on → per-group reset counts + the overwrite warning.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/backup/backup_service.dart';
import 'package:money_ledger/features/backup/backup_ui.dart';
import 'package:money_ledger/features/backup/ledger_backup.dart';
import 'package:money_ledger/features/history/group_history.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';

import 'helpers/test_providers.dart';

ExpenseModel _e(String id, {bool deleted = false}) => ExpenseModel(
  id: id,
  roomId: 'trip',
  description: id,
  amountCents: 100,
  currency: 'EUR',
  paidBy: 'p1',
  splitsJson: '{"p1":100}',
  createdAt: 1,
  updatedAt: 2,
  deleted: deleted,
);

GroupRestorePlan _plan(String id, {bool isNew = false, int changes = 0}) =>
    GroupRestorePlan(
      summary: BackupGroupSummary(
        groupId: id,
        name: id,
        expenseCount: 2,
        settlementCount: 0,
        memberCount: 2,
      ),
      isNew: isNew,
      wasLeft: false,
      changes: changes,
    );

RestorePreview _preview() => RestorePreview(
  backup: parseBackup(
    buildBackupJson(account: '@me:x', exportedAt: 1, groups: const []),
  ),
  groups: [
    _plan('trip'),
    _plan('flat', changes: 1),
    _plan('fresh', isNew: true),
  ],
  otherAccount: false,
);

final _exactPlans = {
  'trip': GroupResetPlan(
    groupId: 'trip',
    beforeId: 0,
    changes: [
      ResetChange.expense(ResetEffect.restored, _e('a')),
      ResetChange.expense(ResetEffect.reverted, _e('b')),
      ResetChange.expense(ResetEffect.removed, _e('c', deleted: true)),
      ResetChange.expense(ResetEffect.removed, _e('d', deleted: true)),
    ],
    meta: const GroupModel(roomId: 'trip', name: 'Trip', currency: 'EUR'),
    arriving: 1,
    skipped: 1,
  ),
};

Future<List<bool>> _open(
  WidgetTester tester, {
  Locale? locale,
  bool shared = true,
  Map<String, GroupResetPlan>? exactPlans,
}) async {
  final changes = <bool>[];
  await tester.pumpWidget(
    testApp(
      locale: locale,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<bool>(
            context: context,
            builder: (_) => RestorePreviewDialog(
              preview: _preview(),
              exactPlans: exactPlans ?? _exactPlans,
              exactShared: shared,
              onExactChanged: changes.add,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return changes;
}

void main() {
  testWidgets('off by default: the merge preview, no warning', (tester) async {
    await _open(tester);
    expect(find.byKey(const Key('restoreExactSwitch')), findsOneWidget);
    expect(find.text('Exactly this state'), findsOneWidget);
    final sw = tester.widget<SwitchListTile>(
      find.byKey(const Key('restoreExactSwitch')),
    );
    expect(sw.value, isFalse);
    expect(find.byKey(const Key('restoreExactWarning')), findsNothing);
    expect(find.byKey(const Key('restoreExactTag-trip')), findsNothing);
    expect(find.text('up to date'), findsOneWidget); // trip, merge view
  });

  testWidgets('on: per-group counts, the overwrite warning, and the choice '
      'is reported', (tester) async {
    final changes = await _open(tester);
    await tester.tap(find.byKey(const Key('restoreExactSwitch')));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(
      find.textContaining('also other members'),
      findsOneWidget,
      reason: 'warns that others\' newer changes are overwritten',
    );
    final tag = tester.widget<Text>(
      find.byKey(const Key('restoreExactTag-trip')),
    );
    // 1 restored + 1 arriving via the merge = 2 come back.
    expect(
      tag.data,
      '2 entries come back · 1 change is undone · 2 entries are removed · '
      'group settings',
    );
    // A group that can't be reset exactly (not an active member): merge only.
    expect(find.text('only missing entries'), findsOneWidget);
    // A new group just comes back.
    expect(find.text('new'), findsOneWidget);
    expect(find.textContaining("can't be used"), findsOneWidget);

    await tester.tap(find.byKey(const Key('restoreExactSwitch')));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    expect(find.byKey(const Key('restoreExactWarning')), findsNothing);
  });

  testWidgets('German + local mode wording', (tester) async {
    await _open(tester, locale: const Locale('de'), shared: false);
    expect(find.text('Genau diesen Stand'), findsOneWidget);
    await tester.tap(find.byKey(const Key('restoreExactSwitch')));
    await tester.pumpAndSettle();
    expect(
      find.text('Neuere Änderungen in diesen Gruppen werden überschrieben.'),
      findsOneWidget,
    );
  });

  testWidgets('no group can be reset → no option', (tester) async {
    await _open(tester, exactPlans: const {});
    expect(find.byKey(const Key('restoreExactSwitch')), findsNothing);
  });

  testWidgets('a plain RestorePreviewDialog (backup file) has no option', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => RestorePreviewDialog(preview: _preview()),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('restoreExactSwitch')), findsNothing);
  });
}
