/// G51 spike: a minimal NIP-01 relay connection over `web_socket_channel`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';

import 'link_crypto.dart';

/// The only relays the spike talks to (Leo, 2026-10-17: option C).
const kSpikeRelays = ['wss://nos.lol', 'wss://nostr.mom'];

class OkResult {
  OkResult(this.accepted, this.message, this.ms);
  final bool accepted;
  final String message;
  final int ms;
  @override
  String toString() =>
      '${accepted ? 'OK true' : 'OK false'} "$message" (${ms}ms)';
}

class FetchResult {
  FetchResult(this.events, this.eose, this.ms, this.closedReason);
  final List<NostrEvent> events;
  final bool eose;
  final int ms;
  final String? closedReason;
}

class Relay {
  Relay._(this.url, this._ch) {
    _sub = _ch.stream.listen(
      (data) {
        try {
          final msg = jsonDecode(data as String) as List;
          if (msg.isNotEmpty && msg[0] == 'NOTICE') {
            stderr.writeln('[$url] NOTICE ${msg.length > 1 ? msg[1] : ''}');
            notices.add('${msg.length > 1 ? msg[1] : ''}');
          }
          _ctrl.add(msg);
        } catch (e) {
          stderr.writeln('[$url] bad frame: $e');
        }
      },
      onDone: () {
        closed = true;
        closeCode = _ch.closeCode;
        closeReason = _ch.closeReason;
        _ctrl.add(const ['__closed__']);
      },
      onError: (Object e) {
        closed = true;
        _ctrl.add(['__closed__', '$e']);
      },
    );
  }

  final String url;
  final IOWebSocketChannel _ch;
  late final StreamSubscription<dynamic> _sub;
  final _ctrl = StreamController<List<dynamic>>.broadcast();
  final notices = <String>[];
  bool closed = false;
  int? closeCode;
  String? closeReason;

  Stream<List<dynamic>> get messages => _ctrl.stream;

  static Future<Relay> connect(String url) async {
    final ch = IOWebSocketChannel.connect(
      Uri.parse(url),
      connectTimeout: const Duration(seconds: 10),
    );
    await ch.ready;
    return Relay._(url, ch);
  }

  void send(List<Object?> frame) => _ch.sink.add(jsonEncode(frame));

  Future<OkResult> publish(
    NostrEvent e, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final sw = Stopwatch()..start();
    final done = Completer<OkResult>();
    final sub = messages.listen((m) {
      if (done.isCompleted) return;
      if (m[0] == 'OK' && m[1] == e.id) {
        done.complete(
          OkResult(
            m[2] == true,
            '${m.length > 3 ? m[3] : ''}',
            sw.elapsedMilliseconds,
          ),
        );
      } else if (m[0] == '__closed__') {
        done.complete(
          OkResult(
            false,
            'socket closed (code $closeCode ${closeReason ?? ''} ${m.length > 1 ? m[1] : ''})'
                .trim(),
            sw.elapsedMilliseconds,
          ),
        );
      }
    });
    send(['EVENT', e.toJson()]);
    try {
      return await done.future.timeout(
        timeout,
        onTimeout: () =>
            OkResult(false, 'timeout (no OK)', sw.elapsedMilliseconds),
      );
    } finally {
      await sub.cancel();
    }
  }

  var _subCounter = 0;

  Future<FetchResult> fetch(
    Map<String, Object?> filter, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final subId = 'g51-${_subCounter++}-${hexOf(randomBytes(4))}';
    final sw = Stopwatch()..start();
    final events = <NostrEvent>[];
    final done = Completer<FetchResult>();
    final sub = messages.listen((m) {
      if (done.isCompleted) return;
      if (m[0] == 'EVENT' && m[1] == subId) {
        events.add(NostrEvent.fromJson((m[2] as Map).cast<String, dynamic>()));
      } else if (m[0] == 'EOSE' && m[1] == subId) {
        done.complete(FetchResult(events, true, sw.elapsedMilliseconds, null));
      } else if (m[0] == 'CLOSED' && m[1] == subId) {
        done.complete(
          FetchResult(events, false, sw.elapsedMilliseconds, '${m[2]}'),
        );
      } else if (m[0] == '__closed__') {
        done.complete(
          FetchResult(events, false, sw.elapsedMilliseconds, 'socket closed'),
        );
      }
    });
    send(['REQ', subId, filter]);
    try {
      return await done.future.timeout(
        timeout,
        onTimeout: () =>
            FetchResult(events, false, sw.elapsedMilliseconds, 'timeout'),
      );
    } finally {
      await sub.cancel();
      if (!closed) send(['CLOSE', subId]);
    }
  }

  /// Live subscription: yields (event, receivedAtMs).
  Stream<(NostrEvent, int)> subscribe(Map<String, Object?> filter) {
    final subId = 'g51-live-${hexOf(randomBytes(4))}';
    final out = StreamController<(NostrEvent, int)>();
    final sub = messages.listen((m) {
      if (m[0] == 'EVENT' && m[1] == subId) {
        out.add((
          NostrEvent.fromJson((m[2] as Map).cast<String, dynamic>()),
          DateTime.now().millisecondsSinceEpoch,
        ));
      } else if (m[0] == 'CLOSED' && m[1] == subId) {
        stderr.writeln('[$url] CLOSED ${m[2]}');
      }
    });
    out.onCancel = () async {
      await sub.cancel();
      if (!closed) send(['CLOSE', subId]);
    };
    send(['REQ', subId, filter]);
    return out.stream;
  }

  Future<void> close() async {
    await _sub.cancel();
    await _ch.sink.close();
    await _ctrl.close();
  }
}

/// Polite spacing between publishes (§4.4: ≥ 5 s per group).
Future<void> pause([int seconds = 5]) =>
    Future.delayed(Duration(seconds: seconds));

/// Appends a JSON line to results/<name>.jsonl and prints it.
void record(String name, Map<String, Object?> row) {
  final dir = Directory('results')..createSync(recursive: true);
  final line = jsonEncode({
    'at': DateTime.now().toUtc().toIso8601String(),
    ...row,
  });
  File(
    '${dir.path}/$name.jsonl',
  ).writeAsStringSync('$line\n', mode: FileMode.append);
  stdout.writeln(line);
}

/// Publishes a kind-5 deletion and records the answer.
Future<void> cleanup(
  String exp,
  Relay r,
  String priv,
  List<String> ids,
  List<String> dTags,
) async {
  final del = deletionEvent(priv, ids: ids, dTags: dTags);
  final ok = await r.publish(del);
  record(exp, {
    'relay': r.url,
    'step': 'nip09-delete',
    'ids': ids.length,
    'ok': ok.accepted,
    'msg': ok.message,
  });
}
