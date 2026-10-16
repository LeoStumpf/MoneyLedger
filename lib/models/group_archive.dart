/// G16: device-local group archive (plain Dart, unit-tested).
///
/// Archiving is a **personal view preference** — it hides a (usually
/// settled-up) group in the collapsed "Archived" section of the groups page
/// on this device, for this account. Nothing is sent; peers are unaffected.
/// Stored in `AppSettings` (`archived_group:<groupId>`, JSON).
///
/// **New activity un-archives automatically**: the archive remembers a
/// [GroupArchive.fingerprint] of the group's ledger (every expense and
/// payment id + `updated_at`, tombstones included) at archive time. Any new,
/// edited or deleted record — from a peer, another of our devices, a restore
/// or this device — changes the fingerprint, and the group is shown among
/// the active groups again (derived on read: nothing is written on the
/// inbound path, so it also holds for records that arrive via background
/// sync). Rationale: an archived group is out of sight, and a new expense
/// there usually means a new debt — it must not stay hidden. Member / name
/// changes don't count as activity.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'expense_model.dart';

class GroupArchive {
  /// When the user archived the group (ms epoch, informational).
  final int archivedAt;

  /// [ledgerFingerprint] of the group's records at archive time.
  final String fingerprint;

  const GroupArchive({required this.archivedAt, required this.fingerprint});

  String encode() => jsonEncode({'at': archivedAt, 'fp': fingerprint});

  /// Null for a missing or corrupt value (= not archived).
  static GroupArchive? decode(String? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final fp = m['fp'];
      if (fp is! String) return null;
      return GroupArchive(archivedAt: m['at'] as int? ?? 0, fingerprint: fp);
    } catch (_) {
      return null;
    }
  }

  /// Whether the group is still archived given its current
  /// [ledgerFingerprint] — false once anything changed since archiving.
  bool holdsFor(String currentFingerprint) => fingerprint == currentFingerprint;
}

/// A short, order-independent fingerprint of a group's ledger: SHA-256 over
/// the sorted `kind:id@updated_at` of every expense and settlement **incl.
/// tombstones** (16 hex chars). Every new version of a record has a higher
/// clock, so any add / edit / delete changes it.
String ledgerFingerprint(
  Iterable<ExpenseModel> expenses,
  Iterable<SettlementModel> settlements,
) {
  final lines = [
    for (final e in expenses) 'e:${e.id}@${e.updatedAt}',
    for (final s in settlements) 's:${s.id}@${s.updatedAt}',
  ]..sort();
  return sha256
      .convert(utf8.encode(lines.join('\n')))
      .toString()
      .substring(0, 16);
}
