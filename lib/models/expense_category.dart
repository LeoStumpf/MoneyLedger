/// G16 expense categories — the fixed set, their stable wire ids and the
/// description heuristic that pre-fills one (plain Dart, no Flutter).
///
/// The **wire id** (`food`, `transport`, …) is what the expense payload's
/// optional `category` field, the DB, the backup and the CSV carry — stable
/// English ids, never translated (labels come from the ARB files). An id this
/// app version doesn't know (a newer peer's category) is kept verbatim on the
/// record and shown as [ExpenseCategory.other].
///
/// G47: a group may also define **custom** categories (`c:<uuidv7>` ids, see
/// [CustomCategory]) in its signed meta; [resolveCategory] maps an expense's
/// id to what it shows as.
library;

enum ExpenseCategory {
  food('food'),
  groceries('groceries'),
  transport('transport'),
  accommodation('accommodation'),
  entertainment('entertainment'),
  shopping('shopping'),
  home('home'),
  health('health'),
  travel('travel'),
  other('other');

  const ExpenseCategory(this.wire);

  /// The stable id on the wire / in the DB.
  final String wire;

  /// The category for a wire id: null for none, [other] for an unknown id.
  static ExpenseCategory? fromWire(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final c in values) {
      if (c.wire == id) return c;
    }
    return other;
  }
}

/// G47: prefix of a **custom** (per-group) category id — `c:<uuidv7>`.
/// Built-in wire ids never contain `:`.
const kCustomCategoryPrefix = 'c:';

/// G47: at most this many custom categories per group (hidden ones count).
const kMaxCustomCategories = 50;

/// G47: a custom category's name is 1 … this many UTF-16 code units, trimmed.
const kMaxCategoryNameLength = 40;

/// G47: longest accepted custom category id (`c:` + a UUID is 38).
const kMaxCustomCategoryIdLength = 64;

/// G47: the fixed icon set of custom categories — stable **wire keys** (the
/// UI maps them to Material icons, `expense_category_ui.dart`). Never rename
/// or remove a key: it is part of signed group metas.
const kCustomCategoryIcons = <String>[
  'tag',
  'star',
  'heart',
  'pets',
  'child',
  'gift',
  'sports',
  'music',
  'book',
  'work',
  'tools',
  'phone',
  'beach',
  'coffee',
  'savings',
  'party',
];

/// The icon a new custom category starts with (and a CSV import uses).
const kDefaultCustomCategoryIcon = 'tag';

/// Whether [id] names a custom category (`c:…`), not a built-in one.
bool isCustomCategoryId(String? id) =>
    id != null && id.startsWith(kCustomCategoryPrefix);

/// Whether [name] is a storable custom category name: already trimmed and
/// 1 … [kMaxCategoryNameLength] long.
bool isValidCategoryName(String name) =>
    name.isNotEmpty &&
    name.length <= kMaxCategoryNameLength &&
    name.trim() == name;

/// G47: a per-group custom category, defined in the group's **signed meta**
/// (`categories`), so every member sees the same set. [hidden] categories
/// aren't offered for new expenses but still label existing ones. There is
/// no delete — hiding keeps old expenses labelled.
class CustomCategory {
  final String id;
  final String name;

  /// A key of [kCustomCategoryIcons].
  final String icon;
  final bool hidden;

  const CustomCategory({
    required this.id,
    required this.name,
    required this.icon,
    this.hidden = false,
  });

  /// The wire / signed form: `hidden` only when true, so the body of a
  /// visible category stays minimal.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    if (hidden) 'hidden': true,
  };

  CustomCategory copyWith({String? name, String? icon, bool? hidden}) =>
      CustomCategory(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        hidden: hidden ?? this.hidden,
      );

  @override
  bool operator ==(Object other) =>
      other is CustomCategory &&
      other.id == id &&
      other.name == name &&
      other.icon == icon &&
      other.hidden == hidden;

  @override
  int get hashCode => Object.hash(id, name, icon, hidden);

  @override
  String toString() => 'CustomCategory($id, $name, $icon, hidden: $hidden)';
}

/// Stands in for a malformed `categories` entry so the meta is refused as
/// `invalid_record` (`groupMetaProblem`) instead of being silently trimmed.
const _invalidCategory = CustomCategory(id: '', name: '', icon: '');

/// The custom categories of a wire / stored `categories` value: null → none;
/// anything malformed (not a list, an entry that isn't an object of string
/// fields) yields an invalid entry, which the content rules refuse.
List<CustomCategory> parseCustomCategories(Object? raw) {
  if (raw == null) return const [];
  if (raw is! List) return const [_invalidCategory];
  String str(Object? v) => v is String ? v : '';
  return [
    for (final e in raw)
      e is Map
          ? CustomCategory(
              id: str(e['id']),
              name: str(e['name']),
              icon: str(e['icon']),
              hidden: e['hidden'] == true,
            )
          : _invalidCategory,
  ];
}

/// What an expense's category id shows as (G47): a built-in category, or a
/// custom one of the group. [key] identifies it for filters — the built-in
/// wire id or the custom id.
class ResolvedCategory {
  final ExpenseCategory? builtin;
  final CustomCategory? custom;
  const ResolvedCategory.builtin(ExpenseCategory this.builtin) : custom = null;
  const ResolvedCategory.custom(CustomCategory this.custom) : builtin = null;

  String get key => custom?.id ?? builtin!.wire;

  @override
  bool operator ==(Object other) =>
      other is ResolvedCategory &&
      other.builtin == builtin &&
      other.custom == custom;

  @override
  int get hashCode => Object.hash(builtin, custom);
}

/// Resolves an expense's category [id] against the group's [custom]
/// categories: null/empty → none; a built-in wire id → it; a custom id the
/// group defines → it (hidden ones too — they still label old expenses);
/// anything else (a newer peer's built-in, a custom id the group doesn't
/// define) → [ExpenseCategory.other]. The id itself is never changed.
ResolvedCategory? resolveCategory(String? id, List<CustomCategory> custom) {
  if (id == null || id.isEmpty) return null;
  if (isCustomCategoryId(id)) {
    for (final c in custom) {
      if (c.id == id) return ResolvedCategory.custom(c);
    }
    return const ResolvedCategory.builtin(ExpenseCategory.other);
  }
  return ResolvedCategory.builtin(ExpenseCategory.fromWire(id)!);
}

/// Maximum length of an expense note (characters; enforced by the form —
/// inbound notes are kept as signed, the to-device size budget bounds them).
const kMaxNoteLength = 500;

/// [note] trimmed, or null when blank — the form's normalisation, so an
/// empty note is never stored or signed as `""`.
String? normalizeNote(String? note) {
  final t = note?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// Keyword stems per category (EN + DE, lower case), matched against the
/// start of each word of a description. Order matters: the first category
/// with a hit wins, so more specific ones come first.
const _keywords = <ExpenseCategory, List<String>>{
  ExpenseCategory.groceries: [
    'grocer',
    'supermarket',
    'aldi',
    'lidl',
    'rewe',
    'edeka',
    'migros',
    'coop',
    'tesco',
    'lebensmittel',
    'einkauf',
    'supermarkt',
  ],
  ExpenseCategory.food: [
    'pizza',
    'dinner',
    'lunch',
    'breakfast',
    'brunch',
    'restaurant',
    'café',
    'cafe',
    'coffee',
    'bar',
    'beer',
    'drinks',
    'wine',
    'burger',
    'sushi',
    'kebab',
    'döner',
    'doner',
    'snack',
    'ice cream',
    'icecream',
    'fondue',
    'pastéis',
    'pasteis',
    'seafood',
    'takeaway',
    'essen',
    'abendessen',
    'mittagessen',
    'frühstück',
    'kaffee',
    'bier',
    'wein',
    'getränke',
    'eis',
  ],
  ExpenseCategory.accommodation: [
    'hotel',
    'hostel',
    'airbnb',
    'apartment',
    'chalet',
    'cabin',
    'camping',
    'booking',
    'unterkunft',
    'ferienwohnung',
    'zimmer',
    'übernachtung',
  ],
  ExpenseCategory.travel: [
    'flight',
    'plane',
    'airline',
    'ferry',
    'trip',
    'tour',
    'visa',
    'flug',
    'fähre',
    'ausflug',
    'reise',
  ],
  ExpenseCategory.transport: [
    'taxi',
    'uber',
    'bolt',
    'bus',
    'tram',
    'train',
    'metro',
    'subway',
    'ticket',
    'fuel',
    'gas',
    'petrol',
    'parking',
    'toll',
    'car',
    'rental car',
    'bahn',
    'zug',
    'benzin',
    'tanken',
    'diesel',
    'parken',
    'maut',
    'mietwagen',
  ],
  ExpenseCategory.entertainment: [
    'cinema',
    'movie',
    'concert',
    'theatre',
    'theater',
    'museum',
    'show',
    'party',
    'club',
    'game',
    'netflix',
    'spotify',
    'ski pass',
    'ski passes',
    'fado',
    'kino',
    'konzert',
    'eintritt',
  ],
  ExpenseCategory.home: [
    'rent',
    'electricity',
    'internet',
    'wifi',
    'water',
    'heating',
    'cleaning',
    'utilities',
    'furniture',
    'miete',
    'strom',
    'heizung',
    'nebenkosten',
    'putzmittel',
    'reinigung',
    'möbel',
    'wasser',
  ],
  ExpenseCategory.health: [
    'pharmacy',
    'doctor',
    'medicine',
    'dentist',
    'hospital',
    'apotheke',
    'arzt',
    'medikament',
    'zahnarzt',
  ],
  ExpenseCategory.shopping: [
    'shopping',
    'clothes',
    'shoes',
    'gift',
    'present',
    'souvenir',
    'kleidung',
    'schuhe',
    'geschenk',
  ],
};

/// A category guessed from [description] — only a **prefill suggestion** for
/// the add-expense form (the user can change or clear it). Matches keyword
/// stems at word starts, case-insensitively ("Pizza" → food, "Taxi to the
/// airport" → transport); short stems (≤ 4 letters: "bar", "bus", "car") must
/// be the whole word, so "barber" or "business" don't match. Null when
/// nothing matches.
ExpenseCategory? suggestCategory(String description) {
  final text = description.toLowerCase();
  if (text.trim().isEmpty) return null;
  bool letterAt(int i) =>
      i >= 0 && i < text.length && _isLetter(text.codeUnitAt(i));
  bool hit(String stem) {
    final wholeWord = stem.length <= 4;
    for (var i = text.indexOf(stem); i >= 0; i = text.indexOf(stem, i + 1)) {
      if (letterAt(i - 1)) continue; // not at a word start
      if (wholeWord && letterAt(i + stem.length)) continue;
      return true;
    }
    return false;
  }

  for (final MapEntry(key: category, value: stems) in _keywords.entries) {
    if (stems.any(hit)) return category;
  }
  return null;
}

bool _isLetter(int c) =>
    (c >= 0x61 && c <= 0x7a) || // a-z
    (c >= 0x41 && c <= 0x5a) || // A-Z
    c >= 0xc0; // Latin-1 letters and beyond (ä, ö, ü, é, …)
