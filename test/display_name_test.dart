import 'dart:convert';

import 'package:api_dashboard/data/api_client.dart';
import 'package:api_dashboard/data/models.dart';
import 'package:api_dashboard/screens/status_screen.dart';
import 'package:api_dashboard/widgets/service_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> service(
  String provider, {
  Object? displayName = 'absent',
}) => {
  'provider': provider,
  if (displayName != 'absent') 'displayName': displayName,
  'state': 'up',
  'lastProbe': {
    'timestamp': '2026-01-01T11:59:40.000Z',
    'latencyMs': 100,
    'success': true,
    'statusCode': 200,
    'error': null,
  },
  'windowMinutes': 60,
  'sampleCount': 5,
  'uptimePercent': 100.0,
  'avgLatencyMs': 100,
  'p95LatencyMs': 120,
  'breaches': <Object>[],
};

ApiClient clientWith(List<Map<String, dynamic>> services) => ApiClient(
  baseUrl: 'http://api.test',
  client: MockClient((req) async {
    if (req.url.path == '/api/status') {
      return http.Response(
        jsonEncode({
          'generatedAt': '2026-01-01T12:00:00.000Z',
          'services': services,
        }),
        200,
      );
    }
    return http.Response(
      jsonEncode({
        'provider': req.url.queryParameters['provider'],
        'minutes': 60,
        'uptimePercent': 100.0,
        'points': <Object>[],
      }),
      200,
    );
  }),
);

void main() {
  group('providerLabel', () {
    test('uses the display name when there is one', () {
      expect(providerLabel('github', displayName: 'GitHub'), 'GitHub');
    });

    test('capitalises the key when there is none', () {
      expect(providerLabel('github'), 'Github');
      expect(providerLabel('github', displayName: null), 'Github');
    });

    test('ignores a blank display name', () {
      expect(providerLabel('github', displayName: '  '), 'Github');
      expect(providerLabel('', displayName: null), '');
    });
  });

  group('ServiceStatus.fromJson', () {
    test('reads displayName', () {
      final s = ServiceStatus.fromJson(
        service('github', displayName: 'GitHub'),
      );
      expect(s.displayName, 'GitHub');
    });

    test('accepts a missing or null displayName (older backends)', () {
      expect(ServiceStatus.fromJson(service('github')).displayName, isNull);
      expect(
        ServiceStatus.fromJson(service('github', displayName: null))
            .displayName,
        isNull,
      );
    });
  });

  group('dashboard', () {
    testWidgets('cards show the display name, falling back to the key', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StatusScreen(
            client: clientWith([
              service('github', displayName: 'GitHub'),
              service('httpbin'),
            ]),
            refreshInterval: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Github'), findsNothing);
      expect(find.text('Httpbin'), findsOneWidget);
    });

    testWidgets('the detail screen title uses the display name', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StatusScreen(
            client: clientWith([service('github', displayName: 'GitHub')]),
            refreshInterval: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('GitHub'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('GitHub')),
        findsOneWidget,
      );
    });
  });
}
