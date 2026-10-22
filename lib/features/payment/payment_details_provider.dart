/// G74: the user's own payment details (device-local, per ledger).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../onboarding/onboarding_provider.dart' show settingsDaoProvider;
import '../../models/member_model.dart';
import 'payment_details.dart';

/// The stored details, or null when none are set.
final myPaymentDetailsProvider = StreamProvider.autoDispose<PaymentDetails?>(
  (ref) => ref
      .watch(settingsDaoProvider)
      .watchPaymentDetailsRaw()
      .map(PaymentDetails.decode),
);

/// Stores [details] for the current ledger; an empty one clears them.
Future<void> savePaymentDetails(WidgetRef ref, PaymentDetails details) {
  final dao = ref.read(settingsDaoProvider);
  if (details == PaymentDetails.empty) return dao.clearPaymentDetails();
  return dao.setPaymentDetailsRaw(details.encode());
}

/// G74: participant id → the payment details a debt owed to them can be
/// paid with — each participant's synced `payment` field, and for [myId]
/// my own settings ([mine]) first. Participants without usable details are
/// absent.
Map<String, PaymentDetails> creditorPaymentDetails(
  List<MemberModel> members, {
  required String myId,
  PaymentDetails? mine,
}) => {
  for (final m in members)
    if (m.payment case final p? when !p.isEmpty) m.userId: p,
  if (mine != null && !mine.isEmpty && myId.isNotEmpty) myId: mine,
};
