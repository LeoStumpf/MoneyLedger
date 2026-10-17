/// G78: the expense form's receipt photo (Android only, this device only) —
/// add / view / remove, hidden where there is no store (web, demo), a
/// duplicate starts without one, and the ledger row's indicator.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/expenses_dao.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/ledger_transport.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/features/expenses/add_expense_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/receipts/receipt_field.dart';
import 'package:money_ledger/features/receipts/receipt_picker.dart';
import 'package:money_ledger/features/receipts/receipt_store.dart';
import 'package:money_ledger/models/expense_model.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/test_providers.dart';

const _alice = '@alice:x.org';
const _bob = '@bob:x.org';

/// A 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

const _edited = ExpenseModel(
  id: 'e1',
  roomId: 'g1',
  description: 'Dinner',
  amountCents: 4200,
  currency: 'EUR',
  paidBy: _alice,
  splitsJson: '{"$_alice":2100,"$_bob":2100}',
  createdAt: 1000,
  updatedAt: 1000,
);

Future<(AppDatabase, FakeMatrixNetwork)> _seed() async {
  final db = openTestDatabase();
  await GroupsDao(db).upsertGroupLww(
    const GroupsCompanion(
      roomId: Value('g1'),
      name: Value('Trip'),
      currency: Value('EUR'),
      updatedAt: Value(1000),
    ),
  );
  for (final u in [_alice, _bob]) {
    await MembersDao(db).upsertMemberLww(
      MembersCompanion(
        groupId: const Value('g1'),
        userId: Value(u),
        matrixId: Value(u),
        status: const Value('active'),
        updatedAt: const Value(1),
      ),
    );
  }
  return (db, FakeMatrixNetwork());
}

Future<void> _pumpForm(
  WidgetTester tester,
  Widget page, {
  required AppDatabase db,
  required FakeMatrixNetwork net,
  ReceiptStore? store,
  List<ReceiptSource>? picks,
  Uint8List? picked,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 1800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    testRouterApp(
      page,
      overrides: [
        ...signingUiOverrides(),
        appDatabaseProvider.overrideWith((ref) => db),
        ledgerTransportProvider.overrideWith((ref) => net.clientFor(_alice)),
        receiptStoreProvider.overrideWithValue(store),
        receiptPickerProvider.overrideWithValue((source) async {
          picks?.add(source);
          return picked;
        }),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSave(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  testWidgets('no receipt section where there is no store (web, demo, '
      'desktop)', (tester) async {
    final (db, net) = await _seed();
    addTearDown(db.close);
    await _pumpForm(
      tester,
      const AddExpensePage(roomId: 'g1'),
      db: db,
      net: net,
    );
    expect(find.byKey(const Key('expenseDescription')), findsOneWidget);
    expect(find.byKey(const Key('receiptSection')), findsNothing);
    expect(find.byType(ReceiptField), findsNothing);
  });

  testWidgets('new expense: take a photo → thumbnail → saved under the new '
      "expense's id, nothing of it sent", (tester) async {
    final (db, net) = await _seed();
    addTearDown(db.close);
    final received = <TransportMessage>[];
    net.clientFor(_bob).onMessage.listen(received.add);
    final store = InMemoryReceiptStore();
    final picks = <ReceiptSource>[];
    await _pumpForm(
      tester,
      const AddExpensePage(roomId: 'g1'),
      db: db,
      net: net,
      store: store,
      picks: picks,
      picked: _png,
    );
    expect(
      find.text(
        'Only on this device — not shared with the group, not in backups.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('receiptThumbnail')), findsNothing);

    await tester.tap(find.byKey(const Key('receiptAdd')));
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    await tester.tap(find.byKey(const Key('receiptCamera')));
    await tester.pumpAndSettle();
    expect(picks, [ReceiptSource.camera]);
    expect(find.byKey(const Key('receiptThumbnail')), findsOneWidget);
    expect(store.files, isEmpty, reason: 'written only on Add');

    await tester.enterText(
      find.byKey(const Key('expenseDescription')),
      'Pizza',
    );
    await tester.enterText(find.byKey(const Key('expenseAmount')), '20');
    await tester.pump();
    await tester.tap(find.byKey(const Key('submitExpense')));
    await _pumpSave(tester);
    await tester.pumpAndSettle();

    final saved = (await ExpensesDao(db).getExpensesForRoom('g1')).single;
    expect(store.files.keys, [saved.id]);
    expect(store.files[saved.id], _png);
    expect(received, hasLength(1));
    expect(
      jsonEncode(received.single.content),
      isNot(contains('receipt')),
      reason: 'the photo is never part of the record',
    );
  });

  testWidgets('edit: the stored photo shows, opens full screen, and '
      '*Remove* + *Save* deletes it without a new version', (tester) async {
    final (db, net) = await _seed();
    addTearDown(db.close);
    await ExpensesDao(db).upsertExpenseLww(expenseCompanion(_edited));
    final received = <TransportMessage>[];
    net.clientFor(_bob).onMessage.listen(received.add);
    final store = InMemoryReceiptStore()..files['e1'] = _png;
    await _pumpForm(
      tester,
      const AddExpensePage(roomId: 'g1', initial: _edited),
      db: db,
      net: net,
      store: store,
    );
    expect(find.byKey(const Key('receiptThumbnail')), findsOneWidget);

    // Full screen, zoomable.
    await tester.tap(find.byKey(const Key('receiptThumbnail')));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptViewerPage), findsOneWidget);
    expect(find.byKey(const Key('receiptViewer')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('receiptRemove')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('receiptThumbnail')), findsNothing);
    expect(store.files, contains('e1'), reason: 'removed only on Save');
    await tester.tap(find.byKey(const Key('submitExpense')));
    await _pumpSave(tester);
    await tester.pumpAndSettle();

    expect(store.files, isEmpty);
    expect(find.text('Receipt photo removed'), findsOneWidget);
    expect(find.text('host'), findsOneWidget, reason: 'the form closed');
    expect(received, isEmpty, reason: 'a photo-only change syncs nothing');
    final stored = await ExpensesDao(db).getExpenseById('e1');
    expect(stored!.updatedAt, 1000, reason: 'no new version');
  });

  testWidgets('edit: replacing the photo from the gallery stores the new one', (
    tester,
  ) async {
    final (db, net) = await _seed();
    addTearDown(db.close);
    await ExpensesDao(db).upsertExpenseLww(expenseCompanion(_edited));
    final store = InMemoryReceiptStore()..files['e1'] = Uint8List(3);
    final picks = <ReceiptSource>[];
    await _pumpForm(
      tester,
      const AddExpensePage(roomId: 'g1', initial: _edited),
      db: db,
      net: net,
      store: store,
      picks: picks,
      picked: _png,
    );
    await tester.tap(find.byKey(const Key('receiptReplace')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('receiptGallery')));
    await tester.pumpAndSettle();
    expect(picks, [ReceiptSource.gallery]);
    await tester.tap(find.byKey(const Key('submitExpense')));
    await _pumpSave(tester);
    await tester.pumpAndSettle();
    expect(store.files['e1'], _png);
    expect(find.text('Receipt photo saved'), findsOneWidget);
  });

  testWidgets('a cancelled pick changes nothing; a picked photo makes '
      'leaving ask first', (tester) async {
    final (db, net) = await _seed();
    addTearDown(db.close);
    await ExpensesDao(db).upsertExpenseLww(expenseCompanion(_edited));
    Uint8List? next; // null = the user cancelled the camera
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testRouterApp(
        const AddExpensePage(roomId: 'g1', initial: _edited),
        overrides: [
          ...signingUiOverrides(),
          appDatabaseProvider.overrideWith((ref) => db),
          ledgerTransportProvider.overrideWith((ref) => net.clientFor(_alice)),
          receiptStoreProvider.overrideWithValue(InMemoryReceiptStore()),
          receiptPickerProvider.overrideWithValue((_) async => next),
        ],
      ),
    );
    await tester.pumpAndSettle();
    Future<void> takePhoto() async {
      await tester.tap(find.byKey(const Key('receiptAdd')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('receiptCamera')));
      await tester.pumpAndSettle();
    }

    await takePhoto();
    expect(find.byKey(const Key('receiptThumbnail')), findsNothing);
    next = _png;
    await takePhoto();
    expect(find.byKey(const Key('receiptThumbnail')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('discardChanges')));
    await tester.pumpAndSettle();
    expect(find.text('host'), findsOneWidget);
  });

  testWidgets('a failing camera / picker shows an error', (tester) async {
    final (db, net) = await _seed();
    addTearDown(db.close);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testRouterApp(
        const AddExpensePage(roomId: 'g1'),
        overrides: [
          ...signingUiOverrides(),
          appDatabaseProvider.overrideWith((ref) => db),
          ledgerTransportProvider.overrideWith((ref) => net.clientFor(_alice)),
          receiptStoreProvider.overrideWithValue(InMemoryReceiptStore()),
          receiptPickerProvider.overrideWithValue(
            (_) async => throw StateError('no_available_camera'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('receiptAdd')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('receiptCamera')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't get the photo"), findsOneWidget);
    expect(find.byKey(const Key('receiptThumbnail')), findsNothing);
  });

  testWidgets('a duplicate (G75) does not copy the photo', (tester) async {
    final (db, net) = await _seed();
    addTearDown(db.close);
    final store = InMemoryReceiptStore()..files['e1'] = _png;
    await _pumpForm(
      tester,
      const AddExpensePage(roomId: 'g1', copyFrom: _edited),
      db: db,
      net: net,
      store: store,
    );
    expect(find.byKey(const Key('receiptSection')), findsOneWidget);
    expect(find.byKey(const Key('receiptThumbnail')), findsNothing);
    expect(find.byKey(const Key('receiptAdd')), findsOneWidget);
  });

  testWidgets('German: section, hint and source sheet', (tester) async {
    final (db, net) = await _seed();
    addTearDown(db.close);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testRouterApp(
        const AddExpensePage(roomId: 'g1'),
        locale: const Locale('de'),
        overrides: [
          ...signingUiOverrides(),
          appDatabaseProvider.overrideWith((ref) => db),
          ledgerTransportProvider.overrideWith((ref) => net.clientFor(_alice)),
          receiptStoreProvider.overrideWithValue(InMemoryReceiptStore()),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Belegfoto'), findsOneWidget);
    expect(find.text('Belegfoto hinzufügen'), findsOneWidget);
    expect(find.textContaining('Nur auf diesem Gerät'), findsOneWidget);
    await tester.tap(find.byKey(const Key('receiptAdd')));
    await tester.pumpAndSettle();
    expect(find.text('Foto aufnehmen'), findsOneWidget);
    expect(find.text('Aus der Galerie wählen'), findsOneWidget);
  });
}
