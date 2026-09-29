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
  });
}

class _Recorder implements Alerter {
  _Recorder(this.breaches);
  final List<SlaBreach> breaches;

  @override
  void alert(SlaBreach breach) => breaches.add(breach);
}
