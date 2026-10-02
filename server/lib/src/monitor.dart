import 'alerter.dart';
import 'breach_tracker.dart';
import 'logger.dart';
import 'probe.dart';
import 'probe_result.dart';
import 'probe_store.dart';
import 'sla.dart';
import 'stored_event.dart';

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
  /// resolves and later reopens. A resolved breach sends one recovery message
  /// saying how long it lasted.
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
      events = tracker.update(
        policy.provider,
        detectBreaches(policy, window),
        at: _now(),
      );
    } catch (e) {
      logger.error('could not evaluate ${policy.provider} SLA: $e');
      return result;
    }

    for (final event in events) {
      _recordEvent(event);
      if (event.kind == BreachEventKind.resolved) {
        _sendRecovery(event);
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

  /// Saves the event for the dashboard's notification feed. A storage error
  /// is logged and must not stop the alert.
  void _recordEvent(BreachEvent event) {
    try {
      store.insertBreachEvent(
        StoredBreachEvent(
          provider: event.breach.provider,
          type: event.breach.type,
          kind: event.kind,
          message: event.breach.message,
          timestamp: _now().toUtc(),
          duration: event.duration,
        ),
      );
    } catch (e) {
      logger.error('could not store ${event.breach.provider} event: $e');
    }
  }

  void _sendRecovery(BreachEvent event) {
    final b = event.breach;
    final lasted = event.duration ?? Duration.zero;
    final lastFailure = _lastFailure(b, lasted);
    logger.info(
      '${b.provider} ${b.type.name} breach resolved after '
      '${formatDuration(lasted)}${lastFailureSuffix(lastFailure)}',
    );
    try {
      alerter.recovered(b, lasted, lastFailure: lastFailure);
    } catch (e) {
      logger.error('recovery alert failed for ${b.provider}: $e');
    }
  }

  /// When the newest failed probe behind an uptime breach ran. An uptime
  /// breach resolves only once its failures have left the window, so they
  /// are looked up from one window before the breach opened. Null for
  /// latency breaches, or when the lookup fails.
  DateTime? _lastFailure(SlaBreach breach, Duration lasted) {
    if (breach.type != SlaBreachType.uptime) return null;
    try {
      final since = _now().subtract(lasted + policy.window);
      final failures = store
          .query(policy.provider, since: since)
          .where((r) => !r.success);
      return failures.isEmpty ? null : failures.last.timestamp;
    } catch (e) {
      logger.error('could not look up ${policy.provider} failures: $e');
      return null;
    }
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
