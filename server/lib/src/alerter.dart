import 'sla.dart';

/// Receives SLA breaches and their recoveries.
abstract interface class Alerter {
  void alert(SlaBreach breach);

  /// [breach] is over; it lasted [duration]. [lastFailure] is when the
  /// newest failed probe behind an uptime breach ran, so the message can
  /// report the outage rather than the window; null when unknown.
  void recovered(SlaBreach breach, Duration duration, {DateTime? lastFailure});
}

/// `, last failure 21:04:53 UTC`, or an empty string when [lastFailure] is
/// null.
String lastFailureSuffix(DateTime? lastFailure) {
  if (lastFailure == null) return '';
  final t = lastFailure.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return ', last failure ${two(t.hour)}:${two(t.minute)}:${two(t.second)} UTC';
}

/// Human-readable duration such as `45s`, `12m 5s` or `2h 3m`.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

/// Writes breaches to a text sink (stdout by default).
class ConsoleAlerter implements Alerter {
  ConsoleAlerter([void Function(String line)? sink]) : _sink = sink ?? print;

  final void Function(String line) _sink;

  @override
  void alert(SlaBreach breach) => _sink(
    '[SLA BREACH] ${breach.provider} (${breach.type.name}): '
    '${breach.message}',
  );

  @override
  void recovered(
    SlaBreach breach,
    Duration duration, {
    DateTime? lastFailure,
  }) => _sink(
    '[SLA RECOVERED] ${breach.provider} (${breach.type.name}) after '
    '${formatDuration(duration)}${lastFailureSuffix(lastFailure)}',
  );
}
