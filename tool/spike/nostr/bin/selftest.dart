// Offline checks: BIP-340 vector 0, event sign/verify, envelope round trip,
// AAD binding.
import 'dart:convert';
import 'package:bip340/bip340.dart' as bip340;
import 'package:nostr_spike/link_crypto.dart';

Future<void> main() async {
  // BIP-340 test vector 0 (aux = 0).
  const sk = '0000000000000000000000000000000000000000000000000000000000000003';
  const msg =
      '0000000000000000000000000000000000000000000000000000000000000000';
  final sig = bip340.sign(sk, msg, msg);
  check(
    bip340.getPublicKey(sk).toUpperCase() ==
        'F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9',
    'vector0 pub',
  );
  check(
    sig.toUpperCase() ==
        'E907831F80848D1069A5371B402410364BDF1C5F8307B0084C55F1CE2DCA821525F66A4A85EA8B71E482A74F382D2CE5EBEEE8FDB2172F477DF4900D310536C0',
    'vector0 sig',
  );
  final priv = newPrivateKey();
  final keys = await deriveLinkKeys(randomBytes(32));
  check(keys.topic.length == 64, 'topic len');
  final pub = publicKeyOf(priv);
  final plain = utf8.encode(jsonEncode(syntheticSnapshot()));
  final c = await packContent(plain, keys.encKey, keys.topic, pub);
  final back = await unpackContent(c, keys.encKey, keys.topic, pub);
  check(utf8.decode(back) == utf8.decode(plain), 'round trip');
  var failed = false;
  try {
    await unpackContent(c, keys.encKey, keys.topic, 'ff' * 32);
  } catch (_) {
    failed = true;
  }
  check(failed, 'AAD binding');
  final e = signEvent(
    priv,
    kind: kLinkKind,
    tags: linkTags(keys.topic, expiresAt: nowSec() + 600),
    content: c,
    createdAt: nowSec(),
  );
  check(verifyEvent(e), 'event verify');
  print(
    'snapshot: ${plain.length} B json → content ${c.length} chars, frame ${e.frameBytes} B',
  );
  print('selftest OK');
}

void check(bool ok, String what) {
  if (!ok) throw StateError('FAIL $what');
  print('ok $what');
}
