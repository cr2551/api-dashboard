import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

ProbeResult probe(int ms, {bool ok = true}) => ProbeResult(
      provider: 'stripe',
      timestamp: DateTime.utc(2026, 1, 1),
      latency: Duration(milliseconds: ms),
      success: ok,
    );

void main() {
  const policy = SlaPolicy(
    provider: 'stripe',
    maxP95Latency: Duration(milliseconds: 500),
    minUptimePercent: 90,
    minSamples: 5,
  );

  test('no breach when thresholds are met', () {
    final r = [for (var i = 0; i < 10; i++) probe(200)];
    expect(detectBreaches(policy, r), isEmpty);
  });

  test('flags a latency breach', () {
    final r = [for (var i = 0; i < 10; i++) probe(900)];
    final b = detectBreaches(policy, r).single;
    expect(b.type, SlaBreachType.latency);
    expect(b.provider, 'stripe');
    expect(b.message, contains('900ms'));
  });

  test('flags an uptime breach', () {
    final r = [
      for (var i = 0; i < 8; i++) probe(100),
      probe(100, ok: false),
      probe(100, ok: false),
    ];
    final b = detectBreaches(policy, r).single;
    expect(b.type, SlaBreachType.uptime);
    expect(b.message, contains('80.00%'));
  });

  test('reports both breaches together', () {
    final r = [
      for (var i = 0; i < 5; i++) probe(900),
      probe(1, ok: false),
      probe(1, ok: false),
    ];
    expect(
      detectBreaches(policy, r).map((b) => b.type),
      [SlaBreachType.uptime, SlaBreachType.latency],
    );
  });

  test('boundary values are not breaches', () {
    final r = [
      for (var i = 0; i < 9; i++) probe(500),
      probe(1, ok: false),
    ];
    expect(detectBreaches(policy, r), isEmpty);
  });

  test('too few samples is not judged', () {
    final r = [probe(9000), probe(9000, ok: false)];
    expect(detectBreaches(policy, r), isEmpty);
  });

  test('all-failed window is an uptime breach only', () {
    final r = [for (var i = 0; i < 5; i++) probe(100, ok: false)];
    expect(detectBreaches(policy, r).single.type, SlaBreachType.uptime);
  });
}
