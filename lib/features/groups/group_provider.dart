import 'package:drift/drift.dart';
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
