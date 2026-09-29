import 'dart:convert';

import 'package:api_dashboard/data/api_client.dart';
import 'package:api_dashboard/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const statusJson = {
  'generatedAt': '2026-01-01T12:00:00.000Z',
  'services': [
    {
      'provider': 'stripe',
      'state': 'down',
      'lastProbe': {
        'timestamp': '2026-01-01T11:59:50.000Z',
        'latencyMs': 250,
        'success': false,
        'statusCode': 500,
        'error': 'HTTP 500',
      },
      'windowMinutes': 60,
      'sampleCount': 4,
      'uptimePercent': 75.0,
      'avgLatencyMs': 200,
      'p95LatencyMs': 250,
      'breaches': [
        {'type': 'uptime', 'message': 'uptime 75.00% is below 99.9%'},
      ],
    },
    {
      'provider': 'other',
      'state': 'unknown',
      'lastProbe': null,
      'windowMinutes': 60,
      'sampleCount': 0,
      'uptimePercent': null,
      'avgLatencyMs': null,
      'p95LatencyMs': null,
      'breaches': [],
    },
  ],
};

ApiClient clientFor(
  Future<http.Response> Function(http.Request) handler, {
  http.Client Function(MockClientHandler)? make,
}) => ApiClient(baseUrl: 'http://api.test:9000', client: MockClient(handler));

void main() {
  test('getStatus parses services, probes and breaches', () async {
    late Uri seen;
    final client = clientFor((req) async {
      seen = req.url;
      return http.Response(jsonEncode(statusJson), 200);
    });

    final snapshot = await client.getStatus();

    expect(seen.toString(), 'http://api.test:9000/api/status');
    expect(snapshot.generatedAt, DateTime.utc(2026, 1, 1, 12));
    final s = snapshot.services.first;
    expect(s.provider, 'stripe');
    expect(s.state, ServiceState.down);
    expect(s.lastProbe!.statusCode, 500);
    expect(s.lastProbe!.success, isFalse);
    expect(s.uptimePercent, 75.0);
    expect(s.p95LatencyMs, 250);
    expect(s.breaches.single.type, 'uptime');
  });

  test('handles services with no data', () async {
    final client = clientFor(
      (_) async => http.Response(jsonEncode(statusJson), 200),
    );
    final s = (await client.getStatus()).services.last;
    expect(s.state, ServiceState.unknown);
    expect(s.lastProbe, isNull);
    expect(s.uptimePercent, isNull);
    expect(s.avgLatencyMs, isNull);
  });

  test('getHistory sends provider and minutes and parses points', () async {
    late Uri seen;
    final client = clientFor((req) async {
      seen = req.url;
      return http.Response(
        jsonEncode({
          'provider': 'stripe',
          'minutes': 30,
          'uptimePercent': 100.0,
          'points': [
            {
              'timestamp': '2026-01-01T11:50:00.000Z',
              'latencyMs': 120,
              'success': true,
              'statusCode': 200,
              'error': null,
            },
          ],
        }),
        200,
      );
    });

    final h = await client.getHistory('stripe', minutes: 30);

    expect(seen.path, '/api/history');
    expect(seen.queryParameters, {'provider': 'stripe', 'minutes': '30'});
    expect(h.uptimePercent, 100.0);
    expect(h.points.single.latencyMs, 120);
    expect(h.points.single.timestamp, DateTime.utc(2026, 1, 1, 11, 50));
  });

  test('non-200 responses become ApiException', () async {
    final client = clientFor((_) async => http.Response('{}', 404));
    expect(client.getStatus(), throwsA(isA<ApiException>()));
  });

  test('network errors become ApiException', () async {
    final client = clientFor((_) async => throw http.ClientException('down'));
    expect(
      client.getStatus(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('api.test'),
        ),
      ),
    );
  });

  test('malformed bodies become ApiException', () async {
    final client = clientFor((_) async => http.Response('not json', 200));
    expect(client.getStatus(), throwsA(isA<ApiException>()));
  });
}
