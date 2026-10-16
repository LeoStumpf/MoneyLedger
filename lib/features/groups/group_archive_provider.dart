import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/sync/sync_status_provider.dart'
    show allExpensesForGroupProvider, allSettlementsForGroupProvider;
import '../../models/group_archive.dart';
import '../expenses/expenses_provider.dart';
import '../onboarding/onboarding_provider.dart' show settingsDaoProvider;

part 'group_archive_provider.g.dart';

/// G16: this account's archive entries on this device, by group id.
@riverpod
Stream<Map<String, GroupArchive>> groupArchives(Ref ref) =>
    ref.watch(settingsDaoProvider).watchArchivedGroups();

/// The current [ledgerFingerprint] of [groupId] (null while loading).
@riverpod
String? groupLedgerFingerprint(Ref ref, String groupId) {
  final expenses = ref.watch(allExpensesForGroupProvider(groupId));
  final settlements = ref.watch(allSettlementsForGroupProvider(groupId));
  if (!expenses.hasValue || !settlements.hasValue) return null;
  return ledgerFingerprint(expenses.value!, settlements.value!);
}

/// Whether [groupId] is archived here and had no activity since (see
/// [GroupArchive]). While the ledger is still loading an archived group
/// stays archived (no flicker between the sections).
@riverpod
bool groupArchived(Ref ref, String groupId) {
  final archive = ref.watch(groupArchivesProvider).value?[groupId];
  if (archive == null) return false;
  final fingerprint = ref.watch(groupLedgerFingerprintProvider(groupId));
  return fingerprint == null || archive.holdsFor(fingerprint);
}

/// Archives / un-archives a group on this device (G16). Device-local: no
/// write is replicated.
@riverpod
class GroupArchiver extends _$GroupArchiver {
  @override
  FutureOr<void> build() {}

  Future<void> archive(String groupId) async {
    // Capture the DAOs before the first await (G19).
    final settings = ref.read(settingsDaoProvider);
    final expenses = ref.read(expensesDaoProvider);
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final fingerprint = ledgerFingerprint(
        await expenses.getAllExpensesForGroup(groupId),
        await expenses.getAllSettlementsForGroup(groupId),
      );
      await settings.archiveGroup(
        groupId,
        GroupArchive(
          archivedAt: DateTime.now().millisecondsSinceEpoch,
          fingerprint: fingerprint,
        ),
      );
    });
    if (ref.mounted) state = result;
  }

  Future<void> unarchive(String groupId) async {
    final settings = ref.read(settingsDaoProvider);
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => settings.unarchiveGroup(groupId),
    );
    if (ref.mounted) state = result;
  }
}
