import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'probe.dart';
import 'probe_result.dart';

/// Why [HttpProbe.judge] rejected a response.
typedef ProbeFailure = ({String error, ProbeErrorKind kind});

/// Probes any HTTP endpoint with a `GET` and judges the response status.
///
/// A response is a success when its status equals [expectedStatus], or, when
/// that is null, when it is any 2xx. The HTTP client, clock and stopwatch are
/// injectable so probes can be unit tested without network access.
///
/// **Retry policy:** a probe that fails at the transport level (timeout,
/// connection or TLS error) is retried [retries] times (default once) before
/// it counts as a failure, so a single dropped packet does not dent uptime.
/// HTTP responses are never retried: a 4xx/5xx is a real answer from the
/// provider. The recorded latency is that of the final attempt, and the
/// timestamp is when the probe started.
class HttpProbe implements Probe {
  /// Extra attempts after a transport-level failure, unless overridden.
  static const defaultRetries = 1;

  HttpProbe({
    required this.provider,
    required this.endpoint,
    this.headers = const {},
    this.expectedStatus,
    this.timeout = const Duration(seconds: 10),
    this.retries = defaultRetries,
    http.Client? client,
    DateTime Function()? now,
    Stopwatch Function()? stopwatch,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       _stopwatch = stopwatch ?? Stopwatch.new;

  @override
  final String provider;

  final Uri endpoint;

  /// Extra request headers. Keep secrets out of config files: build these
  /// from env vars or `config.json` in code.
  final Map<String, String> headers;

  /// Exact status that counts as success; null means any 2xx.
  final int? expectedStatus;
  final Duration timeout;

  /// Extra attempts after a transport-level failure.
  final int retries;
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

  bool _isSuccess(int code) => expectedStatus == null
      ? code >= 200 && code < 300
      : code == expectedStatus;

  /// Judges a response whose status already counts as a success. Returns
  /// null when it is fine, or why it failed. The default accepts every such
  /// response; subclasses override it to read the body.
  ProbeFailure? judge(http.Response response) => null;

  Future<ProbeResult> _attempt(DateTime timestamp) async {
    final watch = _stopwatch()..start();
    try {
      final response = await _client
          .get(endpoint, headers: headers)
          .timeout(timeout);
      watch.stop();
      final code = response.statusCode;
      final failure = _isSuccess(code)
          ? judge(response)
          : (error: 'HTTP $code', kind: _classifyStatus(code));
      return ProbeResult(
        provider: provider,
        timestamp: timestamp,
        latency: watch.elapsed,
        success: failure == null,
        statusCode: code,
        error: failure?.error,
        errorKind: failure?.kind,
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
