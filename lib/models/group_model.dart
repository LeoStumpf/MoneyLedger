class GroupModel {
  final String roomId;
  final String name;
  final String currency;
  final int updatedAt; // ms epoch, LWW clock for the group meta (name/currency)

  const GroupModel({
    required this.roomId,
    required this.name,
    required this.currency,
    this.updatedAt = 0,
  });
}
