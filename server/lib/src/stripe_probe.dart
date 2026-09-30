import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'probe.dart';
import 'probe_result.dart';

/// Probes Stripe by calling the authenticated, read-only `GET /v1/balance`.
///
/// Use a test-mode secret key (`sk_test_...`). The HTTP client and clock are
/// injectable so the probe can be unit tested without network access.
///
/// **Retry policy:** a probe that fails at the transport level (timeout,
/// connection or TLS error) is retried [retries] times (default once) before
/// it counts as a failure, so a single dropped packet does not dent uptime.
/// HTTP responses are never retried: a 4xx/5xx is a real answer from the
/// provider. The recorded latency is that of the final attempt, and the
/// timestamp is when the probe started.
class StripeProbe implements Probe {
  StripeProbe({
    required this.apiKey,
    http.Client? client,
    DateTime Function()? now,
    Stopwatch Function()? stopwatch,
    this.timeout = const Duration(seconds: 10),
    this.retries = 1,
    Uri? endpoint,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       _stopwatch = stopwatch ?? Stopwatch.new,
       endpoint = endpoint ?? Uri.parse('https://api.stripe.com/v1/balance');

  static const providerName = 'stripe';

  @override
  String get provider => providerName;

  final String apiKey;
  final Duration timeout;

  /// Extra attempts after a transport-level failure.
  final int retries;
  final Uri endpoint;
  final http.Client _client;
  final DateTime Function() _now;
  final Stopwatch Function() _stopwatch;

  @override
  Future<ProbeResult> run() async {
    final timestamp = _now().toUtc();
    var result = await _attempt(timestamp);
    for (var i = 0; i < retries && _isTransportFailure(result); i++) {
      result = await _attempt(timestamp);
    }
    return result;
  }

  bool _isTransportFailure(ProbeResult r) => switch (r.errorKind) {
    ProbeErrorKind.timeout ||
    ProbeErrorKind.connection ||
    ProbeErrorKind.tls => true,
    _ => false,
  };

  Future<ProbeResult> _attempt(DateTime timestamp) async {
    final watch = _stopwatch()..start();
    try {
      final response = await _client
          .get(endpoint, headers: {'Authorization': 'Bearer $apiKey'})
          .timeout(timeout);
      watch.stop();
      final code = response.statusCode;
      final ok = code >= 200 && code < 300;
      return ProbeResult(
        provider: provider,
        timestamp: timestamp,
        latency: watch.elapsed,
        success: ok,
        statusCode: code,
        error: ok ? null : 'HTTP $code',
        errorKind: ok ? null : _classifyStatus(code),
      );
    } catch (e) {
      watch.stop();
      return ProbeResult(
        provider: provider,
        timestamp: timestamp,
        latency: watch.elapsed,
        success: false,
        error: e.toString(),
        errorKind: classifyProbeError(e),
      );
    }
  }

  ProbeErrorKind _classifyStatus(int code) {
    if (code >= 500) return ProbeErrorKind.http5xx;
    if (code >= 400) return ProbeErrorKind.http4xx;
    return ProbeErrorKind.other;
  }

  void close() => _client.close();
}

final _tlsHint = RegExp(r'handshake|certificate|tls|ssl', caseSensitive: false);

/// Maps an exception thrown by an HTTP call to a [ProbeErrorKind].
ProbeErrorKind classifyProbeError(Object e) {
  if (e is TimeoutException) return ProbeErrorKind.timeout;
  if (e is TlsException) return ProbeErrorKind.tls;
  if (e is SocketException) return ProbeErrorKind.connection;
  // package:http wraps dart:io errors in a ClientException with only text.
  if (e is http.ClientException) {
    return _tlsHint.hasMatch(e.message)
        ? ProbeErrorKind.tls
        : ProbeErrorKind.connection;
  }
  return ProbeErrorKind.other;
}
