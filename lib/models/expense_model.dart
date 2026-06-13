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
  });
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
  });
}
