// E4 live latency, two processes on this laptop:
//   dart run bin/e4_live.dart sub <secretHex> <seconds>
//   dart run bin/e4_live.dart pub <secretHex> <count> <intervalSec>
//   dart run bin/e4_live.dart report
// The publisher replaces one addressable event (same d) every interval and
// logs seq → send time; the subscriber decrypts each live event and logs
// seq → receive time per relay. `report` joins them (p50 / p95).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:nostr_spike/link_crypto.dart';
import 'package:nostr_spike/relay.dart';

Future<void> main(List<String> a) async {
  switch (a.first) {
    case 'sub':
      return sub(a[1], int.parse(a[2]));
    case 'pub':
      return pub(a[1], int.parse(a[2]), int.parse(a[3]));
    case 'report':
      return report();
  }
}

int ms() => DateTime.now().millisecondsSinceEpoch;

Future<void> sub(String secretHex, int seconds) async {
  final keys = await deriveLinkKeys(bytesOfHex(secretHex));
  final subs = <StreamSubscription<dynamic>>[];
  final relays = <Relay>[];
  for (final url in kSpikeRelays) {
    final r = await Relay.connect(url);
    relays.add(r);
    subs.add(
      r
          .subscribe({
            'kinds': [kLinkKind],
            '#d': [keys.topic],
            'since': nowSec() - 5,
          })
          .listen((x) async {
            final (e, recvAt) = x;
            try {
              final p =
                  jsonDecode(
                        utf8.decode(
                          await unpackContent(
                            e.content,
                            keys.encKey,
                            keys.topic,
                            e.pubkey,
                          ),
                        ),
                      )
                      as Map;
              record('e4_sub', {
                'relay': url,
                'seq': p['seq'],
                'recvAt': recvAt,
                'verified': verifyEvent(e),
              });
            } catch (err) {
              record('e4_sub', {'relay': url, 'error': '$err'});
            }
          }),
    );
  }
  stdout.writeln('subscribed');
  await Future<void>.delayed(Duration(seconds: seconds));
  for (final s in subs) {
    await s.cancel();
  }
  for (final r in relays) {
    await r.close();
  }
}

Future<void> pub(String secretHex, int count, int interval) async {
  final keys = await deriveLinkKeys(bytesOfHex(secretHex));
  final priv = newPrivateKey();
  final relays = [for (final url in kSpikeRelays) await Relay.connect(url)];
  var last = 0;
  final ids = <String>[];
  for (var seq = 0; seq < count; seq++) {
    final createdAt = last = (nowSec() > last ? nowSec() : last + 1);
    final c = await packContent(
      utf8.encode(jsonEncode({'seq': seq, 'pad': hexOf(randomBytes(400))})),
      keys.encKey,
      keys.topic,
      publicKeyOf(priv),
    );
    final e = signEvent(
      priv,
      kind: kLinkKind,
      tags: linkTags(keys.topic, expiresAt: nowSec() + 600),
      content: c,
      createdAt: createdAt,
    );
    ids.add(e.id);
    final sentAt = ms();
    final oks = await Future.wait([for (final r in relays) r.publish(e)]);
    for (var i = 0; i < relays.length; i++) {
      record('e4_pub', {
        'relay': relays[i].url,
        'seq': seq,
        'sentAt': sentAt,
        'ok': oks[i].accepted,
        'msg': oks[i].message,
        'okMs': oks[i].ms,
        'frame': e.frameBytes,
      });
    }
    await pause(interval);
  }
  for (final r in relays) {
    await cleanup('e4_pub', r, priv, ids.sublist(ids.length - 1), [keys.topic]);
    await r.close();
  }
}

void report() {
  List<Map<String, dynamic>> rows(String f) => File('results/$f.jsonl')
      .readAsLinesSync()
      .map((l) => (jsonDecode(l) as Map).cast<String, dynamic>())
      .toList();
  final pubs = rows('e4_pub'), subs = rows('e4_sub');
  for (final url in kSpikeRelays) {
    final sent = {
      for (final p in pubs.where((p) => p['relay'] == url && p['seq'] != null))
        p['seq']: p,
    };
    final lat = <int>[], ok = <int>[];
    for (final p in sent.values) {
      ok.add(p['okMs'] as int);
    }
    for (final s in subs.where((s) => s['relay'] == url && s['seq'] != null)) {
      final p = sent[s['seq']];
      if (p != null) lat.add((s['recvAt'] as int) - (p['sentAt'] as int));
    }
    String q(List<int> v) {
      if (v.isEmpty) return 'n/a';
      v.sort();
      int at(double f) => v[((v.length - 1) * f).round()];
      return 'n=${v.length} p50=${at(.5)} p95=${at(.95)} max=${v.last}';
    }

    stdout.writeln(
      '$url  live delivery ms: ${q(lat)}  | OK ms: ${q(ok)}  | published ${sent.length}, accepted ${sent.values.where((p) => p['ok'] == true).length}',
    );
  }
}
