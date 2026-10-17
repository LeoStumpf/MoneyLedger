/// G71 (U30): Flutter's accessibility guidelines on the main pages — every
/// tap target ≥ 48 dp (Android), every tappable thing has a label, text
/// contrast — at 360 dp in English.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:money_ledger/core/database/account_database.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/sync/sync_status_provider.dart';
import 'package:money_ledger/core/theme/app_theme.dart';
import 'package:money_ledger/features/auth/auth_provider.dart';
import 'package:money_ledger/features/devices/device_provider.dart';
import 'package:money_ledger/features/backup/backup_restore_page.dart';
import 'package:money_ledger/features/balance/balance_calculator.dart';
import 'package:money_ledger/features/balance/balance_page.dart';
import 'package:money_ledger/features/balance/record_payment_dialog.dart';
import 'package:money_ledger/features/expenses/add_expense_page.dart';
import 'package:money_ledger/features/expenses/expenses_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/create_group_page.dart';
import 'package:money_ledger/features/groups/group_members_page.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/groups/group_settings_page.dart';
import 'package:money_ledger/features/groups/groups_page.dart';
import 'package:money_ledger/features/history/restore_points.dart';
import 'package:money_ledger/features/settings/settings_page.dart';
import 'package:money_ledger/models/expense_model.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_auth_gateway.dart';
import 'helpers/fake_device_gateway.dart';
import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/l10n.dart';
import 'helpers/test_providers.dart';

const _g = 'g1';
const _me = '@anna:x.org';
const _bob = '@bob:x.org';

MemberModel _member(String id, String name, {String? mxid}) => MemberModel(
  groupId: _g,
  userId: id,
  displayName: name,
  matrixId: mxid,
  status: 'active',
  updatedAt: 1,
);

final _members = [
  _member(_me, 'Anna', mxid: _me),
  _member(_bob, 'Bob', mxid: _bob),
  _member('p-carl', 'Carl'),
];

const _group = GroupModel(roomId: _g, name: 'Rome 2026', currency: 'EUR');

const _expenses = [
  ExpenseModel(
    id: 'e1',
    roomId: _g,
    description: 'Pizza',
    amountCents: 4200,
    currency: 'EUR',
    paidBy: _me,
    splitsJson: '{"$_me":2100,"$_bob":2100}',
    createdAt: 5000,
    category: 'food',
    note: 'Tip included',
    updatedAt: 9000, // newer than the peers' last sync → pending
  ),
  ExpenseModel(
    id: 'e2',
    roomId: _g,
    description: 'Tickets',
    amountCents: 3000,
    currency: 'EUR',
    paidBy: _bob,
    splitsJson: '{"$_me":1500,"$_bob":1500}',
    createdAt: 6000,
  ),
];

const _settlements = [
  SettlementModel(
    id: 's1',
    roomId: _g,
    amountCents: 500,
    currency: 'EUR',
    fromUser: _bob,
    toUser: _me,
    createdAt: 7000,
  ),
];

const _debts = [DebtEntry(from: _bob, to: _me, cents: 100, currency: 'EUR')];

/// A 360 × 780 dp phone.
void _phone(WidgetTester tester, {double height = 780}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(360, height);
  addTearDown(tester.view.reset);
}

List<dynamic> _overrides({
  List<dynamic> extra = const [],
  GroupSyncStatus syncStatus = const GroupSyncStatus(
    pendingPeers: {},
    minPeerInSyncAt: null,
  ),
}) => [
  ...testOverrides(
    syncStatus: syncStatus,
    isLoggedIn: true,
    members: _members,
    groups: const [_group],
    expenses: _expenses,
    settlements: _settlements,
    debts: _debts,
  ),
  currentUserIdProvider.overrideWith((_) => _me),
  currentParticipantProvider.overrideWith((ref, g) async => _members.first),
  snapshotsSupportedProvider.overrideWithValue(true),
  // No sync engine (signed-out placeholder DB), never a Matrix client.
  appDatabaseProvider.overrideWithValue(
    AppDatabase.signedOut(SignedOutExecutor()),
  ),
  ledgerTransportProvider.overrideWith(
    (ref) => FakeMatrixNetwork().clientFor(_me),
  ),
  authGatewayProvider.overrideWith(
    (ref) async => FakeAuthGateway(initialUserId: _me),
  ),
  deviceGatewayProvider.overrideWith(
    (ref) async => FakeDeviceGateway(const []),
  ),
  ...extra,
];

/// Every guideline the page must meet. Text contrast is checked where the
/// page has no translucent overlays (it is unstable with them).
Future<void> _expectGuidelines(
  WidgetTester tester, {
  bool contrast = true,
}) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (contrast) {
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }
  // Let debounce / animation timers of the page run out.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 1));
}

Widget _routed(Widget page, List<dynamic> overrides) {
  final router = GoRouter(
    initialLocation: '/page',
    routes: [GoRoute(path: '/page', builder: (_, _) => page)],
  );
  return ProviderScope(
    overrides: [...overrides],
    child: MaterialApp.router(
      theme: AppTheme.light(isWeb: false),
      locale: const Locale('en'),
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      routerConfig: router,
    ),
  );
}

Future<AppDatabase> _seed() async {
  final db = openTestDatabase();
  await GroupsDao(db).upsertGroupLww(
    const GroupsCompanion(
      roomId: Value(_g),
      name: Value('Rome 2026'),
      currency: Value('EUR'),
      updatedAt: Value(1000),
    ),
  );
  for (final (id, name) in [(_me, 'Anna'), (_bob, 'Bob')]) {
    await MembersDao(db).upsertMemberLww(
      MembersCompanion(
        groupId: const Value(_g),
        userId: Value(id),
        displayName: Value(name),
        matrixId: Value(id),
        status: const Value('active'),
        updatedAt: const Value(1),
      ),
    );
  }
  return db;
}

void main() {
  testWidgets('groups page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_routed(const GroupsPage(), _overrides()));
    await tester.pumpAndSettle();
    expect(find.text('Rome 2026'), findsOneWidget);
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('group page (ledger), incl. a pending sync cloud', (
    tester,
  ) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(
        const ExpensesPage(roomId: _g),
        _overrides(
          syncStatus: const GroupSyncStatus(
            pendingPeers: {_bob},
            minPeerInSyncAt: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pizza'), findsOneWidget);
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('balance page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(const BalancePage(roomId: _g), _overrides()),
    );
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('payment dialog', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(
        const Scaffold(
          body: RecordPaymentDialog(
            participants: {'a': 'Anna', 'b': 'Bob'},
            initialFrom: 'a',
            initialTo: 'b',
            currency: 'EUR',
          ),
        ),
        const [],
      ),
    );
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('settings page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_routed(const SettingsPage(), _overrides()));
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('group settings page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(const GroupSettingsPage(roomId: _g), _overrides()),
    );
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('people page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _routed(const GroupMembersPage(roomId: _g), [
        currentUserIdProvider.overrideWithValue(_me),
        groupMembersProvider(_g).overrideWith((ref) => Stream.value(_members)),
        ledgerGroupsProvider.overrideWith((_) => Stream.value([_group])),
        ...FakeTrustStore().overrides(FakeDeviceGateway(const [])),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('backup & restore page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_routed(const BackupRestorePage(), _overrides()));
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('create group page', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_routed(const CreateGroupPage(), _overrides()));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('createGroupPersonField')),
      'Carl',
    );
    await tester.tap(find.byKey(const Key('createGroupPersonAdd')));
    await tester.pumpAndSettle();
    await _expectGuidelines(tester);
    handle.dispose();
  });

  group('add expense', () {
    for (final mode in ['Equally', 'Amounts', 'Shares', '%']) {
      testWidgets('split mode $mode', (tester) async {
        // Tall enough that no field is half scrolled out of view.
        _phone(tester, height: 1600);
        final handle = tester.ensureSemantics();
        final db = await _seed();
        addTearDown(db.close);
        final net = FakeMatrixNetwork();
        await tester.pumpWidget(
          _routed(const AddExpensePage(roomId: _g), [
            ...signingUiOverrides(),
            appDatabaseProvider.overrideWithValue(db),
            ledgerTransportProvider.overrideWith((ref) => net.clientFor(_me)),
          ]),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('expenseAmount')), '10');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(mode));
        await tester.tap(find.text(mode));
        await tester.pumpAndSettle();
        // Something left, so the "put the rest here" buttons show.
        if (mode == 'Amounts' || mode == '%') {
          final field = find.descendant(
            of: find.byType(Card),
            matching: find.byType(TextField),
          );
          await tester.enterText(field.first, '1');
          await tester.pumpAndSettle();
        }
        await _expectGuidelines(tester);
        handle.dispose();
      });
    }
  });

  group('screen reader', () {
    testWidgets('a ledger row reads as one sentence, incl. its category, '
        'note, amount, effect and sync state', (tester) async {
      _phone(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _routed(
          const ExpensesPage(roomId: _g),
          _overrides(
            syncStatus: const GroupSyncStatus(
              pendingPeers: {_bob},
              minPeerInSyncAt: 8000,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final data = tester.getSemantics(find.text('Pizza')).getSemanticsData();
      final spoken = '${data.label} ${data.tooltip}';
      for (final part in [
        'Food & drink',
        'Pizza',
        '€42.00',
        'You paid',
        'you lent €21.00',
        'Has a note',
        'Not synced yet',
      ]) {
        expect(spoken, contains(part));
      }
      // The day headers are headings.
      expect(
        tester.getSemantics(find.byKey(const Key('dayHeader')).first),
        isSemantics(isHeader: true),
      );
      // The app-bar cloud is a status with its explanation, not a
      // (disabled) button.
      final cloud = find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').startsWith('Waiting for'),
      );
      expect(cloud, findsOneWidget);
      expect(
        find.ancestor(of: cloud, matching: find.byType(IconButton)),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('balance page: sections are headings', (tester) async {
      _phone(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _routed(const BalancePage(roomId: _g), _overrides()),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('Suggested payments')),
        isSemantics(isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('equal split: each checkbox is read with its person', (
      tester,
    ) async {
      _phone(tester);
      final handle = tester.ensureSemantics();
      final db = await _seed();
      addTearDown(db.close);
      await tester.pumpWidget(
        _routed(const AddExpensePage(roomId: _g), [
          ...signingUiOverrides(),
          appDatabaseProvider.overrideWithValue(db),
          ledgerTransportProvider.overrideWith(
            (ref) => FakeMatrixNetwork().clientFor(_me),
          ),
        ]),
      );
      await tester.pumpAndSettle();
      final box = find.byType(Checkbox).first;
      await tester.ensureVisible(box);
      expect(
        tester.getSemantics(box),
        isSemantics(label: 'Anna\n€0.00', isChecked: true),
      );
      handle.dispose();
    });
  });

  group('form flow (U12)', () {
    Future<AppDatabase> pumpForm(
      WidgetTester tester, {
      ExpenseModel? initial,
    }) async {
      _phone(tester);
      final db = await _seed();
      addTearDown(db.close);
      await tester.pumpWidget(
        _routed(AddExpensePage(roomId: _g, initial: initial), [
          ...signingUiOverrides(),
          appDatabaseProvider.overrideWithValue(db),
          ledgerTransportProvider.overrideWith(
            (ref) => FakeMatrixNetwork().clientFor(_me),
          ),
        ]),
      );
      await tester.pumpAndSettle();
      return db;
    }

    EditableText editable(WidgetTester tester, Key key) =>
        tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(EditableText),
          ),
        );

    testWidgets('new expense: description focused, Next → amount (decimal '
        'keyboard, Done), category after the date', (tester) async {
      await pumpForm(tester);
      final desc = editable(tester, const Key('expenseDescription'));
      expect(desc.focusNode.hasFocus, isTrue);
      expect(desc.textInputAction, TextInputAction.next);

      await tester.enterText(find.byKey(const Key('expenseDescription')), 'X');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      final amount = editable(tester, const Key('expenseAmount'));
      expect(amount.focusNode.hasFocus, isTrue);
      expect(desc.focusNode.hasFocus, isFalse);
      expect(amount.textInputAction, TextInputAction.done);
      expect(
        amount.keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );

      // Done closes the keyboard (nothing is submitted).
      await tester.enterText(find.byKey(const Key('expenseAmount')), '12');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(amount.focusNode.hasFocus, isFalse);
      expect(find.byType(AddExpensePage), findsOneWidget);

      // Order: description, amount, payer, date, category.
      double y(Key k) => tester.getTopLeft(find.byKey(k)).dy;
      expect(
        y(const Key('expenseAmount')),
        greaterThan(y(const Key('expenseDescription'))),
      );
      expect(
        y(const Key('expenseDate')),
        greaterThan(y(const Key('expenseAmount'))),
      );
      expect(
        y(const Key('categoryPickerField')),
        greaterThan(y(const Key('expenseDate'))),
      );
    });

    testWidgets('editing an expense opens without a keyboard', (tester) async {
      await pumpForm(tester, initial: _expenses.first);
      final desc = editable(tester, const Key('expenseDescription'));
      expect(desc.focusNode.hasFocus, isFalse);
    });

    testWidgets('payment dialog: blank amount focused, Done records it', (
      tester,
    ) async {
      _phone(tester);
      Object? result;
      await tester.pumpWidget(
        _routed(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => result = await showDialog<Object>(
                  context: context,
                  builder: (_) => const RecordPaymentDialog(
                    participants: {'a': 'Anna', 'b': 'Bob'},
                    initialFrom: 'a',
                    initialTo: 'b',
                    currency: 'EUR',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
          const [],
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final amount = editable(tester, const Key('paymentAmount'));
      expect(amount.focusNode.hasFocus, isTrue);
      expect(amount.textInputAction, TextInputAction.done);

      // Done with an incomplete draft does nothing …
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(RecordPaymentDialog), findsOneWidget);
      // … with a valid amount it records the payment.
      await tester.enterText(find.byKey(const Key('paymentAmount')), '5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(RecordPaymentDialog), findsNothing);
      expect(result, isA<PaymentDraft>());
      expect((result! as PaymentDraft).cents, 500);
    });

    testWidgets('payment dialog prefilled from a debt: no keyboard', (
      tester,
    ) async {
      _phone(tester);
      await tester.pumpWidget(
        _routed(
          const Scaffold(
            body: RecordPaymentDialog(
              participants: {'a': 'Anna', 'b': 'Bob'},
              initialFrom: 'a',
              initialTo: 'b',
              initialCents: 100,
              currency: 'EUR',
            ),
          ),
          const [],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        editable(tester, const Key('paymentAmount')).focusNode.hasFocus,
        isFalse,
      );
    });

    testWidgets('create group: name focused, Next → people field, which '
        'keeps the focus after adding (G64)', (tester) async {
      _phone(tester);
      await tester.pumpWidget(_routed(const CreateGroupPage(), _overrides()));
      await tester.pumpAndSettle();
      final name = tester.widget<EditableText>(
        find.descendant(
          of: find.byType(TextFormField),
          matching: find.byType(EditableText),
        ),
      );
      expect(name.focusNode.hasFocus, isTrue);
      expect(name.textInputAction, TextInputAction.next);
      await tester.enterText(find.byType(TextFormField), 'Rome');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      final person = editable(tester, const Key('createGroupPersonField'));
      expect(person.focusNode.hasFocus, isTrue);

      await tester.enterText(
        find.byKey(const Key('createGroupPersonField')),
        'Carl',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('createGroupPersonChip-0')), findsOneWidget);
      expect(person.focusNode.hasFocus, isTrue);
    });
  });
}
