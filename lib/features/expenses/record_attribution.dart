import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/app_session.dart';
import '../../core/database/daos/signing_dao.dart';
import '../../core/l10n/l10n.dart';
import '../../core/sync/record_signing.dart';
import '../../core/sync/record_verifier.dart';
import '../../core/theme/app_theme.dart';
import '../../models/member_model.dart';
import '../../models/record_signature.dart';
import '../../core/matrix/record_crypto.dart';
import '../devices/device_provider.dart';
import '../groups/group_provider.dart';
import 'expenses_provider.dart';

/// G6: the device-key history of this account — every record's signature
/// status is derived from it ([signatureStatus]).
final knownDeviceKeysProvider = StreamProvider.autoDispose<List<KnownKey>>(
  (ref) => ref.watch(signingDaoProvider).watchAllKeys(),
);

/// G6: a refused newer version of one record, if any.
final rejectedVersionProvider = StreamProvider.autoDispose
    .family<RefusedVersion?, ({String group, RecordKind kind, String id})>(
      (ref, r) => ref
          .watch(signingDaoProvider)
          .watchRejected(r.group, r.kind.wire, r.id),
    );

/// G11: whether the device that signed [s] is one this account verified by
/// emoji comparison (exact user, device and key). Null for our own
/// signatures — G6 already flags "not from one of your devices". Pure.
bool? signerVerifiedByMe(
  RecordSignature s, {
  required String myMxid,
  required Set<SignerId> trusted,
}) => s.user == myMxid
    ? null
    : trusted.contains(SignerId(user: s.user, device: s.device, key: s.key));

/// The display name for the account [mxid] in a group: "you" for ourselves,
/// else the participant it claims, else its localpart.
String editorName(
  String mxid, {
  required String myMxid,
  required List<MemberModel> members,
  required AppLocalizations l,
}) {
  if (mxid == myMxid) return l.recordYou;
  return claimedBy(members, mxid)?.label ?? localpartOf(mxid);
}

/// Pure view model of a record's authorship line (G6), unit-testable.
class Attribution {
  /// "Added by X · Last edited by Y", or the legacy / unsigned note.
  final String line;

  /// The pieces of [line] ("Added by X", "Last edited by Y") — shown one per
  /// line, each ellipsized, when [line] doesn't fit on one (G33: long MXID
  /// localparts used to wrap mid-name).
  final List<String> parts;

  /// A warning or hint under the line (unverifiable, conflict, "not from
  /// one of your devices"); null when all is well.
  final String? hint;

  /// Whether [hint] is a problem (shown in the error colour; the list flags
  /// such records too).
  final bool problem;

  const Attribution({
    required this.line,
    List<String>? parts,
    this.hint,
    this.problem = false,
  }) : parts = parts ?? const [];
}

Attribution attributionFor({
  required RecordSignature? origin,
  required RecordSignature? sig,
  required int createdAt,
  required int updatedAt,
  required String myMxid,
  required List<MemberModel> members,
  required List<KnownKey> keys,
  required AppLocalizations l,
  RecordKind kind = RecordKind.expense,
  String? group,
}) {
  if (sig == null) return Attribution(line: l.recordUnsigned);
  final added = kind == RecordKind.settlement
      ? l.recordRecordedBy
      : l.recordAddedBy;
  String name(String mxid) =>
      editorName(mxid, myMxid: myMxid, members: members, l: l);
  final parts = [
    if (origin != null) added(name(origin.user)),
    if (origin == null || updatedAt != createdAt)
      l.recordEditedBy(name(sig.user)),
  ];
  // The weakest of the two signatures decides the hint.
  String? hint;
  var problem = false;
  for (final s in [?origin, sig]) {
    final st = signatureStatus(s, keys, group: group).status;
    if (s.user == myMxid &&
        (st == SigStatus.unverified || st == SigStatus.conflict)) {
      return Attribution(
        line: parts.join(' · '),
        parts: parts,
        hint: l.recordNotYourDevice,
        problem: true,
      );
    }
    if (st == SigStatus.conflict) {
      hint = l.recordSigConflict(name(s.user));
      problem = true;
    } else if (st == SigStatus.unverified && !problem) {
      hint = l.recordSigUnverified;
    }
  }
  return Attribution(
    line: parts.join(' · '),
    parts: parts,
    hint: hint,
    problem: problem,
  );
}

/// Whether the list should flag a record (G6): a key conflict, or someone
/// claiming to be us from a device we don't know. Unverifiable signatures of
/// others are only shown on the edit page.
bool recordNeedsAttention({
  required RecordSignature? origin,
  required RecordSignature? sig,
  required String myMxid,
  required List<KnownKey> keys,
  String? group,
}) {
  for (final s in [?origin, ?sig]) {
    final st = signatureStatus(s, keys, group: group).status;
    if (st == SigStatus.conflict) return true;
    if (s.user == myMxid && st == SigStatus.unverified) return true;
  }
  return false;
}

/// "Added by X · Last edited by Y" for an expense / payment (G6), with a
/// warning for conflicts (G46: unverifiable signatures only in the details), a
/// details dialog (device + how it was verified) and a notice when a newer
/// version was refused.
class RecordAttribution extends ConsumerWidget {
  const RecordAttribution({
    super.key,
    required this.groupId,
    required this.kind,
    required this.recordId,
    required this.origin,
    required this.sig,
    required this.createdAt,
    required this.updatedAt,
    this.members,
  });

  /// The group's participants when the caller already has them (avoids a
  /// second members stream); else watched from the DB.
  final List<MemberModel>? members;

  final String groupId;
  final RecordKind kind;
  final String recordId;
  final RecordSignature? origin;
  final RecordSignature? sig;
  final int createdAt;
  final int updatedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // G40: local mode signs nothing and everything is "you" — no footer.
    if (ref.watch(localModeActiveProvider)) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
    final members =
        this.members ??
        ref.watch(groupMembersProvider(groupId)).value ??
        const <MemberModel>[];
    final keys = ref.watch(knownDeviceKeysProvider).value ?? const [];
    final trusted = ref.watch(trustedDevicesProvider).value ?? const {};
    final me = ref.watch(currentUserIdProvider);
    final rejected = ref
        .watch(
          rejectedVersionProvider((group: groupId, kind: kind, id: recordId)),
        )
        .value;
    final a = attributionFor(
      origin: origin,
      sig: sig,
      createdAt: createdAt,
      updatedAt: updatedAt,
      myMxid: me,
      members: members,
      keys: keys,
      l: l,
      kind: kind,
      group: groupId,
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    String name(String mxid) =>
        editorName(mxid, myMxid: me, members: members, l: l);
    return Column(
      key: const Key('recordAttribution'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _AttributionLine(a, style: muted)),
            if (sig != null)
              IconButton(
                key: const Key('recordSignatureInfo'),
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                tooltip: l.recordSignatureDetails,
                icon: Icon(
                  a.problem ? Icons.gpp_maybe_outlined : Icons.info_outline,
                  color: a.problem ? theme.colorScheme.error : null,
                ),
                onPressed: () => _showDetails(context, keys, name, me, trusted),
              ),
          ],
        ),
        // G46: only a real problem shows under the line; an unverifiable
        // (accepted) signature is in the details dialog only.
        if (a.hint != null && a.problem)
          Text(
            a.hint!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        if (rejected != null && rejected.updatedAt > updatedAt) ...[
          const SizedBox(height: Insets.xs),
          Text(
            l.recordVersionRejected(
              name(rejected.relayedBy),
              name(rejected.claimedSigner ?? rejected.relayedBy),
            ),
            key: const Key('recordVersionRejected'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  void _showDetails(
    BuildContext context,
    List<KnownKey> keys,
    String Function(String) name,
    String me,
    Set<SignerId> trusted,
  ) {
    final l = context.l10n;
    String statusText(RecordSignature s) {
      final st = signatureStatus(s, keys, group: groupId);
      return switch (st.status) {
        SigStatus.verified => l.recordSigVerified,
        SigStatus.vouched => l.recordSigVouched(name(st.vouchedBy ?? '')),
        SigStatus.conflict => l.recordSigConflict(name(s.user)),
        SigStatus.unverified => l.recordSigUnverified,
        SigStatus.legacy => l.recordUnsigned,
      };
    }

    Widget block(String title, RecordSignature s, int at) => Padding(
      padding: const EdgeInsets.only(bottom: Insets.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          Text(l.recordSignedByDevice(s.device, context.date(at))),
          Text(statusText(s)),
          if (signerVerifiedByMe(s, myMxid: me, trusted: trusted)
              case final byMe?)
            Text(
              byMe
                  ? l.recordDeviceVerifiedByYou
                  : l.recordDeviceNotVerifiedByYou,
            ),
        ],
      ),
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.recordSignatureDetails),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (origin != null)
              block(
                kind == RecordKind.settlement
                    ? l.recordRecordedBy(name(origin!.user))
                    : l.recordAddedBy(name(origin!.user)),
                origin!,
                createdAt,
              ),
            if (sig != null)
              block(l.recordEditedBy(name(sig!.user)), sig!, updatedAt),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
  }
}

/// The attribution line: "Added by X · Last edited by Y" on one line when it
/// fits, else wrapped **between** the parts, each ellipsized — never a long
/// name broken across lines (G33). A [Wrap], not a LayoutBuilder: this also
/// sits in dialogs, which measure intrinsic widths.
class _AttributionLine extends StatelessWidget {
  const _AttributionLine(this.a, {this.style});
  final Attribution a;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (a.parts.length < 2) return Text(a.line, style: style);
    return Semantics(
      label: a.line,
      excludeSemantics: true,
      child: Wrap(
        spacing: Insets.xs,
        children: [
          for (var i = 0; i < a.parts.length; i++)
            Text(
              i < a.parts.length - 1 ? '${a.parts[i]} ·' : a.parts[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
        ],
      ),
    );
  }
}
