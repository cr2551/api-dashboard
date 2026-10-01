import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'probe_result.dart';
import 'probe_store.dart';
import 'sla.dart';
import 'stats.dart';

const _cors = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, OPTIONS',
  'access-control-allow-headers': 'content-type, authorization',
};

/// JSON API for the dashboard:
///
/// * `GET /api/status`: one entry per policy (state, latest probe, uptime,
///   latency stats and current SLA breaches over the policy window, plus the
///   optional friendly `displayName` from [displayNames]).
/// * `GET /api/history?provider=stripe&minutes=60`: probes for the chart.
///
/// When [authToken] is set, every request except the CORS preflight must send
/// `Authorization: Bearer <token>`, otherwise it gets a 401. With no token the
/// API is open, which is only safe while it listens on localhost.
Handler apiHandler({
  required ProbeStore store,
  required List<SlaPolicy> policies,
  String? authToken,
  Map<String, String> displayNames = const {},
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
      'displayName': displayNames[policy.provider],
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
    // Browsers send the preflight without credentials, so it must not need
    // them; it carries no data.
    if (request.method == 'OPTIONS') {
      return Response(204, headers: _cors);
    }
    if (authToken != null && !_hasValidToken(request, authToken)) {
      return Response(
        401,
        body: jsonEncode({'error': 'unauthorized'}),
        headers: {
          'content-type': 'application/json',
          'www-authenticate': 'Bearer',
          ..._cors,
        },
      );
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

bool _hasValidToken(Request request, String expected) {
  final header = request.headers['authorization'];
  if (header == null) return false;
  const prefix = 'bearer ';
  if (header.length <= prefix.length ||
      header.substring(0, prefix.length).toLowerCase() != prefix) {
    return false;
  }
  final given = header.substring(prefix.length).trim();
  return _constantTimeEquals(utf8.encode(given), utf8.encode(expected));
}

/// Compares without stopping at the first difference, so response time does
/// not reveal how much of a guessed token was right.
bool _constantTimeEquals(List<int> a, List<int> b) {
  var diff = a.length ^ b.length;
  for (var i = 0; i < a.length && i < b.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

Map<String, dynamic> _probeJson(ProbeResult r) => {
  'timestamp': r.timestamp.toUtc().toIso8601String(),
  'latencyMs': r.latency.inMilliseconds,
  'success': r.success,
  'statusCode': r.statusCode,
  'error': r.error,
  'errorKind': r.errorKind?.name,
};
