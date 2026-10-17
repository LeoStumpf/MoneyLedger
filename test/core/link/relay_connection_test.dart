import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/link/link_envelope.dart';
import 'package:money_ledger/core/link/nostr/nostr_event.dart';
import 'package:money_ledger/core/link/nostr/nostr_frames.dart';
import 'package:money_ledger/core/link/nostr/nostr_relay_pool.dart';
import 'package:money_ledger/core/link/nostr/relay_connection.dart';

/// The real WebSocket adapter against a tiny relay on localhost (no
/// network): `EVENT` → `OK true`, `REQ` → `EOSE`, `CLOSE` ignored,
/// anything else echoed.
void main() {
  late HttpServer server;
  late String url;
  final sockets = <WebSocket>[];

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'ws://127.0.0.1:${server.port}';
    server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      sockets.add(ws);
      ws.listen((data) {
        final msg = jsonDecode(data as String) as List;
        switch (msg[0]) {
          case 'EVENT':
            ws.add(jsonEncode(['OK', (msg[1] as Map)['id'], true, '']));
          case 'REQ':
            ws.add(jsonEncode(['EOSE', msg[1]]));
          case 'CLOSE':
            break;
          default:
            ws.add(data);
        }
      });
    });
  });

  tearDown(() async {
    for (final s in sockets) {
      await s.close();
    }
    sockets.clear();
    await server.close(force: true);
  });

  test('send / receive / remote close', () async {
    final c = await const WebSocketRelayConnector().connect(url);
    final frames = StreamIterator(c.frames);
    c.send('["PING"]');
    expect(await frames.moveNext(), isTrue);
    expect(frames.current, '["PING"]');
    await sockets.single.close();
    expect(await frames.moveNext(), isFalse);
    c.send('ignored after close');
    await c.close();
  });

  test('connect to a closed port throws', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    await expectLater(
      const WebSocketRelayConnector().connect('ws://127.0.0.1:$port'),
      throwsA(anything),
    );
  });

  test('the pool works over a real WebSocket', () async {
    final pool = NostrRelayPool(relays: [url]);
    addTearDown(pool.close);
    final e = signNostrEvent(
      privateKey: '${'00' * 31}03',
      kind: kLinkEventKind,
      tags: const [
        ['d', 't'],
      ],
      content: '1:AAAA',
      createdAt: 1792000000,
    );
    final r = await pool.publish(e);
    expect(r.single.status, NostrPublishStatus.accepted);
    final f = await pool.fetchOnce(const [
      NostrFilter(kinds: [kLinkEventKind]),
    ]);
    expect(f.relays[url], NostrFetchRelayStatus.eose);
    expect(pool.isConnected(url), isTrue);
  });
}
