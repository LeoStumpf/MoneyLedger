// E2 addressable replacement, E3 cross-author #d filter (3 keys),
// E5 connect → EOSE timing. Small synthetic events, expiration +10 min,
// NIP-09 cleanup at the end.
import 'dart:convert';
import 'package:nostr_spike/link_crypto.dart';
import 'package:nostr_spike/relay.dart';

Future<void> main() async {
  for (final url in kSpikeRelays) {
    final keys = await deriveLinkKeys(randomBytes(32));
    final dX = keys.topic;
    final a = newPrivateKey();
    final aPub = publicKeyOf(a);
    final r = await Relay.connect(url);
    Future<NostrEvent> ev(
      String priv,
      String d,
      int createdAt,
      String label,
    ) async {
      final c = await packContent(
        utf8.encode(
          jsonEncode({'label': label, 'pad': hexOf(randomBytes(200))}),
        ),
        keys.encKey,
        d,
        publicKeyOf(priv),
      );
      return signEvent(
        priv,
        kind: kLinkKind,
        tags: linkTags(d, expiresAt: nowSec() + 600),
        content: c,
        createdAt: createdAt,
      );
    }

    final aIds = <String>[];
    // ---- E2
    final t0 = nowSec() - 30;
    Future<void> pub(NostrEvent e, String label) async {
      final ok = await r.publish(e);
      aIds.add(e.id);
      record('e2', {
        'relay': url,
        'label': label,
        'created_at': e.createdAt,
        'id': e.id.substring(0, 12),
        'ok': ok.accepted,
        'msg': ok.message,
      });
      await pause(5);
    }

    Future<void> check(String expectLabel, NostrEvent expect) async {
      final f = await r.fetch({
        'kinds': [kLinkKind],
        '#d': [dX],
        'authors': [aPub],
      });
      record('e2', {
        'relay': url,
        'check': expectLabel,
        'returned': f.events.map((e) => e.id.substring(0, 12)).toList(),
        'pass': f.events.length == 1 && f.events.single.id == expect.id,
      });
    }

    final v1 = await ev(a, dX, t0, 'v1'), v2 = await ev(a, dX, t0 + 1, 'v2');
    await pub(v1, 'v1');
    await pub(v2, 'v2 (+1 s)');
    await check('only v2', v2);
    // Same second, higher id first → the lower id must replace it.
    var p = [await ev(a, dX, t0 + 2, 'p1a'), await ev(a, dX, t0 + 2, 'p1b')]
      ..sort((x, y) => x.id.compareTo(y.id));
    await pub(p[1], 'same-second higher id first');
    await pub(p[0], 'same-second lower id second');
    await check('lowest id of t0+2', p[0]);
    // Same second, lower id first → the higher id must not replace it.
    p = [await ev(a, dX, t0 + 3, 'p2a'), await ev(a, dX, t0 + 3, 'p2b')]
      ..sort((x, y) => x.id.compareTo(y.id));
    await pub(p[0], 'same-second lower id first');
    await pub(p[1], 'same-second higher id second');
    await check('lowest id of t0+3', p[0]);
    // Older version after a newer one.
    await pub(
      await ev(a, dX, t0 - 10, 'stale'),
      'older created_at after newer',
    );
    await check('still lowest id of t0+3', p[0]);
    // ---- E3: three authors, one d.
    final dY = hexOf(randomBytes(32));
    final authors = [newPrivateKey(), newPrivateKey(), newPrivateKey()];
    final yIds = <String>[];
    for (final k in authors) {
      final e = await ev(k, dY, nowSec(), 'author');
      final ok = await r.publish(e);
      yIds.add(e.id);
      record('e3', {
        'relay': url,
        'author': e.pubkey.substring(0, 8),
        'ok': ok.accepted,
        'msg': ok.message,
      });
      await pause(5);
    }
    final f = await r.fetch({
      'kinds': [kLinkKind],
      '#d': [dY],
    });
    var decrypted = 0;
    for (final e in f.events) {
      if (!verifyEvent(e)) continue;
      try {
        await unpackContent(e.content, keys.encKey, dY, e.pubkey);
        decrypted++;
      } catch (_) {}
    }
    record('e3', {
      'relay': url,
      'returned': f.events.length,
      'distinctAuthors': f.events.map((e) => e.pubkey).toSet().length,
      'allHaveD': f.events.every((e) => e.tag('d') == dY),
      'verifiedAndDecrypted': decrypted,
      'pass': f.events.length == 3 && decrypted == 3,
    });
    await r.close();
    // ---- E5: fresh connection → REQ both topics → EOSE.
    for (var i = 0; i < 10; i++) {
      final sw = Stopwatch()..start();
      final c = await Relay.connect(url);
      final connectMs = sw.elapsedMilliseconds;
      final g = await c.fetch({
        'kinds': [kLinkKind],
        '#d': [dX, dY],
      });
      record('e5', {
        'relay': url,
        'run': i,
        'connectMs': connectMs,
        'reqToEoseMs': g.ms,
        'totalMs': sw.elapsedMilliseconds,
        'events': g.events.length,
        'eose': g.eose,
      });
      await c.close();
      await pause(2);
    }
    // ---- cleanup
    final c = await Relay.connect(url);
    await cleanup('e2', c, a, aIds, [dX]);
    for (var i = 0; i < authors.length; i++) {
      await pause(2);
      await cleanup('e3', c, authors[i], [yIds[i]], [dY]);
    }
    await c.close();
  }
}
