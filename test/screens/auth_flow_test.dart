import 'dart:convert';

import 'package:api_dashboard/data/api_client.dart';
import 'package:api_dashboard/screens/service_detail_screen.dart';
import 'package:api_dashboard/screens/status_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const goodToken = 'good-token';

final statusBody = jsonEncode({
  'generatedAt': '2026-01-01T12:00:00.000Z',
  'services': [
    {
      'provider': 'stripe',
      'state': 'up',
      'lastProbe': {
        'timestamp': '2026-01-01T11:59:40.000Z',
        'latencyMs': 180,
        'success': true,
        'statusCode': 200,
        'error': null,
      },
      'windowMinutes': 60,
      'sampleCount': 10,
      'uptimePercent': 99.0,
      'avgLatencyMs': 200,
      'p95LatencyMs': 400,
      'breaches': <Object>[],
    },
  ],
});

final historyBody = jsonEncode({
  'provider': 'stripe',
  'minutes': 60,
  'uptimePercent': 100.0,
  'points': [
    {
      'timestamp': '2026-01-01T12:00:00.000Z',
      'latencyMs': 100,
      'success': true,
      'statusCode': 200,
      'error': null,
    },
  ],
});

/// A backend that behaves like the real one with API_TOKEN=[goodToken].
class FakeBackend {
  final requests = <http.Request>[];

  Future<http.Response> handle(http.Request req) async {
    requests.add(req);
    if (req.headers['Authorization'] != 'Bearer $goodToken') {
      return http.Response('{"error":"unauthorized"}', 401);
    }
    return http.Response(
      req.url.path == '/api/status' ? statusBody : historyBody,
      200,
    );
  }
}

ApiClient clientFor(FakeBackend backend, {String? token}) => ApiClient(
  baseUrl: 'http://api.test',
  apiToken: token,
  client: MockClient(backend.handle),
);

Future<void> enterToken(WidgetTester tester, String token) async {
  await tester.enterText(find.byType(TextField), token);
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  group('status screen', () {
    Widget app(ApiClient c, {Duration? refresh}) => MaterialApp(
      home: StatusScreen(client: c, refreshInterval: refresh),
    );

    testWidgets('a 401 without a token offers to enter one', (tester) async {
      await tester.pumpWidget(app(clientFor(FakeBackend())));
      await tester.pumpAndSettle();

      expect(find.textContaining('requires an access token'), findsOneWidget);
      expect(find.text('Enter access token'), findsOneWidget);
      expect(find.text('Stripe'), findsNothing);
    });

    testWidgets('entering the right token loads the dashboard', (tester) async {
      final backend = FakeBackend();
      final client = clientFor(backend);
      await tester.pumpWidget(app(client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter access token'));
      await tester.pumpAndSettle();
      expect(find.text('Backend access token'), findsOneWidget);
      await enterToken(tester, goodToken);

      expect(find.text('Stripe'), findsOneWidget);
      expect(find.textContaining('access token'), findsNothing);
      expect(client.apiToken, goodToken);
      expect(
        backend.requests.last.headers['Authorization'],
        'Bearer $goodToken',
      );
    });

    testWidgets('a wrong token says it was rejected and can be retried', (
      tester,
    ) async {
      final client = clientFor(FakeBackend());
      await tester.pumpWidget(app(client));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Enter access token'));
      await tester.pumpAndSettle();
      await enterToken(tester, 'nope');
      expect(find.textContaining('rejected'), findsOneWidget);

      // The dialog now says the last token was rejected.
      await tester.tap(find.text('Enter access token'));
      await tester.pumpAndSettle();
      expect(find.textContaining('last token was rejected'), findsOneWidget);
      await enterToken(tester, goodToken);
      expect(find.text('Stripe'), findsOneWidget);
    });

    testWidgets('a preconfigured token works without any prompt', (
      tester,
    ) async {
      await tester.pumpWidget(app(clientFor(FakeBackend(), token: goodToken)));
      await tester.pumpAndSettle();
      expect(find.text('Stripe'), findsOneWidget);
      expect(find.text('Enter access token'), findsNothing);
    });

    testWidgets('cancelling the dialog changes nothing', (tester) async {
      final backend = FakeBackend();
      await tester.pumpWidget(app(clientFor(backend)));
      await tester.pumpAndSettle();
      final before = backend.requests.length;

      await tester.tap(find.text('Enter access token'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(backend.requests.length, before);
      expect(find.text('Enter access token'), findsOneWidget);
    });

    testWidgets('the app bar key button can change the token', (tester) async {
      final client = clientFor(FakeBackend(), token: goodToken);
      await tester.pumpWidget(app(client));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Access token'));
      await tester.pumpAndSettle();
      await enterToken(tester, 'changed');

      expect(client.apiToken, 'changed');
      expect(find.textContaining('rejected'), findsOneWidget);
    });

    testWidgets('the token field hides the value until asked', (tester) async {
      await tester.pumpWidget(app(clientFor(FakeBackend())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter access token'));
      await tester.pumpAndSettle();

      EditableText field() =>
          tester.widget<EditableText>(find.byType(EditableText));
      expect(field().obscureText, isTrue);
      await tester.tap(find.byTooltip('Show token'));
      await tester.pump();
      expect(field().obscureText, isFalse);
    });

    testWidgets('the token dialog does not overflow on a short screen', (
      tester,
    ) async {
      // A phone in landscape (the browser pane that showed the bug was 365 px tall).
      tester.view.physicalSize = const Size(700, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app(clientFor(FakeBackend())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter access token'));
      await tester.pumpAndSettle();

      expect(find.text('Backend access token'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('polling stops while unauthorized', (tester) async {
      final backend = FakeBackend();
      await tester.pumpWidget(
        app(clientFor(backend), refresh: const Duration(seconds: 10)),
      );
      await tester.pumpAndSettle();
      final after = backend.requests.length;

      await tester.pump(const Duration(seconds: 35));
      expect(backend.requests.length, after);
    });
  });

  group('detail screen', () {
    Widget app(ApiClient c) => MaterialApp(
      home: ServiceDetailScreen(client: c, provider: 'stripe'),
    );

    testWidgets('a 401 offers the token prompt and recovers', (tester) async {
      final client = clientFor(FakeBackend());
      await tester.pumpWidget(app(client));
      await tester.pumpAndSettle();

      expect(find.textContaining('requires an access token'), findsOneWidget);
      await tester.tap(find.text('Enter access token'));
      await tester.pumpAndSettle();
      await enterToken(tester, goodToken);

      expect(find.textContaining('access token'), findsNothing);
      expect(client.apiToken, goodToken);
    });
  });
}
