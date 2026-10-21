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

  /// G6: signature of this meta version (null = legacy / unsigned).
  final RecordSignature? sig;

  /// G6: written while the signer wasn't ready; signed before it is sent.
  final bool pendingSign;

  /// G52: display-only, unsigned, unhashed "changed by" hint of a meta
  /// version written in a link group (see `ExpenseModel.linkAuthor`).
  final String? linkAuthor;

  const GroupModel({
    required this.roomId,
    required this.name,
    required this.currency,
    this.updatedAt = 0,
    this.categories = const [],
    this.link,
    this.lockedAt,
    this.sig,
    this.pendingSign = false,
    this.linkAuthor,
  });

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
        sig: sig,
        pendingSign: pendingSign,
        linkAuthor: linkAuthor,
      );

  /// G53: the next meta version (clock [updatedAt]) with the content of
  /// this one, the given fields replaced — unsigned, no author hint.
  /// [link] / [lockedAt]: pass [keepLinkState] (the default) to keep them.
  GroupModel nextVersion({
    required int updatedAt,
    String? name,
    String? currency,
    List<CustomCategory>? categories,
    Object? link = keepLinkState,
    Object? lockedAt = keepLinkState,
  }) => GroupModel(
    roomId: roomId,
    name: name ?? this.name,
    currency: currency ?? this.currency,
    updatedAt: updatedAt,
    categories: categories ?? this.categories,
    link: identical(link, keepLinkState) ? this.link : link as GroupLink?,
    lockedAt: identical(lockedAt, keepLinkState)
        ? this.lockedAt
        : lockedAt as int?,
  );

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
    linkAuthor: author,
  );

  /// The custom categories offered for new expenses (not hidden).
  List<CustomCategory> get visibleCategories => [
    for (final c in categories)
      if (!c.hidden) c,
  ];
}

/// Sentinel for [GroupModel.nextVersion]: keep the current link state.
const Object keepLinkState = Object();
