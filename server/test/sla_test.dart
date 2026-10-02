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
    expect(detectBreaches(policy, r).map((b) => b.type), [
      SlaBreachType.uptime,
      SlaBreachType.latency,
    ]);
  });

  test('boundary values are not breaches', () {
    final r = [for (var i = 0; i < 9; i++) probe(500), probe(1, ok: false)];
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

  group('message says whether the service is up right now', () {
    test('uptime breach after the service came back', () {
      final r = [
        for (var i = 0; i < 8; i++) probe(100),
        probe(100, ok: false),
        probe(100, ok: false),
        probe(100),
      ];
      expect(
        detectBreaches(policy, r).single.message,
        'uptime 81.82% is below 90.0% (last probe OK)',
      );
    });

    test('uptime breach while the service is still down', () {
      final r = [
        for (var i = 0; i < 8; i++) probe(100),
        probe(100, ok: false),
        probe(100, ok: false),
      ];
      expect(
        detectBreaches(policy, r).single.message,
        'uptime 80.00% is below 90.0% (last probe failed)',
      );
    });

    test('latency breach', () {
      final r = [for (var i = 0; i < 10; i++) probe(900)];
      expect(
        detectBreaches(policy, r).single.message,
        'p95 latency 900ms exceeds 500ms (last probe OK)',
      );
    });

    test('an empty window is not judged even with minSamples 0', () {
      const p = SlaPolicy(provider: 'stripe', minSamples: 0);
      expect(detectBreaches(p, const []), isEmpty);
    });
  });

  group('minLatencySamples', () {
    const guarded = SlaPolicy(
      provider: 'stripe',
      maxP95Latency: Duration(milliseconds: 1500),
      minUptimePercent: 90,
      minSamples: 5,
      minLatencySamples: 20,
    );

    // Case study 1 re-run: one 7183 ms probe among normal ones.
    List<ProbeResult> oneSlowAmong(int total) => [
      for (var i = 0; i < 8; i++) probe(170),
      probe(7183),
      for (var i = 9; i < total; i++) probe(170),
    ];

    test('without it, one slow probe in 9 opens a latency breach', () {
      const unguarded = SlaPolicy(
        provider: 'stripe',
        maxP95Latency: Duration(milliseconds: 1500),
        minSamples: 5,
      );
      final b = detectBreaches(unguarded, oneSlowAmong(9)).single;
      expect(b.type, SlaBreachType.latency);
    });

    test('with it, p95 is not judged below that many probes', () {
      expect(detectBreaches(guarded, oneSlowAmong(19)), isEmpty);
    });

    test('at that many probes one slow probe no longer decides p95', () {
      expect(detectBreaches(guarded, oneSlowAmong(20)), isEmpty);
    });

    test('sustained slowness still breaches once there is enough data', () {
      final r = [for (var i = 0; i < 20; i++) probe(2000)];
      expect(detectBreaches(guarded, r).single.type, SlaBreachType.latency);
    });

    test('only successful probes count towards it', () {
      final r = [for (var i = 0; i < 19; i++) probe(2000), probe(1, ok: false)];
      // 20 probes but 19 successes: latency is not judged yet.
      expect(
        detectBreaches(guarded, r).map((b) => b.type),
        isNot(contains(SlaBreachType.latency)),
      );
    });

    test('uptime is still judged from minSamples', () {
      final r = [for (var i = 0; i < 4; i++) probe(100), probe(100, ok: false)];
      expect(detectBreaches(guarded, r).single.type, SlaBreachType.uptime);
    });
  });

  group('consecutiveFailures debounce', () {
    const debounced = SlaPolicy(
      provider: 'stripe',
      minUptimePercent: 99, // any single failed probe breaches
      minSamples: 1,
      consecutiveFailures: 3,
    );

    List<ProbeResult> upThenDown(int downCount) => [
      for (var i = 0; i < 10; i++) probe(100),
      for (var i = 0; i < downCount; i++) probe(100, ok: false),
    ];

    test('a single blip does not report', () {
      expect(detectBreaches(debounced, upThenDown(1)), isEmpty);
    });

    test('below the threshold does not report', () {
      // 2 bad evaluations in a row, but 3 are required.
      expect(detectBreaches(debounced, upThenDown(2)), isEmpty);
    });

    test('exactly at the threshold reports', () {
      final b = detectBreaches(debounced, upThenDown(3)).single;
      expect(b.type, SlaBreachType.uptime);
    });

    test('recovery resets the count', () {
      const p = SlaPolicy(
        provider: 'stripe',
        minUptimePercent: 70,
        consecutiveFailures: 3,
      );
      // Judged as of each probe the uptime is 0%, 50%, 67%, 75% and 60%.
      // The 75% is healthy, so the streak restarts and the final 60% is
      // only the first bad evaluation of a new streak.
      final r = [
        probe(100, ok: false),
        probe(100),
        probe(100),
        probe(100),
        probe(100, ok: false),
      ];
      expect(detectBreaches(p, r), isEmpty);
    });

    test('default of 1 reports immediately', () {
      expect(detectBreaches(policy, upThenDown(5)), isNotEmpty);
    });
  });
}
