import 'probe_result.dart';

/// Average latency of successful probes, or null when there are none.
Duration? averageLatency(List<ProbeResult> results) {
  final ok = results.where((r) => r.success).toList();
  if (ok.isEmpty) return null;
  final micros = ok.fold<int>(0, (sum, r) => sum + r.latency.inMicroseconds);
  return Duration(microseconds: micros ~/ ok.length);
}

/// Nearest-rank 95th percentile latency of successful probes, or null when
/// there are none.
Duration? p95Latency(List<ProbeResult> results) {
  final sorted = results.where((r) => r.success).map((r) => r.latency).toList()
    ..sort();
  if (sorted.isEmpty) return null;
  final rank = (0.95 * sorted.length).ceil();
  return sorted[rank - 1];
}

/// Percentage (0-100) of probes that succeeded, or null when there are none.
double? uptimePercent(List<ProbeResult> results) {
  if (results.isEmpty) return null;
  final ok = results.where((r) => r.success).length;
  return ok * 100 / results.length;
}
