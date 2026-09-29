import 'sla.dart';

/// Receives SLA breaches.
abstract interface class Alerter {
  void alert(SlaBreach breach);
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
}
