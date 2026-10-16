import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/matrix/device_gateway.dart';
import 'device_provider.dart';

/// Security screen (Phase F): lists the user's own Matrix devices with their
/// verified status and lets them run an SAS (emoji) verification against an
/// unverified session. Verification is **visibility + manual**, not enforced —
/// replication still reaches unverified devices.
class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(myDevicesProvider);
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l.devicesTitle)),
      body: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text(l.couldNotLoadDevices(e.toString()))),
        data: (devices) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                deviceTrustSummary(devices, l),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            for (final d in devices) _DeviceTile(device: d),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends ConsumerWidget {
  final DeviceInfo device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = device.isThisDevice
        ? (Icons.smartphone, scheme.primary)
        : device.verified
        ? (Icons.verified_user, scheme.primary)
        : (Icons.gpp_maybe, scheme.error);

    final l = context.l10n;
    final status = device.isThisDevice
        ? l.thisDevice
        : device.verified
        ? l.verified
        : l.notVerified;

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(device.label),
      subtitle: Text('${device.deviceId} • $status'),
      trailing: device.needsVerification
          ? TextButton(
              onPressed: () => _startVerification(context, ref),
              child: Text(l.verify),
            )
          : null,
    );
  }

  Future<void> _startVerification(BuildContext context, WidgetRef ref) async {
    final gateway = await ref.read(deviceGatewayProvider.future);
    if (!context.mounted) return;
    final session = gateway.verifyDevice(device.deviceId);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VerificationDialog(session: session, device: device),
    );
    session.dispose();
    ref.invalidate(myDevicesProvider); // refresh verified state
  }
}

/// Drives the SAS exchange from the [VerificationSession] stream.
class _VerificationDialog extends StatelessWidget {
  final VerificationSession session;
  final DeviceInfo device;
  const _VerificationDialog({required this.session, required this.device});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VerificationState>(
      stream: session.updates,
      builder: (context, snapshot) {
        final state =
            snapshot.data ??
            const VerificationState(VerificationPhase.starting);
        return AlertDialog(
          title: Text(context.l10n.verifyDeviceTitle(device.label)),
          content: _content(context, state),
          actions: _actions(context, state),
        );
      },
    );
  }

  Widget _content(BuildContext context, VerificationState state) {
    final l = context.l10n;
    switch (state.phase) {
      case VerificationPhase.starting:
        return const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        );
      case VerificationPhase.compareEmojis:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.verifyCompareEmoji),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                for (final e in state.emojis)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(e.emoji, style: const TextStyle(fontSize: 30)),
                      Text(
                        e.name,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
              ],
            ),
          ],
        );
      case VerificationPhase.success:
        return Text(l.deviceVerified);
      case VerificationPhase.failed:
        return Text(
          state.error != null
              ? l.verificationFailedWithError(state.error.toString())
              : l.verificationFailed,
        );
    }
  }

  List<Widget> _actions(BuildContext context, VerificationState state) {
    final l = context.l10n;
    switch (state.phase) {
      case VerificationPhase.compareEmojis:
        return [
          TextButton(
            onPressed: () {
              session.cancel();
              Navigator.pop(context);
            },
            child: Text(l.emojiNoMatch),
          ),
          FilledButton(
            onPressed: () => session.confirmMatch(),
            child: Text(l.emojiMatch),
          ),
        ];
      case VerificationPhase.success:
      case VerificationPhase.failed:
        return [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.done),
          ),
        ];
      case VerificationPhase.starting:
        return [
          TextButton(
            onPressed: () {
              session.cancel();
              Navigator.pop(context);
            },
            child: Text(l.cancel),
          ),
        ];
    }
  }
}
