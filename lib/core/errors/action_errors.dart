/// Friendly messages for failed user actions (G67, U25) — the counterpart of
/// `describeAuthError` (G20) for everything after sign-in: saving, deleting,
/// adding people, export / import / restore, …
///
/// No widgets: [classifyActionError] sorts an error into a few
/// [ActionErrorKind]s — by its type where the app defines it, else by its
/// text (platform / database errors aren't imported here, and their type
/// names are minified on the web). [describeActionError] adds the localized
/// title + hint; the raw text stays available as [ActionErrorMessage.detail]
/// for the "Details" affordance only.
library;

import 'dart:async';

import '../../features/expenses/expenses_provider.dart'
    show RecordDeletedException;
import '../../features/groups/group_provider.dart' show LinkOnlyGroupException;
import '../../l10n/app_localizations.dart';
import '../link/link_snapshot.dart' show LinkSnapshotTooLargeException;
import '../matrix/ledger_transport.dart' show TransportUnavailableException;
import '../sync/payload_budget.dart' show PayloadTooLargeException;
import '../sync/record_signing.dart' show SignatureRequiredException;

enum ActionErrorKind {
  /// The ledger DB closed / the account switched while the action ran.
  interrupted,

  /// Nothing can be sent: signed out / encryption not ready.
  relayUnavailable,

  /// The record was deleted meanwhile (G60).
  recordGone,

  /// A message over the homeserver's size limit (G14).
  tooLarge,

  /// A Matrix membership change in a link-only group (G52).
  linkOnly,

  /// G53: the change must be signed (mixed / locked group) and this device
  /// has no Matrix account.
  signatureRequired,

  /// Reading / writing a file failed.
  file,

  /// The local database reported an error.
  storage,
  timeout,
  network,

  /// Malformed data (not JSON, wrong format …).
  invalidData,
  unknown,
}

/// A classified error, ready to show: [title] + optional [hint], with the
/// raw technical [detail] behind "Details".
class ActionErrorMessage {
  const ActionErrorMessage(
    this.kind, {
    required this.title,
    this.hint,
    this.detail,
  });

  final ActionErrorKind kind;
  final String title;
  final String? hint;
  final String? detail;

  @override
  String toString() => 'ActionErrorMessage($kind)';
}

bool _has(String s, List<String> needles) => needles.any(s.contains);

/// The kind of [error] (see [ActionErrorKind]). Pure.
ActionErrorKind classifyActionError(Object error) {
  if (error is RecordDeletedException) return ActionErrorKind.recordGone;
  if (error is TransportUnavailableException) {
    return ActionErrorKind.relayUnavailable;
  }
  if (error is PayloadTooLargeException ||
      error is LinkSnapshotTooLargeException) {
    return ActionErrorKind.tooLarge;
  }
  if (error is LinkOnlyGroupException) return ActionErrorKind.linkOnly;
  if (error is SignatureRequiredException) {
    return ActionErrorKind.signatureRequired;
  }
  if (error is TimeoutException) return ActionErrorKind.timeout;
  if (error is FormatException) return ActionErrorKind.invalidData;

  final s = error.toString();
  final lower = s.toLowerCase();
  if (_has(s, const [
    'FileSystemException',
    'PathAccessException',
    'PathNotFoundException',
    'PathExistsException',
  ])) {
    return ActionErrorKind.file;
  }
  if (_has(s, const [
        'SocketException',
        'ClientException',
        'HandshakeException',
      ]) ||
      _has(lower, const [
        'failed host lookup',
        'connection refused',
        'network is unreachable',
        'connection reset',
        'xmlhttprequest error',
      ])) {
    return ActionErrorKind.network;
  }
  if (error is StateError &&
          _has(lower, const [
            'closed',
            'switched',
            'no ledger database',
            'no matrix account signed in',
          ]) ||
      _has(lower, const [
        "can't re-open a database",
        'database is closed',
        'database has been closed',
      ])) {
    return ActionErrorKind.interrupted;
  }
  if (_has(s, const [
        'SqliteException',
        'DriftWrappedException',
        'DriftRemoteException',
        'CouldNotRollBackException',
      ]) ||
      _has(lower, const [
        'database is locked',
        'database or disk is full',
        'disk i/o error',
        'no space left',
        'disk full',
      ])) {
    return ActionErrorKind.storage;
  }
  if (_has(s, const ['TimeoutException'])) return ActionErrorKind.timeout;
  return ActionErrorKind.unknown;
}

/// [error] as a friendly, localized message (G67). The raw text is only
/// the [ActionErrorMessage.detail].
ActionErrorMessage describeActionError(Object error, AppLocalizations l) {
  final kind = classifyActionError(error);
  final (title, hint) = switch (kind) {
    ActionErrorKind.interrupted => (
      l.errorInterruptedTitle,
      l.errorInterruptedHint,
    ),
    ActionErrorKind.relayUnavailable => (l.errorRelayTitle, l.errorRelayHint),
    ActionErrorKind.recordGone => (
      l.errorRecordGoneTitle,
      l.errorRecordGoneHint,
    ),
    ActionErrorKind.tooLarge => (l.errorTooLargeTitle, l.errorTooLargeHint),
    ActionErrorKind.linkOnly => (l.errorLinkOnlyTitle, l.errorLinkOnlyHint),
    ActionErrorKind.signatureRequired => (
      l.errorSignatureRequiredTitle,
      l.errorSignatureRequiredHint,
    ),
    ActionErrorKind.file => (l.errorFileTitle, l.errorFileHint),
    ActionErrorKind.storage => (l.errorStorageTitle, l.errorStorageHint),
    ActionErrorKind.timeout => (l.errorTimeoutTitle, l.errorTimeoutHint),
    ActionErrorKind.network => (l.errorNetworkTitle, l.errorNetworkHint),
    ActionErrorKind.invalidData => (
      l.errorInvalidDataTitle,
      l.errorInvalidDataHint,
    ),
    ActionErrorKind.unknown => (l.errorUnknownTitle, l.errorUnknownHint),
  };
  final detail = error.toString();
  return ActionErrorMessage(
    kind,
    title: title,
    hint: hint,
    detail: detail.isEmpty ? null : detail,
  );
}
