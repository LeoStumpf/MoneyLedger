import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/matrix/transport_provider.dart';
import '../expenses/expenses_provider.dart';
import '../groups/group_provider.dart';
import 'balance_calculator.dart';
import 'balance_provider.dart';
import 'record_payment_dialog.dart';

class BalancePage extends ConsumerStatefulWidget {
  final String roomId;
  const BalancePage({super.key, required this.roomId});

  @override
  ConsumerState<BalancePage> createState() => _BalancePageState();
}

class _BalancePageState extends ConsumerState<BalancePage> {
  @override
  Widget build(BuildContext context) {
    final debts = ref.watch(balanceForRoomProvider(widget.roomId));
    final names = ref.watch(participantNamesProvider(widget.roomId));
    final transport = ref.watch(ledgerTransportProvider).value;
    // "Me" is this device's participant in the group (id may differ from the
    // MXID once a local slot has been claimed); fall back to the raw MXID.
    final me = ref.watch(currentParticipantProvider(widget.roomId)).value;
    final myId = me?.userId ?? transport?.userId ?? '';
    // G28: any active member may record a payment between any two
    // participants. G26: removed from the group → read-only, nothing to record.
    final canRecord = me?.isActive ?? true;
    final adderState = ref.watch(expenseAdderProvider);
    final busy = adderState.isLoading;
    // Kept alive for the dialog: members (choices) + group (default currency).
    ref.watch(groupMembersProvider(widget.roomId));
    ref.watch(ledgerGroupsProvider);
    String nameOf(String id) => names[id] ?? id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Balance'),
        actions: [
          if (canRecord)
            IconButton(
              key: const Key('recordPayment'),
              icon: const Icon(Icons.payments_outlined),
              tooltip: 'Record payment',
              onPressed: busy ? null : () => _recordPayment(context, myId),
            ),
        ],
      ),
      body: Stack(
        children: [
          debts.isEmpty
              ? const Center(child: Text('All settled up!'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: debts.length,
                  itemBuilder: (context, i) {
                    final d = debts[i];
                    final amount = (d.cents / 100).toStringAsFixed(2);
                    final currency = d.currency;
                    final isMine = d.from == myId;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          Icons.arrow_forward,
                          color: isMine ? Colors.red : Colors.grey,
                        ),
                        title: Text(
                          nameOf(d.from),
                          style: TextStyle(
                            fontWeight: isMine
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text('owes ${nameOf(d.to)}'),
                        trailing: Text(
                          '$amount $currency',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  color: isMine
                                      ? Colors.red
                                      : Colors.grey[700]),
                        ),
                        // Any debt — ours, a local person's, or one owed to
                        // us — can be settled by recording the payment.
                        onTap: canRecord && !busy
                            ? () => _recordPayment(context, myId, debt: d)
                            : null,
                      ),
                    );
                  },
                ),
          // Overlay spinner while the settlement event is being sent.
          if (busy)
            const ColoredBox(
              color: Colors.black26,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  /// Opens the payment dialog — prefilled from [debt] (debtor → creditor, the
  /// owed amount) or, from the app-bar action, with us as the payer — and
  /// records the confirmed payment as a settlement.
  Future<void> _recordPayment(BuildContext context, String myId,
      {DebtEntry? debt}) async {
    final messenger = ScaffoldMessenger.of(context);
    final members =
        ref.read(groupMembersProvider(widget.roomId)).value ?? const [];
    final names = ref.read(participantNamesProvider(widget.roomId));
    final group = (ref.read(ledgerGroupsProvider).value ?? const [])
        .where((g) => g.roomId == widget.roomId)
        .firstOrNull;
    // Active participants (claimed and local); a tapped debt may involve a
    // former member, who stays selectable for that payment.
    final participants = <String, String>{
      for (final m in members)
        if (m.isActive) m.userId: names[m.userId] ?? m.userId,
      if (debt != null) debt.from: names[debt.from] ?? debt.from,
      if (debt != null) debt.to: names[debt.to] ?? debt.to,
    };
    final ids = participants.keys.toList();
    final defaultFrom = participants.containsKey(myId)
        ? myId
        : (ids.isNotEmpty ? ids.first : null);
    final defaultTo =
        ids.where((id) => id != defaultFrom).firstOrNull;

    final draft = await showDialog<PaymentDraft>(
      context: context,
      builder: (_) => RecordPaymentDialog(
        participants: participants,
        initialFrom: debt?.from ?? defaultFrom,
        initialTo: debt?.to ?? defaultTo,
        initialCents: debt?.cents,
        debtCents: debt?.cents,
        currency: debt?.currency ?? group?.currency ?? 'EUR',
      ),
    );
    if (draft == null || !mounted) return;

    await ref.read(expenseAdderProvider.notifier).addSettlement(
          roomId: widget.roomId,
          amountCents: draft.cents,
          currency: draft.currency,
          fromUser: draft.from,
          toUser: draft.to,
        );

    if (!mounted) return;
    final error = ref.read(expenseAdderProvider).error;
    messenger.showSnackBar(SnackBar(
        content: Text(error != null ? 'Failed: $error' : 'Payment recorded')));
  }
}
