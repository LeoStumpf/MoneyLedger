/// G59: smarter split defaults — the SplitEditor prefills a mode from the
/// current split, offers "fill the rest" / "rest here" / "rescale", and Shares
/// has +/- steppers. Pure math is covered in split_calculator_test.dart.
library;

import 'package:flutter/material.dart';
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
}
