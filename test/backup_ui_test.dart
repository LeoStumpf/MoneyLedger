/// Backup UI (G5) + CSV import preview (G13): settings sheet entries, the
/// restore / CSV preview dialogs and the groups-page nudge card.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_ledger/core/l10n/formatting.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/backup/backup_providers.dart';
import 'package:money_ledger/features/backup/backup_service.dart';
import 'package:money_ledger/features/backup/backup_ui.dart';
import 'package:money_ledger/features/backup/csv_import.dart';
import 'package:money_ledger/features/backup/ledger_backup.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

void main() {
  group('settings sheet', () {
    testWidgets('shows the backup section: never backed up', (tester) async {
      await tester.pumpWidget(
        testApp(const GroupsPage(), overrides: testOverrides(isLoggedIn: true)),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Backup'), findsOneWidget);
      expect(find.text('Last backup: never'), findsOneWidget);
      expect(find.byKey(const Key('backupExportTile')), findsOneWidget);
      expect(find.text('Back up all groups'), findsOneWidget);
      // The export says the file is not encrypted.
      expect(find.textContaining('not encrypted'), findsOneWidget);
      expect(find.byKey(const Key('backupRestoreTile')), findsOneWidget);
      expect(find.text('Restore from backup'), findsOneWidget);
    });

    testWidgets('backing up closes the sheet so its snackbar is visible', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(const GroupsPage(), overrides: testOverrides(isLoggedIn: true)),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      // No file dialog in tests → the export fails; what matters is that the
      // result shows on the page, not under the (closed) sheet.
      await tester.tap(find.byKey(const Key('backupExportTile')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('backupExportTile')), findsNothing);
      expect(find.textContaining('Export failed'), findsOneWidget);
    });

    testWidgets('shows the last backup date (German)', (tester) async {
      final at = DateTime(2026, 10, 1, 12).millisecondsSinceEpoch;
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          locale: const Locale('de'),
          overrides: testOverrides(isLoggedIn: true, lastBackupAt: at),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Einstellungen'));
      await tester.pumpAndSettle();

      expect(
        find.text('Letzte Sicherung: ${formatDate(at, 'de')}'),
        findsOneWidget,
      );
      expect(find.text('Alle Gruppen sichern'), findsOneWidget);
    });
  });

  group('restore preview dialog', () {
    LedgerBackup backup({String? account = '@me:x'}) => parseBackup(
      buildBackupJson(
        account: account,
        exportedAt: DateTime(2026, 10, 2).millisecondsSinceEpoch,
        groups: const [],
      ),
    );
    GroupRestorePlan plan(
      String name, {
      bool isNew = false,
      bool wasLeft = false,
      int changes = 0,
      int expenses = 2,
      int payments = 1,
    }) => GroupRestorePlan(
      summary: BackupGroupSummary(
        groupId: name,
        name: name,
        expenseCount: expenses,
        settlementCount: payments,
        memberCount: 2,
      ),
      isNew: isNew,
      wasLeft: wasLeft,
      changes: changes,
    );

    Future<bool?> show(WidgetTester tester, RestorePreview p) async {
      bool? result;
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showDialog<bool>(
                context: context,
                builder: (_) => RestorePreviewDialog(preview: p),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('a no-op restore says so', (tester) async {
      await show(
        tester,
        RestorePreview(
          backup: backup(),
          groups: [plan('G7a Test'), plan('G7a Probe')],
          otherAccount: false,
        ),
      );
      expect(find.text('Backup from Oct 2, 2026'), findsOneWidget);
      expect(find.text('2 groups · 4 expenses · 2 payments'), findsOneWidget);
      expect(find.text('No new groups'), findsOneWidget);
      expect(
        find.text('Everything in this backup is already on this device.'),
        findsOneWidget,
      );
      expect(find.text('up to date'), findsNWidgets(2));
      expect(find.byKey(const Key('restoreOtherAccount')), findsNothing);
    });

    testWidgets('new / left / changed groups and another account', (
      tester,
    ) async {
      await show(
        tester,
        RestorePreview(
          backup: backup(account: '@other:y'),
          groups: [
            plan('Fresh', isNew: true, changes: 5),
            plan('Gone', isNew: true, wasLeft: true, changes: 4),
            plan('Edited', changes: 1),
          ],
          otherAccount: true,
        ),
      );
      expect(find.byKey(const Key('restoreOtherAccount')), findsOneWidget);
      expect(find.textContaining('made by @other:y'), findsOneWidget);
      expect(find.text('2 new groups'), findsOneWidget);
      expect(find.text('10 entries will be added or updated.'), findsOneWidget);
      expect(find.text('new'), findsOneWidget);
      expect(find.text('left earlier — comes back'), findsOneWidget);
      expect(find.text('1 change'), findsOneWidget);
      expect(find.textContaining('Groups you left or deleted'), findsOneWidget);

      await tester.tap(find.byKey(const Key('restoreConfirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('restorePreviewDialog')), findsNothing);
    });

    testWidgets('backup error messages are localized', (tester) async {
      expect(
        backupErrorMessage(
          const BackupFormatException(
            BackupErrorKind.newerVersion,
            '',
            version: 3,
          ),
          en,
        ),
        contains('newer version of MoneyLedger (format 3)'),
      );
      expect(
        backupErrorMessage(
          const BackupFormatException(BackupErrorKind.notABackup, ''),
          de,
        ),
        'Diese Datei ist keine MoneyLedger-Sicherung.',
      );
    });
  });

  testWidgets('CSV preview dialog shows the name warnings', (tester) async {
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => const CsvImportPreviewDialog(
                preview: CsvImportPreview(
                  groupName: 'Trip',
                  isNewGroup: false,
                  expenseCount: 3,
                  paymentCount: 1,
                  unmatched: ['Sam', 'Kim'],
                  ambiguous: ['Alex'],
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Import CSV?'), findsOneWidget);
    expect(
      find.textContaining('Merges into your group “Trip”'),
      findsOneWidget,
    );
    expect(find.text('3 expenses · 1 payment'), findsOneWidget);
    expect(find.textContaining('new people: Sam, Kim'), findsOneWidget);
    expect(find.textContaining('the active one is used: Alex'), findsOneWidget);
  });

  group('backup nudge on the groups page', () {
    const group = GroupModel(roomId: 'g1', name: 'Solo', currency: 'EUR');
    const meMember = MemberModel(
      groupId: 'g1',
      userId: '@me:x',
      displayName: 'Me',
      matrixId: '@me:x',
      status: 'active',
      updatedAt: 1,
    );
    // A tiny in-memory stand-in for the snooze setting.
    int? snoozedUntil;
    late List<StreamController<int?>> listeners;
    late List<int> snoozedTo;
    setUp(() {
      snoozedUntil = null;
      listeners = [];
      snoozedTo = [];
    });

    List<dynamic> overrides(List<MemberModel> members, {int? lastBackupAt}) => [
      isLoggedInProvider.overrideWith((ref) => true),
      ledgerGroupsProvider.overrideWith((_) => Stream.value(const [group])),
      allMembersProvider.overrideWith((_) => Stream.value(members)),
      // The group card's overview reads these (G17).
      groupMembersProvider.overrideWith((ref, g) => Stream.value(members)),
      expensesForRoomProvider.overrideWith((ref, g) => Stream.value([])),
      settlementsForRoomProvider.overrideWith((ref, g) => Stream.value([])),
      currentUserIdProvider.overrideWith((_) => '@me:x'),
      lastBackupAtProvider.overrideWith((_) => Stream.value(lastBackupAt)),
      backupNudgeSnoozedUntilProvider.overrideWith((ref) {
        final c = StreamController<int?>()..add(snoozedUntil);
        listeners.add(c);
        ref.onDispose(c.close);
        return c.stream;
      }),
      snoozeBackupNudgeProvider.overrideWith(
        (_) => (until) async {
          snoozedTo.add(until);
          snoozedUntil = until;
          for (final c in listeners) {
            if (!c.isClosed) c.add(until);
          }
        },
      ),
    ];

    testWidgets('shows for a solo group without backup; Later snoozes it', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(const GroupsPage(), overrides: overrides([meMember])),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('backupNudge')), findsOneWidget);
      expect(find.text('Back up your groups'), findsOneWidget);
      expect(
        find.textContaining('1 group exists only on this device'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('backupNudgeLater')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backupNudge')), findsNothing);
      expect(
        snoozedTo.single - DateTime.now().millisecondsSinceEpoch,
        greaterThan(const Duration(days: 29).inMilliseconds),
      );
    });

    testWidgets('hidden when another claimed member can restore the group', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          overrides: overrides([
            meMember,
            const MemberModel(
              groupId: 'g1',
              userId: '@bo:x',
              displayName: 'Bo',
              matrixId: '@bo:x',
              status: 'active',
              updatedAt: 1,
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Solo'), findsOneWidget);
      expect(find.byKey(const Key('backupNudge')), findsNothing);
    });

    testWidgets('hidden after a recent backup', (tester) async {
      await tester.pumpWidget(
        testApp(
          const GroupsPage(),
          overrides: overrides([
            meMember,
          ], lastBackupAt: DateTime.now().millisecondsSinceEpoch),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Solo'), findsOneWidget);
      expect(find.byKey(const Key('backupNudge')), findsNothing);
    });
  });
}
