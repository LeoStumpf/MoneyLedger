import 'expense_category.dart';
import 'record_signature.dart';

class GroupModel {
  final String roomId;
  final String name;
  final String currency;
  final int updatedAt; // ms epoch, LWW clock for the group meta (name/currency)

  /// G47: the group's custom expense categories, in definition order (part
  /// of the signed meta, and of its hash, only when non-empty).
  final List<CustomCategory> categories;

  /// G6: signature of this meta version (null = legacy / unsigned).
  final RecordSignature? sig;

  /// G6: written while the signer wasn't ready; signed before it is sent.
  final bool pendingSign;

  const GroupModel({
    required this.roomId,
    required this.name,
    required this.currency,
    this.updatedAt = 0,
    this.categories = const [],
    this.sig,
    this.pendingSign = false,
  });

  /// A copy with the G6 signing fields replaced (content unchanged).
  GroupModel withSigning({RecordSignature? sig, bool pendingSign = false}) =>
      GroupModel(
        roomId: roomId,
        name: name,
        currency: currency,
        updatedAt: updatedAt,
        categories: categories,
        sig: sig,
        pendingSign: pendingSign,
      );

  /// The custom categories offered for new expenses (not hidden).
  List<CustomCategory> get visibleCategories => [
    for (final c in categories)
      if (!c.hidden) c,
  ];
}
