/// DEV-K: the invite state follows the link channel — a lock by another
/// member makes this device leave the relays (channel deleted) without any
/// action here; the group page used to keep the link sync icon ("sending to
/// the relays …") until it was reopened.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/database/daos/link_dao.dart';
import 'package:money_ledger/core/session/app_session.dart';
import 'package:money_ledger/features/expenses/expenses_provider.dart';
import 'package:money_ledger/features/groups/group_provider.dart';
import 'package:money_ledger/features/link/link_invite.dart';
import 'package:money_ledger/models/group_model.dart';
import 'package:money_ledger/models/link_model.dart';
import 'package:money_ledger/models/member_model.dart';

import '../helpers/eventually.dart';
import '../helpers/in_memory_database.dart';

const _g = 'g1';

void main() {
  test('a channel deleted under the provider (lock by a peer) turns the '
      'state from open to not open', () async {
    final db = openTestDatabase();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        localModeActiveProvider.overrideWithValue(true),
        currentUserIdProvider.overrideWithValue(''),
        groupMembersProvider(
          _g,
        ).overrideWith((ref) => Stream.value(const <MemberModel>[])),
        ledgerGroupsProvider.overrideWith(
          (ref) => Stream.value(const <GroupModel>[]),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    final dao = LinkDao(db);
    await dao.putChannel(
      const LinkChannelModel(
        groupId: _g,
        epoch: 1,
        secret: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8',
        nostrPriv:
            '1111111111111111111111111111111111111111111111111111111111111111',
        openedAt: 1,
      ),
    );
    final sub = container.listen(linkInviteStateProvider(_g), (_, _) {});
    addTearDown(sub.close);
    await eventually(
      () =>
          container.read(linkInviteStateProvider(_g)).value ==
          LinkInviteState.open,
    );
    await dao.deleteChannel(_g);
    await eventually(
      () =>
          container.read(linkInviteStateProvider(_g)).hasValue &&
          container.read(linkInviteStateProvider(_g)).value !=
              LinkInviteState.open,
    );
  });
}
