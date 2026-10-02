/// Why a probe failed.
enum ProbeErrorKind {
  /// No answer within the probe timeout.
  timeout,

  /// Could not reach the host (DNS failure, refused or dropped connection).
  connection,

  /// TLS handshake or certificate problem.
  tls,

  /// The provider answered with a 4xx status (often our own key or request).
  http4xx,

  /// The provider answered with a 5xx status (the provider is failing).
  http5xx,

  /// The provider's own status page reports an incident.
  reported,

  /// Any other non-2xx status or unexpected error.
  other,
}

/// Outcome of a single probe against an external API.
class ProbeResult {
  const ProbeResult({
    required this.provider,
    required this.timestamp,
    required this.latency,
    required this.success,
    this.statusCode,
    this.error,
    this.errorKind,
  });

  final String provider;
  final DateTime timestamp;
  final Duration latency;
  final bool success;
  final int? statusCode;
  final String? error;

  /// Null for successful probes (and for rows stored before categories
  /// existed).
  final ProbeErrorKind? errorKind;
}
