/// An in-memory "virtual Matrix network": multiple users across multiple
/// simulated homeservers, with rooms, membership, state, timeline, and basic
/// federation rules — but no real Matrix client, no sqlite3, no network.
///
/// Each [FakeTransport] is one user's view (one "device"), all sharing one
/// [FakeMatrixNetwork]. Wire it into the app by overriding `ledgerTransportProvider`
/// with `net.clientFor(userId)`.
///
/// No `package:matrix` import — it only depends on the plain-Dart transport port.
library;

import 'dart:async';

import 'package:money_ledger/core/matrix/ledger_transport.dart';

class FakeMatrixNetwork {
  final Map<String, _FakeRoom> _rooms = {};
  final Map<String, FakeTransport> _clients = {};
  int _eventSeq = 0;
  int _ts = 1700000000000;

  /// Returns (creating on first use) the transport view for [userId], e.g.
  /// `@alice:x.org`. Create a user's transport before they need to receive
  /// invites/events so delivery has somewhere to go.
  FakeTransport clientFor(String userId) =>
      _clients.putIfAbsent(userId, () => FakeTransport(this, userId));

  static String _serverOf(String id) => id.substring(id.indexOf(':') + 1);

  // ── mutations ────────────────────────────────────────────────────────────

  String createGroup(String creator, String name, String currency) {
    final id = '!room${_rooms.length}:${_serverOf(creator)}';
    _rooms[id] = _FakeRoom(id, name)
      ..groupState = {'currency': currency}
      ..members[creator] = TransportMembership.join;
    return id;
  }

  void invite(String roomId, String inviter, String userId) {
    final room = _rooms[roomId];
    if (room == null) throw TransportJoinException('Unknown room $roomId');
    room.members[userId] = TransportMembership.invite;
    room.inviterOf[userId] = inviter;
    _notify(userId); // deliver the invite as a sync tick
  }

  void join(String roomId, String userId) {
    final room = _rooms[roomId];
    if (room == null) throw TransportJoinException('Unknown room $roomId');
    final current = room.members[userId];
    final hasContext = current == TransportMembership.invite ||
        current == TransportMembership.join;
    final local = _serverOf(roomId) == _serverOf(userId);
    // Federation rule: joining a room hosted on another server by id requires
    // a resolvable resident server. Being invited carries that (the inviter's
    // server) — mirroring how the real fix derives `via` from the invite.
    // A user on a remote server with no invite cannot join: this is exactly the
    // "No known servers" failure the bare joinRoomById produced.
    if (!local && !hasContext) {
      throw TransportJoinException('No known servers for $roomId');
    }
    room.members[userId] = TransportMembership.join;
    _notify(userId);
  }

  void leave(String roomId, String userId) {
    final room = _rooms[roomId];
    if (room == null) return;
    room.members[userId] = TransportMembership.leave;
    _notify(userId);
  }

  void kick(String roomId, String actor, String userId) {
    final room = _rooms[roomId];
    if (room == null) throw TransportJoinException('Unknown room $roomId');
    room.members[userId] = TransportMembership.leave;
    _notify(userId);
  }

  void send(
      String roomId, String sender, String type, Map<String, dynamic> content) {
    final room = _rooms[roomId];
    if (room == null) throw TransportJoinException('Unknown room $roomId');
    final event = TransportEvent(
      eventId: '\$evt${_eventSeq++}',
      type: type,
      senderId: sender,
      originServerTs: _ts++,
      content: content,
    );
    room.timeline.add(event);
    for (final entry in room.members.entries) {
      if (entry.value == TransportMembership.join) {
        _deliver(entry.key, roomId, [event]);
      }
    }
  }

  // ── views ────────────────────────────────────────────────────────────────

  List<TransportRoom> roomsFor(String userId) {
    final result = <TransportRoom>[];
    for (final room in _rooms.values) {
      final m = room.members[userId];
      if (m == null || m == TransportMembership.leave) continue;
      result.add(_view(room, userId));
    }
    return result;
  }

  TransportRoom? roomFor(String userId, String roomId) {
    final room = _rooms[roomId];
    if (room == null) return null;
    if (room.members[userId] == null) return null;
    return _view(room, userId);
  }

  TransportRoom _view(_FakeRoom room, String userId) {
    final m = room.members[userId] ?? TransportMembership.leave;
    // Invited users only see strip state (no custom group state), like Matrix —
    // so currency is unknown until they actually join.
    final groupState = m == TransportMembership.join ? room.groupState : null;
    return TransportRoom(
      id: room.id,
      displayName: room.name.isNotEmpty ? room.name : room.id,
      membership: m,
      groupState: groupState,
    );
  }

  List<TransportMember> participants(
      String roomId, Set<TransportMembership> memberships) {
    final room = _rooms[roomId];
    if (room == null) return [];
    return room.members.entries
        .where((e) => memberships.contains(e.value))
        .map((e) =>
            TransportMember(id: e.key, membership: e.value, displayName: null))
        .toList();
  }

  List<TransportEvent> timeline(String roomId, String userId) {
    final room = _rooms[roomId];
    if (room == null) return [];
    if (room.members[userId] != TransportMembership.join) return [];
    return List.of(room.timeline);
  }

  // ── sync delivery ──────────────────────────────────────────────────────────

  void _notify(String userId) =>
      _clients[userId]?._emit(const TransportSyncUpdate({}));

  void _deliver(String userId, String roomId, List<TransportEvent> events) =>
      _clients[userId]?._emit(TransportSyncUpdate({roomId: events}));

  /// Lets queued stream events propagate to listeners. Call after each action
  /// before asserting on derived provider state.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

class _FakeRoom {
  final String id;
  String name;
  Map<String, dynamic>? groupState;
  final Map<String, TransportMembership> members = {};
  final Map<String, String> inviterOf = {};
  final List<TransportEvent> timeline = [];
  _FakeRoom(this.id, this.name);
}

class FakeTransport implements LedgerTransport {
  final FakeMatrixNetwork _net;
  @override
  final String userId;
  final StreamController<TransportSyncUpdate> _controller =
      StreamController.broadcast();

  FakeTransport(this._net, this.userId);

  void _emit(TransportSyncUpdate u) {
    if (!_controller.isClosed) _controller.add(u);
  }

  void dispose() => _controller.close();

  @override
  Stream<TransportSyncUpdate> get onSync => _controller.stream;

  @override
  List<TransportRoom> get rooms => _net.roomsFor(userId);

  @override
  TransportRoom? room(String roomId) => _net.roomFor(userId, roomId);

  @override
  Future<String> createGroup(String name, String currency) async =>
      _net.createGroup(userId, name, currency);

  @override
  Future<void> invite(String roomId, String otherUserId) async =>
      _net.invite(roomId, userId, otherUserId);

  @override
  Future<void> join(String roomId) async => _net.join(roomId, userId);

  @override
  Future<void> leave(String roomId) async => _net.leave(roomId, userId);

  @override
  Future<void> kick(String roomId, String otherUserId) async =>
      _net.kick(roomId, userId, otherUserId);

  @override
  Future<void> sendExpense(String roomId, Map<String, dynamic> content) async =>
      _net.send(roomId, userId, expenseEventType, content);

  @override
  Future<void> sendSettlement(
          String roomId, Map<String, dynamic> content) async =>
      _net.send(roomId, userId, settlementEventType, content);

  @override
  Future<List<TransportMember>> participants(
    String roomId, {
    Set<TransportMembership> memberships = const {TransportMembership.join},
  }) async =>
      _net.participants(roomId, memberships);

  @override
  Future<List<TransportEvent>> timelineEvents(String roomId) async =>
      _net.timeline(roomId, userId);

  @override
  Future<void> loadHistory(String roomId) async {
    // The fake keeps the whole timeline in memory, so there's nothing to page.
  }
}
