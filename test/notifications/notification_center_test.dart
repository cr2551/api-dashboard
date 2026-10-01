import 'package:api_dashboard/data/service_event.dart';
import 'package:api_dashboard/notifications/notification_center.dart';
import 'package:api_dashboard/notifications/notification_prefs.dart';
import 'package:api_dashboard/notifications/system_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeEventsBackend backend;
  late FakeNotifier notifier;
  late MemoryNotificationPrefs prefs;
  late NotificationCenter center;
  late List<List<ServiceEvent>> streamed;

  NotificationCenter build({
    int maxEvents = 200,
    String? token,
    FakeNotifier? withNotifier,
  }) {
    notifier = withNotifier ?? notifier;
    final c = NotificationCenter(
      client: backend.client(token: token),
      notifier: notifier,
      prefs: prefs,
      maxEvents: maxEvents,
    );
    c.newEvents.listen(streamed.add);
    return c;
  }

  setUp(() {
    backend = FakeEventsBackend();
    notifier = FakeNotifier(current: NotifPermission.granted);
    prefs = MemoryNotificationPrefs();
    streamed = [];
    center = build();
  });
  tearDown(() => center.dispose());

  Future<void> enableSystem() async {
    await center.setSystemNotifications(true);
    expect(center.systemEnabled, isTrue);
  }

  group('first run', () {
    test('loads history silently', () async {
      for (var i = 1; i <= 3; i++) {
        backend.add(eventJson(i));
      }
      await center.init();
      await enableSystem();

      await center.poll();
      await Future<void>.delayed(Duration.zero);

      expect(center.events.map((e) => e.id), [3, 2, 1], reason: 'newest first');
      expect(center.unread, 0);
      expect(streamed, isEmpty);
      expect(notifier.shown, isEmpty);
      expect(prefs.lastEventId, 3);
    });

    test('with no history, anything later counts as new', () async {
      await center.init();
      await enableSystem();
      await center.poll();
      expect(prefs.lastEventId, 0);

      backend.add(eventJson(1));
      await center.poll();
      await Future<void>.delayed(Duration.zero);

      expect(center.unread, 1);
      expect(streamed.single.single.id, 1);
      expect(notifier.shown, hasLength(1));
    });
  });

  group('polling', () {
    test('asks only for events after the last one seen', () async {
      backend.add(eventJson(1));
      await center.init();
      await center.poll();
      backend.requests.clear();

      await center.poll();

      expect(backend.requests.single.queryParameters['after'], '1');
    });

    test('new events are added on top and counted as unread', () async {
      await center.init();
      await center.poll(); // baseline
      backend
        ..add(eventJson(1))
        ..add(eventJson(2, kind: 'resolved', durationSeconds: 90));

      await center.poll();
      await Future<void>.delayed(Duration.zero); // let the stream deliver

      expect(center.events.map((e) => e.id), [2, 1]);
      expect(center.unread, 2);
      expect(streamed.single.map((e) => e.id), [1, 2], reason: 'oldest first');
    });

    test('a poll with nothing new changes nothing', () async {
      backend.add(eventJson(1));
      await center.init();
      await center.poll();
      var notified = 0;
      center.addListener(() => notified++);

      await center.poll();

      expect(notified, 0);
      expect(center.unread, 0);
    });

    test('keeps at most maxEvents', () async {
      center.dispose();
      center = build(maxEvents: 3);
      await center.init();
      await center.poll();
      for (var i = 1; i <= 5; i++) {
        backend.add(eventJson(i));
      }
      await center.poll();
      expect(center.events.map((e) => e.id), [5, 4, 3]);
    });

    test('alerts from while the app was closed count as new', () async {
      for (var i = 1; i <= 5; i++) {
        backend.add(eventJson(i));
      }
      // The user last saw event 2 before closing the app.
      prefs.lastEventId = 2;
      prefs.enabled = true;
      await center.init();

      await center.poll();

      expect(center.events.map((e) => e.id), [5, 4, 3]);
      expect(center.unread, 3);
      expect(notifier.shown.single.title, '3 new alerts');
    });

    test('a reset backend is reloaded from its history, silently', () async {
      // We saw up to event 9 on a previous backend or database.
      prefs.lastEventId = 9;
      prefs.enabled = true;
      await center.init();
      backend
        ..add(eventJson(1, message: 'fresh one'))
        ..add(eventJson(2, message: 'fresh two'));

      await center.poll();
      await Future<void>.delayed(Duration.zero);

      expect(center.events.map((e) => e.id), [2, 1]);
      expect(center.unread, 0, reason: 'history, not news');
      expect(notifier.shown, isEmpty);
      expect(streamed, isEmpty);
      expect(prefs.lastEventId, 2);

      // And it keeps working from the new position.
      backend.add(eventJson(3));
      await center.poll();
      expect(center.unread, 1);
      expect(center.events.first.id, 3);
    });

    test('a reset backend drops the old list', () async {
      backend.add(eventJson(5, message: 'old'));
      await center.init();
      await center.poll();
      expect(center.events.single.message, 'old');

      // The backend is replaced by one with different, lower ids.
      backend.events
        ..clear()
        ..add(eventJson(1, message: 'new'));
      await center.poll();

      expect(center.events.map((e) => e.message), ['new']);
    });

    test('an older backend without latestId keeps the old behaviour', () async {
      backend.omitLatestId = true;
      backend.add(eventJson(1));
      await center.init();
      await center.poll();
      backend.add(eventJson(2));
      await center.poll();
      expect(center.events.map((e) => e.id), [2, 1]);
    });

    test('does not poll twice at once', () async {
      await center.init();
      await Future.wait([center.poll(), center.poll(), center.poll()]);
      expect(backend.requests, hasLength(1));
    });

    test(
      'a connection error is swallowed and the next poll recovers',
      () async {
        await center.init();
        backend.offline = true;
        await center.poll();
        expect(center.events, isEmpty);

        backend.offline = false;
        backend.add(eventJson(1));
        await center.poll();
        expect(center.events, hasLength(1));
      },
    );
  });

  group('auth', () {
    test('a 401 pauses polling until resume()', () async {
      backend.failWith = 401;
      await center.init();
      await center.poll();
      final after401 = backend.requests.length;

      await center.poll();
      await center.poll();
      expect(backend.requests.length, after401, reason: 'paused');

      backend.failWith = null;
      backend.add(eventJson(1));
      center.resume();
      await Future<void>.delayed(Duration.zero);

      expect(backend.requests.length, greaterThan(after401));
      expect(center.events, hasLength(1));
    });
  });

  group('system notifications', () {
    test('one new alert shows its title and body', () async {
      await center.init();
      await enableSystem();
      await center.poll();
      backend.add(
        eventJson(
          7,
          displayName: 'Stripe API',
          message: 'p95 latency too high',
        ),
      );

      await center.poll();

      final shown = notifier.shown.single;
      expect(shown.id, 7);
      expect(shown.title, 'SLA breach: Stripe API');
      expect(shown.body, 'p95 latency too high');
    });

    test('a recovery says how long it lasted', () async {
      await center.init();
      await enableSystem();
      await center.poll();
      backend.add(
        eventJson(8, kind: 'resolved', type: 'latency', durationSeconds: 725),
      );

      await center.poll();

      final shown = notifier.shown.single;
      expect(shown.title, 'Recovered: Stripe');
      expect(shown.body, 'Latency is back within SLA after 12m 5s');
    });

    test('several alerts become one summary', () async {
      await center.init();
      await enableSystem();
      await center.poll();
      for (var i = 1; i <= 5; i++) {
        backend.add(eventJson(i, provider: 'svc$i', message: 'm$i'));
      }

      await center.poll();

      final shown = notifier.shown.single;
      expect(shown.title, '5 new alerts');
      expect(shown.body, contains('SLA breach: Svc5: m5'));
      expect(shown.body, contains('+2 more'));
    });

    test('nothing is shown while they are off', () async {
      await center.init();
      await center.poll();
      backend.add(eventJson(1));
      await center.poll();
      expect(notifier.shown, isEmpty);
      expect(center.unread, 1, reason: 'still listed and counted');
    });

    test('turning them on asks for permission and remembers', () async {
      await center.init();
      await center.setSystemNotifications(true);
      expect(notifier.requests, 1);
      expect(center.systemEnabled, isTrue);
      expect(prefs.enabled, isTrue);

      await center.setSystemNotifications(false);
      expect(center.systemEnabled, isFalse);
      expect(prefs.enabled, isFalse);
    });

    test('a denied prompt leaves them off and says blocked', () async {
      notifier.onRequest = NotifPermission.denied;
      await center.init();
      await center.setSystemNotifications(true);
      expect(center.systemEnabled, isFalse);
      expect(center.permission, NotifPermission.denied);
      expect(prefs.enabled, isFalse);
    });

    test('revoked permission switches them off on start', () async {
      prefs.enabled = true;
      notifier.current = NotifPermission.denied;
      await center.init();
      expect(center.systemEnabled, isFalse);
    });

    test('an unsupported platform never enables them', () async {
      center.dispose();
      center = build(
        withNotifier: FakeNotifier(current: NotifPermission.unsupported),
      );
      prefs.enabled = true;
      await center.init();
      expect(center.systemEnabled, isFalse);
      expect(center.permission, NotifPermission.unsupported);
    });

    test('the saved setting survives a restart', () async {
      await center.init();
      await enableSystem();
      center.dispose();

      center = build();
      await center.init();
      expect(center.systemEnabled, isTrue);
    });

    test('sendTest shows a notification', () async {
      await center.init();
      await enableSystem();
      await center.sendTest();
      expect(notifier.shown.single.title, 'Test notification');
    });
  });

  test('markAllRead clears the unread count once', () async {
    await center.init();
    await center.poll();
    backend.add(eventJson(1));
    await center.poll();
    expect(center.unread, 1);

    var notified = 0;
    center.addListener(() => notified++);
    center.markAllRead();
    center.markAllRead();

    expect(center.unread, 0);
    expect(notified, 1);
  });
}
