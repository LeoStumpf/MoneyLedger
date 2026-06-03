/// The app's transport port: a narrow, plain-Dart interface over whatever
/// delivers ledger data (the real Matrix client, or an in-memory fake in tests).
///
/// **No `package:matrix` import may ever be added to this file.** Everything
/// here is plain Dart so that test code (and the fake network) can depend on it
/// without pulling in the Matrix SDK / native sqlite3. The real implementation
/// lives in `matrix_ledger_transport.dart`.
library;

// Matrix event types used across the app. Kept here (not in matrix_service.dart)
// so both the real adapter and matrix-free test code can reference them.
const groupStateEventType = 'app.moneyledger.group';
const expenseEventType = 'com.moneyledger.expense';
const settlementEventType = 'com.moneyledger.settlement';

enum TransportMembership { join, invite, leave }

/// A member of a room, as the app cares about it.
class TransportMember {
  final String id;
  final String? displayName;
  final TransportMembership membership;

  const TransportMember({
    required this.id,
    this.displayName,
    required this.membership,
  });
}

/// A timeline event (expense / settlement / anything), in plain-Dart form.
class TransportEvent {
  final String eventId;
  final String type;
  final String senderId;
  final int originServerTs; // millis since epoch
  final Map<String, dynamic> content;

  const TransportEvent({
    required this.eventId,
    required this.type,
    required this.senderId,
    required this.originServerTs,
    required this.content,
  });
}

/// A room as the app sees it. [groupState] is the content of the
/// `app.moneyledger.group` state event, or null when this room is not a ledger
/// group *or* its state isn't visible yet (e.g. while only invited — matching
/// Matrix strip-state behaviour).
class TransportRoom {
  final String id;
  final String displayName;
  final TransportMembership membership;
  final Map<String, dynamic>? groupState;

  const TransportRoom({
    required this.id,
    required this.displayName,
    required this.membership,
    this.groupState,
  });

  bool get isLedgerGroup => groupState != null;
  String get currency => groupState?['currency'] as String? ?? 'EUR';
}

/// Delta delivered on each sync: the new timeline events per joined room.
/// An empty map is still a meaningful tick (membership/state may have changed —
/// consumers re-read [LedgerTransport.rooms]).
class TransportSyncUpdate {
  final Map<String, List<TransportEvent>> newTimelineEvents;
  const TransportSyncUpdate(this.newTimelineEvents);
}

/// Thrown when a transport operation (e.g. a federated join with no resolvable
/// resident server) fails.
class TransportJoinException implements Exception {
  final String message;
  TransportJoinException(this.message);
  @override
  String toString() => 'TransportJoinException: $message';
}

/// The operations the app needs from its sync/transport layer.
abstract interface class LedgerTransport {
  String get userId;

  /// Fires on every sync. Broadcast — multiple listeners are supported.
  Stream<TransportSyncUpdate> get onSync;

  /// All rooms currently known for this user (join + invite).
  List<TransportRoom> get rooms;
  TransportRoom? room(String roomId);

  Future<String> createGroup(String name, String currency);
  Future<void> invite(String roomId, String userId);

  /// Joins [roomId]. Implementations are responsible for supplying any
  /// resident-server hints needed for a federated join.
  Future<void> join(String roomId);
  Future<void> leave(String roomId);
  Future<void> kick(String roomId, String userId);

  Future<void> sendExpense(String roomId, Map<String, dynamic> content);
  Future<void> sendSettlement(String roomId, Map<String, dynamic> content);

  Future<List<TransportMember>> participants(
    String roomId, {
    Set<TransportMembership> memberships,
  });

  Future<List<TransportEvent>> timelineEvents(String roomId);
}

/// Pure: resident-server hints derivable from a room id and the inviter's MXID.
/// Used to join a federated room by id (the `via` parameter). The room id's
/// origin server is always the creating homeserver and a guaranteed resident
/// server; the inviter's server is a second good candidate.
List<String> viaServersFrom(String roomId, String? inviterId) {
  final servers = <String>{};
  final colon = roomId.indexOf(':');
  if (colon != -1 && colon + 1 < roomId.length) {
    servers.add(roomId.substring(colon + 1));
  }
  if (inviterId != null) {
    final ic = inviterId.indexOf(':');
    if (ic != -1 && ic + 1 < inviterId.length) {
      servers.add(inviterId.substring(ic + 1));
    }
  }
  return servers.toList();
}
