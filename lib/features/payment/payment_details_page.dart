/// G74: **Settings → Payment details** — the user's own bank account
/// (account holder, IBAN, optional BIC) and PayPal.me name. Optional,
/// stored device-local (per ledger) and written into my participant in
/// every group I'm active in (`payment_publisher.dart`, link groups too —
/// the page says anyone with a group's link can read them): the balance
/// page shows them as a GiroCode / PayPal.me QR code / link
/// (`payment_request_sheet.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/action_error.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/large_text.dart';
import 'payment_details.dart';
import 'payment_details_provider.dart';

/// Route of the payment details page.
const kPaymentDetailsLocation = '/settings/payment';

class PaymentDetailsPage extends ConsumerWidget {
  const PaymentDetailsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(myPaymentDetailsProvider);
    return Scaffold(
      appBar: AppBar(title: AppBarTitle(l.paymentDetailsPageTitle)),
      body: async.isLoading && !async.hasValue
          ? const Center(child: CircularProgressIndicator())
          : PaymentDetailsForm(initial: async.value ?? PaymentDetails.empty),
    );
  }
}

/// The form itself (initialised once from [initial]).
class PaymentDetailsForm extends ConsumerStatefulWidget {
  const PaymentDetailsForm({super.key, required this.initial});

  final PaymentDetails initial;

  @override
  ConsumerState<PaymentDetailsForm> createState() => _PaymentDetailsFormState();
}

class _PaymentDetailsFormState extends ConsumerState<PaymentDetailsForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial.name);
  late final _iban = TextEditingController(
    text: widget.initial.iban == null ? '' : formatIban(widget.initial.iban!),
  );
  late final _bic = TextEditingController(text: widget.initial.bic);
  late final _paypal = TextEditingController(text: widget.initial.paypalMe);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _iban.dispose();
    _bic.dispose();
    _paypal.dispose();
    super.dispose();
  }

  String? _trimmed(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  /// The details the form holds (only meaningful once it validates).
  PaymentDetails _details() {
    final iban = _trimmed(_iban);
    final bic = _trimmed(_bic);
    final paypal = _trimmed(_paypal);
    return PaymentDetails(
      name: _trimmed(_name),
      iban: iban == null ? null : normalizeIban(iban),
      bic: bic == null ? null : normalizeBic(bic),
      paypalMe: paypal == null ? null : normalizePaypalMe(paypal),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l = context.l10n;
    final errors = ActionErrors.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final details = _details();
    setState(() => _saving = true);
    try {
      await savePaymentDetails(ref, details);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      errors.show(e);
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          details == PaymentDetails.empty
              ? l.paymentDetailsCleared
              : l.paymentDetailsSaved,
        ),
      ),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      setState(() => _saving = false);
    }
  }

  void _clear() {
    for (final c in [_name, _iban, _bic, _paypal]) {
      c.clear();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget gap() => const SizedBox(height: Insets.l);
    return ContentWidth(
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          key: const Key('paymentDetailsList'),
          padding: EdgeInsets.fromLTRB(
            Insets.page,
            Insets.m,
            Insets.page,
            Insets.xl + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Text(
              l.paymentDetailsIntro,
              key: const Key('paymentDetailsIntro'),
              style: muted,
            ),
            const SizedBox(height: Insets.s),
            Text(
              l.paymentDetailsLinkWarning,
              key: const Key('paymentDetailsLinkWarning'),
              style: muted,
            ),
            gap(),
            Semantics(
              header: true,
              child: Text(
                l.paymentBankSection,
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: Insets.s),
            TextFormField(
              key: const Key('paymentNameField'),
              controller: _name,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              maxLength: 70,
              decoration: InputDecoration(labelText: l.paymentNameLabel),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty && _iban.text.trim().isNotEmpty) {
                  return l.paymentNameRequired;
                }
                return null;
              },
            ),
            const SizedBox(height: Insets.s),
            TextFormField(
              key: const Key('paymentIbanField'),
              controller: _iban,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l.paymentIbanLabel,
                hintText: 'DE89 3704 0044 0532 0130 00',
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return null;
                return isValidIban(normalizeIban(t))
                    ? null
                    : l.paymentIbanInvalid;
              },
            ),
            const SizedBox(height: Insets.s),
            TextFormField(
              key: const Key('paymentBicField'),
              controller: _bic,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l.paymentBicLabel,
                helperText: l.paymentBicHelper,
                helperMaxLines: 3,
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return null;
                return isValidBic(normalizeBic(t)) ? null : l.paymentBicInvalid;
              },
            ),
            gap(),
            Semantics(
              header: true,
              child: Text(
                l.paymentPaypalSection,
                style: theme.textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: Insets.s),
            TextFormField(
              key: const Key('paymentPaypalField'),
              controller: _paypal,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: l.paymentPaypalLabel,
                prefixText: 'paypal.me/',
                helperText: l.paymentPaypalHelper,
                helperMaxLines: 3,
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return null;
                return normalizePaypalMe(t) == null
                    ? l.paymentPaypalInvalid
                    : null;
              },
              onFieldSubmitted: (_) => _save(),
            ),
            gap(),
            FilledButton(
              key: const Key('paymentDetailsSave'),
              onPressed: _saving ? null : _save,
              child: Text(l.save),
            ),
            if (widget.initial != PaymentDetails.empty)
              TextButton(
                key: const Key('paymentDetailsClear'),
                onPressed: _saving ? null : _clear,
                child: Text(l.paymentDetailsClear),
              ),
          ],
        ),
      ),
    );
  }
}
