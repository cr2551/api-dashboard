import 'dart:convert';

import 'package:api_dashboard/data/api_client.dart';
import 'package:api_dashboard/data/service_event.dart';
import 'package:api_dashboard/notifications/notification_center.dart';
import 'package:api_dashboard/notifications/notification_prefs.dart';
import 'package:api_dashboard/notifications/system_notifier.dart';
import 'package:api_dashboard/screens/notifications_screen.dart';
import 'package:api_dashboard/screens/status_screen.dart';
import 'package:api_dashboard/widgets/notification_bell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

final now = DateTime.utc(2026, 1, 1, 12, 10);

void main() {
  late FakeEventsBackend backend;
  late FakeNotifier notifier;
  late NotificationCenter center;

  setUp(() {
    backend = FakeEventsBackend();
    notifier = FakeNotifier(current: NotifPermission.undecided);
    center = NotificationCenter(
      client: backend.client(),
      notifier: notifier,
      prefs: MemoryNotificationPrefs(),
    );
  });
  tearDown(() => center.dispose());

  /// Loads the existing events as silent history, then adds new ones.
  Future<void> arrive(List<Map<String, dynamic>> events) async {
    await center.init();
    await center.poll();
    events.forEach(backend.add);
    await center.poll();
  }

  group('ServiceEvent', () {
    test('an opened breach reads as a headline and the raw message', () {
      final e = ServiceEvent.fromJson(
        eventJson(1, displayName: 'GitHub', message: 'uptime 0% is low'),
      );
      expect(e.title, 'SLA breach: GitHub');
      expect(e.body, 'uptime 0% is low');
      expect(e.kind, EventKind.opened);
      expect(e.type, BreachType.uptime);
      expect(e.duration, isNull);
    });

    test('a recovery includes the duration', () {
      final e = ServiceEvent.fromJson(
        eventJson(2, kind: 'resolved', type: 'latency', durationSeconds: 3725),
      );
      expect(e.title, 'Recovered: Stripe');
      expect(e.body, 'Latency is back within SLA after 1h 2m');
    });

    test('falls back to the capitalised key and an unknown type', () {
      final e = ServiceEvent.fromJson(eventJson(3, type: 'mystery'));
      expect(e.serviceLabel, 'Stripe');
      expect(e.type, BreachType.uptime);
    });

    test('formatEventDuration picks a readable unit', () {
      expect(formatEventDuration(const Duration(seconds: 45)), '45s');
      expect(
        formatEventDuration(const Duration(minutes: 12, seconds: 5)),
        '12m 5s',
      );
      expect(
        formatEventDuration(const Duration(hours: 2, minutes: 3)),
        '2h 3m',
      );
    });
  });

  group('ApiClient.getEvents', () {
    test('sends after and limit and parses the events', () async {
      backend
        ..add(eventJson(1))
        ..add(eventJson(2, kind: 'resolved', durationSeconds: 30));
      final list = await backend.client().getEvents(after: 0, limit: 5);

      expect(backend.requests.single.queryParameters, {
        'after': '0',
        'limit': '5',
      });
      expect(list.map((e) => e.id), [1, 2]);
      expect(list.last.duration, const Duration(seconds: 30));
    });

    test('omits after when it is null', () async {
      await backend.client().getEvents();
      expect(
        backend.requests.single.queryParameters.containsKey('after'),
        isFalse,
      );
    });

    test('a 401 is an UnauthorizedException', () async {
      backend.failWith = 401;
      expect(
        backend.client().getEvents(),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('a malformed body is an ApiException', () async {
      final client = ApiClient(
        baseUrl: 'http://api.test',
        client: MockClient(
          (_) async => http.Response(jsonEncode({'events': 'nope'}), 200),
        ),
      );
      expect(client.getEvents(), throwsA(isA<ApiException>()));
    });
  });

  group('NotificationBell', () {
    Widget bell() => MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: [NotificationBell(center: center, onPressed: () {})],
        ),
      ),
    );

    testWidgets('has no badge when nothing is unread', (tester) async {
      await tester.pumpWidget(bell());
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
      expect(find.byType(Badge), findsOneWidget);
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    });

    testWidgets('shows the unread count and clears it', (tester) async {
      await tester.pumpWidget(bell());
      await tester.runAsync(
        () => arrive([eventJson(1), eventJson(2), eventJson(3)]),
      );
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active), findsOneWidget);
      expect(find.byTooltip('Notifications (3 unread)'), findsOneWidget);

      center.markAllRead();
      await tester.pump();
      expect(find.text('3'), findsNothing);
    });
  });

  group('NotificationsScreen', () {
    Widget screen({void Function(ServiceEvent)? onOpen}) => MaterialApp(
      home: NotificationsScreen(
        center: center,
        onOpenService: onOpen,
        now: () => now,
      ),
    );

    testWidgets('shows an empty state', (tester) async {
      await tester.runAsync(center.init);
      await tester.pumpWidget(screen());
      expect(find.textContaining('No alerts yet'), findsOneWidget);
    });

    testWidgets('lists alerts newest first and marks them read', (
      tester,
    ) async {
      await tester.runAsync(
        () => arrive([
          eventJson(
            1,
            displayName: 'Always 503',
            message: 'uptime 0.00% is below 99.9%',
            at: DateTime.utc(2026, 1, 1, 12, 5),
          ),
          eventJson(
            2,
            displayName: 'Always 503',
            kind: 'resolved',
            durationSeconds: 120,
            at: DateTime.utc(2026, 1, 1, 12, 9),
          ),
        ]),
      );
      expect(center.unread, 2);

      await tester.pumpWidget(screen());
      await tester.pump();

      expect(center.unread, 0, reason: 'opening the list reads everything');
      expect(find.text('Recovered: Always 503'), findsOneWidget);
      expect(find.text('SLA breach: Always 503'), findsOneWidget);
      expect(find.textContaining('after 2m 0s'), findsOneWidget);
      expect(
        find.textContaining('uptime 0.00% is below 99.9%'),
        findsOneWidget,
      );
      expect(find.textContaining('1m ago'), findsOneWidget);
      // Newest first.
      final recovered = tester.getTopLeft(find.text('Recovered: Always 503'));
      final opened = tester.getTopLeft(find.text('SLA breach: Always 503'));
      expect(recovered.dy, lessThan(opened.dy));
    });

    testWidgets('tapping an alert opens that service', (tester) async {
      ServiceEvent? opened;
      await tester.runAsync(() => arrive([eventJson(1, provider: 'github')]));
      await tester.pumpWidget(screen(onOpen: (e) => opened = e));
      await tester.pump();

      await tester.tap(find.text('SLA breach: Github'));
      expect(opened?.provider, 'github');
    });

    testWidgets('alerts arriving while it is open are read at once', (
      tester,
    ) async {
      await tester.runAsync(() => arrive([]));
      await tester.pumpWidget(screen());

      await tester.runAsync(() async {
        backend.add(eventJson(1));
        await center.poll();
      });
      await tester.pump();

      expect(find.text('SLA breach: Stripe'), findsOneWidget);
      expect(center.unread, 0);
    });

    group('system notifications switch', () {
      Future<void> open(WidgetTester tester) async {
        await tester.runAsync(center.init);
        await tester.pumpWidget(screen());
      }

      SwitchListTile tile(WidgetTester tester) =>
          tester.widget<SwitchListTile>(find.byType(SwitchListTile));

      testWidgets('is off, enabled and explains itself by default', (
        tester,
      ) async {
        await open(tester);
        expect(tile(tester).value, isFalse);
        expect(tile(tester).onChanged, isNotNull);
        expect(
          find.textContaining('cannot alert you once closed'),
          findsOneWidget,
        );
        expect(find.text('Send test notification'), findsNothing);
      });

      testWidgets('turning it on asks permission and offers a test', (
        tester,
      ) async {
        await open(tester);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        expect(notifier.requests, 1);
        expect(tile(tester).value, isTrue);

        await tester.tap(find.text('Send test notification'));
        await tester.pump();
        expect(notifier.shown.single.title, 'Test notification');
      });

      testWidgets('a blocked permission explains how to fix it', (
        tester,
      ) async {
        notifier.onRequest = NotifPermission.denied;
        await open(tester);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();

        expect(tile(tester).value, isFalse);
        expect(find.textContaining('Blocked'), findsOneWidget);
        expect(find.text('Send test notification'), findsNothing);
      });

      testWidgets('is disabled where notifications are not supported', (
        tester,
      ) async {
        notifier.current = NotifPermission.unsupported;
        await open(tester);
        expect(tile(tester).onChanged, isNull);
        expect(find.textContaining('Not supported'), findsOneWidget);
      });
    });
  });

  group('StatusScreen integration', () {
    final statusBody = jsonEncode({
      'generatedAt': '2026-01-01T12:00:00.000Z',
      'services': <Object>[],
    });

    ApiClient client() => ApiClient(
      baseUrl: 'http://api.test',
      client: MockClient((req) async {
        if (req.url.path == '/api/events') return backend.handle(req);
        return http.Response(statusBody, 200);
      }),
    );

    Widget app({NotificationCenter? withCenter}) => MaterialApp(
      home: StatusScreen(
        client: client(),
        refreshInterval: null,
        notifications: withCenter,
      ),
    );

    testWidgets('no bell without a notification center', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byType(NotificationBell), findsNothing);
    });

    testWidgets('a new alert shows a snackbar with a View action', (
      tester,
    ) async {
      await tester.runAsync(center.init);
      await tester.runAsync(center.poll);
      await tester.pumpWidget(app(withCenter: center));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationBell), findsOneWidget);

      await tester.runAsync(() async {
        backend.add(eventJson(1, displayName: 'Always 503'));
        await center.poll();
      });
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('SLA breach: Always 503: uptime 50.00%'),
        findsOneWidget,
      );
      expect(find.text('1'), findsOneWidget, reason: 'badge count');

      await tester.pump(const Duration(milliseconds: 500)); // slide-in ends
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(center.unread, 0);
    });

    testWidgets('several alerts are summarised in one snackbar', (
      tester,
    ) async {
      await tester.runAsync(center.init);
      await tester.runAsync(center.poll);
      await tester.pumpWidget(app(withCenter: center));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        backend
          ..add(eventJson(1))
          ..add(eventJson(2, kind: 'resolved', durationSeconds: 5));
        await center.poll();
      });
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('2 new alerts, latest: Recovered: Stripe'),
        findsOneWidget,
      );
    });

    testWidgets('no snackbar while the alerts list is open', (tester) async {
      await tester.runAsync(center.init);
      await tester.runAsync(center.poll);
      await tester.pumpWidget(app(withCenter: center));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NotificationBell));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);

      await tester.runAsync(() async {
        backend.add(eventJson(1, displayName: 'Always 503'));
        await center.poll();
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(SnackBar), findsNothing);
      // The alert is simply listed, already read.
      expect(find.text('SLA breach: Always 503'), findsOneWidget);
    });

    testWidgets('the bell opens the alerts list', (tester) async {
      await tester.runAsync(center.init);
      await tester.pumpWidget(app(withCenter: center));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NotificationBell));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
    });
  });
}
