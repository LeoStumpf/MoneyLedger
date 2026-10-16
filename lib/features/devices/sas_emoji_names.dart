// SAS emoji descriptions (English + German), by SAS emoji number 0–63.
//
// Generated once from the Matrix specification's `data-definitions/sas-emoji.json`
// (https://github.com/matrix-org/matrix-spec, commit 7aaeac07608f, 2023-08-22),
// Copyright The Matrix.org Foundation C.I.C., licensed under the Apache License,
// Version 2.0 — see THIRD_PARTY_NOTICES.md. Only the `description` (en) and
// `translated_descriptions.de` fields are kept. The emoji order is fixed by the
// spec (it's part of the SAS protocol), so this table never needs regenerating.

/// `[number] → (en, de)` — index = the SDK's `KeyVerificationEmoji.number`.
const List<({String emoji, String en, String de})> kSasEmojiNames = [
  (emoji: '🐶', en: 'Dog', de: 'Hund'),
  (emoji: '🐱', en: 'Cat', de: 'Katze'),
  (emoji: '🦁', en: 'Lion', de: 'Löwe'),
  (emoji: '🐎', en: 'Horse', de: 'Pferd'),
  (emoji: '🦄', en: 'Unicorn', de: 'Einhorn'),
  (emoji: '🐷', en: 'Pig', de: 'Schwein'),
  (emoji: '🐘', en: 'Elephant', de: 'Elefant'),
  (emoji: '🐰', en: 'Rabbit', de: 'Hase'),
  (emoji: '🐼', en: 'Panda', de: 'Panda'),
  (emoji: '🐓', en: 'Rooster', de: 'Hahn'),
  (emoji: '🐧', en: 'Penguin', de: 'Pinguin'),
  (emoji: '🐢', en: 'Turtle', de: 'Schildkröte'),
  (emoji: '🐟', en: 'Fish', de: 'Fisch'),
  (emoji: '🐙', en: 'Octopus', de: 'Oktopus'),
  (emoji: '🦋', en: 'Butterfly', de: 'Schmetterling'),
  (emoji: '🌷', en: 'Flower', de: 'Blume'),
  (emoji: '🌳', en: 'Tree', de: 'Baum'),
  (emoji: '🌵', en: 'Cactus', de: 'Kaktus'),
  (emoji: '🍄', en: 'Mushroom', de: 'Pilz'),
  (emoji: '🌏', en: 'Globe', de: 'Globus'),
  (emoji: '🌙', en: 'Moon', de: 'Mond'),
  (emoji: '☁️', en: 'Cloud', de: 'Wolke'),
  (emoji: '🔥', en: 'Fire', de: 'Feuer'),
  (emoji: '🍌', en: 'Banana', de: 'Banane'),
  (emoji: '🍎', en: 'Apple', de: 'Apfel'),
  (emoji: '🍓', en: 'Strawberry', de: 'Erdbeere'),
  (emoji: '🌽', en: 'Corn', de: 'Mais'),
  (emoji: '🍕', en: 'Pizza', de: 'Pizza'),
  (emoji: '🎂', en: 'Cake', de: 'Kuchen'),
  (emoji: '❤️', en: 'Heart', de: 'Herz'),
  (emoji: '😀', en: 'Smiley', de: 'Lächeln'),
  (emoji: '🤖', en: 'Robot', de: 'Roboter'),
  (emoji: '🎩', en: 'Hat', de: 'Hut'),
  (emoji: '👓', en: 'Glasses', de: 'Brille'),
  (emoji: '🔧', en: 'Spanner', de: 'Schraubenschlüssel'),
  (emoji: '🎅', en: 'Santa', de: 'Weihnachtsmann'),
  (emoji: '👍', en: 'Thumbs Up', de: 'Daumen Hoch'),
  (emoji: '☂️', en: 'Umbrella', de: 'Regenschirm'),
  (emoji: '⌛', en: 'Hourglass', de: 'Sanduhr'),
  (emoji: '⏰', en: 'Clock', de: 'Uhr'),
  (emoji: '🎁', en: 'Gift', de: 'Geschenk'),
  (emoji: '💡', en: 'Light Bulb', de: 'Glühbirne'),
  (emoji: '📕', en: 'Book', de: 'Buch'),
  (emoji: '✏️', en: 'Pencil', de: 'Bleistift'),
  (emoji: '📎', en: 'Paperclip', de: 'Büroklammer'),
  (emoji: '✂️', en: 'Scissors', de: 'Schere'),
  (emoji: '🔒', en: 'Lock', de: 'Schloss'),
  (emoji: '🔑', en: 'Key', de: 'Schlüssel'),
  (emoji: '🔨', en: 'Hammer', de: 'Hammer'),
  (emoji: '☎️', en: 'Telephone', de: 'Telefon'),
  (emoji: '🏁', en: 'Flag', de: 'Flagge'),
  (emoji: '🚂', en: 'Train', de: 'Zug'),
  (emoji: '🚲', en: 'Bicycle', de: 'Fahrrad'),
  (emoji: '✈️', en: 'Aeroplane', de: 'Flugzeug'),
  (emoji: '🚀', en: 'Rocket', de: 'Rakete'),
  (emoji: '🏆', en: 'Trophy', de: 'Pokal'),
  (emoji: '⚽', en: 'Ball', de: 'Ball'),
  (emoji: '🎸', en: 'Guitar', de: 'Gitarre'),
  (emoji: '🎺', en: 'Trumpet', de: 'Trompete'),
  (emoji: '🔔', en: 'Bell', de: 'Glocke'),
  (emoji: '⚓', en: 'Anchor', de: 'Anker'),
  (emoji: '🎧', en: 'Headphones', de: 'Kopfhörer'),
  (emoji: '📁', en: 'Folder', de: 'Ordner'),
  (emoji: '📌', en: 'Pin', de: 'Stecknadel'),
];

/// The spec's description of SAS emoji [number] in [languageCode] (`de`, else
/// English); `null` when [number] is unknown (out of range / not given).
String? sasEmojiName(int? number, String languageCode) {
  if (number == null || number < 0 || number >= kSasEmojiNames.length) {
    return null;
  }
  final e = kSasEmojiNames[number];
  return languageCode == 'de' ? e.de : e.en;
}
