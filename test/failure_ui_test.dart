import 'dart:convert';

import 'package:api_dashboard/data/api_client.dart';
import 'package:api_dashboard/data/failure_kind.dart';
import 'package:api_dashboard/data/models.dart';
import 'package:api_dashboard/screens/service_detail_screen.dart';
import 'package:api_dashboard/screens/status_screen.dart';
import 'package:api_dashboard/widgets/failure_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> probe({
  bool ok = true,
  String? kind,
  int minute = 0,
  String? error,
}) => {
  'timestamp': DateTime.utc(2026, 1, 1, 12, minute).toIso8601String(),
  'latencyMs': 100,
  'success': ok,
  'statusCode': ok ? 200 : 503,
  'error': ok ? null : (error ?? 'HTTP 503'),
  'errorKind': kind,
};

Map<String, dynamic> service(Map<String, dynamic> last) => {
  'provider': 'stripe',
  'state': last['success'] == true ? 'up' : 'down',
  'lastProbe': last,
  'windowMinutes': 60,
  'sampleCount': 5,
  'uptimePercent': 80.0,
  'avgLatencyMs': 100,
  'p95LatencyMs': 120,
  'breaches': <Object>[],
};

ApiClient client({
  Map<String, dynamic>? last,
  List<Map<String, dynamic>> points = const [],
}) => ApiClient(
  baseUrl: 'http://api.test',
  client: MockClient((req) async {
    if (req.url.path == '/api/status') {
      return http.Response(
        jsonEncode({
          'generatedAt': '2026-01-01T12:05:00.000Z',
          'services': [service(last ?? probe())],
        }),
        200,
      );
    }
    return http.Response(
      jsonEncode({
        'provider': 'stripe',
        'minutes': 60,
        'uptimePercent': 80.0,
        'points': points,
      }),
      200,
    );
  }),
);

Future<void> pumpStatus(WidgetTester tester, ApiClient c) async {
  await tester.pumpWidget(
    // A fresh key so pumping twice in one test rebuilds the state.
    MaterialApp(
      home: StatusScreen(key: UniqueKey(), client: c, refreshInterval: null),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('FailureKind.parse', () {
    test('maps every backend name', () {
      for (final kind in FailureKind.values) {
        expect(FailureKind.parse(kind.name), kind);
      }
    });

    test('null stays null and unknown names become other', () {
      expect(FailureKind.parse(null), isNull);
      expect(FailureKind.parse('quantum-glitch'), FailureKind.other);
    });

    test('every kind has a label, an icon and a hint', () {
      for (final kind in FailureKind.values) {
        expect(kind.label, isNotEmpty);
        expect(kind.hint, isNotEmpty);
      }
    });
  });

  test('ProbePoint reads errorKind', () {
    final p = ProbePoint.fromJson(probe(ok: false, kind: 'tls'));
    expect(p.errorKind, FailureKind.tls);
    expect(ProbePoint.fromJson(probe()).errorKind, isNull);
    // Older backends do not send the field at all.
    final old = probe(ok: false)..remove('errorKind');
    expect(ProbePoint.fromJson(old).errorKind, isNull);
  });

  group('FailureChip', () {
    testWidgets('shows the label, a count and the hint as a tooltip', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FailureChip(kind: FailureKind.timeout, count: 3),
          ),
        ),
      );
      expect(find.text('Timeout × 3'), findsOneWidget);
      expect(find.byIcon(Icons.timer_off_outlined), findsOneWidget);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        FailureKind.timeout.hint,
      );
    });

    testWidgets('a missing kind reads Unclassified', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FailureChip(kind: null))),
      );
      expect(find.text('Unclassified'), findsOneWidget);
    });
  });

  group('service card', () {
    testWidgets('a failed probe shows its failure type', (tester) async {
      await pumpStatus(tester, client(last: probe(ok: false, kind: 'http5xx')));
      expect(find.byType(FailureChip), findsOneWidget);
      expect(find.text('HTTP 5xx'), findsOneWidget);
    });

    testWidgets('each kind is labelled', (tester) async {
      final labels = {
        'timeout': 'Timeout',
        'connection': 'Connection / DNS',
        'tls': 'TLS / certificate',
        'http4xx': 'HTTP 4xx',
        'other': 'Other',
      };
      for (final e in labels.entries) {
        await pumpStatus(tester, client(last: probe(ok: false, kind: e.key)));
        expect(find.text(e.value), findsOneWidget, reason: e.key);
      }
    });

    testWidgets('a failure with no category says Unclassified', (tester) async {
      await pumpStatus(tester, client(last: probe(ok: false)));
      expect(find.text('Unclassified'), findsOneWidget);
    });

    testWidgets('a healthy service shows no failure chip', (tester) async {
      await pumpStatus(tester, client());
      expect(find.byType(FailureChip), findsNothing);
    });
  });

  group('detail screen', () {
    Future<void> openDetail(WidgetTester tester, ApiClient c) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ServiceDetailScreen(client: c, provider: 'stripe'),
        ),
      );
      await tester.pumpAndSettle();
    }

    test('failureCounts groups by kind, most frequent first', () {
      final points = [
        for (final j in [
          probe(),
          probe(ok: false, kind: 'timeout'),
          probe(ok: false, kind: 'http5xx'),
          probe(ok: false, kind: 'http5xx'),
          probe(ok: false),
        ])
          ProbePoint.fromJson(j),
      ];
      final counts = failureCounts(points);
      expect(counts.map((e) => e.key), [
        FailureKind.http5xx,
        FailureKind.timeout,
        null,
      ]);
      expect(counts.map((e) => e.value), [2, 1, 1]);
    });

    testWidgets('summarises failure types with counts and a hint', (
      tester,
    ) async {
      await openDetail(
        tester,
        client(
          points: [
            probe(minute: 0),
            probe(ok: false, kind: 'timeout', minute: 1),
            probe(ok: false, kind: 'http5xx', minute: 2),
            probe(ok: false, kind: 'http5xx', minute: 3),
          ],
        ),
      );

      expect(find.text('Failure types'), findsOneWidget);
      expect(find.text('HTTP 5xx × 2'), findsOneWidget);
      expect(find.text('Timeout × 1'), findsOneWidget);
      expect(
        find.textContaining(
          'Most recent: HTTP 5xx. ${FailureKind.http5xx.hint}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no failure section when every probe succeeded', (
      tester,
    ) async {
      await openDetail(tester, client(points: [probe(), probe(minute: 1)]));
      expect(find.text('Failure types'), findsNothing);
      expect(find.byType(FailureChip), findsNothing);
    });
  });
}
