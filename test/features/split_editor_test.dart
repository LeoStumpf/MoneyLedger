/// G59: smarter split defaults — the SplitEditor prefills a mode from the
/// current split, offers "fill the rest" / "rest here" / "rescale", and Shares
/// has +/- steppers. Pure math is covered in split_calculator_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/expenses/split_editor.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/test_providers.dart';

MemberModel _m(String id) => MemberModel(
  groupId: 'g1',
  userId: id,
  displayName: id.toUpperCase(),
  status: 'active',
  updatedAt: 1,
);

void main() {
  late ValueNotifier<int> total;
  SplitPlan? plan;

  setUp(() {
    total = ValueNotifier(0);
    plan = null;
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    List<String> ids = const ['a', 'b'],
    int totalCents = 0,
    Map<String, int>? initial,
    Locale? locale,
    bool canSetTotal = false,
  }) async {
    total.value = totalCents;
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<int>(
              valueListenable: total,
              builder: (_, t, _) => SplitEditor(
                members: [for (final id in ids) _m(id)],
                totalCents: t,
                currency: 'EUR',
                initialSplit: initial,
                onPlanChanged: (p) => plan = p,
                onSetTotal: canSetTotal ? (c) => total.value = c : null,
              ),
            ),
          ),
        ),
        locale: locale,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> setTotal(WidgetTester tester, int cents) async {
    total.value = cents;
    await tester.pumpAndSettle();
  }

  Finder fields() => find.descendant(
    of: find.byType(SplitEditor),
    matching: find.byType(TextField),
  );

  List<String> values(WidgetTester tester) => [
    for (final e in tester.widgetList<TextField>(fields())) e.controller!.text,
  ];

  Future<void> mode(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, int row, String text) async {
    await tester.enterText(fields().at(row), text);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  int? resolved(String id) => plan!.resolve(total.value).shares[id];

  group('Exact: fill the rest', () {
    testWidgets('5 € with 2.50 € typed for one person → Distribute', (
      tester,
    ) async {
      await pumpEditor(tester);
      await mode(tester, 'Exact');
      // No amount yet: the fields stay open (blank).
      expect(values(tester), ['', '']);
      expect(find.text('Enter the amount first'), findsOneWidget);
      expect(
        find.text('Empty fields share the rest · 0 = not involved'),
        findsOneWidget,
      );

      await setTotal(tester, 500);
      await type(tester, 0, '2.50');
      expect(find.text('€2.50 left'), findsOneWidget);
      expect(plan!.resolve(500).isValid, isFalse);

      await tapText(tester, 'Distribute');
      expect(values(tester), ['2.50', '2.50']);
      expect(find.text('Adds up to the total'), findsOneWidget);
      expect(plan!.resolve(500).isValid, isTrue);
      expect(plan!.exact, {'a': 250, 'b': 250});
    });

    testWidgets('a prefilled row absorbs the change of a typed one', (
      tester,
    ) async {
      await pumpEditor(tester, ids: ['a', 'b', 'c'], totalCents: 500);
      await mode(tester, 'Exact');
      expect(values(tester), ['1.67', '1.67', '1.66']);

      await type(tester, 0, '3');
      expect(find.text('€1.33 too much'), findsOneWidget);
      await tapText(tester, 'Distribute');
      // The typed 3.00 stays; the auto rows share the remaining 2.00.
      expect(values(tester), ['3', '1.00', '1.00']);
      expect(plan!.resolve(500).isValid, isTrue);
    });

    testWidgets('the per-row button puts the whole remainder there', (
      tester,
    ) async {
      await pumpEditor(tester, totalCents: 500);
      await mode(tester, 'Exact');
      await type(tester, 0, '1');
      await type(tester, 1, '');
      expect(find.text('€4.00 left'), findsOneWidget);

      await tester.tap(find.byTooltip('Put the rest here').at(1));
      await tester.pumpAndSettle();
      expect(values(tester), ['1', '4.00']);
      expect(plan!.exact, {'a': 100, 'b': 400});
      // Nothing left → the buttons are hidden.
      expect(find.byTooltip('Put the rest here').hitTestable(), findsNothing);
    });

    testWidgets('a changed total keeps typed amounts and offers rescale', (
      tester,
    ) async {
      await pumpEditor(tester, totalCents: 500);
      await mode(tester, 'Exact');
      await type(tester, 0, '3');
      await type(tester, 1, '2');
      expect(find.text('Adds up to the total'), findsOneWidget);

      await setTotal(tester, 1000);
      expect(values(tester), ['3', '2']);
      expect(find.text('€5.00 left'), findsOneWidget);
      expect(find.text('Distribute'), findsNothing);
      await tapText(tester, 'Rescale proportionally');
      expect(values(tester), ['6.00', '4.00']);
      expect(plan!.resolve(1000).isValid, isTrue);
    });

    testWidgets('explicit 0 stays out of the fill', (tester) async {
      await pumpEditor(tester, ids: ['a', 'b', 'c'], totalCents: 900);
      await mode(tester, 'Exact');
      await type(tester, 0, '3');
      await type(tester, 1, '0');
      await type(tester, 2, '');
      await tapText(tester, 'Distribute');
      expect(values(tester), ['3', '0', '6.00']);
      expect(plan!.exact, {'a': 300, 'c': 600});
    });

    testWidgets('German: status and action', (tester) async {
      await pumpEditor(tester, totalCents: 500, locale: const Locale('de'));
      await mode(tester, 'Genau');
      await type(tester, 0, '2,5');
      await type(tester, 1, '');
      expect(find.text('noch 2,50 € offen'), findsOneWidget);
      await tapText(tester, 'Verteilen');
      expect(values(tester), ['2,5', '2,50']);
    });
  });

  group('mode switch prefills from the current split', () {
    testWidgets('Equal → Exact shows the equal amounts, excluded = 0', (
      tester,
    ) async {
      await pumpEditor(tester, ids: ['a', 'b', 'c'], totalCents: 1000);
      await tester.tap(find.byType(Checkbox).at(2));
      await tester.pumpAndSettle();
      await mode(tester, 'Exact');
      expect(values(tester), ['5.00', '5.00', '0']);
      expect(plan!.resolve(1000).isValid, isTrue);
      expect(plan!.exact, {'a': 500, 'b': 500});
    });

    testWidgets('Equal → Shares: 1 each; Equal → %: sums to 100', (
      tester,
    ) async {
      await pumpEditor(tester, ids: ['a', 'b', 'c'], totalCents: 1000);
      await mode(tester, 'Shares');
      expect(values(tester), ['1', '1', '1']);
      expect(resolved('a'), 334);

      await pumpEditor(tester, ids: ['a', 'b', 'c'], totalCents: 1000);
      await mode(tester, '%');
      expect(values(tester), ['33.34', '33.33', '33.33']);
      expect(find.text('Adds up to 100%'), findsOneWidget);
      expect(plan!.resolve(1000).isValid, isTrue);
    });

    testWidgets('Exact → Shares → % stay proportional', (tester) async {
      await pumpEditor(tester, totalCents: 2000);
      await mode(tester, 'Exact');
      await type(tester, 0, '15');
      await type(tester, 1, '5');
      await mode(tester, 'Shares');
      expect(values(tester), ['3', '1']);
      expect(resolved('a'), 1500);
      await mode(tester, '%');
      expect(values(tester), ['75', '25']);
      await mode(tester, 'Equal');
      expect(plan!.included, ['a', 'b']);
    });

    testWidgets('G61: uneven amounts → small shares, same cents', (
      tester,
    ) async {
      await pumpEditor(tester, totalCents: 1000);
      await mode(tester, 'Exact');
      await type(tester, 0, '3.33');
      await type(tester, 1, '6.67');
      await mode(tester, 'Shares');
      expect(values(tester), ['1', '2']);
      expect(resolved('a'), 333);
      expect(resolved('b'), 667);
    });

    testWidgets('a peek returns to what was typed', (tester) async {
      await pumpEditor(tester, totalCents: 2000);
      await mode(tester, 'Exact');
      await type(tester, 0, '15');
      await type(tester, 1, '5');
      await mode(tester, 'Equal');
      await mode(tester, 'Exact');
      expect(values(tester), ['15', '5']);
      // A change in between converts instead.
      await mode(tester, 'Equal');
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pumpAndSettle();
      await mode(tester, 'Exact');
      expect(values(tester), ['20.00', '0']);
    });

    testWidgets('an incomplete split keeps the target mode as it was', (
      tester,
    ) async {
      await pumpEditor(tester, totalCents: 2000);
      await mode(tester, 'Shares');
      await type(tester, 0, '3');
      await mode(tester, 'Exact');
      expect(values(tester), ['15.00', '5.00']);
      await type(tester, 1, '1'); // doesn't add up any more
      await mode(tester, 'Shares');
      expect(values(tester), ['3', '1']);
    });

    testWidgets('editing a stored split converts the same way', (tester) async {
      await pumpEditor(
        tester,
        ids: ['a', 'b', 'c'],
        totalCents: 4200,
        initial: {'a': 3000, 'b': 1200},
      );
      expect(values(tester), ['30.00', '12.00', '0']);
      await mode(tester, 'Shares');
      expect(values(tester), ['5', '2', '0']);
      expect(resolved('a'), 3000);
    });
  });

  group('Percent and Shares', () {
    testWidgets('Percent: Distribute and rest-here for open people', (
      tester,
    ) async {
      await pumpEditor(tester, ids: ['a', 'b', 'c'], totalCents: 1000);
      await mode(tester, '%');
      await type(tester, 0, '50');
      expect(find.text('16.66% too much'), findsOneWidget);
      await tapText(tester, 'Distribute');
      expect(values(tester), ['50', '25', '25']);
      expect(plan!.resolve(1000).isValid, isTrue);

      await type(tester, 1, '10');
      await type(tester, 2, '');
      expect(find.text('40% left'), findsOneWidget);
      await tester.tap(find.byTooltip('Put the rest here').at(2));
      await tester.pumpAndSettle();
      expect(values(tester), ['50', '10', '40']);
      expect(resolved('c'), 400);
    });

    testWidgets('Shares: +/- steppers, never below 0', (tester) async {
      await pumpEditor(tester, totalCents: 900);
      await mode(tester, 'Shares');
      await tester.tap(find.byTooltip('One share more').at(0));
      await tester.pumpAndSettle();
      expect(values(tester), ['2', '1']);
      expect(resolved('a'), 600);

      final less = find.byTooltip('One share less').at(1);
      await tester.tap(less);
      await tester.pumpAndSettle();
      expect(values(tester), ['2', '0']);
      expect(plan!.weights, {'a': 2});
      final button = tester.widget<IconButton>(
        find.ancestor(of: less, matching: find.byType(IconButton)),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('G61: live remainder, set total, fine-tune', () {
    Finder setTotalBtn() => find.byKey(const Key('splitSetTotal'));
    String remainingText(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('splitRemaining'))).data!;

    testWidgets('the remainder updates on every keystroke, next to the '
        'action', (tester) async {
      await pumpEditor(tester, totalCents: 1000);
      await mode(tester, 'Exact');
      await type(tester, 0, '2');
      await type(tester, 1, '');
      expect(remainingText(tester), '€8.00 left');
      await type(tester, 0, '2.5');
      expect(remainingText(tester), '€7.50 left');
      await type(tester, 0, '12.5');
      expect(remainingText(tester), '€2.50 too much');
      // Label and action share one row (same Wrap).
      final wrap = find.ancestor(
        of: find.byKey(const Key('splitRemaining')),
        matching: find.byType(Wrap),
      );
      expect(
        find.descendant(of: wrap, matching: find.text('Distribute')),
        findsNothing, // nothing open can absorb a negative rest
      );
      expect(
        find.descendant(
          of: wrap,
          matching: find.text('Rescale proportionally'),
        ),
        findsOneWidget,
      );
      await type(tester, 0, '10');
      expect(find.byKey(const Key('splitRemaining')), findsNothing);
      expect(find.text('Adds up to the total'), findsOneWidget);
    });

    testWidgets('too much → "Set total to the sum" next to rescale', (
      tester,
    ) async {
      await pumpEditor(tester, totalCents: 1000, canSetTotal: true);
      await mode(tester, 'Exact');
      await type(tester, 0, '8');
      await type(tester, 1, '5');
      expect(remainingText(tester), '€3.00 too much');
      expect(find.text('Rescale proportionally'), findsOneWidget);
      expect(find.text('Set total to the sum'), findsOneWidget);

      await tester.tap(setTotalBtn());
      await tester.pumpAndSettle();
      expect(total.value, 1300);
      expect(values(tester), ['8', '5']);
      expect(find.text('Adds up to the total'), findsOneWidget);
      expect(plan!.resolve(1300).isValid, isTrue);
      expect(plan!.exact, {'a': 800, 'b': 500});
      expect(setTotalBtn(), findsNothing);
    });

    testWidgets('not offered when something is left, without the callback, '
        'or in other modes', (tester) async {
      await pumpEditor(tester, totalCents: 1000, canSetTotal: true);
      await mode(tester, 'Exact');
      await type(tester, 0, '2');
      await type(tester, 1, '3');
      expect(remainingText(tester), '€5.00 left');
      expect(setTotalBtn(), findsNothing);
      await mode(tester, '%');
      await type(tester, 0, '80');
      await type(tester, 1, '50');
      expect(setTotalBtn(), findsNothing);

      await pumpEditor(tester, totalCents: 1000);
      await mode(tester, 'Exact');
      await type(tester, 0, '8');
      await type(tester, 1, '5');
      expect(remainingText(tester), '€3.00 too much');
      expect(setTotalBtn(), findsNothing);
    });

    testWidgets('no amount yet: typed rows can become the total', (
      tester,
    ) async {
      await pumpEditor(tester, canSetTotal: true);
      await mode(tester, 'Exact');
      expect(setTotalBtn(), findsNothing); // nothing typed
      await type(tester, 0, '4');
      await type(tester, 1, '1.5');
      expect(find.text('Enter the amount first'), findsOneWidget);
      await tester.tap(setTotalBtn());
      await tester.pumpAndSettle();
      expect(total.value, 550);
      expect(find.text('Adds up to the total'), findsOneWidget);
    });

    testWidgets('Shares 4:1 → "Fine-tune as amounts" gives 4.00 / 1.00', (
      tester,
    ) async {
      await pumpEditor(tester, totalCents: 500);
      await mode(tester, 'Shares');
      await type(tester, 0, '4');
      await tester.tap(find.byKey(const Key('splitFineTune')));
      await tester.pumpAndSettle();
      // Now Exact, rows prefilled (and still "open" for Distribute).
      expect(find.text('Adds up to the total'), findsOneWidget);
      expect(values(tester), ['4.00', '1.00']);
      expect(plan!.mode, SplitMode.exact);
      expect(plan!.exact, {'a': 400, 'b': 100});

      await type(tester, 0, '3.5');
      expect(remainingText(tester), '€0.50 left');
      await tapText(tester, 'Distribute');
      expect(values(tester), ['3.5', '1.50']);
    });

    testWidgets('fine-tune converts even when Exact was only peeked at', (
      tester,
    ) async {
      await pumpEditor(tester, totalCents: 1000);
      await mode(tester, 'Exact'); // 5.00 / 5.00
      await mode(tester, 'Shares'); // 1 / 1 (converted)
      // Back to Exact via the action right away (a peek would also show
      // 5.00 / 5.00) — then change the shares and fine-tune again.
      await tester.tap(find.byTooltip('One share more').at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('splitFineTune')));
      await tester.pumpAndSettle();
      expect(values(tester), ['6.67', '3.33']);
      await mode(tester, 'Shares');
      await tester.tap(find.byKey(const Key('splitFineTune')));
      await tester.pumpAndSettle();
      expect(values(tester), ['6.67', '3.33']);
    });

    testWidgets('fine-tune hidden without an amount or any share', (
      tester,
    ) async {
      await pumpEditor(tester);
      await mode(tester, 'Shares');
      expect(find.byKey(const Key('splitFineTune')), findsNothing);
      await setTotal(tester, 500);
      expect(find.text('Fine-tune as amounts'), findsOneWidget);
      await type(tester, 0, '0');
      await type(tester, 1, '0');
      expect(find.byKey(const Key('splitFineTune')), findsNothing);
    });

    testWidgets('German labels', (tester) async {
      await pumpEditor(
        tester,
        totalCents: 1000,
        canSetTotal: true,
        locale: const Locale('de'),
      );
      await mode(tester, 'Anteile');
      expect(find.text('Als Beträge feinjustieren'), findsOneWidget);
      await mode(tester, 'Genau');
      await type(tester, 0, '8');
      await type(tester, 1, '5');
      expect(remainingText(tester), '3,00\u00a0€ zu viel');
      expect(find.text('Proportional anpassen'), findsOneWidget);
      expect(find.text('Gesamtbetrag auf die Summe setzen'), findsOneWidget);
    });

    // 360 dp phone, the (wide, square-glyph) test font: every action row
    // wraps instead of overflowing, in English and German.
    for (final locale in [null, const Locale('de')]) {
      final lang = locale?.languageCode ?? 'en';
      testWidgets('[$lang] 360 dp: action rows wrap without overflow', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 780);
        addTearDown(tester.view.reset);
        final de = lang == 'de';
        await pumpEditor(
          tester,
          ids: ['a', 'b', 'c'],
          totalCents: 1000,
          canSetTotal: true,
          locale: locale,
        );
        await mode(tester, de ? 'Anteile' : 'Shares');
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('splitFineTune')), findsOneWidget);

        await mode(tester, de ? 'Genau' : 'Exact');
        await type(tester, 0, '8');
        await type(tester, 1, '5');
        await type(tester, 2, '3');
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('splitRescale')), findsOneWidget);
        expect(setTotalBtn(), findsOneWidget);
        // Every label is shown in full (wrapped, never cut).
        for (final p in tester.renderObjectList<RenderParagraph>(
          find.descendant(
            of: find.byType(Wrap),
            matching: find.byType(RichText),
          ),
        )) {
          expect(p.didExceedMaxLines, isFalse);
          expect(p.size.width, lessThanOrEqualTo(360));
        }

        await type(tester, 0, '1');
        expect(find.byKey(const Key('splitRemaining')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await mode(tester, '%');
        await type(tester, 0, '10');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
