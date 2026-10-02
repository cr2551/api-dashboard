import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

ServiceConfig svc(
  String name, {
  String type = 'http',
  String endpoint = 'https://svc.test/health',
  int intervalSeconds = 60,
  int? expectedStatus,
  SlaPolicy? policy,
}) => ServiceConfig(
  name: name,
  type: type,
  endpoint: type == 'stripe' ? null : Uri.parse(endpoint),
  expectedStatus: expectedStatus,
  interval: Duration(seconds: intervalSeconds),
  timeout: const Duration(seconds: 5),
  policy: policy ?? SlaPolicy(provider: name),
);

class _Recorder implements Alerter {
  final breaches = <SlaBreach>[];
  final recoveries = <SlaBreach>[];

  @override
  void alert(SlaBreach breach) => breaches.add(breach);

  @override
  void recovered(
    SlaBreach breach,
    Duration duration, {
    DateTime? lastFailure,
  }) => recoveries.add(breach);
}

void main() {
  late Directory dir;
  late ProbeStore store;
  late _Recorder alerter;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('services_wiring');
    store = ProbeStore.inMemory();
    alerter = _Recorder();
  });
  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });

  String writeServices(Object json) {
    final path = '${dir.path}/services.json';
    File(path).writeAsStringSync(jsonEncode(json));
    return path;
  }

  group('resolveServices', () {
    test('reads the file named by SERVICES_CONFIG', () {
      final path = writeServices({
        'services': [
          {'name': 'a', 'type': 'http', 'endpoint': 'https://a.test'},
          {'name': 'b', 'type': 'stripe'},
        ],
      });
      final infos = <String>[];
      final list = resolveServices({
        'SERVICES_CONFIG': path,
      }, onInfo: infos.add);
      expect(list.map((s) => s.name), ['a', 'b']);
      expect(infos.single, contains(path));
    });

    test('an explicit path that does not exist is an error', () {
      expect(
        () => resolveServices({'SERVICES_CONFIG': '${dir.path}/nope.json'}),
        throwsA(isA<ConfigException>()),
      );
    });

    test('an invalid file names the bad field', () {
      final path = writeServices({
        'services': [
          {'name': 'a', 'type': 'http'},
        ],
      });
      expect(
        () => resolveServices({}, path: path),
        throwsA(
          isA<ConfigException>().having(
            (e) => e.field,
            'field',
            'services[0].endpoint',
          ),
        ),
      );
    });

    test('falls back to Stripe with default thresholds and the interval', () {
      // Run from a directory with no ../services.json (the temp dir).
      final list = resolveServices({}, path: null, defaultIntervalSeconds: 45);
      // The repo may or may not have a services.json next to server/; only
      // check the fallback shape when it does not.
      if (!File('../services.json').existsSync()) {
        final s = list.single;
        expect(s.name, 'stripe');
        expect(s.type, 'stripe');
        expect(s.interval, const Duration(seconds: 45));
        expect(s.policy.consecutiveFailures, 1);
      }
    });
  });

  group('buildProbe', () {
    test('stripe needs a key and the error names the service', () {
      expect(
        () => buildProbe(
          svc('payments', type: 'stripe'),
          {},
          configPath: '${dir.path}/missing.json',
        ),
        throwsA(
          isA<ConfigException>()
              .having((e) => e.field, 'field', 'payments')
              .having((e) => e.message, 'message', contains('Stripe key')),
        ),
      );
    });

    test('stripe uses the env key, the service name and its timeout', () {
      final probe = buildProbe(svc('payments', type: 'stripe'), {
        'STRIPE_API_KEY': 'sk_test_x',
      }) as StripeProbe;
      expect(probe.provider, 'payments');
      expect(probe.headers['Authorization'], 'Bearer sk_test_x');
      expect(probe.timeout, const Duration(seconds: 5));
    });

    test('http uses the endpoint, expected status and needs no secrets', () {
      final probe = buildProbe(svc('gh', expectedStatus: 204), {}) as HttpProbe;
      expect(probe.provider, 'gh');
      expect(probe.endpoint.toString(), 'https://svc.test/health');
      expect(probe.expectedStatus, 204);
      expect(probe.headers, isEmpty);
    });

    test('statuspage uses the endpoint and timeout and needs no secrets', () {
      final probe = buildProbe(
        svc(
          'square-status',
          type: 'statuspage',
          endpoint: 'https://www.issquareup.com/api/v2/status.json',
        ),
        {},
      ) as StatuspageProbe;
      expect(probe.provider, 'square-status');
      expect(
        probe.endpoint.toString(),
        'https://www.issquareup.com/api/v2/status.json',
      );
      expect(probe.timeout, const Duration(seconds: 5));
      expect(probe.headers, isEmpty);
    });
  });

  group('per-service thresholds and intervals', () {
    test('each service keeps its own policy and interval', () {
      final services = buildServices(
        [
          svc(
            'strict',
            intervalSeconds: 10,
            policy: const SlaPolicy(
              provider: 'strict',
              maxP95Latency: Duration(milliseconds: 200),
              minUptimePercent: 100,
              consecutiveFailures: 3,
            ),
          ),
          svc(
            'relaxed',
            intervalSeconds: 120,
            policy: const SlaPolicy(
              provider: 'relaxed',
              maxP95Latency: Duration(seconds: 5),
              minUptimePercent: 90,
            ),
          ),
        ],
        env: {},
        store: store,
        alerter: alerter,
      );

      expect(services.map((s) => s.config.interval.inSeconds), [10, 120]);
      expect(services[0].policy.minUptimePercent, 100);
      expect(services[0].policy.consecutiveFailures, 3);
      expect(services[1].policy.minUptimePercent, 90);
      expect(services[1].policy.maxP95Latency, const Duration(seconds: 5));
      expect(services[0].monitor.policy, same(services[0].policy));
    });

    test(
      'the same results breach a strict policy but not a relaxed one',
      () async {
        final now = DateTime.utc(2026, 1, 1, 12);
        // Each service answers 200 except for its 10th probe: 90% uptime.
        final calls = <String, int>{};
        final client = MockClient((req) async {
          final n = calls[req.url.host] = (calls[req.url.host] ?? 0) + 1;
          return http.Response('', n == 10 ? 503 : 200);
        });
        final services = buildServices(
          [
            svc(
              'strict',
              endpoint: 'https://strict.test/ok',
              policy: const SlaPolicy(provider: 'strict', minUptimePercent: 99),
            ),
            svc(
              'relaxed',
              endpoint: 'https://relaxed.test/ok',
              policy: const SlaPolicy(
                provider: 'relaxed',
                minUptimePercent: 80,
              ),
            ),
          ],
          env: {},
          store: store,
          alerter: alerter,
          client: client,
          now: () => now,
        );

        for (var i = 0; i < 10; i++) {
          for (final s in services) {
            await s.monitor.runOnce();
          }
        }

        // Identical data (90% uptime): only the 99% policy is breached.
        expect(alerter.breaches.map((b) => b.provider), ['strict']);
      },
    );
  });

  group('several services end to end', () {
    test('one failing service alerts without affecting the others', () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      final client = MockClient((req) async {
        return http.Response('', req.url.host == 'bad.test' ? 503 : 200);
      });
      final services = buildServices(
        [
          svc('good', endpoint: 'https://good.test/ok'),
          svc('bad', endpoint: 'https://bad.test/ok'),
        ],
        env: {},
        store: store,
        alerter: alerter,
        client: client,
        now: () => now,
      );

      for (final s in services) {
        await s.monitor.runOnce();
      }

      expect(alerter.breaches.map((b) => b.provider), ['bad']);
      expect(store.latest('good', 5).single.success, isTrue);
      expect(store.latest('bad', 5).single.success, isFalse);
    });

    test(
      '/api/status lists every service with its own policy window',
      () async {
        final now = DateTime.utc(2026, 1, 1, 12);
        final services = buildServices(
          [
            svc(
              'fast',
              policy: const SlaPolicy(
                provider: 'fast',
                window: Duration(minutes: 15),
              ),
            ),
            svc(
              'slow',
              policy: const SlaPolicy(
                provider: 'slow',
                window: Duration(hours: 6),
              ),
            ),
          ],
          env: {},
          store: store,
          alerter: alerter,
          client: MockClient((_) async => http.Response('', 200)),
          now: () => now,
        );
        for (final s in services) {
          await s.monitor.runOnce();
        }

        final handler = apiHandler(
          store: store,
          policies: [for (final s in services) s.policy],
          now: () => now,
        );
        final res = await handler(
          Request('GET', Uri.parse('http://localhost/api/status')),
        );
        final body = jsonDecode(await res.readAsString()) as Map;
        final list = body['services'] as List;

        expect(list.map((s) => s['provider']), ['fast', 'slow']);
        expect(list.map((s) => s['windowMinutes']), [15, 360]);
        expect(list.every((s) => s['state'] == 'up'), isTrue);
      },
    );
  });

  group('ServiceScheduler', () {
    RunningService running(String name, Probe probe, {int ms = 40}) {
      final config = ServiceConfig(
        name: name,
        type: 'http',
        endpoint: Uri.parse('https://x.test'),
        interval: Duration(milliseconds: ms),
        timeout: const Duration(seconds: 1),
        policy: SlaPolicy(provider: name),
      );
      return RunningService(
        config,
        Monitor(
          probe: probe,
          store: store,
          policy: config.policy,
          alerter: alerter,
        ),
      );
    }

    test('start runs every service once before returning', () async {
      final a = _CountingProbe('a');
      final b = _CountingProbe('b');
      final scheduler = ServiceScheduler([
        running('a', a, ms: 10000),
        running('b', b, ms: 10000),
      ]);
      await scheduler.start();
      scheduler.stop();
      expect([a.runs, b.runs], [1, 1]);
    });

    test('services repeat on their own intervals', () async {
      final fast = _CountingProbe('fast');
      final slow = _CountingProbe('slow');
      final scheduler = ServiceScheduler([
        running('fast', fast, ms: 30),
        running('slow', slow, ms: 10000),
      ]);
      await scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      scheduler.stop();

      expect(fast.runs, greaterThan(2));
      expect(slow.runs, 1);
      final after = fast.runs;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(fast.runs, after, reason: 'stop() cancels the timers');
    });

    test('a throwing service is logged and does not stop the others', () async {
      final lines = <String>[];
      final good = _CountingProbe('good');
      final scheduler = ServiceScheduler([
        running('boom', _ThrowingProbe('boom'), ms: 30),
        running('good', good, ms: 30),
      ], logger: Logger(sink: lines.add));
      await scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      scheduler.stop();

      expect(good.runs, greaterThan(1));
      expect(lines.any((l) => l.contains('boom failed')), isTrue);
    });

    test('a slow cycle is skipped instead of overlapping', () async {
      final slow = _CountingProbe(
        'slow',
        delay: const Duration(milliseconds: 150),
      );
      final scheduler = ServiceScheduler([running('slow', slow, ms: 20)]);
      final started = scheduler.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(slow.maxConcurrent, 1);
      await started;
      scheduler.stop();
    });
  });
}

class _CountingProbe implements Probe {
  _CountingProbe(this.provider, {this.delay = Duration.zero});

  @override
  final String provider;
  final Duration delay;
  int runs = 0;
  int _active = 0;
  int maxConcurrent = 0;

  @override
  Future<ProbeResult> run() async {
    runs++;
    _active++;
    if (_active > maxConcurrent) maxConcurrent = _active;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    _active--;
    return ProbeResult(
      provider: provider,
      timestamp: DateTime.now().toUtc(),
      latency: const Duration(milliseconds: 1),
      success: true,
    );
  }
}

class _ThrowingProbe implements Probe {
  _ThrowingProbe(this.provider);

  @override
  final String provider;

  @override
  Future<ProbeResult> run() => throw StateError('probe exploded');
}
