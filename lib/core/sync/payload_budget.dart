import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// G14 — how big one ledger to-device payload may be (plain Dart).
///
/// **The real limit.** Synapse (matrix.org) rejects a `/sendToDevice` whose
/// content for any single (user, device) is larger than
/// `MAX_TO_DEVICE_CONTENT_SIZE` = **65536 bytes** of canonical JSON (HTTP 413,
/// "too large to send") — it must fit a federation EDU. The spec doesn't
/// state a limit yet (matrix-spec PR #2340), but every homeserver has to
/// stay below what federation can carry, so 64 KiB is the budget everywhere.
/// (The whole HTTP request — up to 20 devices per request in
/// `sendToDeviceEncryptedChunked` — is capped far higher, ~12.5 MB.)
///
/// **What counts** is the *encrypted* event content per device:
/// `{"algorithm", "sender_key", "ciphertext": {CURVE_KEY: {"type", "body"}}}`
/// where `body` is unpadded base64 of an Olm message whose plaintext is the
/// SDK's envelope `{"type", "content": PAYLOAD, "sender", "keys",
/// "recipient", "recipient_keys"}` (see
/// `OlmManager.encryptToDeviceMessagePayload`). So:
///
///     event ≈ 200 + 4/3 × (olm overhead ≈ 180 + envelope ≈ 400 + payload)
///
/// which puts the hard ceiling for our JSON payload at ≈ **48.5 KB** (UTF-8).
/// We aim for [kMaxPayloadBytes] (40 000 bytes) — ~18 % headroom for long
/// MXIDs, a pre-key Olm message and estimate error.
const kToDeviceContentLimit = 65536;

/// Fixed bytes around the ciphertext in the encrypted event content
/// (algorithm, 43-char sender key, recipient curve key, type, JSON syntax).
const _encryptedWrapperBytes = 200;

/// Olm message overhead (version, ratchet key, counter, MAC, AES-CBC padding;
/// a pre-key message adds the identity / one-time / base keys).
const _olmOverheadBytes = 180;

/// The SDK's plaintext envelope around our content: event type, sender /
/// recipient MXIDs and their Ed25519 keys (generous for long MXIDs).
const _envelopeBytes = 400;

/// The UTF-8 size of [content] as JSON — what the Olm plaintext contains.
int encodedPayloadBytes(Map<String, dynamic> content) =>
    utf8.encode(jsonEncode(content)).length;

/// Estimated size of the encrypted to-device event content for a payload of
/// [plainBytes] bytes (see the formula above) — compare with
/// [kToDeviceContentLimit].
int estimateEncryptedEventBytes(int plainBytes) =>
    _encryptedWrapperBytes +
    ((plainBytes + _olmOverheadBytes + _envelopeBytes) * 4 + 2) ~/ 3;

/// The largest payload whose encrypted event still fits
/// [kToDeviceContentLimit] (≈ 48.5 KB).
const kHardMaxPayloadBytes =
    ((kToDeviceContentLimit - _encryptedWrapperBytes) * 3) ~/ 4 -
    _olmOverheadBytes -
    _envelopeBytes;

/// The size bootstraps are chunked to and above which digests switch to
/// hash buckets.
const kMaxPayloadBytes = 40000;

/// The payload budget the sync code packs messages to. Injectable so tests
/// can force chunked bootstraps / bucketed digests with small groups.
final payloadBudgetProvider = Provider<int>((ref) => kMaxPayloadBytes);

/// Thrown by a transport for a payload whose encrypted event would exceed
/// [kToDeviceContentLimit] — the homeserver would refuse it (HTTP 413) and
/// the SDK would only log it. A sync fault (it counts against `SyncHealth`):
/// the senders chunk to [kMaxPayloadBytes], so this means a ceiling was hit
/// (e.g. a bootstrap header with hundreds of members).
class PayloadTooLargeException implements Exception {
  final String type;
  final int bytes;
  const PayloadTooLargeException(this.type, this.bytes);

  @override
  String toString() =>
      'Payload too large: $type is $bytes bytes '
      '(max ≈ $kHardMaxPayloadBytes per to-device message)';
}

/// Throws [PayloadTooLargeException] when [content] can't be sent as one
/// to-device message.
void checkPayloadSize(String type, Map<String, dynamic> content) {
  final bytes = encodedPayloadBytes(content);
  if (bytes > kHardMaxPayloadBytes) {
    throw PayloadTooLargeException(type, bytes);
  }
}
