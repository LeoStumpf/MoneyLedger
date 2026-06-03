import 'package:matrix/matrix.dart';

import 'ledger_transport.dart';
import 'matrix_service.dart';

/// Real [LedgerTransport] backed by the Matrix SDK [Client]. This is the only
/// place that translates between `package:matrix` types and the app's
/// plain-Dart transport DTOs.
class MatrixLedgerTransport implements LedgerTransport {
  final Client _client;
  MatrixLedgerTransport(this._client);

  @override
  String get userId => _client.userID ?? '';

  @override
  Stream<TransportSyncUpdate> get onSync =>
      _client.onSync.stream.map(_toSyncUpdate);

  @override
  List<TransportRoom> get rooms => _client.rooms.map(_toRoom).toList();

  @override
  TransportRoom? room(String roomId) {
    final r = _client.getRoomById(roomId);
    return r == null ? null : _toRoom(r);
  }

  @override
  Future<String> createGroup(String name, String currency) =>
      _client.createLedgerGroup(name, currency);

  @override
  Future<void> invite(String roomId, String userId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw TransportJoinException('Room not found: $roomId');
    await room.invite(userId);
  }

  @override
  Future<void> join(String roomId) async {
    // Federation-safe join: supply resident-server hints so the homeserver can
    // resolve a room created on another server. Without `via`, a bare
    // joinRoomById fails over federation (the original "Accept does nothing"
    // bug). See docs/fix-second-user-cannot-see-group.md.
    await _client.joinRoom(roomId, via: _viaFor(roomId));
  }

  @override
  Future<void> leave(String roomId) async {
    await _client.getRoomById(roomId)?.leave();
  }

  @override
  Future<void> kick(String roomId, String userId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) throw TransportJoinException('Room not found: $roomId');
    await room.kick(userId);
  }

  @override
  Future<void> sendExpense(String roomId, Map<String, dynamic> content) async {
    await _client.sendExpenseEvent(roomId, content);
  }

  @override
  Future<void> sendSettlement(
      String roomId, Map<String, dynamic> content) async {
    await _client.sendSettlementEvent(roomId, content);
  }

  @override
  Future<List<TransportMember>> participants(
    String roomId, {
    Set<TransportMembership> memberships = const {TransportMembership.join},
  }) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return [];
    final users =
        await room.requestParticipants(memberships.map(_toMatrix).toList());
    return users
        .map((u) => TransportMember(
              id: u.id,
              displayName: u.displayName,
              membership: _fromMatrix(u.membership),
            ))
        .toList();
  }

  @override
  Future<List<TransportEvent>> timelineEvents(String roomId) async {
    final room = _client.getRoomById(roomId);
    if (room == null) return [];
    final timeline = await room.getTimeline();
    return timeline.events.map(_toEvent).toList();
  }

  @override
  Future<void> loadHistory(String roomId) => _client.loadRoomHistory(roomId);

  // ── mapping helpers ─────────────────────────────────────────────────────

  /// Resident-server hints for [roomId]: the room id's origin server plus the
  /// server of whoever invited us (read from our own membership event).
  List<String> _viaFor(String roomId) {
    final room = _client.getRoomById(roomId);
    final me = _client.userID;
    String? inviter;
    if (room != null && me != null) {
      inviter = room.getState(EventTypes.RoomMember, me)?.senderId;
    }
    return viaServersFrom(roomId, inviter);
  }

  TransportSyncUpdate _toSyncUpdate(SyncUpdate sync) {
    final result = <String, List<TransportEvent>>{};
    for (final entry in (sync.rooms?.join ?? {}).entries) {
      final events = entry.value.timeline?.events ?? [];
      if (events.isEmpty) continue;
      result[entry.key] = events
          .map((e) => TransportEvent(
                eventId: e.eventId,
                type: e.type,
                senderId: e.senderId,
                originServerTs: e.originServerTs.millisecondsSinceEpoch,
                content: e.content,
              ))
          .toList();
    }
    return TransportSyncUpdate(result);
  }

  TransportRoom _toRoom(Room room) => TransportRoom(
        id: room.id,
        displayName: room.name.isNotEmpty ? room.name : room.id,
        membership: _fromMatrix(room.membership),
        groupState: room.getState(groupStateEventType)?.content,
      );

  TransportEvent _toEvent(Event e) => TransportEvent(
        eventId: e.eventId,
        type: e.type,
        senderId: e.senderId,
        originServerTs: e.originServerTs.millisecondsSinceEpoch,
        content: e.content,
      );

  static TransportMembership _fromMatrix(Membership m) {
    switch (m) {
      case Membership.join:
        return TransportMembership.join;
      case Membership.invite:
        return TransportMembership.invite;
      default:
        return TransportMembership.leave;
    }
  }

  static Membership _toMatrix(TransportMembership m) {
    switch (m) {
      case TransportMembership.join:
        return Membership.join;
      case TransportMembership.invite:
        return Membership.invite;
      case TransportMembership.leave:
        return Membership.leave;
    }
  }
}
