import 'package:drift/drift.dart';
import 'package:matrix/matrix.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/database/app_database.dart';
import '../../core/matrix/matrix_service.dart';
import '../../models/group_model.dart';
import '../auth/auth_provider.dart';
import '../expenses/expenses_provider.dart';

part 'group_provider.g.dart';

@riverpod
Stream<List<GroupModel>> ledgerGroups(Ref ref) {
  return ref.watch(groupsDaoProvider).watchAllGroups();
}

@riverpod
Stream<List<Room>> pendingInvites(Ref ref) async* {
  final client = await ref.watch(matrixClientProvider.future);
  yield _invitedRooms(client);
  await for (final _ in client.onSync.stream) {
    yield _invitedRooms(client);
  }
}

List<Room> _invitedRooms(Client client) =>
    client.rooms.where((r) => r.membership == Membership.invite).toList();

@riverpod
class GroupCreator extends _$GroupCreator {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> create(String name, String currency) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = await ref.read(matrixClientProvider.future);
      final roomId = await client.createLedgerGroup(name, currency);
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
      final client = await ref.read(matrixClientProvider.future);
      final room = client.getRoomById(roomId);
      if (room == null) throw Exception('Room not found');
      await room.invite(userId);
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
      final client = await ref.read(matrixClientProvider.future);
      await client.joinRoomById(roomId);
    });
  }

  Future<void> decline(String roomId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = await ref.read(matrixClientProvider.future);
      final room = client.getRoomById(roomId);
      await room?.leave();
    });
  }
}
