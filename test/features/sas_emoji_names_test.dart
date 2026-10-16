/// G36: localized SAS emoji names (Matrix spec `sas-emoji.json`, EN + DE).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/features/devices/sas_emoji_names.dart';

void main() {
  test('the table has all 64 spec emoji, each named in both languages', () {
    expect(kSasEmojiNames, hasLength(64));
    for (var i = 0; i < 64; i++) {
      final e = kSasEmojiNames[i];
      expect(e.emoji, isNotEmpty, reason: '#$i emoji');
      expect(e.en.trim(), isNotEmpty, reason: '#$i en');
      expect(e.de.trim(), isNotEmpty, reason: '#$i de');
      expect(sasEmojiName(i, 'en'), e.en);
      expect(sasEmojiName(i, 'de'), e.de);
    }
    // The emoji are distinct (the spec's 64 symbols).
    expect(kSasEmojiNames.map((e) => e.emoji).toSet(), hasLength(64));
  });

  test('spot checks against the spec order', () {
    expect(sasEmojiName(0, 'en'), 'Dog');
    expect(sasEmojiName(0, 'de'), 'Hund');
    expect(kSasEmojiNames[0].emoji, '🐶');
    expect(sasEmojiName(34, 'en'), 'Spanner');
    expect(sasEmojiName(34, 'de'), 'Schraubenschlüssel');
    expect(sasEmojiName(36, 'de'), 'Daumen Hoch');
    expect(sasEmojiName(63, 'en'), 'Pin');
    expect(sasEmojiName(63, 'de'), 'Stecknadel');
  });

  test('other languages fall back to English; unknown numbers to null', () {
    expect(sasEmojiName(1, 'fr'), 'Cat');
    expect(sasEmojiName(null, 'de'), isNull);
    expect(sasEmojiName(-1, 'de'), isNull);
    expect(sasEmojiName(64, 'en'), isNull);
  });
}
