/// Backup UI (G5) + CSV import preview (G13): settings sheet entries, the
/// restore / CSV preview dialogs and the groups-page nudge card.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_ledger/core/l10n/formatting.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/backup/backup_crypto.dart';
import 'package:money_ledger/features/backup/backup_providers.dart';
import 'package:money_ledger/features/backup/backup_service.dart';
import 'package:money_ledger/features/backup/backup_ui.dart';
import 'package:money_ledger/features/backup/csv_import.dart';
import 'package:money_ledger/features/backup/ledger_backup.dart';
import 'package:money_ledger/features/groups/group_archive_provider.dart';
import 'package:money_ledger/features/groups/group_exit_dialog.dart';
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
      // The export says the file can be encrypted — else it is plain text.
      expect(find.textContaining('optionally encrypted'), findsOneWidget);
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
      // (G56: the sheet grew a Devices tile — scroll the backup tile in.)
      await tester.ensureVisible(find.byKey(const Key('backupExportTile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('backupExportTile')));
      await tester.pumpAndSettle();

      // G34: first the optional passphrase; empty = plaintext, with a warning.
      expect(find.byKey(const Key('backupExportTile')), findsNothing);
      expect(find.byKey(const Key('backupPassphraseDialog')), findsOneWidget);
      expect(find.byKey(const Key('backupPlaintextWarning')), findsOneWidget);
      await tester.tap(find.byKey(const Key('backupPassphraseSave')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('backupPassphraseDialog')), findsNothing);
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

    testWidgets('G41: a local backup restored into an account is taken over', (
      tester,
    ) async {
      await show(
        tester,
        RestorePreview(
          backup: backup(account: 'local:self'),
          groups: [plan('Trip', isNew: true, changes: 4)],
          otherAccount: false,
          takeover: RestoreTakeover.localIntoAccount,
          myAccount: '@lea:x.test',
        ),
      );
      expect(find.byKey(const Key('restoreTakeover')), findsOneWidget);
      expect(
        find.textContaining('made without a Matrix account'),
        findsOneWidget,
      );
      expect(find.textContaining('into @lea:x.test'), findsOneWidget);
      expect(find.byKey(const Key('restoreOtherAccount')), findsNothing);
    });

    testWidgets('G41: an account backup restored in local mode (German)', (
      tester,
    ) async {
      bool? result;
      await tester.pumpWidget(
        testApp(
          locale: const Locale('de'),
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showDialog<bool>(
                context: context,
                builder: (_) => RestorePreviewDialog(
                  preview: RestorePreview(
                    backup: backup(account: '@lea:x.test'),
                    groups: [plan('Trip', isNew: true, changes: 4)],
                    otherAccount: false,
                    takeover: RestoreTakeover.accountIntoLocal,
                    myAccount: 'local:self',
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
      expect(find.byKey(const Key('restoreTakeover')), findsOneWidget);
      expect(
        find.textContaining('gehört zum Matrix-Konto @lea:x.test'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('restoreOtherAccount')), findsNothing);
      expect(result, isNull);
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
    var ownDeviceProtects = false;
    late List<StreamController<int?>> listeners;
    late List<int> snoozedTo;
    setUp(() {
      ownDeviceProtects = false;
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
      // G34: no second device of ours (unless a test says otherwise).
      ownDeviceProtectionProvider.overrideWith((_) => ownDeviceProtects),
      // G16: no archived groups (no drift stream in widget tests).
      groupArchivesProvider.overrideWith((_) => Stream.value(const {})),
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

    testWidgets('hidden when another device of ours holds the groups (G34)', (
      tester,
    ) async {
      ownDeviceProtects = true;
      await tester.pumpWidget(
        testApp(const GroupsPage(), overrides: overrides([meMember])),
      );
      await tester.pumpAndSettle();
      expect(find.text('Solo'), findsOneWidget);
      expect(find.byKey(const Key('backupNudge')), findsNothing);
    });
  });

  group('G34 passphrase dialog', () {
    Future<String? Function()> open(WidgetTester tester) async {
      String? result;
      var done = false;
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => const BackupPassphraseDialog(),
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      return () => done ? result : 'not closed';
    }

    testWidgets('empty = unencrypted, with the plaintext warning', (
      tester,
    ) async {
      final result = await open(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('backupPlaintextWarning')), findsOneWidget);
      expect(find.byKey(const Key('backupPassphraseConfirm')), findsNothing);
      await tester.tap(find.byKey(const Key('backupPassphraseSave')));
      await tester.pumpAndSettle();
      expect(result(), '');
    });

    testWidgets('a passphrase needs the matching confirmation; strength hint', (
      tester,
    ) async {
      final result = await open(tester);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('backupPassphrase')), 'abc');
      await tester.pump();
      expect(find.byKey(const Key('backupPlaintextWarning')), findsNothing);
      expect(find.byKey(const Key('backupKeepSafe')), findsOneWidget);
      expect(find.textContaining('Strength: weak'), findsOneWidget);
      // Not confirmed yet → Save disabled.
      FilledButton save() => tester.widget<FilledButton>(
        find.byKey(const Key('backupPassphraseSave')),
      );
      expect(save().onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('backupPassphrase')),
        'correct horse battery staple',
      );
      await tester.enterText(
        find.byKey(const Key('backupPassphraseConfirm')),
        'correct horse battery stable',
      );
      await tester.pump();
      expect(find.text('Strength: strong'), findsOneWidget);
      expect(find.text("The passphrases don't match"), findsOneWidget);
      expect(save().onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('backupPassphraseConfirm')),
        'correct horse battery staple',
      );
      await tester.pump();
      expect(find.text("The passphrases don't match"), findsNothing);
      await tester.tap(find.byKey(const Key('backupPassphraseSave')));
      await tester.pumpAndSettle();
      expect(result(), 'correct horse battery staple');
    });

    testWidgets('German', (tester) async {
      await tester.pumpWidget(
        testApp(
          locale: const Locale('de'),
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => const BackupPassphraseDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Sicherung schützen?'), findsOneWidget);
      expect(find.textContaining('nicht verschlüsselt'), findsOneWidget);
    });
  });

  testWidgets('G34 unlock: a wrong passphrase asks again, the right one '
      'decrypts; cancel gives up', (tester) async {
    final tried = <String>[];
    Future<String> decrypt(String text, String pass) async {
      tried.add(pass);
      if (pass != 'right') throw const WrongPassphraseException();
      return 'PLAIN';
    }

    String? result = 'pending';
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await unlockEncryptedBackup(context, 'X', decrypt),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Encrypted backup'), findsOneWidget);
    // Empty → Unlock disabled.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('backupUnlockConfirm')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('backupUnlockPassphrase')),
      'wrong',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('backupUnlockConfirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Wrong passphrase'), findsOneWidget);
    expect(result, 'pending');

    await tester.enterText(
      find.byKey(const Key('backupUnlockPassphrase')),
      'right',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('backupUnlockConfirm')));
    await tester.pumpAndSettle();
    expect(result, 'PLAIN');
    expect(tried, ['wrong', 'right']);
    expect(find.byKey(const Key('backupUnlockDialog')), findsNothing);

    // Cancel → null.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('G34 leave/delete dialog shows the backup result inside it', (
    tester,
  ) async {
    bool? confirmed;
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => confirmed = await confirmGroupExit(
              context,
              kind: GroupExitKind.leave,
              groupName: 'Trip',
              warning: null,
              onBackup: () async => 'Encrypted backup saved: b.json',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exitBackupResult')), findsNothing);
    await tester.tap(find.byKey(const Key('exitBackupButton')));
    await tester.pumpAndSettle();
    expect(find.text('Encrypted backup saved: b.json'), findsOneWidget);
    expect(find.text('Leave group?'), findsOneWidget); // still open
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  test('G34 saved-backup messages', () {
    expect(
      backupSavedMessage(en, fileName: null, encrypted: false),
      'Backup saved',
    );
    expect(
      backupSavedMessage(en, fileName: 'x (1).json', encrypted: false),
      'Backup saved: x (1).json',
    );
    expect(
      backupSavedMessage(de, fileName: null, encrypted: true),
      'Verschlüsselte Sicherung gespeichert',
    );
  });

  testWidgets('G34 restore preview: removed + encrypted are spelled out', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => RestorePreviewDialog(
                encrypted: true,
                preview: RestorePreview(
                  backup: parseBackup(
                    buildBackupJson(
                      account: '@me:x',
                      exportedAt: 1,
                      groups: const [],
                    ),
                  ),
                  groups: const [
                    GroupRestorePlan(
                      summary: BackupGroupSummary(
                        groupId: 'g',
                        name: 'Trip',
                        expenseCount: 1,
                        settlementCount: 0,
                        memberCount: 1,
                      ),
                      isNew: true,
                      wasLeft: false,
                      changes: 3,
                      removed: true,
                    ),
                  ],
                  otherAccount: false,
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
    expect(find.byKey(const Key('restoreEncrypted')), findsOneWidget);
    expect(find.text('read-only — you were removed'), findsOneWidget);
    expect(find.textContaining('comes back read-only'), findsOneWidget);
  });
}
