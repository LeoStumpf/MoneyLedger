import 'package:matrix/matrix.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/matrix/matrix_service.dart';
import '../auth/auth_provider.dart';

part 'group_provider.g.dart';

@riverpod
Stream<List<Room>> ledgerGroups(Ref ref) async* {
  final client = await ref.watch(matrixClientProvider.future);
  yield client.ledgerGroups;
  await for (final _ in client.onSync.stream) {
    yield client.ledgerGroups;
  }
}

@riverpod
class GroupCreator extends _$GroupCreator {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> create(String name, String currency) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final client = await ref.read(matrixClientProvider.future);
      await client.createLedgerGroup(name, currency);
    });
  }
}
