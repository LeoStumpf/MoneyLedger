/// G74: the user's own payment details (device-local, per ledger).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../onboarding/onboarding_provider.dart' show settingsDaoProvider;
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
