import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../auth/auth_provider.dart';

/// TEMPORARY — Phase B0 spike. Validates the roomless encrypted to-device path
/// (device discovery + send + receive) against a real homeserver, before
/// committing to the Phase B transport rewrite. Delete this file, its route in
/// `core/router.dart`, and the debug button in `groups_page.dart` once the
/// roomless relay is validated. See ~/.claude/plans/vectorized-tinkering-moon.md.
const _spikePingType = 'com.moneyledger.spike.ping';

class ToDeviceSmokePage extends ConsumerStatefulWidget {
  const ToDeviceSmokePage({super.key});

  @override
  ConsumerState<ToDeviceSmokePage> createState() => _ToDeviceSmokePageState();
}

class _ToDeviceSmokePageState extends ConsumerState<ToDeviceSmokePage> {
  final _targetCtrl = TextEditingController();
  final _log = <String>[];
  StreamSubscription<ToDeviceEvent>? _sub;
  bool _wired = false;

  void _append(String line) {
    if (!mounted) return;
    setState(() => _log.insert(
        0, '${DateTime.now().toIso8601String().substring(11, 19)}  $line'));
  }

  /// One-time wiring once the client is available (called from build's data
  /// branch). Avoids setState here — build is already in progress.
  void _wire(Client client) {
    if (_wired) return;
    _wired = true;
    _targetCtrl.text = client.userID ?? '';
    _sub = client.onToDeviceEvent.stream
        .where((e) => e.type == _spikePingType)
        .listen((e) => _append('PING IN  from ${e.sender}: ${e.content}'));
    _log.insert(
        0,
        'Ready. mxid=${client.userID} device=${client.deviceID} '
            'e2ee=${client.encryptionEnabled}');
  }

  Future<void> _resolve(Client client) async {
    final target = _targetCtrl.text.trim();
    if (target.isEmpty) return;
    _append('Resolving devices for $target ...');
    try {
      await client.updateUserDeviceKeys(additionalUsers: {target});
      final devices =
          client.userDeviceKeys[target]?.deviceKeys.values.toList() ??
              <DeviceKeys>[];
      _append('OK ${devices.length} device(s) for $target:');
      for (final d in devices) {
        _append('   - ${d.deviceId} curve25519=${d.curve25519Key != null} '
            'verified=${d.verified} blocked=${d.blocked}');
      }
      if (devices.isEmpty) {
        _append('   (none - user has no app/keys, or query blocked)');
      }
    } catch (e) {
      _append('FAIL resolve: $e');
    }
  }

  Future<void> _sendPing(Client client) async {
    final target = _targetCtrl.text.trim();
    if (target.isEmpty) return;
    if (!client.encryptionEnabled) {
      _append('FAIL encryption not enabled - sendToDeviceEncrypted is a no-op');
      return;
    }
    final devices = client.userDeviceKeys[target]?.deviceKeys.values.toList() ??
        <DeviceKeys>[];
    if (devices.isEmpty) {
      _append('No known devices for $target - tap "Resolve devices" first.');
      return;
    }
    _append('Sending ping to ${devices.length} device(s) of $target '
        '(your current device is auto-excluded) ...');
    try {
      await client.sendToDeviceEncrypted(devices, _spikePingType, {
        'msg': 'hello from MoneyLedger spike',
        'from': client.userID,
        'ts': DateTime.now().toIso8601String(),
      });
      _append('OK send completed (no error)');
    } catch (e) {
      _append('FAIL send: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _targetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clientAsync = ref.watch(matrixClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('to-device spike (debug)')),
      body: clientAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Client error: $e')),
        data: (client) {
          _wire(client);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _targetCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Target MXID',
                    hintText: '@friend:matrix.org',
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _resolve(client),
                      child: const Text('Resolve devices'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _sendPing(client),
                      child: const Text('Send ping'),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                const Text(
                  'Receive needs a 2nd app instance (other account/device): '
                  'enter each other\'s MXID and tap Send on both.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: _log.length,
                    itemBuilder: (_, i) => Text(
                      _log[i],
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
