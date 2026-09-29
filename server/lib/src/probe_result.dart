/// Outcome of a single probe against an external API.
class ProbeResult {
  const ProbeResult({
    required this.provider,
    required this.timestamp,
    required this.latency,
    required this.success,
    this.statusCode,
    this.error,
  });

  final String provider;
  final DateTime timestamp;
  final Duration latency;
  final bool success;
  final int? statusCode;
  final String? error;
}
