enum EventKind { opened, resolved }

/// Which SLA a breach is about.
enum BreachType {
  latency('Latency'),
  uptime('Uptime');

  const BreachType(this.label);
  final String label;

  static BreachType parse(String name) =>
      values.firstWhere((t) => t.name == name, orElse: () => BreachType.uptime);
}

/// A breach that opened or resolved, from `GET /api/events`.
class ServiceEvent {
  const ServiceEvent({
    required this.id,
    required this.provider,
    required this.type,
    required this.kind,
    required this.message,
    required this.timestamp,
    this.displayName,
    this.duration,
  });

  factory ServiceEvent.fromJson(Map<String, dynamic> json) => ServiceEvent(
    id: json['id'] as int,
    provider: json['provider'] as String,
    displayName: json['displayName'] as String?,
    type: BreachType.parse(json['type'] as String),
    kind: json['kind'] == 'resolved' ? EventKind.resolved : EventKind.opened,
    message: json['message'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    duration: json['durationSeconds'] == null
        ? null
        : Duration(seconds: json['durationSeconds'] as int),
  );

  final int id;
  final String provider;
  final String? displayName;
  final BreachType type;
  final EventKind kind;
  final String message;
  final DateTime timestamp;

  /// How long the breach lasted; only for [EventKind.resolved].
  final Duration? duration;

  /// Name to show: the configured display name, else the capitalised key.
  String get serviceLabel {
    final name = displayName;
    if (name != null && name.trim().isNotEmpty) return name;
    return provider.isEmpty
        ? provider
        : provider[0].toUpperCase() + provider.substring(1);
  }

  /// Short headline, for example `SLA breach: Stripe`.
  String get title => kind == EventKind.opened
      ? 'SLA breach: $serviceLabel'
      : 'Recovered: $serviceLabel';

  /// One-line detail, for example `uptime 0.00% is below 99.9%`.
  String get body => kind == EventKind.opened
      ? message
      : '${type.label} is back within SLA'
            '${duration == null ? '' : ' after ${formatEventDuration(duration!)}'}';
}

/// `45s`, `12m 5s` or `2h 3m`.
String formatEventDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
