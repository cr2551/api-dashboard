import 'breach_tracker.dart';
import 'sla.dart';

/// A breach that opened or resolved, as saved for the dashboard's
/// notification feed.
class StoredBreachEvent {
  const StoredBreachEvent({
    required this.provider,
    required this.type,
    required this.kind,
    required this.message,
    required this.timestamp,
    this.duration,
    this.id,
  });

  /// Assigned by the store; null before the event is saved.
  final int? id;
  final String provider;
  final SlaBreachType type;
  final BreachEventKind kind;
  final String message;
  final DateTime timestamp;

  /// How long the breach lasted. Only set when [kind] is resolved.
  final Duration? duration;
}
