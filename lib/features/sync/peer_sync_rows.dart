/// G68 (U24) + G52 step 9: the rows of a group's sync sheet — one per
/// person — for Matrix groups (anti-entropy proofs, `PeerSyncStates`) and
/// link groups (the publishers seen on the relays, `link_peers`). Pure Dart;
/// the sheet is `group_sync_sheet.dart`.
library;

import 'dart:math' as math;

import '../../core/sync/record_validation.dart' show isValidMxid;
import '../../core/sync/sync_health.dart';
import '../../models/link_model.dart';
import '../../models/member_model.dart';

/// What a person's row says.
enum PeerSyncKind {
  /// Matrix: proven to hold everything we hold. Link: their phone
  /// published exactly our state ("has everything", §5.3).
  upToDate,

  /// Matrix: not yet proven to hold our latest change ([PeerSyncRow.at] =
  /// last proof, null = never).
  waiting,

  /// Matrix: no signed-in device (G24).
  noDevice,

  /// Matrix: no verified device while verified-only sync is on (G11).
  unverified,

  /// Link: their phone last published at [PeerSyncRow.at] — whether that
  /// covers our change can't be told (§5.3).
  published,

  /// Link: every device of this person seen here deleted its copy of the
  /// group ([PeerSyncRow.at] = when this device learned it) — G53 round 3,
  /// decision 6.
  deletedGroup,
}

class PeerSyncRow {
  /// The participant (null: a link publisher naming nobody we know).
  final String? participantId;

  /// The participant's name (null: unknown).
  final String? name;

  /// This account / this person's other devices.
  final bool isSelf;

  final PeerSyncKind kind;

  /// ms epoch: last proof (Matrix) / last publish (link) / when the
  /// deletion was learned ([PeerSyncKind.deletedGroup]).
  final int? at;

  /// Link: how many devices (publishers) of this person were seen.
  final int devices;

  const PeerSyncRow({
    required this.participantId,
    required this.name,
    required this.kind,
    this.isSelf = false,
    this.at,
    this.devices = 1,
  });

  @override
  String toString() =>
      'PeerSyncRow($name, ${kind.name}, self: $isSelf, at: $at, '
      'devices: $devices)';
}

/// The Matrix rows: every active participant with a Matrix account except
/// us, then — when one of them ever proved it — "your other devices".
/// Sorted by name; ours last.
List<PeerSyncRow> matrixPeerRows({
  required String selfMxid,
  required List<MemberModel> members,
  required Map<String, int> peerInSyncAt,
  required int maxRecordUpdatedAt,
  required SyncHealthState health,
}) {
  final rows = <PeerSyncRow>[];
  MemberModel? self;
  for (final m in members) {
    if (!m.isActive || !isValidMxid(m.matrixId)) continue;
    final mxid = m.matrixId!;
    if (mxid == selfMxid) {
      self = m;
      continue;
    }
    final at = peerInSyncAt[mxid];
    final upToDate = (at ?? 0) >= maxRecordUpdatedAt && at != null;
    rows.add(
      PeerSyncRow(
        participantId: m.userId,
        name: m.label,
        at: at == null || at == 0 ? null : at,
        kind: upToDate
            ? PeerSyncKind.upToDate
            : health.unverifiedPeers.contains(mxid)
            ? PeerSyncKind.unverified
            : health.unreachablePeers.contains(mxid)
            ? PeerSyncKind.noDevice
            : PeerSyncKind.waiting,
      ),
    );
  }
  rows.sort((a, b) => a.name!.toLowerCase().compareTo(b.name!.toLowerCase()));
  final own = peerInSyncAt[selfMxid];
  if (own != null && own > 0) {
    rows.add(
      PeerSyncRow(
        participantId: self?.userId,
        name: self?.label,
        isSelf: true,
        at: own,
        kind: own >= maxRecordUpdatedAt
            ? PeerSyncKind.upToDate
            : PeerSyncKind.waiting,
      ),
    );
  }
  return rows;
}

/// How many active participants have no Matrix account (they never sync;
/// the sheet says so).
int localOnlyPeople(List<MemberModel> members) =>
    members.where((m) => m.isActive && !isValidMxid(m.matrixId)).length;

/// The link rows: the publishers seen on the group's topic, one row per
/// participant they name as `me` (newest publish, device count); a
/// publisher naming nobody in [members] gets an unnamed row. "Has
/// everything" when a single-part publisher's snapshot digest equals
/// [ourDigest] (our delivered snapshot — null while ours isn't on the
/// relays) and we publish one part too ([ourParts]). A person whose every
/// publisher deleted its copy ([LinkPeerModel.left]) gets a "deleted the
/// group" row (G53 round 3); otherwise the deleted ones are left out. Our
/// own other devices
/// ([myParticipantId]) come last; the rest by name (unnamed last).
List<PeerSyncRow> linkPeerRows({
  required List<LinkPeerModel> peers,
  required List<MemberModel> members,
  required String? myParticipantId,
  required String? ourDigest,
  required int ourParts,
}) {
  final byId = {for (final m in members) m.userId: m};
  final grouped = <String, List<LinkPeerModel>>{};
  for (final p in peers) {
    final key = p.me != null && byId.containsKey(p.me) ? p.me! : '';
    (grouped[key] ??= []).add(p);
  }
  bool same(LinkPeerModel p) =>
      ourDigest != null &&
      ourParts <= 1 &&
      p.snapshotDigest == ourDigest &&
      p.eventIds.keys.every((part) => part == 0);
  final rows = <PeerSyncRow>[];
  for (final e in grouped.entries) {
    final member = byId[e.key];
    // G53 round 3 (decision 6): devices that deleted their copy only count
    // while no other device of the person still has it.
    final kept = [
      for (final p in e.value)
        if (!p.left) p,
    ];
    if (kept.isEmpty) {
      rows.add(
        PeerSyncRow(
          participantId: member?.userId,
          name: member?.label,
          isSelf: myParticipantId != null && e.key == myParticipantId,
          kind: PeerSyncKind.deletedGroup,
          at: e.value.map((p) => p.leftAt!).reduce(math.max),
          devices: e.value.length,
        ),
      );
      continue;
    }
    final list = kept;
    final newest = list.reduce(
      (a, b) => b.lastCreatedAt > a.lastCreatedAt ? b : a,
    );
    rows.add(
      PeerSyncRow(
        participantId: member?.userId,
        name: member?.label,
        isSelf: myParticipantId != null && e.key == myParticipantId,
        kind: list.any(same) ? PeerSyncKind.upToDate : PeerSyncKind.published,
        at: newest.lastCreatedAt > 0 ? newest.lastCreatedAt * 1000 : null,
        devices: list.length,
      ),
    );
  }
  int rank(PeerSyncRow r) => r.isSelf ? 2 : (r.name == null ? 1 : 0);
  rows.sort((a, b) {
    final c = rank(a).compareTo(rank(b));
    if (c != 0) return c;
    return (a.name ?? '').toLowerCase().compareTo((b.name ?? '').toLowerCase());
  });
  return rows;
}
