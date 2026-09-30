import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'probe_result.dart';
import 'probe_store.dart';
import 'sla.dart';
import 'stats.dart';

const _cors = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, OPTIONS',
  'access-control-allow-headers': 'content-type',
};

/// JSON API for the dashboard:
///
/// * `GET /api/status`: one entry per policy (state, latest probe, uptime,
///   latency stats and current SLA breaches over the policy window).
/// * `GET /api/history?provider=stripe&minutes=60`: probes for the chart.
Handler apiHandler({
  required ProbeStore store,
  required List<SlaPolicy> policies,
  DateTime Function()? now,
}) {
  final clock = now ?? DateTime.now;

  Response json(Object body, {int status = 200}) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json', ..._cors},
  );

  Response error(int status, String message) =>
      json({'error': message}, status: status);

  Map<String, dynamic> serviceStatus(SlaPolicy policy) {
    final now = clock();
    final results = store.query(
      policy.provider,
      since: now.subtract(policy.window),
    );
    final last = results.isEmpty ? null : results.last;
    return {
      'provider': policy.provider,
      'state': last == null ? 'unknown' : (last.success ? 'up' : 'down'),
      'lastProbe': last == null ? null : _probeJson(last),
      'windowMinutes': policy.window.inMinutes,
      'sampleCount': results.length,
      'uptimePercent': uptimePercent(results),
      'avgLatencyMs': averageLatency(results)?.inMilliseconds,
      'p95LatencyMs': p95Latency(results)?.inMilliseconds,
      'breaches': [
        for (final b in detectBreaches(policy, results))
          {'type': b.type.name, 'message': b.message},
      ],
    };
  }

  return (Request request) {
    if (request.method == 'OPTIONS') {
      return Response(204, headers: _cors);
    }
    if (request.method != 'GET') return error(405, 'method not allowed');

    switch (request.url.path) {
      case 'api/status':
        return json({
          'generatedAt': clock().toUtc().toIso8601String(),
          'services': [for (final p in policies) serviceStatus(p)],
        });
      case 'api/history':
        final provider = request.url.queryParameters['provider'];
        if (provider == null || !policies.any((p) => p.provider == provider)) {
          return error(404, 'unknown provider');
        }
        final minutes = int.tryParse(
          request.url.queryParameters['minutes'] ?? '60',
        );
        if (minutes == null || minutes <= 0) {
          return error(400, 'minutes must be a positive integer');
        }
        final results = store.query(
          provider,
          since: clock().subtract(Duration(minutes: minutes)),
        );
        return json({
          'provider': provider,
          'minutes': minutes,
          'uptimePercent': uptimePercent(results),
          'points': [for (final r in results) _probeJson(r)],
        });
      default:
        return error(404, 'not found');
    }
  };
}

Map<String, dynamic> _probeJson(ProbeResult r) => {
  'timestamp': r.timestamp.toUtc().toIso8601String(),
  'latencyMs': r.latency.inMilliseconds,
  'success': r.success,
  'statusCode': r.statusCode,
  'error': r.error,
};
