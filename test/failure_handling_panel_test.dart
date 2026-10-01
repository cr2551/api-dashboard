import 'dart:convert';

import 'package:api_dashboard/data/api_client.dart';
import 'package:api_dashboard/data/models.dart';
import 'package:api_dashboard/data/service_event.dart';
import 'package:api_dashboard/notifications/notification_center.dart';
import 'package:api_dashboard/notifications/notification_prefs.dart';
import 'package:api_dashboard/notifications/system_notifier.dart';
import 'package:api_dashboard/screens/service_detail_screen.dart';
import 'package:api_dashboard/screens/status_screen.dart';
import 'package:api_dashboard/widgets/failure_handling_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'notifications/fakes.dart';

ServiceSettings settings({
  int? intervalSeconds = 30,
  int? timeoutSeconds = 10,
  int retries = 1,
  int? expectedStatus,
  int maxP95LatencyMs = 1000,
  double minUptimePercent = 99.9,
  int windowMinutes = 60,
  int minSamples = 1,
  int consecutiveFailures = 1,
}) => ServiceSettings(
  intervalSeconds: intervalSeconds,
  timeoutSeconds: timeoutSeconds,
  retries: retries,
  expectedStatus: expectedStatus,
  maxP95LatencyMs: maxP95LatencyMs,
  minUptimePercent: minUptimePercent,
  windowMinutes: windowMinutes,
  minSamples: minSamples,
  consecutiveFailures: consecutiveFailures,
);

String text(ServiceSettings s, String title) =>
    describeHandling(s).firstWhere((step) => step.title == title).text;

ServiceEvent event(
  int id, {
  String provider = 'stripe',
  EventKind kind = EventKind.opened,
  String message = 'uptime 0.00% is below 99.9%',
  Duration? duration,
  DateTime? at,
}) => ServiceEvent(
  id: id,
  provider: provider,
  type: BreachType.uptime,
  kind: kind,
  message: message,
  timestamp: at ?? DateTime.utc(2026, 1, 1, 12, 5),
  duration: duration,
);

void main() {
  group('describeHandling uses the real numbers', () {
    test('checks mention the interval and the timeout', () {
      expect(
        text(settings(), 'Checks'),
        'Checks every 30s with a GET request and waits up to 10s for an answer.',
      );
    });

    test('unknown interval and timeout are left out, not invented', () {
      final t = text(
        settings(intervalSeconds: null, timeoutSeconds: null),
        'Checks',
      );
      expect(t, 'Checks on a schedule with a GET request.');
      expect(t, isNot(contains('null')));
    });

    test('one retry is singular and 4xx/5xx are said not to be retried', () {
      final t = text(settings(retries: 1), 'Retries');
      expect(t, contains('retries 1 time right away'));
      expect(t, contains('4xx and 5xx'));
      expect(t, contains('not retried'));
    });

    test('several retries are plural', () {
      expect(text(settings(retries: 3), 'Retries'), contains('3 times'));
    });

    test('no retries says the first failure counts', () {
      expect(
        text(settings(retries: 0), 'Retries'),
        'A failed check is never retried: the first failure counts.',
      );
    });

    test('failure definition follows expectedStatus', () {
      expect(
        text(settings(), 'What counts as a failure'),
        contains('other than a 2xx'),
      );
      expect(
        text(settings(expectedStatus: 204), 'What counts as a failure'),
        contains('other than HTTP 204'),
      );
    });

    test('the SLA step states the thresholds and the window', () {
      final t = text(
        settings(minUptimePercent: 99, maxP95LatencyMs: 750, windowMinutes: 30),
        'Judging the SLA',
      );
      expect(t, contains('last 30 min'));
      expect(t, contains('at least 99%'));
      expect(t, contains('under 750 ms'));
      expect(t, isNot(contains('does not judge')));
    });

    test('a fractional uptime keeps its decimals', () {
      expect(text(settings(), 'Judging the SLA'), contains('at least 99.9%'));
    });

    test('minimum samples explains when nothing is judged yet', () {
      expect(
        text(settings(minSamples: 5), 'Judging the SLA'),
        contains('fewer than 5 checks'),
      );
    });

    test('debounce is explained only when it is on', () {
      expect(
        text(settings(consecutiveFailures: 1), 'Before alerting'),
        'A breach is reported as soon as it is detected.',
      );
      expect(
        text(settings(consecutiveFailures: 3), 'Before alerting'),
        contains('3 checks in a row'),
      );
    });

    test('alerting always says one alert on open and one on recovery', () {
      expect(text(settings(), 'Alerting'), contains('opens'));
      expect(text(settings(), 'Alerting'), contains('recovers'));
    });
  });

  group('ServiceSettings parsing', () {
    final json = {
      'intervalSeconds': 45,
      'timeoutSeconds': null,
      'retries': 1,
      'expectedStatus': 204,
      'maxP95LatencyMs': 750,
      'minUptimePercent': 99,
      'windowMinutes': 30,
      'minSamples': 5,
      'consecutiveFailures': 3,
    };

    test('reads every field, including nulls and integer percentages', () {
      final s = ServiceSettings.fromJson(json);
      expect(s.intervalSeconds, 45);
      expect(s.timeoutSeconds, isNull);
      expect(s.expectedStatus, 204);
      expect(s.minUptimePercent, 99.0);
      expect(s.consecutiveFailures, 3);
    });

    Map<String, dynamic> service({Object? settingsJson = 'absent'}) => {
      'provider': 'stripe',
      'state': 'up',
      'lastProbe': null,
      'windowMinutes': 60,
      'sampleCount': 0,
      'uptimePercent': null,
      'avgLatencyMs': null,
      'p95LatencyMs': null,
      'breaches': <Object>[],
      if (settingsJson != 'absent') 'settings': settingsJson,
    };

    test('a status carries settings, and older backends have none', () {
      expect(
        ServiceStatus.fromJson(service(settingsJson: json)).settings,
        isNotNull,
      );
      expect(ServiceStatus.fromJson(service()).settings, isNull);
      expect(
        ServiceStatus.fromJson(service(settingsJson: null)).settings,
        isNull,
      );
    });
  });

  group('FailureHandlingPanel', () {
    final now = DateTime.utc(2026, 1, 1, 12, 10);

    Widget panel({
      List<ServiceEvent> events = const [],
      bool expanded = true,
    }) => MaterialApp(
      home: Scaffold(
        body: FailureHandlingPanel(
          settings: settings(consecutiveFailures: 2),
          events: events,
          now: now,
          initiallyExpanded: expanded,
        ),
      ),
    );

    testWidgets('is collapsed to a title by default', (tester) async {
      await tester.pumpWidget(panel(expanded: false));
      expect(find.text('How failures are handled'), findsOneWidget);
      expect(find.textContaining('Checks every 30s'), findsNothing);

      await tester.tap(find.text('How failures are handled'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Checks every 30s', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('explains every step with the real settings', (tester) async {
      await tester.pumpWidget(panel());
      for (final fragment in [
        'Checks every 30s',
        'retries 1 time',
        'other than a 2xx',
        'at least 99.9%',
        '2 checks in a row',
        'One alert when a breach opens',
      ]) {
        expect(
          find.textContaining(fragment, findRichText: true),
          findsOneWidget,
          reason: fragment,
        );
      }
    });

    testWidgets('says when there are no alerts yet', (tester) async {
      await tester.pumpWidget(panel());
      expect(find.text('Recent alerts for this service'), findsOneWidget);
      expect(find.text('None yet.'), findsOneWidget);
    });

    testWidgets('lists recent alerts with what happened and when', (
      tester,
    ) async {
      await tester.pumpWidget(
        panel(
          events: [
            event(
              2,
              kind: EventKind.resolved,
              duration: const Duration(minutes: 2),
              at: DateTime.utc(2026, 1, 1, 12, 9),
            ),
            event(1),
          ],
        ),
      );
      expect(find.text('None yet.'), findsNothing);
      expect(
        find.textContaining(
          'Recovered: Uptime is back within SLA after 2m 0s · 1m ago',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Breach: uptime 0.00% is below 99.9% · 5m ago'),
        findsOneWidget,
      );
    });

    testWidgets('shows only the five most recent alerts', (tester) async {
      await tester.pumpWidget(
        panel(
          events: [
            for (var i = 8; i >= 1; i--) event(i, message: 'breach number $i'),
          ],
        ),
      );
      expect(find.textContaining('breach number 8'), findsOneWidget);
      expect(find.textContaining('breach number 4'), findsOneWidget);
      expect(find.textContaining('breach number 3'), findsNothing);
    });
  });

  group('detail screen', () {
    late FakeEventsBackend backend;
    late NotificationCenter center;

    ApiClient client() => ApiClient(
      baseUrl: 'http://api.test',
      client: MockClient((req) async {
        if (req.url.path == '/api/events') return backend.handle(req);
        return http.Response(
          jsonEncode({
            'provider': 'stripe',
            'minutes': 60,
            'uptimePercent': 100.0,
            'points': <Object>[],
          }),
          200,
        );
      }),
    );

    setUp(() {
      backend = FakeEventsBackend();
      center = NotificationCenter(
        client: client(),
        notifier: FakeNotifier(current: NotifPermission.unsupported),
        prefs: MemoryNotificationPrefs(),
      );
    });
    tearDown(() => center.dispose());

    Widget screen({ServiceSettings? withSettings, NotificationCenter? c}) =>
        MaterialApp(
          home: ServiceDetailScreen(
            client: client(),
            provider: 'stripe',
            settings: withSettings,
            notifications: c,
          ),
        );

    testWidgets('fits a short landscape screen with everything expanded', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(700, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(screen(withSettings: settings(minSamples: 5)));
      await tester.pumpAndSettle();
      // Below the fold on a short screen, so scroll to it first.
      final list = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('How failures are handled'),
        100,
        scrollable: list,
      );
      // Bring the title away from the screen edge so the tap lands on it.
      await tester.drag(list, const Offset(0, -120));
      await tester.pumpAndSettle();
      await tester.tap(find.text('How failures are handled'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Checks every 30s', findRichText: true),
        findsOneWidget,
        reason: 'the section expanded',
      );

      expect(tester.takeException(), isNull, reason: 'no overflow');
      // The end of the expanded section is reachable by scrolling.
      await tester.drag(list, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Recent alerts for this service'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no panel without settings (older backend)', (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.text('How failures are handled'), findsNothing);
    });

    testWidgets('shows the panel when settings are known', (tester) async {
      await tester.pumpWidget(screen(withSettings: settings()));
      await tester.pumpAndSettle();
      expect(find.text('How failures are handled'), findsOneWidget);
    });

    testWidgets('lists only this service\'s alerts and updates live', (
      tester,
    ) async {
      await tester.runAsync(center.init);
      await tester.runAsync(center.poll);
      await tester.pumpWidget(screen(withSettings: settings(), c: center));
      await tester.pumpAndSettle();
      await tester.tap(find.text('How failures are handled'));
      await tester.pumpAndSettle();
      expect(find.text('None yet.'), findsOneWidget);

      await tester.runAsync(() async {
        backend
          ..add(eventJson(1, provider: 'github', message: 'github is down'))
          ..add(eventJson(2, message: 'stripe is down'));
        await center.poll();
      });
      await tester.pump();

      expect(find.textContaining('stripe is down'), findsOneWidget);
      expect(find.textContaining('github is down'), findsNothing);
      expect(find.text('None yet.'), findsNothing);
    });

    testWidgets('the status screen passes the settings through', (
      tester,
    ) async {
      final status = {
        'generatedAt': '2026-01-01T12:00:00.000Z',
        'services': [
          {
            'provider': 'stripe',
            'state': 'up',
            'lastProbe': null,
            'windowMinutes': 60,
            'sampleCount': 0,
            'uptimePercent': null,
            'avgLatencyMs': null,
            'p95LatencyMs': null,
            'breaches': <Object>[],
            'settings': {
              'intervalSeconds': 30,
              'timeoutSeconds': 10,
              'retries': 1,
              'expectedStatus': null,
              'maxP95LatencyMs': 1000,
              'minUptimePercent': 99.9,
              'windowMinutes': 60,
              'minSamples': 1,
              'consecutiveFailures': 1,
            },
          },
        ],
      };
      final c = ApiClient(
        baseUrl: 'http://api.test',
        client: MockClient((req) async {
          if (req.url.path == '/api/status') {
            return http.Response(jsonEncode(status), 200);
          }
          return http.Response(
            jsonEncode({
              'provider': 'stripe',
              'minutes': 60,
              'uptimePercent': null,
              'points': <Object>[],
            }),
            200,
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: StatusScreen(client: c, refreshInterval: null)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stripe'));
      await tester.pumpAndSettle();

      expect(find.text('How failures are handled'), findsOneWidget);
    });
  });
}
