import 'alerter.dart';
import 'breach_tracker.dart';
import 'probe.dart';
import 'probe_result.dart';
import 'probe_store.dart';
import 'sla.dart';

/// Probe -> store -> evaluate SLA -> alert, one cycle at a time.
class Monitor {
  Monitor({
    required this.probe,
    required this.store,
    required this.policy,
    required this.alerter,
    BreachTracker? tracker,
    DateTime Function()? now,
  }) : tracker = tracker ?? BreachTracker(),
       _now = now ?? DateTime.now;

  final Probe probe;
  final ProbeStore store;
  final SlaPolicy policy;
  final Alerter alerter;
  final BreachTracker tracker;
  final DateTime Function() _now;

  /// Runs one cycle and returns the probe result. A breach alerts once, when
  /// it opens; it stays silent while it persists and alerts again only if it
  /// resolves and later reopens. (Resolved events are not announced yet.)
  Future<ProbeResult> runOnce() async {
    final result = await probe.run();
    store.insert(result);
    final window = store.query(
      policy.provider,
      since: _now().subtract(policy.window),
    );
    final events = tracker.update(
      policy.provider,
      detectBreaches(policy, window),
    );
    for (final event in events) {
      if (event.kind == BreachEventKind.opened) alerter.alert(event.breach);
    }
    return result;
  }
}
