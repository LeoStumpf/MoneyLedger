/// G61: long names that share a prefix (MXID localparts such as
/// `moneyledger-test-a-c725` / `…-b-c725`) must stay distinguishable at phone
/// width — in every split mode's rows, the payer dropdown and the payment
/// dialog's from / to pickers. Found on a Pixel at 1080 px (≈ 411 dp); tested
/// at 360 dp, the narrowest common phone.
///
/// The test font's glyphs are square (1 em wide, ≈ 2× a real font's average
/// width), so "readable" is checked with the text scale at 0.5 — roughly what
/// Roboto needs for the same string — and "no overflow" at both scales.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/app_database.dart';
import 'package:money_ledger/core/database/daos/groups_dao.dart';
import 'package:money_ledger/core/database/daos/members_dao.dart';
import 'package:money_ledger/core/matrix/transport_provider.dart';
import 'package:money_ledger/core/theme/app_theme.dart';
import 'package:money_ledger/features/balance/record_payment_dialog.dart';
import 'package:money_ledger/features/expenses/add_expense_page.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/expenses/split_editor.dart';
import 'package:money_ledger/models/member_model.dart';

import 'helpers/fake_ledger_network.dart';
import 'helpers/in_memory_database.dart';
import 'helpers/test_providers.dart';

const _a = 'moneyledger-test-a-c725';
const _b = 'moneyledger-test-b-c725';

MemberModel _m(String id, String name) => MemberModel(
  groupId: 'g1',
  userId: id,
  displayName: name,
  status: 'active',
  updatedAt: 1,
);

/// A 360 × 780 dp phone; [scale] emulates a real font's glyph width.
void _phone(WidgetTester tester, {double scale = 1}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 780);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Every [Text] showing exactly [name] renders it completely (no ellipsis).
void _expectFullyShown(WidgetTester tester, String name, {String? where}) {
  final paragraphs = tester.renderObjectList<RenderParagraph>(
    find.text(name, skipOffstage: false),
  );
  expect(paragraphs, isNotEmpty, reason: '$name missing ($where)');
  for (final p in paragraphs) {
    expect(p.didExceedMaxLines, isFalse, reason: '$name is cut short ($where)');
  }
}

void main() {
  group('split editor rows', () {
    Future<void> pumpEditor(WidgetTester tester, Locale? locale) async {
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(Insets.page),
              child: SplitEditor(
                members: [_m('a', _a), _m('b', _b)],
                totalCents: 1000,
                currency: 'EUR',
                onPlanChanged: (_) {},
              ),
            ),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final locale in [null, const Locale('de')]) {
      final lang = locale?.languageCode ?? 'en';
      // Mode segment labels (the % segment is the same in both languages).
      final modes = lang == 'de'
          ? ['Gleich', 'Beträge', 'Anteile', '%']
          : ['Equally', 'Amounts', 'Shares', '%'];

      testWidgets('[$lang] both long names stay readable in every mode', (
        tester,
      ) async {
        _phone(tester, scale: 0.5);
        await pumpEditor(tester, locale);
        for (final mode in modes) {
          await tester.tap(find.text(mode));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: mode);
          _expectFullyShown(tester, _a, where: mode);
          _expectFullyShown(tester, _b, where: mode);
        }
      });

      // G63 / U14: the spelled-out mode labels fit one line at 360 dp.
      testWidgets('[$lang] the mode labels fit on one line', (tester) async {
        _phone(tester, scale: 0.5);
        await pumpEditor(tester, locale);
        for (final mode in modes.where((m) => m != '%')) {
          final p = tester.renderObject<RenderParagraph>(find.text(mode));
          expect(
            p.getMaxIntrinsicWidth(double.infinity),
            lessThanOrEqualTo(p.size.width + 0.5),
            reason: '"$mode" wraps or is cut',
          );
        }
        // "%" is read out as a word.
        expect(
          find.bySemanticsLabel(lang == 'de' ? 'Prozent' : 'Percent'),
          findsWidgets,
        );
      });

      testWidgets('[$lang] no overflow with the wide test font', (
        tester,
      ) async {
        _phone(tester);
        await pumpEditor(tester, locale);
        for (final mode in modes) {
          await tester.tap(find.text(mode));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: mode);
          // Two lines each, never one ellipsized line.
          for (final name in [_a, _b]) {
            final p = tester.renderObject<RenderParagraph>(find.text(name));
            expect(p.maxLines, 2, reason: mode);
          }
        }
      });
    }
  });

  group('payer dropdown', () {
    Future<AppDatabase> seed() async {
      final db = openTestDatabase();
      await GroupsDao(db).upsertGroupLww(
        const GroupsCompanion(
          roomId: Value('g1'),
          name: Value('Trip'),
          currency: Value('EUR'),
          updatedAt: Value(1000),
        ),
      );
      for (final u in ['@$_a:matrix.org', '@$_b:matrix.org']) {
        await MembersDao(db).upsertMemberLww(
          MembersCompanion(
            groupId: const Value('g1'),
            userId: Value(u),
            matrixId: Value(u),
            status: const Value('active'),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
      }
      return db;
    }

    for (final locale in [null, const Locale('de')]) {
      final lang = locale?.languageCode ?? 'en';
      testWidgets('[$lang] shows the whole name, selected and in the menu', (
        tester,
      ) async {
        _phone(tester, scale: 0.5);
        final db = await seed();
        await tester.pumpWidget(
          testApp(
            const AddExpensePage(roomId: 'g1'),
            locale: locale,
            overrides: [
              ...signingUiOverrides(),
              appDatabaseProvider.overrideWith((ref) => db),
              ledgerTransportProvider.overrideWith(
                (ref) => FakeMatrixNetwork().clientFor('@$_a:matrix.org'),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final payer = find.byKey(const Key('expensePayer'));
        await tester.ensureVisible(payer);
        await tester.pumpAndSettle();
        _expectFullyShown(tester, _a, where: 'selected payer');
        await tester.tap(payer);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        _expectFullyShown(tester, _a, where: 'payer menu');
        _expectFullyShown(tester, _b, where: 'payer menu');
        await db.close();
      });
    }
  });

  group('record payment pickers', () {
    for (final locale in [null, const Locale('de')]) {
      final lang = locale?.languageCode ?? 'en';
      for (final scale in [0.5, 1.0]) {
        testWidgets('[$lang, scale $scale] from / to show distinguishable '
            'names without overflow', (tester) async {
          _phone(tester, scale: scale);
          await tester.pumpWidget(
            testApp(
              Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => const RecordPaymentDialog(
                          participants: {'a': _a, 'b': _b},
                          initialFrom: 'a',
                          initialTo: 'b',
                          currency: 'EUR',
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
              locale: locale,
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (scale < 1) {
            _expectFullyShown(tester, _a, where: 'from');
            _expectFullyShown(tester, _b, where: 'to');
          }

          await tester.tap(find.byKey(const Key('paymentFrom')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (scale < 1) {
            _expectFullyShown(tester, _a, where: 'from menu');
            _expectFullyShown(tester, _b, where: 'from menu');
          }
        });
      }
    }
  });
}
