import 'package:http/http.dart' as http;

import 'probe.dart';
import 'probe_result.dart';

/// Probes Stripe by calling the authenticated, read-only `GET /v1/balance`.
///
/// Use a test-mode secret key (`sk_test_...`). The HTTP client and clock are
/// injectable so the probe can be unit tested without network access.
class StripeProbe implements Probe {
  StripeProbe({
    required this.apiKey,
    http.Client? client,
    DateTime Function()? now,
    Stopwatch Function()? stopwatch,
    this.timeout = const Duration(seconds: 10),
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
  final Uri endpoint;
  final http.Client _client;
  final DateTime Function() _now;
  final Stopwatch Function() _stopwatch;

  @override
  Future<ProbeResult> run() async {
    final timestamp = _now().toUtc();
    final watch = _stopwatch()..start();
    try {
      final response = await _client
          .get(endpoint, headers: {'Authorization': 'Bearer $apiKey'})
          .timeout(timeout);
      watch.stop();
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      return ProbeResult(
        provider: provider,
        timestamp: timestamp,
        latency: watch.elapsed,
        success: ok,
        statusCode: response.statusCode,
        error: ok ? null : 'HTTP ${response.statusCode}',
      );
    } catch (e) {
      watch.stop();
      return ProbeResult(
        provider: provider,
        timestamp: timestamp,
        latency: watch.elapsed,
        success: false,
        error: e.toString(),
      );
    }
  }

  void close() => _client.close();
}
