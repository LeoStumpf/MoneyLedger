/// SyncStatesDao.watchLatestInSyncWith (G34: "another device of ours proved
/// it holds our state" for the backup nudge).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/sync_states_dao.dart';

import '../helpers/in_memory_database.dart';

void main() {
  test(
    'newest lastInSyncAt for one user across groups; null if none',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final dao = SyncStatesDao(db);
      expect(await dao.watchLatestInSyncWith('@me:x').first, isNull);
      await dao.markInSync('g1', '@me:x', 100);
      await dao.markInSync('g2', '@me:x', 300);
      await dao.markInSync('g2', '@bo:x', 900);
      await dao.markDigestSent('g3', '@me:x', 5000); // not a proof
      expect(await dao.watchLatestInSyncWith('@me:x').first, 300);
      expect(await dao.watchLatestInSyncWith('@bo:x').first, 900);
    },
  );
}
