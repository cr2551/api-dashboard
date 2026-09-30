import 'sla.dart';

enum BreachEventKind { opened, resolved }

/// A breach that just started or just ended.
class BreachEvent {
  const BreachEvent(this.kind, this.breach, {this.duration});

  final BreachEventKind kind;
  final SlaBreach breach;

  /// How long the breach lasted. Only set on [BreachEventKind.resolved].
  final Duration? duration;

  @override
  String toString() => 'BreachEvent(${kind.name}, $breach)';
}

/// Remembers which breaches are open per provider and type, and turns the
/// current breach list of each cycle into transitions only: newly opened or
/// resolved. Breaches that stay open produce no event.
///
/// State is in memory only, so a restart re-opens any still-active breach.
class BreachTracker {
  final Map<(String, SlaBreachType), _OpenBreach> _open = {};

  /// [current] is everything [detectBreaches] reports for [provider] this
  /// cycle, and [at] is the time of the evaluation (default: now). Returns the
  /// events since the previous call for that provider; resolved events carry
  /// how long the breach lasted.
  List<BreachEvent> update(
    String provider,
    List<SlaBreach> current, {
    DateTime? at,
  }) {
    final time = at ?? DateTime.now();
    final now = {for (final b in current) (provider, b.type): b};
    final events = <BreachEvent>[];

    for (final entry in now.entries) {
      if (!_open.containsKey(entry.key)) {
        events.add(BreachEvent(BreachEventKind.opened, entry.value));
      }
    }
    for (final entry in _open.entries) {
      if (entry.key.$1 == provider && !now.containsKey(entry.key)) {
        events.add(
          BreachEvent(
            BreachEventKind.resolved,
            entry.value.breach,
            duration: time.difference(entry.value.openedAt),
          ),
        );
      }
    }

    final stillOpen = {
      for (final entry in now.entries)
        entry.key: _open[entry.key] ?? _OpenBreach(entry.value, time),
    };
    _open.removeWhere((key, _) => key.$1 == provider);
    _open.addAll(stillOpen);
    return events;
  }
}

class _OpenBreach {
  _OpenBreach(this.breach, this.openedAt);

  final SlaBreach breach;
  final DateTime openedAt;
}
