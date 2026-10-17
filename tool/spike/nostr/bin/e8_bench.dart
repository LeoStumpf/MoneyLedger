// E8: crypto cost for a realistic 200-record snapshot (bootstrap shape,
// unsigned, synthetic). Pure Dart (no dart:io) so the same file runs as
//   dart compile exe bin/e8_bench.dart -o build/e8 && build/e8
//   dart compile js -O2 bin/e8_bench.dart -o build/e8.js && node build/e8.js
import 'dart:convert';
import 'package:nostr_spike/link_crypto.dart';

const runs = 15;

Future<double> median(Future<void> Function() f, {int n = runs}) async {
  await f(); // warm-up
  final t = <int>[];
  for (var i = 0; i < n; i++) {
    final sw = Stopwatch()..start();
    await f();
    t.add(sw.elapsedMicroseconds);
  }
  t.sort();
  return t[t.length ~/ 2] / 1000;
}

String b64(int n) => base64Url.encode(randomBytes(n)).replaceAll('=', '');

Map<String, dynamic> signedVariant(Map<String, dynamic> snap) {
  Map<String, String> sig() => {
    'user': '@alex:example.org',
    'device': 'ABCDEFGHIJ',
    'key': b64(32),
    'sig': b64(64),
  };
  final s = jsonDecode(jsonEncode(snap)) as Map<String, dynamic>;
  for (final k in ['expenses', 'settlements']) {
    for (final r in s[k] as List) {
      (r as Map)['origin'] = sig();
      r['sig'] = sig();
    }
  }
  for (final r in s['members'] as List) {
    (r as Map)['sig'] = sig();
  }
  return s;
}

Future<void> main() async {
  final secret = randomBytes(32);
  final keys = await deriveLinkKeys(secret);
  final priv = newPrivateKey();
  final pub = publicKeyOf(priv);
  final snap = syntheticSnapshot(records: 200);
  final plain = utf8.encode(jsonEncode(snap));
  late String content;
  final rows = <String, Object>{};
  rows['records'] = 200;
  rows['jsonBytes'] = plain.length;
  rows['deriveMs'] = await median(() async => deriveLinkKeys(secret));
  rows['jsonEncodeMs'] = await median(
    () async => utf8.encode(jsonEncode(snap)),
  );
  rows['packMs (gzip+gcm+b64)'] = await median(() async {
    content = await packContent(plain, keys.encKey, keys.topic, pub);
  });
  rows['contentChars'] = content.length;
  late NostrEvent e;
  rows['signMs (id+bip340)'] = await median(() async {
    e = signEvent(
      priv,
      kind: kLinkKind,
      tags: linkTags(keys.topic, expiresAt: nowSec() + 2592000),
      content: content,
      createdAt: nowSec(),
    );
  });
  rows['frameBytes'] = e.frameBytes;
  rows['verify1Ms'] = await median(() async {
    if (!verifyEvent(e)) throw StateError('verify');
  });
  final twenty = [
    for (var i = 0; i < 20; i++)
      signEvent(
        newPrivateKey(),
        kind: kLinkKind,
        tags: linkTags(keys.topic, expiresAt: nowSec() + 600),
        content: content,
        createdAt: nowSec(),
      ),
  ];
  rows['verify20Ms'] = await median(() async {
    for (final x in twenty) {
      if (!verifyEvent(x)) throw StateError('verify');
    }
  }, n: 5);
  rows['unpackMs (b64+gcm+gunzip+json)'] = await median(
    () async => jsonDecode(
      utf8.decode(await unpackContent(content, keys.encKey, keys.topic, pub)),
    ),
  );
  rows['pack+signMs'] =
      (rows['jsonEncodeMs'] as double) +
      (rows['packMs (gzip+gcm+b64)'] as double) +
      (rows['signMs (id+bip340)'] as double);
  // Size model: content chars per record, unsigned vs. signed (mixed group).
  final signed = utf8.encode(jsonEncode(signedVariant(snap)));
  final signedContent = await packContent(signed, keys.encKey, keys.topic, pub);
  rows['signedJsonBytes'] = signed.length;
  rows['signedContentChars'] = signedContent.length;
  for (final n in [500, 1000]) {
    final c = await packContent(
      utf8.encode(jsonEncode(syntheticSnapshot(records: n))),
      keys.encKey,
      keys.topic,
      pub,
    );
    rows['contentChars@$n'] = c.length;
  }
  rows['note'] =
      'median of $runs (verify20: of 5), after one warm-up; ${identical(1, 1.0) ? 'dart2js' : 'native'}';
  print(const JsonEncoder.withIndent('  ').convert(rows));
}
