import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

class FakeProbe implements Probe {
  FakeProbe(this._results);
  final List<ProbeResult> _results;

  @override
  String get provider => 'stripe';

  @override
  Future<ProbeResult> run() async => _results.removeAt(0);
}

ProbeResult result(int ms, {bool ok = true}) => ProbeResult(
  provider: 'stripe',
  timestamp: DateTime.utc(2026, 1, 1, 12),
  latency: Duration(milliseconds: ms),
  success: ok,
);

void main() {
  final now = DateTime.utc(2026, 1, 1, 12, 1);
  const policy = SlaPolicy(
    provider: 'stripe',
    maxP95Latency: Duration(milliseconds: 500),
    minUptimePercent: 100,
    minSamples: 2,
  );

  late ProbeStore store;
  late List<SlaBreach> alerts;

  Monitor monitor(List<ProbeResult> probes) => Monitor(
    probe: FakeProbe(probes),
    store: store,
    policy: policy,
    alerter: _Recorder(alerts),
    now: () => now,
  );

  setUp(() {
    store = ProbeStore.inMemory();
    alerts = [];
  });
  tearDown(() => store.close());

  test('stores each probe result', () async {
    final m = monitor([result(100)]);
    await m.runOnce();
    expect(store.query('stripe', since: DateTime.utc(2026)), hasLength(1));
  });

  test('does not alert while the SLA is met', () async {
    final m = monitor([result(100), result(120)]);
    await m.runOnce();
    await m.runOnce();
    expect(alerts, isEmpty);
  });

  test('does not alert before minSamples is reached', () async {
    await monitor([result(100, ok: false)]).runOnce();
    expect(alerts, isEmpty);
  });

  test('alerts when the SLA is breached', () async {
    final m = monitor([result(100), result(100, ok: false)]);
    await m.runOnce();
    await m.runOnce();
    expect(alerts.single.type, SlaBreachType.uptime);
  });

  group('alert de-duplication', () {
    late DateTime clock;

    ProbeResult at(DateTime t, {bool ok = true}) => ProbeResult(
      provider: 'stripe',
      timestamp: t,
      latency: const Duration(milliseconds: 100),
      success: ok,
    );

    Monitor clocked(List<ProbeResult> probes) => Monitor(
      probe: FakeProbe(probes),
      store: store,
      policy: policy,
      alerter: _Recorder(alerts),
      now: () => clock,
    );

    test('a persistent breach alerts once', () async {
      final t = DateTime.utc(2026, 1, 1, 12);
      final m = clocked([
        at(t),
        for (var i = 1; i <= 4; i++) at(t.add(Duration(minutes: i)), ok: false),
      ]);
      for (var i = 0; i <= 4; i++) {
        clock = t.add(Duration(minutes: i));
        await m.runOnce();
      }
      expect(alerts, hasLength(1));
      expect(alerts.single.type, SlaBreachType.uptime);
    });

    test('alerts again when a resolved breach reopens', () async {
      final t = DateTime.utc(2026, 1, 1, 12);
      final later = DateTime.utc(2026, 1, 1, 14);
      final m = clocked([
        at(t),
        at(t.add(const Duration(minutes: 1)), ok: false), // opens
        at(t.add(const Duration(minutes: 2)), ok: false), // silent
        at(later), // old results left the window: resolved
        at(later.add(const Duration(minutes: 1)), ok: false), // reopens
      ]);
      for (final time in [
        t,
        t.add(const Duration(minutes: 1)),
        t.add(const Duration(minutes: 2)),
        later,
        later.add(const Duration(minutes: 1)),
      ]) {
        clock = time;
        await m.runOnce();
      }
      expect(alerts, hasLength(2));
    });

    test('sends one recovery with how long the breach lasted', () async {
      final t = DateTime.utc(2026, 1, 1, 12);
      final later = DateTime.utc(2026, 1, 1, 14);
      final recoveries = <Duration>[];
      final m = Monitor(
        probe: FakeProbe([
          at(t),
          at(t.add(const Duration(minutes: 1)), ok: false), // opens at 12:01
          at(later), // resolved at 14:00
          at(later.add(const Duration(minutes: 1))),
        ]),
        store: store,
        policy: policy,
        alerter: _Recorder(alerts, recoveries),
        now: () => clock,
      );
      for (final time in [
        t,
        t.add(const Duration(minutes: 1)),
        later,
        later.add(const Duration(minutes: 1)),
      ]) {
        clock = time;
        await m.runOnce();
      }
      expect(alerts, hasLength(1));
      expect(recoveries, [const Duration(hours: 1, minutes: 59)]);
    });

    test('the recovery says when the last failure happened', () async {
      final t = DateTime.utc(2026, 1, 1, 12);
      final later = DateTime.utc(2026, 1, 1, 14);
      final recorder = _Recorder(alerts);
      final lines = <String>[];
      final m = Monitor(
        probe: FakeProbe([
          at(t),
          at(t.add(const Duration(minutes: 1)), ok: false),
          at(t.add(const Duration(minutes: 2)), ok: false), // last failure
          at(t.add(const Duration(minutes: 3))),
          at(later), // both failures left the window: resolved
        ]),
        store: store,
        policy: policy,
        alerter: recorder,
        logger: Logger(sink: lines.add, now: () => clock),
        now: () => clock,
      );
      for (final time in [
        t,
        t.add(const Duration(minutes: 1)),
        t.add(const Duration(minutes: 2)),
        t.add(const Duration(minutes: 3)),
        later,
      ]) {
        clock = time;
        await m.runOnce();
      }
      expect(recorder.lastFailures, [t.add(const Duration(minutes: 2))]);
      expect(lines.any((l) => l.contains('last failure 12:02:00 UTC')), isTrue);
    });

    test('a latency recovery has no last failure', () async {
      final t = DateTime.utc(2026, 1, 1, 12);
      final later = DateTime.utc(2026, 1, 1, 14);
      final recorder = _Recorder(alerts);
      ProbeResult slow(DateTime time) => ProbeResult(
        provider: 'stripe',
        timestamp: time,
        latency: const Duration(seconds: 2),
        success: true,
      );
      final m = Monitor(
        probe: FakeProbe([
          slow(t),
          slow(t.add(const Duration(minutes: 1))), // latency breach opens
          at(later), // resolved
        ]),
        store: store,
        policy: policy,
        alerter: recorder,
        now: () => clock,
      );
      for (final time in [t, t.add(const Duration(minutes: 1)), later]) {
        clock = time;
        await m.runOnce();
      }
      expect(alerts.single.type, SlaBreachType.latency);
      expect(recorder.lastFailures, [null]);
    });

    test('a failing recovery alert is logged, not thrown', () async {
      final t = DateTime.utc(2026, 1, 1, 12);
      final later = DateTime.utc(2026, 1, 1, 14);
      final lines = <String>[];
      final m = Monitor(
        probe: FakeProbe([
          at(t),
          at(t.add(const Duration(minutes: 1)), ok: false),
          at(later),
        ]),
        store: store,
        policy: policy,
        alerter: _RecoveryThrowing(),
        logger: Logger(sink: lines.add, now: () => t),
        now: () => clock,
      );
      for (final time in [t, t.add(const Duration(minutes: 1)), later]) {
        clock = time;
        await m.runOnce();
      }
      expect(lines.any((l) => l.contains('recovery alert failed')), isTrue);
    });
  });

  group('logging', () {
    late List<String> lines;

    Monitor logged(List<ProbeResult> probes, {Alerter? alerter}) => Monitor(
      probe: FakeProbe(probes),
      store: store,
      policy: policy,
      alerter: alerter ?? _Recorder(alerts),
      logger: Logger(level: LogLevel.debug, sink: lines.add, now: () => now),
      now: () => now,
    );

    setUp(() => lines = []);

    test('logs the probe start at debug level', () async {
      await logged([result(100)]).runOnce();
      expect(lines.first, contains('DEBUG probing stripe'));
    });

    test('logs ok and failed results with latency and error kind', () async {
      final m = logged([
        result(120),
        ProbeResult(
          provider: 'stripe',
          timestamp: now,
          latency: const Duration(milliseconds: 40),
          success: false,
          error: 'HTTP 503',
          errorKind: ProbeErrorKind.http5xx,
        ),
      ]);
      await m.runOnce();
      await m.runOnce();
      expect(lines.any((l) => l.contains('INFO  stripe ok 120ms')), isTrue);
      expect(
        lines.any(
          (l) => l.contains('WARN  stripe FAIL 40ms http5xx: HTTP 503'),
        ),
        isTrue,
      );
    });

    test('logs a breach opening and the alert being sent', () async {
      final m = logged([result(100), result(100, ok: false)]);
      await m.runOnce();
      await m.runOnce();
      expect(lines.any((l) => l.contains('SLA breach opened')), isTrue);
      expect(lines.any((l) => l.contains('alert sent for stripe')), isTrue);
    });

    test('logs a failing alerter without stopping the cycle', () async {
      final m = logged([
        result(100),
        result(100, ok: false),
      ], alerter: _Throwing());
      await m.runOnce();
      await m.runOnce();
      expect(lines.any((l) => l.contains('ERROR alert failed')), isTrue);
    });

    test('logs storage errors instead of throwing', () async {
      final m = logged([result(100)]);
      store.close();
      await m.runOnce();
      expect(
        lines.any((l) => l.contains('ERROR could not store stripe result')),
        isTrue,
      );
      expect(
        lines.any((l) => l.contains('ERROR could not evaluate stripe SLA')),
        isTrue,
      );
    });

    test('info level hides debug lines', () async {
      final quiet = <String>[];
      await Monitor(
        probe: FakeProbe([result(100)]),
        store: store,
        policy: policy,
        alerter: _Recorder(alerts),
        logger: Logger(sink: quiet.add),
        now: () => now,
      ).runOnce();
      expect(quiet.any((l) => l.contains('DEBUG')), isFalse);
      expect(quiet.single, contains('INFO  stripe ok'));
    });
  });

  test('ignores results older than the window', () async {
    store.insert(
      ProbeResult(
        provider: 'stripe',
        timestamp: now.subtract(const Duration(days: 1)),
        latency: const Duration(milliseconds: 100),
        success: false,
      ),
    );
    await monitor([result(100)]).runOnce();
    expect(alerts, isEmpty);
  });

  test('works end to end with StripeProbe and a mock HTTP client', () async {
    final probe = StripeProbe(
      apiKey: 'sk_test_x',
      client: MockClient((_) async => http.Response('', 500)),
      now: () => now,
    );
    final m = Monitor(
      probe: probe,
      store: store,
      policy: const SlaPolicy(provider: 'stripe', minSamples: 1),
      alerter: _Recorder(alerts),
      now: () => now.add(const Duration(seconds: 1)),
    );
    await m.runOnce();
    expect(alerts.single.type, SlaBreachType.uptime);
  });

  group('ConsoleAlerter', () {
    test('formats a breach line', () {
      final lines = <String>[];
      ConsoleAlerter(lines.add).alert(
        const SlaBreach(
          provider: 'stripe',
          type: SlaBreachType.latency,
          message: 'p95 too high',
        ),
      );
      expect(lines.single, '[SLA BREACH] stripe (latency): p95 too high');
    });

    test('formats a recovery line with the duration', () {
      final lines = <String>[];
      ConsoleAlerter(lines.add).recovered(
        const SlaBreach(
          provider: 'stripe',
          type: SlaBreachType.latency,
          message: 'p95 too high',
        ),
        const Duration(minutes: 12, seconds: 5),
      );
      expect(lines.single, '[SLA RECOVERED] stripe (latency) after 12m 5s');
    });

    test('adds the last failure time to a recovery line', () {
      final lines = <String>[];
      ConsoleAlerter(lines.add).recovered(
        const SlaBreach(
          provider: 'stripe',
          type: SlaBreachType.uptime,
          message: 'uptime too low',
        ),
        const Duration(minutes: 59),
        lastFailure: DateTime.utc(2026, 10, 1, 21, 4, 53),
      );
      expect(
        lines.single,
        '[SLA RECOVERED] stripe (uptime) after 59m 0s, '
        'last failure 21:04:53 UTC',
      );
    });

    test('formatDuration picks a readable unit', () {
      expect(formatDuration(const Duration(seconds: 45)), '45s');
      expect(formatDuration(const Duration(minutes: 12, seconds: 5)), '12m 5s');
      expect(formatDuration(const Duration(hours: 2, minutes: 3)), '2h 3m');
    });
  });
}

class _RecoveryThrowing implements Alerter {
  @override
  void alert(SlaBreach breach) {}

  @override
  void recovered(
    SlaBreach breach,
    Duration duration, {
    DateTime? lastFailure,
  }) => throw StateError('channel down');
}

class _Throwing implements Alerter {
  @override
  void alert(SlaBreach breach) => throw StateError('channel down');

  @override
  void recovered(
    SlaBreach breach,
    Duration duration, {
    DateTime? lastFailure,
  }) => throw StateError('channel down');
}

class _Recorder implements Alerter {
  _Recorder(this.breaches, [List<Duration>? recoveries])
    : recoveries = recoveries ?? [];
  final List<SlaBreach> breaches;
  final List<Duration> recoveries;
  final List<DateTime?> lastFailures = [];

  @override
  void alert(SlaBreach breach) => breaches.add(breach);

  @override
  void recovered(SlaBreach breach, Duration duration, {DateTime? lastFailure}) {
    recoveries.add(duration);
    lastFailures.add(lastFailure);
  }
}
