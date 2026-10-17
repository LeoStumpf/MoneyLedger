import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/demo/demo_mode.dart' show kOfflineDemo;
import '../../core/session/app_session.dart' show ledgerIdentityProvider;
import '../../models/expense_model.dart';
import '../expenses/expenses_provider.dart';
import '../history/restore_points.dart' show ledgerDatabaseName;
import 'receipt_store_platform.dart';

/// G78: the receipt photos of one ledger DB — **this device only**: never
/// synced, never in a backup file / snapshot / CSV, Android backup off
/// (G32). One file per expense, keyed by the expense id; the file's
/// existence is the only "has a receipt" flag (no schema change).
///
/// Native (Android): `<app support>/receipts/<db name>/<expense id>.jpg`.
/// Elsewhere (web, desktop, the offline demo): none — see
/// [receiptStoreFactoryProvider].
abstract class ReceiptStore {
  /// The expense ids that have a photo.
  Future<Set<String>> list();

  /// The photo of [expenseId], or null when there is none.
  Future<Uint8List?> read(String expenseId);

  /// Stores [bytes] as the photo of [expenseId] atomically (temp file +
  /// rename), replacing an earlier one.
  Future<void> write(String expenseId, Uint8List bytes);
  Future<void> delete(String expenseId);

  /// Removes the whole store (local data deleted / adopted).
  Future<void> deleteAll();
}

/// Whether [expenseId] can name a receipt file (expense ids are UUIDv7s;
/// anything that could leave the directory is refused).
bool isValidReceiptId(String expenseId) =>
    expenseId.isNotEmpty &&
    expenseId.length <= 128 &&
    !expenseId.startsWith('.') &&
    !expenseId.contains('/') &&
    !expenseId.contains(r'\');

/// A [ReceiptStore] in memory — tests.
class InMemoryReceiptStore implements ReceiptStore {
  final files = <String, Uint8List>{};

  @override
  Future<Set<String>> list() async => files.keys.toSet();
  @override
  Future<Uint8List?> read(String expenseId) async => files[expenseId];
  @override
  Future<void> write(String expenseId, Uint8List bytes) async {
    if (!isValidReceiptId(expenseId)) {
      throw ArgumentError.value(expenseId, 'expenseId');
    }
    files[expenseId] = bytes;
  }

  @override
  Future<void> delete(String expenseId) async => files.remove(expenseId);
  @override
  Future<void> deleteAll() async => files.clear();
}

/// The receipt store of the ledger DB called `dbName`, or null where this
/// platform keeps no receipt photos (Leo 2026-10-17: **Android only** — not
/// on the web, desktop or in the offline demo; the form then shows nothing).
final receiptStoreFactoryProvider =
    Provider<ReceiptStore? Function(String dbName)?>(
      (ref) => kOfflineDemo ? null : platformReceiptStoreFactory(),
    );

/// The receipt store of the **current** ledger DB (null while signed out /
/// unsupported). Rebuilds with the account, like the ledger DB (G4).
final receiptStoreProvider = Provider<ReceiptStore?>((ref) {
  final factory = ref.watch(receiptStoreFactoryProvider);
  if (factory == null) return null;
  final db = ref.watch(appDatabaseProvider);
  final id = ref.watch(ledgerIdentityProvider);
  if (db.isSignedOutPlaceholder || id == null) return null;
  return factory(ledgerDatabaseName(id));
});

/// Whether the expense form offers a receipt photo.
final receiptsSupportedProvider = Provider<bool>(
  (ref) => ref.watch(receiptStoreProvider) != null,
);

/// The expense ids of the current ledger that have a receipt photo (the
/// ledger list's indicator) + the writes that keep it current.
final receiptIndexProvider = AsyncNotifierProvider<ReceiptIndex, Set<String>>(
  ReceiptIndex.new,
);

class ReceiptIndex extends AsyncNotifier<Set<String>> {
  ReceiptStore? _store;

  @override
  Future<Set<String>> build() async {
    final store = _store = ref.watch(receiptStoreProvider);
    if (store == null) return const {};
    try {
      return await store.list();
    } catch (e) {
      debugPrint('[receipts] listing failed: $e');
      return const {};
    }
  }

  /// The photo of [expenseId] (null: none, or unreadable — logged).
  Future<Uint8List?> read(String expenseId) async {
    try {
      return await _store?.read(expenseId);
    } catch (e) {
      debugPrint('[receipts] reading $expenseId failed: $e');
      return null;
    }
  }

  /// Stores the photo of [expenseId]. Throws when it can't be written.
  Future<void> save(String expenseId, Uint8List bytes) async {
    final store = _store;
    if (store == null) throw StateError('no receipt store');
    await store.write(expenseId, bytes);
    _update((ids) => {...ids, expenseId});
  }

  /// Deletes the photo of [expenseId] (no-op without one).
  Future<void> remove(String expenseId) async {
    await _store?.delete(expenseId);
    _update((ids) => {...ids}..remove(expenseId));
  }

  void _update(Set<String> Function(Set<String>) change) {
    if (!ref.mounted) return;
    state = AsyncData(change(state.value ?? const {}));
  }
}

/// G78 lifecycle: deletes every photo in [store] whose expense is gone
/// (group left / deleted, ledger purged) or **tombstoned** (deleted here or
/// by a peer). Runs once per ledger DB open — not at the moment of the
/// delete, so the delete's *Undo* (G67) and a G48 reset in the same session
/// bring the expense back with its photo. Returns how many were deleted.
Future<int> sweepReceipts(
  ReceiptStore store,
  Future<ExpenseModel?> Function(String id) expenseById,
) async {
  var removed = 0;
  for (final id in await store.list()) {
    final e = await expenseById(id);
    if (e == null || e.deleted) {
      await store.delete(id);
      removed++;
    }
  }
  return removed;
}

/// Runs [sweepReceipts] once per ledger DB open (watched by
/// `LedgerSyncHost`). Never throws.
final receiptMaintenanceProvider = FutureProvider.autoDispose<void>((
  ref,
) async {
  final store = ref.watch(receiptStoreProvider);
  if (store == null) return;
  final db = ref.watch(appDatabaseProvider);
  final expenses = ref.read(expensesDaoProvider);
  try {
    final n = await sweepReceipts(store, (id) async {
      if (db.isClosed) throw StateError('ledger closed');
      return expenses.getExpenseById(id);
    });
    if (n > 0) {
      debugPrint('[receipts] deleted $n photo(s) of deleted expenses');
      if (ref.mounted) ref.invalidate(receiptIndexProvider);
    }
  } catch (e) {
    if (!db.isClosed) debugPrint('[receipts] cleanup failed: $e');
  }
});

/// G78: a group was left / deleted on this device — its photos go at once
/// ([expenseIds]: the group's expenses, read before the purge). Best-effort;
/// anything missed is swept on the next start ([sweepReceipts]).
Future<void> deleteReceiptsOf(
  ReceiptStore? store,
  Iterable<String> expenseIds,
) async {
  if (store == null) return;
  for (final id in expenseIds) {
    try {
      await store.delete(id);
    } catch (e) {
      debugPrint('[receipts] deleting $id failed: $e');
    }
  }
}

/// G78 + G40: local mode's ledger was adopted into an account — its
/// expenses (same ids) live on there, so their photos move along ([from] →
/// [to]; one already in [to] is kept). Best-effort, never throws; [from] is
/// deleted with the local ledger's files afterwards.
Future<void> moveReceipts(ReceiptStore? from, ReceiptStore? to) async {
  if (from == null || to == null) return;
  try {
    final existing = await to.list();
    for (final id in await from.list()) {
      if (existing.contains(id)) continue;
      final bytes = await from.read(id);
      if (bytes != null) await to.write(id, bytes);
    }
  } catch (e) {
    debugPrint('[receipts] moving local photos failed: $e');
  }
}
