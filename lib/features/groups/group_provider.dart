import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/database/app_database.dart';
import '../../core/matrix/ledger_transport.dart';
import '../../core/matrix/transport_provider.dart';
import '../../models/group_model.dart';
import '../expenses/expenses_provider.dart';

part 'group_provider.g.dart';

@riverpod
Stream<List<GroupModel>> ledgerGroups(Ref ref) {
  return ref.watch(groupsDaoProvider).watchAllGroups();
}

@riverpod
Stream<List<TransportRoom>> pendingInvites(Ref ref) async* {
  final transport = await ref.watch(ledgerTransportProvider.future);
  yield _invitedRooms(transport);
  await for (final _ in transport.onSync) {
    yield _invitedRooms(transport);
  }
}

List<TransportRoom> _invitedRooms(LedgerTransport transport) => transport.rooms
    .where((r) => r.membership == TransportMembership.invite)
    .toList();

@riverpod
class GroupCreator extends _$GroupCreator {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> create(String name, String currency) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final transport = await ref.read(ledgerTransportProvider.future);
      final roomId = await transport.createGroup(name, currency);
      await ref.read(groupsDaoProvider).upsertGroup(GroupsCompanion(
            roomId: Value(roomId),
            name: Value(name),
            currency: Value(currency),
          ));
    });
  }
}

@riverpod
class UserInviter extends _$UserInviter {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> invite(String roomId, String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final transport = await ref.read(ledgerTransportProvider.future);
      await transport.invite(roomId, userId);
    });
  }
}

@riverpod
class MemberRemover extends _$MemberRemover {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Removes (kicks) [userId] from the room. The expense history they're part
  /// of stays in Drift, so balances are preserved — only their Matrix
  /// membership is cleared. See planned virtual-user model.
  Future<void> remove(String roomId, String userId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final transport = await ref.read(ledgerTransportProvider.future);
      await transport.kick(roomId, userId);
    });
  }
}

@riverpod
class InviteAcceptor extends _$InviteAcceptor {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> accept(String roomId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final transport = await ref.read(ledgerTransportProvider.future);
      // The transport supplies federation hints (`via`) so this works across
      // homeservers — see docs/fix-second-user-cannot-see-group.md.
      await transport.join(roomId);
      // Write to Drift immediately so the group appears without waiting for the
      // next sync. The room's group state may not be loaded yet right after
      // joining (currency falls back to EUR); LedgerSyncer overwrites it with
      // the correct data on the next onSync.
      final room = transport.room(roomId);
      await ref.read(groupsDaoProvider).upsertGroup(GroupsCompanion(
            roomId: Value(roomId),
            name: Value(room?.displayName ?? roomId),
            currency: Value(room?.currency ?? 'EUR'),
          ));
    });
  }

  Future<void> decline(String roomId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final transport = await ref.read(ledgerTransportProvider.future);
      await transport.leave(roomId);
    });
  }
}
