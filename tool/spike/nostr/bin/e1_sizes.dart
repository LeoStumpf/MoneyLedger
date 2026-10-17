// E1: kind-31847 events of growing frame size (only up to the advertised
// 131 072-byte frame limit), expiration now+10 min, then a NIP-09 deletion.
// Usage: dart run bin/e1_sizes.dart [frameBytes ...]
import 'package:nostr_spike/link_crypto.dart';
import 'package:nostr_spike/relay.dart';

Future<void> main(List<String> args) async {
  final sizes = args.isEmpty
      ? [10000, 50000, 100000, 125000, 130000]
      : args.map(int.parse).toList();
  final priv = newPrivateKey();
  final pub = publicKeyOf(priv);
  final keys = await deriveLinkKeys(randomBytes(32));
  for (final url in kSpikeRelays) {
    final ids = <String>[], ds = <String>[];
    for (final target in sizes) {
      final d = '${keys.topic.substring(0, 56)}${hexOf(randomBytes(4))}';
      // Size the random (incompressible) payload so the frame hits `target`.
      final probe = signEvent(
        priv,
        kind: kLinkKind,
        tags: linkTags(d, expiresAt: nowSec() + 600),
        content: '',
        createdAt: nowSec(),
      );
      final contentChars = target - probe.frameBytes;
      final raw = ((contentChars - 2) * 3 ~/ 4) - 28; // nonce + tag
      final content = await packContent(
        randomBytes(raw),
        keys.encKey,
        d,
        pub,
        compress: false,
      );
      final e = signEvent(
        priv,
        kind: kLinkKind,
        tags: linkTags(d, expiresAt: nowSec() + 600),
        content: content,
        createdAt: nowSec(),
      );
      Relay? r;
      try {
        r = await Relay.connect(url);
        final ok = await r.publish(e);
        var stored = false;
        if (ok.accepted && !r.closed) {
          final f = await r.fetch({
            'ids': [e.id],
          });
          stored = f.events.any(
            (x) => x.id == e.id && x.content.length == content.length,
          );
        }
        record('e1', {
          'relay': url,
          'frame': e.frameBytes,
          'content': content.length,
          'ok': ok.accepted,
          'msg': ok.message,
          'okMs': ok.ms,
          'storedAndServed': stored,
          'notices': r.notices,
        });
        if (ok.accepted) {
          ids.add(e.id);
          ds.add(d);
        }
      } catch (err) {
        record('e1', {'relay': url, 'frame': e.frameBytes, 'error': '$err'});
      } finally {
        await r?.close();
      }
      await pause(6);
    }
    if (ids.isNotEmpty) {
      final r = await Relay.connect(url);
      await cleanup('e1', r, priv, ids, ds);
      await pause(2);
      final f = await r.fetch({'ids': ids});
      record('e1', {
        'relay': url,
        'step': 'after-delete',
        'stillServed': f.events.length,
        'of': ids.length,
      });
      await r.close();
    }
  }
}
