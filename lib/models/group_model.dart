import 'record_signature.dart';

class GroupModel {
  final String roomId;
  final String name;
  final String currency;
  final int updatedAt; // ms epoch, LWW clock for the group meta (name/currency)

  /// G6: signature of this meta version (null = legacy / unsigned).
  final RecordSignature? sig;

  /// G6: written while the signer wasn't ready; signed before it is sent.
  final bool pendingSign;

  const GroupModel({
    required this.roomId,
    required this.name,
    required this.currency,
    this.updatedAt = 0,
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
        sig: sig,
        pendingSign: pendingSign,
      );
}
