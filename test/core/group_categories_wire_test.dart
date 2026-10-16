/// G47: the optional `categories` list of the group meta on the wire — part
/// of the signed content and the G27 version hash only when non-empty (so
/// every pre-G47 meta signature and hash stays valid), and its content rules
/// (`groupMetaProblem`).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/matrix/hmac_record_crypto.dart';
import 'package:money_ledger/core/sync/ledger_payloads.dart';
import 'package:money_ledger/core/sync/record_signing.dart';
import 'package:money_ledger/core/sync/record_validation.dart';
import 'package:money_ledger/core/sync/record_version.dart';
import 'package:money_ledger/models/expense_category.dart';
import 'package:money_ledger/models/group_model.dart';

const alice = '@alice:x.org';

const dog = CustomCategory(id: 'c:0192-dog', name: 'Dog', icon: 'pets');
const kids = CustomCategory(
  id: 'c:0192-kids',
  name: 'Kinder & Schule',
  icon: 'child',
  hidden: true,
);

GroupModel meta({List<CustomCategory> categories = const []}) => GroupModel(
  roomId: 'g1',
  name: 'Trip',
  currency: 'EUR',
  updatedAt: 1000,
  categories: categories,
);

Map<String, dynamic> overTheWire(Map<String, dynamic> payload) =>
    jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;

void main() {
  final keys = HmacKeyRegistry();
  final crypto = keys.deviceCrypto(alice, 'AAAA');

  test('a meta without categories keeps the pre-G47 body and hash', () {
    expect(groupMetaContent(meta()).keys.toSet(), {
      't',
      'group',
      'name',
      'currency',
      'updated_at',
    });
    expect(groupMetaPayload(meta()).containsKey('categories'), isFalse);
    // Golden: SHA-256 of the pre-G47 canonical body
    // {"currency":"EUR","group":"g1","name":"Trip",
    //  "t":"com.moneyledger.group","updated_at":1000} (computed outside the
    // app) — unchanged by G47.
    expect(
      groupMetaVersionHash(meta()),
      '839ee378eb0eda7215bda58b19a73731ce3ddffc12a1032c7797ccda80c94511',
    );
    expect(
      groupMetaVersionHash(meta(categories: [dog])),
      isNot(groupMetaVersionHash(meta())),
    );
  });

  test('round trip: sign → wire → parse → verifies, same hash', () async {
    final signed = await signGroupMeta(crypto, meta(categories: [dog, kids]));
    final payload = overTheWire(groupMetaPayload(signed));
    expect(payload['categories'], [
      {'id': 'c:0192-dog', 'name': 'Dog', 'icon': 'pets'},
      {
        'id': 'c:0192-kids',
        'name': 'Kinder & Schule',
        'icon': 'child',
        'hidden': true,
      },
    ]);
    final parsed = groupMetaFromPayload(payload)!;
    expect(parsed.categories, [dog, kids]);
    expect(parsed.visibleCategories, [dog]);
    expect(
      signatureMatches(
        crypto,
        groupMetaBody(parsed, signerOf(parsed.sig!)),
        parsed.sig!,
      ),
      isTrue,
    );
    expect(groupMetaVersionHash(parsed), groupMetaVersionHash(signed));
  });

  test('changing / dropping categories breaks the signature', () async {
    final signed = await signGroupMeta(crypto, meta(categories: [dog, kids]));
    final payload = overTheWire(groupMetaPayload(signed));
    for (final tamper in <void Function(Map<String, dynamic>)>[
      (p) => p.remove('categories'), // what a pre-G47 build effectively does
      (p) => (p['categories'] as List).removeLast(),
      (p) => ((p['categories'] as List).first as Map)['name'] = 'Cat',
      (p) => ((p['categories'] as List).last as Map).remove('hidden'),
      (p) => p['categories'] = (p['categories'] as List).reversed.toList(),
    ]) {
      final p = overTheWire(payload);
      tamper(p);
      final parsed = groupMetaFromPayload(p)!;
      expect(
        signatureMatches(
          crypto,
          groupMetaBody(parsed, signerOf(parsed.sig!)),
          parsed.sig!,
        ),
        isFalse,
      );
    }
  });

  test('bootstraps (and so backups) carry the categories', () {
    final content = overTheWire(
      buildBootstrapContent(
        'g1',
        meta(categories: [dog]),
        const [],
        const [],
        const [],
      ),
    );
    final parsed = groupMetaFromPayload(
      Map<String, dynamic>.from(content['meta'] as Map),
    )!;
    expect(parsed.categories, [dog]);
  });

  group('groupMetaProblem (content rules)', () {
    String? problem(List<CustomCategory> cs) =>
        groupMetaProblem(meta(categories: cs));
    CustomCategory c(String id, {String name = 'X', String icon = 'tag'}) =>
        CustomCategory(id: id, name: name, icon: icon);

    test('valid metas', () {
      expect(problem(const []), isNull);
      expect(problem([dog, kids]), isNull);
      expect(
        problem([
          for (var i = 0; i < kMaxCustomCategories; i++) c('c:$i', name: '$i'),
        ]),
        isNull,
      );
      expect(problem([c('c:a', name: 'x' * kMaxCategoryNameLength)]), isNull);
    });

    test('bounds are refused', () {
      expect(
        problem([for (var i = 0; i <= kMaxCustomCategories; i++) c('c:$i')]),
        isNotNull,
      );
      expect(problem([c('food')]), isNotNull); // not a c: id
      expect(problem([c('c:')]), isNotNull); // empty after the prefix
      expect(problem([c('c:${'x' * kMaxCustomCategoryIdLength}')]), isNotNull);
      expect(problem([c('c:a'), c('c:a', name: 'Y')]), isNotNull); // duplicate
      expect(problem([c('c:a', name: '')]), isNotNull);
      expect(problem([c('c:a', name: ' padded ')]), isNotNull);
      expect(
        problem([c('c:a', name: 'x' * (kMaxCategoryNameLength + 1))]),
        isNotNull,
      );
      expect(problem([c('c:a', icon: 'rocket')]), isNotNull);
      // A malformed wire value parses to an invalid entry → refused.
      expect(
        groupMetaProblem(
          groupMetaFromPayload({
            'group': 'g1',
            'name': 'Trip',
            'categories': 'oops',
          })!,
        ),
        isNotNull,
      );
    });
  });
}
