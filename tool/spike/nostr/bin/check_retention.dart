// E7 follow-up: is each probe from retention_ids.json still served?
// Run at +1 h, 1 d, 3 d, 7 d, 14 d (and after +30 d):
//   cd tool/spike/nostr && dart run bin/check_retention.dart
// Read-only (REQ only, nothing is published). Appends to
// results/retention.jsonl.
import 'dart:convert';
import 'dart:io';
import 'package:nostr_spike/link_crypto.dart';
import 'package:nostr_spike/relay.dart';

Future<void> main() async {
  final j = jsonDecode(File('retention_ids.json').readAsStringSync()) as Map;
  final probes = (j['probes'] as List).cast<Map>();
  final published = DateTime.parse(j['published_at'] as String);
  final age = DateTime.now().toUtc().difference(published);
  stdout.writeln('age ${age.inHours} h ${age.inMinutes % 60} min');
  for (final url in (j['relays'] as List).cast<String>()) {
    try {
      final r = await Relay.connect(url);
      for (final p in probes) {
        final byId = await r.fetch({
          'ids': [p['id']],
        });
        final byD = await r.fetch({
          'kinds': [kLinkKind],
          'authors': [j['pubkey']],
          '#d': [p['d']],
        });
        final ok = byId.events.any((e) => e.id == p['id'] && verifyEvent(e));
        record('retention', {
          'relay': url,
          'probe': p['label'],
          'ageHours': (age.inMinutes / 60).toStringAsFixed(1),
          'servedById': ok,
          'servedByD': byD.events.length,
          'eose': byId.eose,
        });
      }
      await r.close();
    } catch (e) {
      record('retention', {'relay': url, 'error': '$e'});
    }
  }
}
