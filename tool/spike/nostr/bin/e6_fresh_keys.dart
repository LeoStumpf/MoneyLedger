// E6 (polite): six fresh keys = six simulated groups from one IP, one small
// event each at our intended pace (6 s apart), to both relays. No burst.
// First, a cross-relay check: is an event published only to nos.lol served
// by nostr.mom (same host 142.132.206.70)?
import 'dart:convert';
import 'package:nostr_spike/link_crypto.dart';
import 'package:nostr_spike/relay.dart';

Future<void> main() async {
  final relays = [for (final url in kSpikeRelays) await Relay.connect(url)];
  for (var i = 0; i < 6; i++) {
    final keys = await deriveLinkKeys(randomBytes(32));
    final priv = newPrivateKey();
    final c = await packContent(
      utf8.encode(jsonEncode({'group': i, 'pad': hexOf(randomBytes(3000))})),
      keys.encKey,
      keys.topic,
      publicKeyOf(priv),
    );
    final e = signEvent(
      priv,
      kind: kLinkKind,
      tags: linkTags(keys.topic, expiresAt: nowSec() + 600),
      content: c,
      createdAt: nowSec(),
    );
    if (i == 0) {
      final ok = await relays[0].publish(e);
      record('e6', {
        'relay': relays[0].url,
        'key': i,
        'ok': ok.accepted,
        'msg': ok.message,
        'note': 'only to nos.lol',
      });
      await pause(10);
      final f = await relays[1].fetch({
        'ids': [e.id],
      });
      record('e6', {
        'step': 'cross-relay',
        'servedByNostrMom': f.events.isNotEmpty,
      });
    }
    final oks = await Future.wait([for (final r in relays) r.publish(e)]);
    for (var k = 0; k < relays.length; k++) {
      record('e6', {
        'relay': relays[k].url,
        'key': i,
        'frame': e.frameBytes,
        'ok': oks[k].accepted,
        'msg': oks[k].message,
        'okMs': oks[k].ms,
      });
    }
    await pause(6);
  }
  for (final r in relays) {
    record('e6', {'relay': r.url, 'notices': r.notices});
    await r.close();
  }
}
