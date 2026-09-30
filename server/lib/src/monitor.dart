import 'alerter.dart';
import 'breach_tracker.dart';
import 'logger.dart';
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
    Logger? logger,
    DateTime Function()? now,
  }) : tracker = tracker ?? BreachTracker(),
       logger = logger ?? Logger(level: LogLevel.error),
       _now = now ?? DateTime.now;

  final Probe probe;
  final ProbeStore store;
  final SlaPolicy policy;
  final Alerter alerter;
  final BreachTracker tracker;
  final Logger logger;
  final DateTime Function() _now;

  /// Runs one cycle and returns the probe result. A breach alerts once, when
  /// it opens; it stays silent while it persists and alerts again only if it
  /// resolves and later reopens. (Resolved events are not announced yet.)
  ///
  /// A storage or alerter failure is logged and does not stop the cycle.
  Future<ProbeResult> runOnce() async {
    logger.debug('probing ${policy.provider}');
    final result = await probe.run();
    _logResult(result);

    try {
      store.insert(result);
    } catch (e) {
      logger.error('could not store ${policy.provider} result: $e');
    }

    final List<BreachEvent> events;
    try {
      final window = store.query(
        policy.provider,
        since: _now().subtract(policy.window),
      );
      events = tracker.update(policy.provider, detectBreaches(policy, window));
    } catch (e) {
      logger.error('could not evaluate ${policy.provider} SLA: $e');
      return result;
    }

    for (final event in events) {
      if (event.kind != BreachEventKind.opened) {
        logger.info(
          '${event.breach.provider} ${event.breach.type.name} breach '
          'resolved',
        );
        continue;
      }
      logger.warn('SLA breach opened: ${event.breach}');
      try {
        alerter.alert(event.breach);
        logger.info(
          'alert sent for ${event.breach.provider} '
          '${event.breach.type.name}',
        );
      } catch (e) {
        logger.error('alert failed for ${event.breach.provider}: $e');
      }
    }
    return result;
  }

  void _logResult(ProbeResult r) {
    final ms = '${r.latency.inMilliseconds}ms';
    if (r.success) {
      logger.info('${r.provider} ok $ms ${r.statusCode ?? ''}'.trimRight());
    } else {
      logger.warn(
        '${r.provider} FAIL $ms '
        '${r.errorKind?.name ?? 'error'}: ${r.error ?? r.statusCode}',
      );
    }
  }
}
