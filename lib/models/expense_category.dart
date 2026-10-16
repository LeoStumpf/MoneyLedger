/// G16 expense categories — the fixed set, their stable wire ids and the
/// description heuristic that pre-fills one (plain Dart, no Flutter).
///
/// The **wire id** (`food`, `transport`, …) is what the expense payload's
/// optional `category` field, the DB, the backup and the CSV carry — stable
/// English ids, never translated (labels come from the ARB files). An id this
/// app version doesn't know (a newer peer's category) is kept verbatim on the
/// record and shown as [ExpenseCategory.other].
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
