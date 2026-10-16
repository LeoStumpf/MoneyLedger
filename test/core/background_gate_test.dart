/// G18 review (finding 7): the app ↔ background-round gate never lets the two
/// isolates use the stores at the same time — driven with in-isolate ports
/// on a fake registry (the real one is the process-wide IsolateNameServer).
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_ledger/core/background/background_gate.dart';

class _Registry implements PortRegistry {
  final ports = <String, SendPort>{};
  @override
  SendPort? lookup(String name) => ports[name];
  @override
  bool register(SendPort port, String name) {
    if (ports.containsKey(name)) return false;
    ports[name] = port;
    return true;
  }

  @override
  void remove(String name) => ports.remove(name);
}

const _main = 'io.github.leostumpf.moneyledger.main';
const _background = 'io.github.leostumpf.moneyledger.background';

void main() {
  late _Registry reg;
  final open = <ReceivePort>[];
  setUp(() => reg = _Registry());
  tearDown(() {
    for (final p in open) {
      p.close();
    }
    open.clear();
  });

  /// A registered side that never answers (busy / dead isolate).
  void silent(String name) {
    final p = ReceivePort();
    open.add(p);
    reg.register(p.sendPort, name);
  }

  test('the round never removes an unanswering app — it skips', () async {
    silent(_main);
    final gate = BackgroundIsolateGate(reg);
    expect(await gate.tryAcquire(), isFalse);
    expect(reg.lookup(_main), isNotNull, reason: 'mapping kept');
    expect(reg.lookup(_background), isNull);
  });

  test('the round never removes an unanswering round either', () async {
    silent(_background);
    expect(await BackgroundIsolateGate(reg).tryAcquire(), isFalse);
    expect(reg.lookup(_background), isNotNull);
  });

  test('the app waits until the round has closed its stores', () async {
    final round = BackgroundIsolateGate(reg);
    expect(await round.tryAcquire(), isTrue);
    var storesClosed = false;
    unawaited(
      round.abort.then((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        storesClosed = true;
        round.release();
      }),
    );
    var waiting = 0;
    final app = AppIsolateGate.withRegistry(reg);
    addTearDown(app.release);
    final ok = await app.claim(
      askTimeout: const Duration(milliseconds: 100),
      onWaiting: () => waiting++,
    );
    expect(ok, isTrue);
    expect(storesClosed, isTrue);
    expect(waiting, 1);
    expect(reg.lookup(_background), isNull);
  });

  test(
    'a stale round mapping (nothing answers) is removed by the app',
    () async {
      silent(_background);
      final app = AppIsolateGate.withRegistry(reg);
      addTearDown(app.release);
      final ok = await app.claim(
        askTimeout: const Duration(milliseconds: 50),
        staleAfter: const Duration(milliseconds: 300),
      );
      expect(ok, isTrue);
      expect(reg.lookup(_background), isNull);
    },
  );

  test('a round that answers but never stops: the app keeps waiting up to '
      'maxWait (no parallel open before that)', () async {
    final p = ReceivePort();
    open.add(p);
    p.listen((msg) {
      if (msg is List && msg[0] == 'ping') (msg[1] as SendPort).send('pong');
    });
    reg.register(p.sendPort, _background);
    final app = AppIsolateGate.withRegistry(reg);
    addTearDown(app.release);
    final sw = Stopwatch()..start();
    final ok = await app.claim(
      askTimeout: const Duration(milliseconds: 50),
      staleAfter: const Duration(milliseconds: 200),
      maxWait: const Duration(milliseconds: 600),
    );
    expect(ok, isFalse);
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(600));
    expect(reg.lookup(_background), isNotNull, reason: 'alive: not removed');
  });

  test('a round started while the app is registered is refused', () async {
    final app = AppIsolateGate.withRegistry(reg);
    addTearDown(app.release);
    expect(await app.claim(), isTrue);
    expect(await BackgroundIsolateGate(reg).tryAcquire(), isFalse);
    app.release(); // the app's engine detached
    expect(await BackgroundIsolateGate(reg).tryAcquire(), isTrue);
  });
}
