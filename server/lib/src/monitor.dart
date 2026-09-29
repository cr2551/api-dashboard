import 'alerter.dart';
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
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Probe probe;
  final ProbeStore store;
  final SlaPolicy policy;
  final Alerter alerter;
  final DateTime Function() _now;

  /// Runs one cycle and returns the probe result. Every current breach is
  /// alerted on every cycle (no de-duplication yet).
  Future<ProbeResult> runOnce() async {
    final result = await probe.run();
    store.insert(result);
    final window = store.query(
      policy.provider,
      since: _now().subtract(policy.window),
    );
    for (final breach in detectBreaches(policy, window)) {
      alerter.alert(breach);
    }
    return result;
  }
}
