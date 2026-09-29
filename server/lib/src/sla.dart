import 'probe_result.dart';
import 'stats.dart';

/// Thresholds a provider must meet over a rolling [window].
class SlaPolicy {
  const SlaPolicy({
    required this.provider,
    this.maxP95Latency = const Duration(seconds: 1),
    this.minUptimePercent = 99.9,
    this.window = const Duration(hours: 1),
    this.minSamples = 1,
  });

  final String provider;
  final Duration maxP95Latency;
  final double minUptimePercent;
  final Duration window;

  /// Fewer probes than this in the window is too little data to judge.
  final int minSamples;
}

enum SlaBreachType { latency, uptime }

class SlaBreach {
  const SlaBreach({
    required this.provider,
    required this.type,
    required this.message,
  });

  final String provider;
  final SlaBreachType type;
  final String message;

  @override
  String toString() => 'SlaBreach($provider, $type: $message)';
}

/// Evaluates [results] (already limited to the policy window) against
/// [policy]. Returns an empty list when the SLA is met or there is not enough
/// data to decide.
List<SlaBreach> detectBreaches(SlaPolicy policy, List<ProbeResult> results) {
  if (results.length < policy.minSamples) return const [];
  final breaches = <SlaBreach>[];

  final uptime = uptimePercent(results)!;
  if (uptime < policy.minUptimePercent) {
    breaches.add(SlaBreach(
      provider: policy.provider,
      type: SlaBreachType.uptime,
      message: 'uptime ${uptime.toStringAsFixed(2)}% is below '
          '${policy.minUptimePercent}%',
    ));
  }

  final p95 = p95Latency(results);
  if (p95 != null && p95 > policy.maxP95Latency) {
    breaches.add(SlaBreach(
      provider: policy.provider,
      type: SlaBreachType.latency,
      message: 'p95 latency ${p95.inMilliseconds}ms exceeds '
          '${policy.maxP95Latency.inMilliseconds}ms',
    ));
  }
  return breaches;
}
