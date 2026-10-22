import 'record_signature.dart';

class ExpenseModel {
  final String id;
  final String roomId;
  final String? matrixEventId;
  final String description;
  final int amountCents;
  final String currency;

  /// The participant who paid the whole amount; `''` when several people
  /// paid ([payersJson] is set — G76).
  final String paidBy;
  final String splitsJson;

  /// G76: who paid how much when **several** people paid — a JSON
  /// `{participantId: cents}` map (the wire `payers` verbatim), summing to
  /// the amount, ≥ 2 entries; [paidBy] is then `''` (so a pre-G76 build
  /// refuses the version as "no payer" instead of misreading it). Null =
  /// [paidBy] paid everything (the pre-G76 shape). See `expense_payers.dart`.
  final String? payersJson;
  final int createdAt;
  final int updatedAt; // ms epoch, LWW clock
  final bool deleted; // tombstone — kept forever, hidden from the UI

  /// G16: the category's stable wire id (`food`, `transport`, … — see
  /// `expense_category.dart`), null = none. Kept verbatim (an id this
  /// version doesn't know is shown as "other" but never rewritten — it is
  /// part of the signed content).
  final String? category;

  /// G16: optional free-text note, null = none (never an empty string).
  final String? note;

  /// G49: the calendar day the expense happened, ISO `YYYY-MM-DD` (no time,
  /// no time zone — every device shows the same day), null = the local day
  /// of [createdAt]. Only set when it differs from that day (a back-dated
  /// expense); see `expense_date.dart`.
  final String? date;

  /// G6: this version's signature (its editor), null for a grandfathered
  /// pre-G6 row (legacy / unsigned).
  final RecordSignature? sig;

  /// G6: the creator's signed creation statement ("added by"), carried
  /// unchanged across edits; null when unknown (legacy).
  final RecordSignature? origin;

  /// G6: written locally while the signer wasn't ready — signed (same clock)
  /// before it is ever sent. Device-local, never on the wire.
  final bool pendingSign;

  /// G37: the G27 content hash as cached in the DB (`version_hash`), set only
  /// when read from a row the DAO hashed on write; null = compute on demand
  /// (`expenseVersionHash`). Never on the wire.
  final String? versionHash;

  /// G52: display-only "changed by" hint of a version written in a link
  /// group (`by` on the wire: the writer's participant id) — **unsigned and
  /// unhashed**, never part of the signed body or the G27 hash
  /// (`docs/design/no-login-sharing.md` §6.3). Null = none.
  final String? linkAuthor;

  const ExpenseModel({
    required this.id,
    required this.roomId,
    this.matrixEventId,
    required this.description,
    required this.amountCents,
    required this.currency,
    required this.paidBy,
    required this.splitsJson,
    this.payersJson,
    required this.createdAt,
    this.updatedAt = 0,
    this.deleted = false,
    String? category,
    String? note,
    String? date,
    this.sig,
    this.origin,
    this.pendingSign = false,
    this.versionHash,
    this.linkAuthor,
  }) : category = category == '' ? null : category,
       note = note == '' ? null : note,
       date = date == '' ? null : date;

  /// A copy with the G6 signing fields replaced (content unchanged).
  ExpenseModel withSigning({
    RecordSignature? sig,
    RecordSignature? origin,
    bool pendingSign = false,
  }) => ExpenseModel(
    id: id,
    roomId: roomId,
    matrixEventId: matrixEventId,
    description: description,
    amountCents: amountCents,
    currency: currency,
    paidBy: paidBy,
    splitsJson: splitsJson,
    payersJson: payersJson,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deleted: deleted,
    category: category,
    note: note,
    date: date,
    sig: sig,
    origin: origin,
    pendingSign: pendingSign,
    versionHash: versionHash,
    linkAuthor: linkAuthor,
  );

  /// G52: this version as written in a link-only group — unsigned, **not**
  /// `pendingSign` (never signed later), no `origin` (attribution never
  /// lies), [author] as the display-only `by` hint. Content unchanged.
  ExpenseModel asLinkVersion(String? author) => ExpenseModel(
    id: id,
    roomId: roomId,
    matrixEventId: matrixEventId,
    description: description,
    amountCents: amountCents,
    currency: currency,
    paidBy: paidBy,
    splitsJson: splitsJson,
    payersJson: payersJson,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deleted: deleted,
    category: category,
    note: note,
    date: date,
    versionHash: versionHash,
    linkAuthor: author,
  );
}

class SettlementModel {
  final String id;
  final String roomId;
  final String? matrixEventId;
  final int amountCents;
  final String currency;
  final String fromUser;
  final String toUser;
  final int createdAt;
  final int updatedAt; // ms epoch, LWW clock
  final bool deleted; // tombstone — kept forever, hidden from the UI

  /// G60: the calendar day the payment happened, ISO `YYYY-MM-DD` — exactly
  /// like [ExpenseModel.date] (null = the local day of [createdAt]; only set
  /// when it differs from that day).
  final String? date;

  /// G6 signing fields — see [ExpenseModel.sig].
  final RecordSignature? sig;
  final RecordSignature? origin;
  final bool pendingSign;

  /// G37 — see [ExpenseModel.versionHash].
  final String? versionHash;

  /// G52 — see [ExpenseModel.linkAuthor].
  final String? linkAuthor;

  const SettlementModel({
    required this.id,
    required this.roomId,
    this.matrixEventId,
    required this.amountCents,
    required this.currency,
    required this.fromUser,
    required this.toUser,
    required this.createdAt,
    this.updatedAt = 0,
    this.deleted = false,
    String? date,
    this.sig,
    this.origin,
    this.pendingSign = false,
    this.versionHash,
    this.linkAuthor,
  }) : date = date == '' ? null : date;

  /// A copy with the G6 signing fields replaced (content unchanged).
  SettlementModel withSigning({
    RecordSignature? sig,
    RecordSignature? origin,
    bool pendingSign = false,
  }) => SettlementModel(
    id: id,
    roomId: roomId,
    matrixEventId: matrixEventId,
    amountCents: amountCents,
    currency: currency,
    fromUser: fromUser,
    toUser: toUser,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deleted: deleted,
    date: date,
    sig: sig,
    origin: origin,
    pendingSign: pendingSign,
    versionHash: versionHash,
    linkAuthor: linkAuthor,
  );

  /// G52 — see [ExpenseModel.asLinkVersion].
  SettlementModel asLinkVersion(String? author) => SettlementModel(
    id: id,
    roomId: roomId,
    matrixEventId: matrixEventId,
    amountCents: amountCents,
    currency: currency,
    fromUser: fromUser,
    toUser: toUser,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deleted: deleted,
    date: date,
    versionHash: versionHash,
    linkAuthor: author,
  );
}
