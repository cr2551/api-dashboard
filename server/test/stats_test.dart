import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

ProbeResult probe(int ms, {bool ok = true}) => ProbeResult(
  provider: 'stripe',
  timestamp: DateTime.utc(2026, 1, 1),
  latency: Duration(milliseconds: ms),
  success: ok,
);

void main() {
  group('averageLatency', () {
    test('is null with no successful probes', () {
      expect(averageLatency([]), isNull);
      expect(averageLatency([probe(100, ok: false)]), isNull);
    });

    test('averages only successful probes', () {
      final r = [probe(100), probe(300), probe(5000, ok: false)];
      expect(averageLatency(r), const Duration(milliseconds: 200));
    });
  });

  group('p95Latency', () {
    test('is null with no successful probes', () {
      expect(p95Latency([probe(1, ok: false)]), isNull);
    });

    test('uses nearest-rank on successful probes', () {
      final r = [for (var i = 1; i <= 20; i++) probe(i * 10)];
      expect(p95Latency(r), const Duration(milliseconds: 190));
    });

    test('single sample returns that sample', () {
      expect(p95Latency([probe(42)]), const Duration(milliseconds: 42));
    });
  });

  group('uptimePercent', () {
    test('is null with no probes', () {
      expect(uptimePercent([]), isNull);
    });

    test('is the share of successful probes', () {
      final r = [probe(1), probe(1), probe(1, ok: false), probe(1)];
      expect(uptimePercent(r), 75);
    });
  });
}
