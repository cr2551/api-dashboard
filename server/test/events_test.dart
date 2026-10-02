import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

StoredBreachEvent event(
  String provider,
  BreachEventKind kind, {
  SlaBreachType type = SlaBreachType.uptime,
  int minute = 0,
  Duration? duration,
}) => StoredBreachEvent(
  provider: provider,
  type: type,
  kind: kind,
  message: 'msg $minute',
  timestamp: DateTime.utc(2026, 1, 1, 12, minute),
  duration: duration,
);

void main() {
  late ProbeStore store;
  setUp(() => store = ProbeStore.inMemory());
  tearDown(() => store.close());

  group('ProbeStore breach events', () {
    test('an empty store has none', () {
      expect(store.breachEvents(), isEmpty);
    });

    test('round-trips every field and assigns increasing ids', () {
      store
        ..insertBreachEvent(event('stripe', BreachEventKind.opened))
        ..insertBreachEvent(
          event(
            'stripe',
            BreachEventKind.resolved,
            type: SlaBreachType.latency,
            minute: 5,
            duration: const Duration(minutes: 5),
          ),
        );
      final all = store.breachEvents();
      expect(all.map((e) => e.id), [1, 2]);

      final opened = all[0];
      expect(opened.provider, 'stripe');
      expect(opened.type, SlaBreachType.uptime);
      expect(opened.kind, BreachEventKind.opened);
      expect(opened.message, 'msg 0');
      expect(opened.timestamp, DateTime.utc(2026, 1, 1, 12));
      expect(opened.duration, isNull);

      final resolved = all[1];
      expect(resolved.type, SlaBreachType.latency);
      expect(resolved.kind, BreachEventKind.resolved);
      expect(resolved.duration, const Duration(minutes: 5));
    });

    test('afterId returns only newer events, oldest first', () {
      for (var i = 0; i < 5; i++) {
        store.insertBreachEvent(
          event('stripe', BreachEventKind.opened, minute: i),
        );
      }
      expect(store.breachEvents(afterId: 3).map((e) => e.id), [4, 5]);
      expect(store.breachEvents(afterId: 5), isEmpty);
    });

    test('limit keeps the most recent events, still oldest first', () {
      for (var i = 0; i < 10; i++) {
        store.insertBreachEvent(
          event('stripe', BreachEventKind.opened, minute: i),
        );
      }
      expect(store.breachEvents(limit: 3).map((e) => e.id), [8, 9, 10]);
      expect(store.breachEvents(afterId: 2, limit: 3).map((e) => e.id), [
        8,
        9,
        10,
      ]);
    });

    test('latestBreachEventId is 0 when empty and then the highest id', () {
      expect(store.latestBreachEventId(), 0);
      store
        ..insertBreachEvent(event('stripe', BreachEventKind.opened))
        ..insertBreachEvent(event('stripe', BreachEventKind.resolved));
      expect(store.latestBreachEventId(), 2);
    });

    test('a negative limit is rejected and zero returns nothing', () {
      store.insertBreachEvent(event('stripe', BreachEventKind.opened));
      expect(() => store.breachEvents(limit: -1), throwsArgumentError);
      expect(store.breachEvents(limit: 0), isEmpty);
    });
  });

  group('Monitor records events', () {
    final start = DateTime.utc(2026, 1, 1, 12);
    late DateTime clock;
    late int status;
    late Monitor monitor;
    late List<SlaBreach> alerts;

    setUp(() {
      clock = start;
      status = 200;
      alerts = [];
      monitor = Monitor(
        probe: HttpProbe(
          provider: 'svc',
          endpoint: Uri.parse('https://svc.test/'),
          client: MockClient((_) async => http.Response('', status)),
          retries: 0,
          now: () => clock,
        ),
        store: store,
        policy: const SlaPolicy(
          provider: 'svc',
          minUptimePercent: 100,
          window: Duration(minutes: 1),
          minSamples: 2,
        ),
        alerter: _Recorder(alerts),
        now: () => clock,
      );
    });

    Future<void> cycle(int seconds, int code) async {
      clock = start.add(Duration(seconds: seconds));
      status = code;
      await monitor.runOnce();
    }

    test('an opened breach and its recovery are stored once each', () async {
      await cycle(0, 200);
      await cycle(10, 200);
      expect(store.breachEvents(), isEmpty);

      await cycle(20, 503); // opens
      await cycle(30, 503); // still open: nothing new
      var events = store.breachEvents();
      expect(events, hasLength(1));
      expect(events.single.kind, BreachEventKind.opened);
      expect(events.single.provider, 'svc');
      expect(events.single.type, SlaBreachType.uptime);
      expect(events.single.timestamp, start.add(const Duration(seconds: 20)));
      expect(events.single.message, contains('uptime'));

      await cycle(120, 200); // failures left the window: resolved
      events = store.breachEvents();
      expect(events.map((e) => e.kind), [
        BreachEventKind.opened,
        BreachEventKind.resolved,
      ]);
      expect(events.last.duration, const Duration(seconds: 100));
      expect(alerts, hasLength(1));
    });

    test('a storage failure does not stop the alert', () async {
      await cycle(0, 200);
      await cycle(10, 200);
      store.close();
      // Every store call now fails; the cycle must still complete.
      await cycle(20, 503);
      store = ProbeStore.inMemory(); // so tearDown can close something
    });
  });

  group('GET /api/events', () {
    late Handler handler;
    setUp(() {
      handler = apiHandler(
        store: store,
        policies: const [SlaPolicy(provider: 'stripe')],
        displayNames: {'stripe': 'Stripe API'},
      );
    });

    Future<Response> get(String path) =>
        Future.value(handler(Request('GET', Uri.parse('http://x$path'))));

    Future<List<dynamic>> events(String path) async {
      final res = await get(path);
      expect(res.statusCode, 200);
      return (jsonDecode(await res.readAsString()) as Map)['events'] as List;
    }

    test('is empty when nothing happened', () async {
      expect(await events('/api/events'), isEmpty);
    });

    test('returns events with their fields and the display name', () async {
      store
        ..insertBreachEvent(event('stripe', BreachEventKind.opened))
        ..insertBreachEvent(
          event(
            'stripe',
            BreachEventKind.resolved,
            minute: 3,
            duration: const Duration(minutes: 3),
          ),
        );
      final list = await events('/api/events');
      expect(list, hasLength(2));
      expect(list[0], {
        'id': 1,
        'provider': 'stripe',
        'displayName': 'Stripe API',
        'type': 'uptime',
        'kind': 'opened',
        'message': 'msg 0',
        'timestamp': '2026-01-01T12:00:00.000Z',
        'durationSeconds': null,
      });
      expect(list[1]['kind'], 'resolved');
      expect(list[1]['durationSeconds'], 180);
    });

    test(
      'latestId is the highest stored id, even when after hides all',
      () async {
        Future<int> latestId(String path) async {
          final res = await get(path);
          return (jsonDecode(await res.readAsString()) as Map)['latestId']
              as int;
        }

        expect(await latestId('/api/events'), 0);
        for (var i = 0; i < 3; i++) {
          store.insertBreachEvent(
            event('stripe', BreachEventKind.opened, minute: i),
          );
        }
        expect(await latestId('/api/events'), 3);
        expect(await latestId('/api/events?after=3'), 3);
        expect(await events('/api/events?after=3'), isEmpty);
      },
    );

    test('after and limit narrow the result', () async {
      for (var i = 0; i < 6; i++) {
        store.insertBreachEvent(
          event('stripe', BreachEventKind.opened, minute: i),
        );
      }
      expect((await events('/api/events?after=4')).map((e) => e['id']), [5, 6]);
      expect((await events('/api/events?limit=2')).map((e) => e['id']), [5, 6]);
    });

    test('bad parameters are a 400', () async {
      for (final bad in [
        '?after=abc',
        '?after=-1',
        '?limit=0',
        '?limit=201',
        '?limit=x',
      ]) {
        expect((await get('/api/events$bad')).statusCode, 400, reason: bad);
      }
    });

    test('needs the bearer token when one is configured', () async {
      final secured = apiHandler(
        store: store,
        policies: const [SlaPolicy(provider: 'stripe')],
        authToken: 'tok',
      );
      final without = await secured(
        Request('GET', Uri.parse('http://x/api/events')),
      );
      expect(without.statusCode, 401);
      final withToken = await secured(
        Request(
          'GET',
          Uri.parse('http://x/api/events'),
          headers: {'authorization': 'Bearer tok'},
        ),
      );
      expect(withToken.statusCode, 200);
    });
  });
}

class _Recorder implements Alerter {
  _Recorder(this.breaches);
  final List<SlaBreach> breaches;

  @override
  void alert(SlaBreach breach) => breaches.add(breach);

  @override
  void recovered(
    SlaBreach breach,
    Duration duration, {
    DateTime? lastFailure,
  }) {}
}
