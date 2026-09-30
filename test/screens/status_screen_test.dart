import 'dart:convert';

import 'package:api_dashboard/data/api_client.dart';
import 'package:api_dashboard/data/models.dart';
import 'package:api_dashboard/screens/status_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> service({
  String state = 'up',
  bool lastOk = true,
  List<Map<String, String>> breaches = const [],
  bool noData = false,
}) => {
  'provider': 'stripe',
  'state': noData ? 'unknown' : state,
  'lastProbe': noData
      ? null
      : {
          'timestamp': '2026-01-01T11:59:40.000Z',
          'latencyMs': 180,
          'success': lastOk,
          'statusCode': lastOk ? 200 : 500,
          'error': lastOk ? null : 'HTTP 500',
        },
  'windowMinutes': 60,
  'sampleCount': noData ? 0 : 10,
  'uptimePercent': noData ? null : 98.5,
  'avgLatencyMs': noData ? null : 210,
  'p95LatencyMs': noData ? null : 430,
  'breaches': breaches,
};

String snapshot(List<Map<String, dynamic>> services) => jsonEncode({
  'generatedAt': '2026-01-01T12:00:00.000Z',
  'services': services,
});

Widget app(
  ApiClient client, {
  Duration? refresh,
  void Function(ServiceStatus)? onOpen,
}) => MaterialApp(
  home: StatusScreen(
    client: client,
    refreshInterval: refresh,
    onOpenService: onOpen,
  ),
);

ApiClient clientFor(Future<http.Response> Function(http.Request) h) =>
    ApiClient(baseUrl: 'http://api.test', client: MockClient(h));

void main() {
  testWidgets('shows a spinner then the service card', (tester) async {
    await tester.pumpWidget(
      app(clientFor((_) async => http.Response(snapshot([service()]), 200))),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Stripe'), findsOneWidget);
    expect(find.text('Operational'), findsOneWidget);
    expect(find.text('98.50%'), findsOneWidget);
    expect(find.text('180 ms'), findsOneWidget);
    expect(find.text('210 ms'), findsOneWidget);
    expect(find.text('430 ms'), findsOneWidget);
    expect(find.text('Last probe 20s ago'), findsOneWidget);
  });

  testWidgets('shows down state, probe error and SLA breach', (tester) async {
    final body = snapshot([
      service(
        state: 'down',
        lastOk: false,
        breaches: [
          {'type': 'uptime', 'message': 'uptime 80.00% is below 99.9%'},
        ],
      ),
    ]);
    await tester.pumpWidget(
      app(clientFor((_) async => http.Response(body, 200))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Down'), findsOneWidget);
    expect(find.textContaining('HTTP 500'), findsOneWidget);
    expect(
      find.text('SLA breach: uptime 80.00% is below 99.9%'),
      findsOneWidget,
    );
  });

  testWidgets('shows a no-data state', (tester) async {
    await tester.pumpWidget(
      app(
        clientFor(
          (_) async => http.Response(snapshot([service(noData: true)]), 200),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No data'), findsWidgets);
    expect(
      find.textContaining('No probes in the last 60 minutes'),
      findsOneWidget,
    );
  });

  testWidgets('shows an error with retry when the backend is down', (
    tester,
  ) async {
    var fail = true;
    await tester.pumpWidget(
      app(
        clientFor((_) async {
          if (fail) throw http.ClientException('offline');
          return http.Response(snapshot([service()]), 200);
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Cannot reach the backend'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Stripe'), findsOneWidget);
    expect(find.textContaining('Cannot reach'), findsNothing);
  });

  testWidgets('keeps last data and shows a banner if a refresh fails', (
    tester,
  ) async {
    var fail = false;
    await tester.pumpWidget(
      app(
        clientFor((_) async {
          if (fail) throw http.ClientException('offline');
          return http.Response(snapshot([service()]), 200);
        }),
        refresh: const Duration(seconds: 5),
      ),
    );
    await tester.pumpAndSettle();

    fail = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('Stripe'), findsOneWidget);
    expect(find.textContaining('Showing last known data'), findsOneWidget);
  });

  testWidgets('auto-refreshes on the interval', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      app(
        clientFor((_) async {
          calls++;
          return http.Response(snapshot([service()]), 200);
        }),
        refresh: const Duration(seconds: 5),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('tapping a card reports the service', (tester) async {
    ServiceStatus? opened;
    await tester.pumpWidget(
      app(
        clientFor((_) async => http.Response(snapshot([service()]), 200)),
        onOpen: (s) => opened = s,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stripe'));

    expect(opened?.provider, 'stripe');
  });

  testWidgets('tells the user when no services are monitored', (tester) async {
    await tester.pumpWidget(
      app(clientFor((_) async => http.Response(snapshot([]), 200))),
    );
    await tester.pumpAndSettle();
    expect(find.text('No services are being monitored.'), findsOneWidget);
  });
}
