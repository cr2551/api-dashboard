import 'failure_kind.dart';

enum ServiceState { up, down, unknown }

class ProbePoint {
  const ProbePoint({
    required this.timestamp,
    required this.latencyMs,
    required this.success,
    this.statusCode,
    this.error,
    this.errorKind,
  });

  factory ProbePoint.fromJson(Map<String, dynamic> json) => ProbePoint(
    timestamp: DateTime.parse(json['timestamp'] as String),
    latencyMs: json['latencyMs'] as int,
    success: json['success'] as bool,
    statusCode: json['statusCode'] as int?,
    error: json['error'] as String?,
    errorKind: FailureKind.parse(json['errorKind'] as String?),
  );

  final DateTime timestamp;
  final int latencyMs;
  final bool success;
  final int? statusCode;
  final String? error;

  /// Why the probe failed; null on success or for older backends.
  final FailureKind? errorKind;
}

class SlaBreachInfo {
  const SlaBreachInfo({required this.type, required this.message});

  factory SlaBreachInfo.fromJson(Map<String, dynamic> json) => SlaBreachInfo(
    type: json['type'] as String,
    message: json['message'] as String,
  );

  /// `latency` or `uptime`.
  final String type;
  final String message;
}

class ServiceStatus {
  const ServiceStatus({
    required this.provider,
    required this.state,
    required this.windowMinutes,
    required this.sampleCount,
    required this.breaches,
    this.displayName,
    this.lastProbe,
    this.uptimePercent,
    this.avgLatencyMs,
    this.p95LatencyMs,
  });

  factory ServiceStatus.fromJson(Map<String, dynamic> json) => ServiceStatus(
    provider: json['provider'] as String,
    displayName: json['displayName'] as String?,
    state: ServiceState.values.firstWhere(
      (s) => s.name == json['state'],
      orElse: () => ServiceState.unknown,
    ),
    lastProbe: json['lastProbe'] == null
        ? null
        : ProbePoint.fromJson(json['lastProbe'] as Map<String, dynamic>),
    windowMinutes: json['windowMinutes'] as int,
    sampleCount: json['sampleCount'] as int,
    uptimePercent: (json['uptimePercent'] as num?)?.toDouble(),
    avgLatencyMs: json['avgLatencyMs'] as int?,
    p95LatencyMs: json['p95LatencyMs'] as int?,
    breaches: [
      for (final b in json['breaches'] as List)
        SlaBreachInfo.fromJson(b as Map<String, dynamic>),
    ],
  );

  final String provider;

  /// Friendly title chosen in the backend's services config, if any.
  final String? displayName;
  final ServiceState state;
  final ProbePoint? lastProbe;
  final int windowMinutes;
  final int sampleCount;
  final double? uptimePercent;
  final int? avgLatencyMs;
  final int? p95LatencyMs;
  final List<SlaBreachInfo> breaches;
}

class StatusSnapshot {
  const StatusSnapshot({required this.generatedAt, required this.services});

  factory StatusSnapshot.fromJson(Map<String, dynamic> json) => StatusSnapshot(
    generatedAt: DateTime.parse(json['generatedAt'] as String),
    services: [
      for (final s in json['services'] as List)
        ServiceStatus.fromJson(s as Map<String, dynamic>),
    ],
  );

  final DateTime generatedAt;
  final List<ServiceStatus> services;
}

class ServiceHistory {
  const ServiceHistory({
    required this.provider,
    required this.minutes,
    required this.points,
    this.uptimePercent,
  });

  factory ServiceHistory.fromJson(Map<String, dynamic> json) => ServiceHistory(
    provider: json['provider'] as String,
    minutes: json['minutes'] as int,
    uptimePercent: (json['uptimePercent'] as num?)?.toDouble(),
    points: [
      for (final p in json['points'] as List)
        ProbePoint.fromJson(p as Map<String, dynamic>),
    ],
  );

  final String provider;
  final int minutes;
  final double? uptimePercent;
  final List<ProbePoint> points;
}
