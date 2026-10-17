// E7: two small retention probes per relay (same two events on both): one
// with expiration +30 d, one with +10 min. Writes retention_ids.json for
// bin/check_retention.dart. Run once; never re-run (it would overwrite).
import 'dart:convert';
import 'dart:io';
import 'package:nostr_spike/link_crypto.dart';
import 'package:nostr_spike/relay.dart';

Future<void> main() async {
  final out = File('retention_ids.json');
  if (out.existsSync()) {
    stderr.writeln('retention_ids.json exists — not publishing again');
    exit(1);
  }
  final keys = await deriveLinkKeys(randomBytes(32));
  final priv = newPrivateKey();
  final pub = publicKeyOf(priv);
  final probes = <Map<String, Object?>>[];
  final now = nowSec();
  for (final (label, ttl) in [('30d', 30 * 86400), ('10min', 600)]) {
    final d = hexOf(randomBytes(32));
    final c = await packContent(
      utf8.encode(jsonEncode({'probe': label, 'pad': hexOf(randomBytes(300))})),
      keys.encKey,
      d,
      pub,
    );
    final e = signEvent(
      priv,
      kind: kLinkKind,
      tags: linkTags(d, expiresAt: now + ttl),
      content: c,
      createdAt: now,
    );
    final results = <String, Object?>{};
    for (final url in kSpikeRelays) {
      final r = await Relay.connect(url);
      final ok = await r.publish(e);
      results[url] = {'ok': ok.accepted, 'msg': ok.message};
      await r.close();
    }
    probes.add({
      'label': label,
      'id': e.id,
      'd': d,
      'created_at': e.createdAt,
      'expiration': now + ttl,
      'publish': results,
    });
    await pause(5);
  }
  out.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'note':
          'G51 E7 retention probes (synthetic, encrypted with a throwaway secret). Check with: dart run bin/check_retention.dart',
      'published_at': DateTime.fromMillisecondsSinceEpoch(
        now * 1000,
        isUtc: true,
      ).toIso8601String(),
      'pubkey': pub,
      'kind': kLinkKind,
      'relays': kSpikeRelays,
      'probes': probes,
    }),
  );
  stdout.writeln(out.readAsStringSync());
}
