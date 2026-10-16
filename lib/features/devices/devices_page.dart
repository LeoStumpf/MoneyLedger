import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/matrix/device_gateway.dart';
import '../auth/auth_provider.dart';
import 'device_provider.dart';

/// Security screen (Phase F): lists the user's own Matrix devices with their
/// verified status and lets them run an SAS (emoji) verification against an
/// unverified session. Enforced only when the opt-in "Only sync with
/// verified devices" (G11, settings sheet) is on — then unverified devices
/// receive nothing.
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

  Future<void> _startVerification(BuildContext context, WidgetRef ref) =>
      startDeviceVerification(context, ref, device);
}

/// Starts an SAS verification of [device] (own or, G11, another member's —
/// `device.userId`), shows the emoji dialog and records the result in this
/// account's verified-device list.
Future<void> startDeviceVerification(
  BuildContext context,
  WidgetRef ref,
  DeviceInfo device,
) async {
  final record = ref.read(deviceTrustRecorderProvider);
  final gateway = await ref.read(deviceGatewayProvider.future);
  if (!context.mounted) return;
  final session = recordingTrust(
    gateway.verifyDevice(
      device.deviceId,
      userId: device.userId.isEmpty ? null : device.userId,
    ),
    record,
  );
  await showVerificationDialog(context, session, device.label);
  _refreshDeviceState(ref);
}

void _refreshDeviceState(WidgetRef ref) {
  ref.invalidate(myDevicesProvider);
  ref.invalidate(memberDevicesProvider);
}

/// Shows the SAS dialog for [session] until the user closes it, then
/// disposes the session.
Future<void> showVerificationDialog(
  BuildContext context,
  VerificationSession session,
  String label,
) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VerificationDialog(session: session, label: label),
  );
  session.dispose();
}

/// G11: another member's devices (read-only list + Verify per unverified
/// device) in a bottom sheet — opened from the members page.
Future<void> showMemberDevicesSheet(
  BuildContext context, {
  required String matrixId,
  required String name,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _MemberDevicesSheet(matrixId: matrixId, name: name),
);

class _MemberDevicesSheet extends ConsumerWidget {
  const _MemberDevicesSheet({required this.matrixId, required this.name});
  final String matrixId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final devicesAsync = ref.watch(memberDevicesProvider(matrixId));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(l.memberDevicesTitle(name)),
              subtitle: Text(l.memberDevicesBody),
            ),
            devicesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) =>
                  ListTile(title: Text(l.couldNotLoadDevices(e.toString()))),
              data: (devices) => devices.isEmpty
                  ? ListTile(title: Text(l.memberHasNoDevices))
                  : Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final d in devices) _DeviceTile(device: d),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// G11: answers verification requests from other devices (our own, or a
/// member verifying this device) app-wide: asks the user, then runs the same
/// emoji dialog. Mounted in `App`'s builder; [navigatorContext] resolves a
/// context below the router's Navigator.
class IncomingVerificationListener extends ConsumerStatefulWidget {
  const IncomingVerificationListener({
    super.key,
    required this.navigatorContext,
    required this.child,
  });

  final BuildContext? Function() navigatorContext;
  final Widget child;

  @override
  ConsumerState<IncomingVerificationListener> createState() =>
      _IncomingVerificationListenerState();
}

class _IncomingVerificationListenerState
    extends ConsumerState<IncomingVerificationListener> {
  StreamSubscription<IncomingVerification>? _sub;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<DeviceGateway>>(
      deviceGatewayProvider,
      (_, next) => _attach(next.value),
      fireImmediately: true,
    );
  }

  void _attach(DeviceGateway? gateway) {
    _sub?.cancel();
    _sub = gateway?.incomingVerifications.listen(_onRequest);
  }

  Future<void> _onRequest(IncomingVerification request) async {
    final context = widget.navigatorContext();
    if (_busy || context == null || !context.mounted) {
      await request.reject();
      return;
    }
    _busy = true;
    try {
      final l = context.l10n;
      final me = ref.read(accountUserIdProvider);
      final who = request.userId == me
          ? l.incomingVerificationOwnDevice(request.deviceId ?? '?')
          : l.incomingVerificationMember(
              request.userId,
              request.deviceId ?? '?',
            );
      final accept = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(l.incomingVerificationTitle),
          content: Text(who),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.decline),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.accept),
            ),
          ],
        ),
      );
      if (accept != true) {
        await request.reject();
        return;
      }
      if (!context.mounted) return;
      final session = recordingTrust(
        request.accept(),
        ref.read(deviceTrustRecorderProvider),
      );
      await showVerificationDialog(
        context,
        session,
        request.deviceId ?? request.userId,
      );
      if (mounted) _refreshDeviceState(ref);
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Drives the SAS exchange from the [VerificationSession] stream.
class _VerificationDialog extends StatelessWidget {
  final VerificationSession session;
  final String label;
  const _VerificationDialog({required this.session, required this.label});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VerificationState>(
      stream: session.updates,
      builder: (context, snapshot) {
        final state =
            snapshot.data ??
            const VerificationState(VerificationPhase.starting);
        return AlertDialog(
          title: Text(context.l10n.verifyDeviceTitle(label)),
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
