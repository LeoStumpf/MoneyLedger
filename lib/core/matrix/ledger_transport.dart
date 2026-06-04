/// The app's transport port: a narrow, plain-Dart interface over whatever
/// relays ledger data (the real Matrix client, or an in-memory fake in tests).
///
/// **No `package:matrix` import may ever be added to this file.** Everything
/// here is plain Dart so that test code (and the fake network) can depend on it
/// without pulling in the Matrix SDK / native sqlite3. The real implementation
/// lives in `matrix_ledger_transport.dart`.
///
/// Phase B: this is a **roomless relay**. There are no Matrix rooms — groups and
/// membership are owned by the local DB. The transport only resolves a set of
/// member MXIDs to their devices and ships an encrypted to-device payload to
/// them, and exposes an inbound stream of decrypted payloads. The homeserver
/// retains nothing once a to-device message is delivered.
library;

// Payload type tags carried as the to-device event `type`. All app payloads use
// the `com.moneyledger.` prefix so the transport can filter them on receive.
const expenseEventType = 'com.moneyledger.expense';
const settlementEventType = 'com.moneyledger.settlement';
const groupMetaEventType = 'com.moneyledger.group';
const memberEventType = 'com.moneyledger.member';
const bootstrapEventType = 'com.moneyledger.bootstrap';

/// Common prefix for every app to-device payload (used to filter inbound).
const moneyLedgerTypePrefix = 'com.moneyledger.';

/// One decrypted inbound to-device payload.
class TransportMessage {
  final String senderId;
  final String type;
  final Map<String, dynamic> content;

  const TransportMessage({
    required this.senderId,
    required this.type,
    required this.content,
  });
}

/// The operations the app needs from its relay layer.
abstract interface class LedgerTransport {
  /// This device's own Matrix ID.
  String get userId;

  /// Inbound decrypted app payloads. Broadcast — multiple listeners supported.
  Stream<TransportMessage> get onMessage;

  /// Encrypts and relays [content] (tagged [type]) to every device of every
  /// MXID in [userIds]. Best-effort: the homeserver queues undelivered
  /// to-device messages, and the SDK retries failed sends.
  Future<void> sendToUsers(
    Set<String> userIds,
    String type,
    Map<String, dynamic> content,
  );
}
