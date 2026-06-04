/// A group member, projected from the Members table. [status] is `active` or
/// `removed`; [updatedAt] is the LWW logical clock (ms epoch).
class MemberModel {
  final String groupId;
  final String userId;
  final String status;
  final int updatedAt;

  const MemberModel({
    required this.groupId,
    required this.userId,
    required this.status,
    required this.updatedAt,
  });

  bool get isActive => status == 'active';
}
