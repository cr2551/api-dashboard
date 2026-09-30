import 'dart:convert';

import 'package:api_dashboard/data/api_client.dart';
import 'package:api_dashboard/screens/service_detail_screen.dart';
import 'package:api_dashboard/screens/status_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> point(int minute, int ms, {bool ok = true}) => {
  'timestamp': DateTime.utc(2026, 1, 1, 12, minute).toIso8601String(),
  'latencyMs': ms,
  'success': ok,
  'statusCode': ok ? 200 : 500,
  'error': ok ? null : 'HTTP 500',
};

String history(List<Map<String, dynamic>> points, {int minutes = 60}) =>
    jsonEncode({
      'provider': 'stripe',
      'minutes': minutes,
      'uptimePercent': points.isEmpty
          ? null
          : points.where((p) => p['success'] == true).length *
                100 /
                points.length,
      'points': points,
    });

ApiClient clientFor(Future<http.Response> Function(http.Request) h) =>
    ApiClient(baseUrl: 'http://api.test', client: MockClient(h));

Widget app(ApiClient client, {int minutes = 60}) => MaterialApp(
  home: ServiceDetailScreen(
    client: client,
    provider: 'stripe',
    initialMinutes: minutes,
  ),
);

void main() {
  testWidgets('shows uptime, stats and a latency chart', (tester) async {
    late Uri seen;
    await tester.pumpWidget(
      app(
        clientFor((req) async {
          seen = req.url;
          return http.Response(
            history([
              point(0, 100),
              point(1, 300),
              point(2, 200, ok: false),
              point(3, 200),
            ]),
            200,
          );
        }),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    expect(seen.queryParameters, {'provider': 'stripe', 'minutes': '60'});
    expect(find.text('Stripe'), findsOneWidget);
    expect(find.text('75.00%'), findsOneWidget);
    expect(find.text('Uptime (1 hour)'), findsOneWidget);
    expect(find.text('100 / 300 ms'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('changing the range reloads with the new window', (tester) async {
    final requested = <String>[];
    await tester.pumpWidget(
      app(
        clientFor((req) async {
          requested.add(req.url.queryParameters['minutes']!);
          return http.Response(history([point(0, 100)]), 200);
        }),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('24 hours'));
    await tester.pumpAndSettle();

    expect(requested, ['60', '1440']);
    expect(find.text('Uptime (24 hours)'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no probes', (tester) async {
    await tester.pumpWidget(
      app(clientFor((_) async => http.Response(history([]), 200))),
    );
    await tester.pumpAndSettle();

    expect(find.text('No probes in this time range'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('shows an error with retry', (tester) async {
    var fail = true;
    await tester.pumpWidget(
      app(
        clientFor((_) async {
          if (fail) return http.Response('{}', 500);
          return http.Response(history([point(0, 100)]), 200);
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 500'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('tapping a card on the status screen opens the detail', (
    tester,
  ) async {
    final client = clientFor((req) async {
      if (req.url.path == '/api/status') {
        return http.Response(
          jsonEncode({
            'generatedAt': '2026-01-01T12:00:00.000Z',
            'services': [
              {
                'provider': 'stripe',
                'state': 'up',
                'lastProbe': point(0, 100),
                'windowMinutes': 60,
                'sampleCount': 1,
                'uptimePercent': 100.0,
                'avgLatencyMs': 100,
                'p95LatencyMs': 100,
                'breaches': [],
              },
            ],
          }),
          200,
        );
      }
      return http.Response(history([point(0, 100)]), 200);
    });
    await tester.pumpWidget(
      MaterialApp(home: StatusScreen(client: client, refreshInterval: null)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stripe'));
    await tester.pumpAndSettle();

    expect(find.byType(ServiceDetailScreen), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
  });
}
