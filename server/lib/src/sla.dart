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
    this.consecutiveFailures = 1,
  }) : assert(consecutiveFailures >= 1);

  final String provider;
  final Duration maxP95Latency;
  final double minUptimePercent;
  final Duration window;

  /// Fewer probes than this in the window is too little data to judge.
  final int minSamples;

  /// A breach is only reported once it has shown up in this many evaluations
  /// in a row (one evaluation per probe). 1 reports every breach immediately.
  final int consecutiveFailures;
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

  /// What was breached, ending with whether the newest probe in the window
  /// succeeded, e.g. `uptime 87.50% is below 99.0% (last probe OK)`.
  final String message;

  @override
  String toString() => 'SlaBreach($provider, $type: $message)';
}

/// Evaluates [results] (oldest first, already limited to the policy window)
/// against [policy]. Returns an empty list when the SLA is met or there is not
/// enough data to decide.
///
/// With [SlaPolicy.consecutiveFailures] above 1, a breach is only reported if
/// the same breach type also held when judged as of each of the previous
/// probes, so a single blip does not count and recovery resets the streak.
List<SlaBreach> detectBreaches(SlaPolicy policy, List<ProbeResult> results) {
  final latest = _evaluate(policy, results);
  if (policy.consecutiveFailures <= 1) return latest;

  return [
    for (final breach in latest)
      if (_heldForPreviousEvaluations(policy, results, breach.type)) breach,
  ];
}

bool _heldForPreviousEvaluations(
  SlaPolicy policy,
  List<ProbeResult> results,
  SlaBreachType type,
) {
  for (var back = 1; back < policy.consecutiveFailures; back++) {
    final earlier = results.sublist(0, results.length - back);
    if (!_evaluate(policy, earlier).any((b) => b.type == type)) return false;
  }
  return true;
}

List<SlaBreach> _evaluate(SlaPolicy policy, List<ProbeResult> results) {
  if (results.isEmpty || results.length < policy.minSamples) return const [];
  final breaches = <SlaBreach>[];

  // A breach is judged over the whole window, so the service can already be
  // back when it opens. Say so, or the alert reads like an ongoing outage.
  final now = results.last.success ? 'last probe OK' : 'last probe failed';

  final uptime = uptimePercent(results)!;
  if (uptime < policy.minUptimePercent) {
    breaches.add(
      SlaBreach(
        provider: policy.provider,
        type: SlaBreachType.uptime,
        message:
            'uptime ${uptime.toStringAsFixed(2)}% is below '
            '${policy.minUptimePercent}% ($now)',
      ),
    );
  }

  final p95 = p95Latency(results);
  if (p95 != null && p95 > policy.maxP95Latency) {
    breaches.add(
      SlaBreach(
        provider: policy.provider,
        type: SlaBreachType.latency,
        message:
            'p95 latency ${p95.inMilliseconds}ms exceeds '
            '${policy.maxP95Latency.inMilliseconds}ms ($now)',
      ),
    );
  }
  return breaches;
}
