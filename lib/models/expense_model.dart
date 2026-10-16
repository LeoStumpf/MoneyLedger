import 'record_signature.dart';

class ExpenseModel {
  final String id;
  final String roomId;
  final String? matrixEventId;
  final String description;
  final int amountCents;
  final String currency;
  final String paidBy;
  final String splitsJson;
  final int createdAt;
  final int updatedAt; // ms epoch, LWW clock
  final bool deleted; // tombstone — kept forever, hidden from the UI

  /// G6: this version's signature (its editor), null for a grandfathered
  /// pre-G6 row (legacy / unsigned).
  final RecordSignature? sig;

  /// G6: the creator's signed creation statement ("added by"), carried
  /// unchanged across edits; null when unknown (legacy).
  final RecordSignature? origin;

  /// G6: written locally while the signer wasn't ready — signed (same clock)
  /// before it is ever sent. Device-local, never on the wire.
  final bool pendingSign;

  const ExpenseModel({
    required this.id,
    required this.roomId,
    this.matrixEventId,
    required this.description,
    required this.amountCents,
    required this.currency,
    required this.paidBy,
    required this.splitsJson,
    required this.createdAt,
    this.updatedAt = 0,
    this.deleted = false,
    this.sig,
    this.origin,
    this.pendingSign = false,
  });

  /// A copy with the G6 signing fields replaced (content unchanged).
  ExpenseModel withSigning({
    RecordSignature? sig,
    RecordSignature? origin,
    bool pendingSign = false,
  }) => ExpenseModel(
    id: id,
    roomId: roomId,
    matrixEventId: matrixEventId,
    description: description,
    amountCents: amountCents,
    currency: currency,
    paidBy: paidBy,
    splitsJson: splitsJson,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deleted: deleted,
    sig: sig,
    origin: origin,
    pendingSign: pendingSign,
  );
}

class SettlementModel {
  final String id;
  final String roomId;
  final String? matrixEventId;
  final int amountCents;
  final String currency;
  final String fromUser;
  final String toUser;
  final int createdAt;
  final int updatedAt; // ms epoch, LWW clock
  final bool deleted; // tombstone — kept forever, hidden from the UI

  /// G6 signing fields — see [ExpenseModel.sig].
  final RecordSignature? sig;
  final RecordSignature? origin;
  final bool pendingSign;

  const SettlementModel({
    required this.id,
    required this.roomId,
    this.matrixEventId,
    required this.amountCents,
    required this.currency,
    required this.fromUser,
    required this.toUser,
    required this.createdAt,
    this.updatedAt = 0,
    this.deleted = false,
    this.sig,
    this.origin,
    this.pendingSign = false,
  });

  /// A copy with the G6 signing fields replaced (content unchanged).
  SettlementModel withSigning({
    RecordSignature? sig,
    RecordSignature? origin,
    bool pendingSign = false,
  }) => SettlementModel(
    id: id,
    roomId: roomId,
    matrixEventId: matrixEventId,
    amountCents: amountCents,
    currency: currency,
    fromUser: fromUser,
    toUser: toUser,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deleted: deleted,
    sig: sig,
    origin: origin,
    pendingSign: pendingSign,
  );
}
