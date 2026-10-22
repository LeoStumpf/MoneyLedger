/// G54 review: the `why_matrix_hint_dismissed` setting behind the one-time
/// groups-page "Why Matrix?" card — not set → false, dismissed → true for
/// good (idempotent), per ledger DB.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/settings_dao.dart';

import '../helpers/in_memory_database.dart';

void main() {
  test('not dismissed until dismissWhyMatrixHint, then for good', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final dao = SettingsDao(db);
    expect(await dao.watchWhyMatrixHintDismissed().first, isFalse);
    await dao.dismissWhyMatrixHint();
    expect(await dao.watchWhyMatrixHintDismissed().first, isTrue);
    await dao.dismissWhyMatrixHint();
    expect(await dao.watchWhyMatrixHintDismissed().first, isTrue);
  });

  test('per ledger: another DB still shows the hint', () async {
    final a = openTestDatabase();
    final b = openTestDatabase();
    addTearDown(a.close);
    addTearDown(b.close);
    await SettingsDao(a).dismissWhyMatrixHint();
    expect(await SettingsDao(b).watchWhyMatrixHintDismissed().first, isFalse);
  });
}
