/// G74: "{name} pays you {amount}" — the user's own payment details for
/// one debt owed to them, shown **on this device** for the payer to scan:
/// a GiroCode (EPC QR, euro + bank account; scanned by a banking app) and /
/// or a PayPal.me link with the amount (QR + *Share link*). For another
/// currency the bank account is shown as text (GiroCode is euro only).
/// Nothing is sent anywhere unless the user shares the link himself.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/platform/text_sharer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/qr_code_view.dart';
import '../balance/balance_calculator.dart';
import 'payment_details.dart';

enum PaymentMethod { bank, paypal }

/// The methods [details] offers, bank account first.
List<PaymentMethod> paymentMethodsFor(PaymentDetails details) => [
  if (details.hasBankAccount) PaymentMethod.bank,
  if (details.hasPaypal) PaymentMethod.paypal,
];

/// Opens the sheet for [debt] (owed to the user by [payerName]).
Future<void> showPaymentRequestSheet(
  BuildContext context, {
  required PaymentDetails details,
  required DebtEntry debt,
  required String payerName,
  required String groupName,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => PaymentRequestSheet(
    details: details,
    debt: debt,
    payerName: payerName,
    groupName: groupName,
  ),
);

class PaymentRequestSheet extends ConsumerStatefulWidget {
  const PaymentRequestSheet({
    super.key,
    required this.details,
    required this.debt,
    required this.payerName,
    required this.groupName,
  });

  final PaymentDetails details;
  final DebtEntry debt;
  final String payerName;
  final String groupName;

  @override
  ConsumerState<PaymentRequestSheet> createState() =>
      _PaymentRequestSheetState();
}

class _PaymentRequestSheetState extends ConsumerState<PaymentRequestSheet> {
  late PaymentMethod _method = paymentMethodsFor(widget.details).first;

  Future<void> _copy(String text) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger?.showSnackBar(SnackBar(content: Text(l.copiedToClipboard)));
  }

  Future<void> _share(String text) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final outcome = await shareOrCopy(ref.read(textSharerProvider), text);
    if (outcome == ShareOutcome.copied) {
      messenger?.showSnackBar(SnackBar(content: Text(l.shareCopiedFallback)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final d = widget.details;
    final debt = widget.debt;
    final methods = paymentMethodsFor(d);
    final amount = context.money(debt.cents, debt.currency);
    // A QR code never wider than the sheet (360 dp, 200 % font).
    final qrSize = (MediaQuery.sizeOf(context).width - 2 * Insets.page).clamp(
      120.0,
      240.0,
    );

    Widget body;
    switch (_method) {
      case PaymentMethod.bank:
        final epc = epcQrPayload(
          d,
          cents: debt.cents,
          currency: debt.currency,
          remittance: widget.groupName,
        );
        body = Column(
          key: const Key('paymentBankBody'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (epc != null) ...[
              QrCodeView(
                key: const Key('paymentGiroCode'),
                data: epc,
                semanticLabel: l.paymentGiroCodeSemantics(amount),
                size: qrSize,
              ),
              const SizedBox(height: Insets.s),
              Text(
                l.paymentGiroCodeHint,
                textAlign: TextAlign.center,
                style: muted,
              ),
            ] else
              Text(
                l.paymentGiroCodeEuroOnly,
                key: const Key('paymentGiroCodeEuroOnly'),
                textAlign: TextAlign.center,
                style: muted,
              ),
            const SizedBox(height: Insets.m),
            Text(
              d.name!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            Text(
              formatIban(d.iban!),
              key: const Key('paymentIbanText'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFeatures: kTabularFigures,
              ),
            ),
            if (d.bic != null)
              Text('BIC ${d.bic}', textAlign: TextAlign.center, style: muted),
            const SizedBox(height: Insets.s),
            TextButton.icon(
              key: const Key('paymentCopyIban'),
              onPressed: () => _copy(d.iban!),
              icon: const Icon(Icons.copy),
              label: Text(l.paymentCopyIban),
            ),
          ],
        );
      case PaymentMethod.paypal:
        final url = paypalMeUrl(
          d.paypalMe!,
          cents: debt.cents,
          currency: debt.currency,
        );
        body = Column(
          key: const Key('paymentPaypalBody'),
          mainAxisSize: MainAxisSize.min,
          children: [
            QrCodeView(
              key: const Key('paymentPaypalQr'),
              data: url,
              semanticLabel: l.paymentPaypalQrSemantics(amount),
              size: qrSize,
            ),
            const SizedBox(height: Insets.s),
            Text(
              l.paymentPaypalQrHint,
              textAlign: TextAlign.center,
              style: muted,
            ),
            const SizedBox(height: Insets.m),
            Text(
              url,
              key: const Key('paymentPaypalUrl'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Insets.s),
            TextButton.icon(
              key: const Key('paymentShareLink'),
              onPressed: () => _share(url),
              icon: const Icon(Icons.share_outlined),
              label: Text(l.paymentShareLink),
            ),
          ],
        );
    }

    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('paymentRequestSheet'),
        padding: const EdgeInsets.fromLTRB(
          Insets.page,
          0,
          Insets.page,
          Insets.l,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l.paymentRequestTitle(widget.payerName, amount),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: Insets.m),
            if (methods.length > 1) ...[
              Center(
                child: SegmentedButton<PaymentMethod>(
                  key: const Key('paymentMethodSwitch'),
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: PaymentMethod.bank,
                      label: Text(l.paymentMethodBank),
                    ),
                    ButtonSegment(
                      value: PaymentMethod.paypal,
                      label: Text(l.paymentMethodPaypal),
                    ),
                  ],
                  selected: {_method},
                  onSelectionChanged: (s) => setState(() => _method = s.first),
                ),
              ),
              const SizedBox(height: Insets.m),
            ],
            body,
            const SizedBox(height: Insets.s),
            Text(
              l.paymentRequestLocalNote,
              key: const Key('paymentRequestLocalNote'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
