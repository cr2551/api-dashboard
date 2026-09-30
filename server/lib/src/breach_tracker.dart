import 'sla.dart';

enum BreachEventKind { opened, resolved }

/// A breach that just started or just ended.
class BreachEvent {
  const BreachEvent(this.kind, this.breach);

  final BreachEventKind kind;
  final SlaBreach breach;

  @override
  String toString() => 'BreachEvent(${kind.name}, $breach)';
}

/// Remembers which breaches are open per provider and type, and turns the
/// current breach list of each cycle into transitions only: newly opened or
/// resolved. Breaches that stay open produce no event.
///
/// State is in memory only, so a restart re-opens any still-active breach.
class BreachTracker {
  final Map<(String, SlaBreachType), SlaBreach> _open = {};

  /// [current] is everything [detectBreaches] reports for [provider] this
  /// cycle. Returns the events since the previous call for that provider.
  List<BreachEvent> update(String provider, List<SlaBreach> current) {
    final now = {for (final b in current) (provider, b.type): b};
    final events = <BreachEvent>[];

    for (final entry in now.entries) {
      if (!_open.containsKey(entry.key)) {
        events.add(BreachEvent(BreachEventKind.opened, entry.value));
      }
    }
    for (final entry in _open.entries) {
      if (entry.key.$1 == provider && !now.containsKey(entry.key)) {
        events.add(BreachEvent(BreachEventKind.resolved, entry.value));
      }
    }

    _open.removeWhere((key, _) => key.$1 == provider);
    _open.addAll(now);
    return events;
  }
}
