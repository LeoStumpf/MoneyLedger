import 'exchange_rates.dart';
import 'expense_category.dart';
import 'record_signature.dart';

/// G53: the invite link a **signed** group meta carries while the group is
/// shared by link (`docs/design/no-login-sharing.md` §0 #10, §10.1) — a
/// `mixed` group. [secret] is the link secret (base64url, the link's `k`):
/// a **secret**, so [toString] leaves it out — never log it. [epoch] counts
/// the links this meta opened (informational; the topic and keys come from
/// the secret alone).
class GroupLink {
  final int epoch;
  final String secret;

  const GroupLink({required this.epoch, required this.secret});

  Map<String, Object?> toJson() => {'epoch': epoch, 'secret': secret};

  /// [raw] as found on the wire / in the DB; null when absent. A present
  /// but malformed value parses to an **invalid** link (epoch 0, empty
  /// secret) so the content rules refuse the version instead of silently
  /// dropping the field (its signature would not match then anyway).
  static GroupLink? fromJson(Object? raw) {
    if (raw == null) return null;
    if (raw is Map && raw['epoch'] is int && raw['secret'] is String) {
      return GroupLink(
        epoch: raw['epoch'] as int,
        secret: raw['secret'] as String,
      );
    }
    return const GroupLink(epoch: 0, secret: '');
  }

  @override
  bool operator ==(Object other) =>
      other is GroupLink && other.epoch == epoch && other.secret == secret;

  @override
  int get hashCode => Object.hash(epoch, secret);

  @override
  String toString() => 'GroupLink(epoch: $epoch)';
}

class GroupModel {
  final String roomId;
  final String name;
  final String currency;
  final int updatedAt; // ms epoch, LWW clock for the group meta (name/currency)

  /// G47: the group's custom expense categories, in definition order (part
  /// of the signed meta, and of its hash, only when non-empty).
  final List<CustomCategory> categories;

  /// G53: the open invite link of a `mixed` group (signed meta only; part
  /// of the signed body and the G27 hash only when set).
  final GroupLink? link;

  /// G53: when the group was **locked** (made secure-only, ms epoch — the
  /// locking device's clock): a signed meta without [link]. Unsigned
  /// versions newer than it are refused from then on. Signed / hashed only
  /// when set.
  final int? lockedAt;

  /// G73: the group's fixed exchange rates (+ "settle in base"); null =
  /// none. Part of the signed body and the G27 hash only when set.
  final ExchangeRates? exchangeRates;

  /// G6: signature of this meta version (null = legacy / unsigned).
  final RecordSignature? sig;

  /// G6: written while the signer wasn't ready; signed before it is sent.
  final bool pendingSign;

  /// G52: display-only, unsigned, unhashed "changed by" hint of a meta
  /// version written in a link group (see `ExpenseModel.linkAuthor`).
  final String? linkAuthor;

  /// G57 (C1): the per-field LWW clocks of this meta version — field key
  /// ([kMetaFieldName], [kMetaFieldCurrency], [kMetaFieldExchangeRates],
  /// [kMetaFieldLink] or a custom category id) → the clock of the version
  /// that last changed that field. A field without an entry (or with one not
  /// below [updatedAt]) was changed by this version: its clock is
  /// [updatedAt] — so every pre-G57 meta reads as "all fields at
  /// `updated_at`". Read through [clockOf]; signed / hashed only for the
  /// entries below [updatedAt] (`clocks`, only when there are any).
  final Map<String, int> fieldClocks;

  const GroupModel({
    required this.roomId,
    required this.name,
    required this.currency,
    this.updatedAt = 0,
    this.categories = const [],
    this.link,
    this.lockedAt,
    this.exchangeRates,
    this.sig,
    this.pendingSign = false,
    this.linkAuthor,
    this.fieldClocks = const {},
  });

  /// G57: the clock of [field] (see [fieldClocks]). The **empty** link
  /// state (no `link`, no `locked_at` — a group never shared by link) has
  /// clock 0: it never wins over a link opened concurrently (the app never
  /// goes back to it — a lock keeps `locked_at`), and an unsigned meta
  /// (which can't carry the link state) needs no clock for it.
  int clockOf(String field) {
    if (field == kMetaFieldLink && link == null && lockedAt == null) return 0;
    final c = fieldClocks[field];
    return c != null && c < updatedAt ? c : updatedAt;
  }

  /// G57: the per-field clocks the wire carries — one entry per field of
  /// this version (the scalar fields, every category of [categories]) whose
  /// clock is below [updatedAt], keys sorted. Empty for a version that
  /// changed every field (every pre-G57 meta).
  Map<String, int> get wireClocks {
    final keys = [...kMetaScalarFields, for (final c in categories) c.id];
    final out = <String, int>{};
    for (final k in keys..sort()) {
      if (k == kMetaFieldLink && link == null && lockedAt == null) continue;
      final c = clockOf(k);
      if (c < updatedAt) out[k] = c;
    }
    return out;
  }

  /// G53: a signed meta without a link but with [lockedAt] — the group was
  /// made secure-only (§10.1).
  bool get isLocked => sig != null && link == null && lockedAt != null;

  /// A copy with the G6 signing fields replaced (content unchanged).
  GroupModel withSigning({RecordSignature? sig, bool pendingSign = false}) =>
      GroupModel(
        roomId: roomId,
        name: name,
        currency: currency,
        updatedAt: updatedAt,
        categories: categories,
        link: link,
        lockedAt: lockedAt,
        exchangeRates: exchangeRates,
        sig: sig,
        pendingSign: pendingSign,
        linkAuthor: linkAuthor,
        fieldClocks: fieldClocks,
      );

  /// G57: a copy at clock [at] (content, per-field clocks and link-author
  /// hint kept, unsigned) — the merged meta a device re-signs as its own
  /// version. Every field keeps its own clock.
  GroupModel atClock(int at) => GroupModel(
    roomId: roomId,
    name: name,
    currency: currency,
    updatedAt: at,
    categories: categories,
    link: link,
    lockedAt: lockedAt,
    exchangeRates: exchangeRates,
    linkAuthor: linkAuthor,
    fieldClocks: {
      for (final k in [...kMetaScalarFields, for (final c in categories) c.id])
        k: clockOf(k),
    },
  );

  /// G53: the next meta version (clock [updatedAt]) with the content of
  /// this one, the given fields replaced — unsigned, no author hint.
  /// [link] / [lockedAt]: pass [keepLinkState] (the default) to keep them.
  /// G73: [exchangeRates] likewise ([keepExchangeRates] = keep, null = none).
  ///
  /// G57: every field that changes gets the new clock, every other keeps
  /// its own ([fieldClocks]) — so a concurrent change of another field on
  /// another device survives the merge. Categories are never deleted: one
  /// missing from [categories] is kept **hidden** (a merge would bring a
  /// dropped one back; old expenses keep their label).
  GroupModel nextVersion({
    required int updatedAt,
    String? name,
    String? currency,
    List<CustomCategory>? categories,
    Object? link = keepLinkState,
    Object? lockedAt = keepLinkState,
    Object? exchangeRates = keepExchangeRates,
  }) {
    final nextName = name ?? this.name;
    final nextCurrency = currency ?? this.currency;
    final nextLink = identical(link, keepLinkState)
        ? this.link
        : link as GroupLink?;
    final nextLockedAt = identical(lockedAt, keepLinkState)
        ? this.lockedAt
        : lockedAt as int?;
    final nextFx = identical(exchangeRates, keepExchangeRates)
        ? this.exchangeRates
        : exchangeRates as ExchangeRates?;
    final wanted = categories ?? this.categories;
    final wantedIds = {for (final c in wanted) c.id};
    final nextCategories = [
      ...wanted,
      for (final c in this.categories)
        if (!wantedIds.contains(c.id)) c.hidden ? c : c.copyWith(hidden: true),
    ];
    final old = {for (final c in this.categories) c.id: c};
    final clocks = <String, int>{
      if (nextName == this.name) kMetaFieldName: clockOf(kMetaFieldName),
      if (nextCurrency == this.currency)
        kMetaFieldCurrency: clockOf(kMetaFieldCurrency),
      if (nextFx == this.exchangeRates)
        kMetaFieldExchangeRates: clockOf(kMetaFieldExchangeRates),
      if (nextLink == this.link && nextLockedAt == this.lockedAt)
        kMetaFieldLink: clockOf(kMetaFieldLink),
      for (final c in nextCategories)
        if (old[c.id] == c) c.id: clockOf(c.id),
    };
    return GroupModel(
      roomId: roomId,
      name: nextName,
      currency: nextCurrency,
      updatedAt: updatedAt,
      categories: nextCategories,
      link: nextLink,
      lockedAt: nextLockedAt,
      exchangeRates: nextFx,
      fieldClocks: clocks,
    );
  }

  /// G52: this version as written in a link-only group — unsigned, not
  /// `pendingSign`, [author] as the `by` hint. G53: an unsigned meta never
  /// carries the link state ([link] / [lockedAt] — those are only valid
  /// signed), so they are dropped.
  GroupModel asLinkVersion(String? author) => GroupModel(
    roomId: roomId,
    name: name,
    currency: currency,
    updatedAt: updatedAt,
    categories: categories,
    exchangeRates: exchangeRates,
    linkAuthor: author,
    // G57: the link field doesn't exist unsigned.
    fieldClocks: {...fieldClocks}..remove(kMetaFieldLink),
  );

  /// The custom categories offered for new expenses (not hidden).
  List<CustomCategory> get visibleCategories => [
    for (final c in categories)
      if (!c.hidden) c,
  ];
}

/// G57: the field keys of the meta's per-field clocks (besides the custom
/// category ids, `c:…`). [kMetaFieldLink] covers `link` and `locked_at`
/// together (the link state).
const kMetaFieldName = 'name';
const kMetaFieldCurrency = 'currency';
const kMetaFieldExchangeRates = 'exchange_rates';
const kMetaFieldLink = 'link';
const kMetaScalarFields = [
  kMetaFieldName,
  kMetaFieldCurrency,
  kMetaFieldExchangeRates,
  kMetaFieldLink,
];

/// Sentinel for [GroupModel.nextVersion]: keep the current link state.
const Object keepLinkState = Object();

/// Sentinel for [GroupModel.nextVersion]: keep the current exchange rates.
const Object keepExchangeRates = _KeepExchangeRates();

class _KeepExchangeRates {
  const _KeepExchangeRates();
}
