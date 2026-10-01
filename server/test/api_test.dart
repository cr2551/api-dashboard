import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1, 12);
  const policy = SlaPolicy(
    provider: 'stripe',
    maxP95Latency: Duration(milliseconds: 500),
    minUptimePercent: 90,
    window: Duration(hours: 1),
  );

  late ProbeStore store;
  late Handler handler;

  void add(int minutesAgo, int ms, {bool ok = true}) => store.insert(
    ProbeResult(
      provider: 'stripe',
      timestamp: now.subtract(Duration(minutes: minutesAgo)),
      latency: Duration(milliseconds: ms),
      success: ok,
      statusCode: ok ? 200 : 500,
    ),
  );

  Future<Response> get(String path, {String method = 'GET'}) => Future.value(
    handler(Request(method, Uri.parse('http://localhost$path'))),
  );

  Future<Map<String, dynamic>> getJson(String path) async =>
      jsonDecode(await (await get(path)).readAsString())
          as Map<String, dynamic>;

  setUp(() {
    store = ProbeStore.inMemory();
    handler = apiHandler(store: store, policies: [policy], now: () => now);
  });
  tearDown(() => store.close());

  group('settings', () {
    test('describe how a service is monitored and judged', () async {
      handler = apiHandler(
        store: store,
        policies: [
          const SlaPolicy(
            provider: 'svc',
            maxP95Latency: Duration(milliseconds: 750),
            minUptimePercent: 99,
            window: Duration(minutes: 30),
            minSamples: 5,
            consecutiveFailures: 3,
          ),
        ],
        serviceConfigs: {
          'svc': ServiceConfig(
            name: 'svc',
            type: 'http',
            endpoint: Uri.parse('https://svc.test/'),
            expectedStatus: 204,
            interval: const Duration(seconds: 45),
            timeout: const Duration(seconds: 7),
            policy: const SlaPolicy(provider: 'svc'),
          ),
        },
        now: () => now,
      );
      final s = (await getJson('/api/status'))['services'].single;
      expect(s['settings'], {
        'intervalSeconds': 45,
        'timeoutSeconds': 7,
        'retries': HttpProbe.defaultRetries,
        'expectedStatus': 204,
        'maxP95LatencyMs': 750,
        'minUptimePercent': 99.0,
        'windowMinutes': 30,
        'minSamples': 5,
        'consecutiveFailures': 3,
      });
    });

    test('probe settings are null when the config is unknown', () async {
      final s = (await getJson('/api/status'))['services'].single;
      expect(s['settings']['intervalSeconds'], isNull);
      expect(s['settings']['timeoutSeconds'], isNull);
      expect(s['settings']['expectedStatus'], isNull);
      // The SLA thresholds always come from the policy.
      expect(s['settings']['maxP95LatencyMs'], 500);
      expect(s['settings']['minUptimePercent'], 90.0);
      expect(s['settings']['consecutiveFailures'], 1);
    });
  });

  group('errorKind', () {
    test('is exposed on the last probe and in the history points', () async {
      store
        ..insert(
          ProbeResult(
            provider: 'stripe',
            timestamp: now.subtract(const Duration(minutes: 2)),
            latency: const Duration(milliseconds: 100),
            success: true,
            statusCode: 200,
          ),
        )
        ..insert(
          ProbeResult(
            provider: 'stripe',
            timestamp: now.subtract(const Duration(minutes: 1)),
            latency: const Duration(milliseconds: 50),
            success: false,
            error: 'HTTP 503',
            statusCode: 503,
            errorKind: ProbeErrorKind.http5xx,
          ),
        );

      final status = (await getJson('/api/status'))['services'].single;
      expect(status['lastProbe']['errorKind'], 'http5xx');

      final points =
          (await getJson('/api/history?provider=stripe'))['points'] as List;
      expect(points.map((p) => p['errorKind']), [null, 'http5xx']);
    });
  });

  group('displayName', () {
    test('is included when configured and null otherwise', () async {
      handler = apiHandler(
        store: store,
        policies: [
          policy,
          const SlaPolicy(provider: 'github'),
        ],
        displayNames: {'github': 'GitHub'},
        now: () => now,
      );
      final services = (await getJson('/api/status'))['services'] as List;
      expect(services[0]['provider'], 'stripe');
      expect(services[0]['displayName'], isNull);
      expect(services[1]['provider'], 'github');
      expect(services[1]['displayName'], 'GitHub');
    });
  });

  group('/api/status', () {
    test('is unknown when there are no probes', () async {
      final s = (await getJson('/api/status'))['services'].single;
      expect(s['provider'], 'stripe');
      expect(s['state'], 'unknown');
      expect(s['lastProbe'], isNull);
      expect(s['uptimePercent'], isNull);
      expect(s['breaches'], isEmpty);
    });

    test('reports up state, stats and latest probe', () async {
      add(3, 100);
      add(2, 300);
      add(1, 200);
      final body = await getJson('/api/status');
      final s = body['services'].single;
      expect(body['generatedAt'], now.toIso8601String());
      expect(s['state'], 'up');
      expect(s['sampleCount'], 3);
      expect(s['uptimePercent'], 100);
      expect(s['avgLatencyMs'], 200);
      expect(s['p95LatencyMs'], 300);
      expect(s['lastProbe']['latencyMs'], 200);
      expect(s['breaches'], isEmpty);
    });

    test('reports down state and SLA breaches', () async {
      add(3, 100);
      add(2, 100);
      add(1, 100, ok: false);
      final s = (await getJson('/api/status'))['services'].single;
      expect(s['state'], 'down');
      expect(s['lastProbe']['statusCode'], 500);
      expect(s['breaches'].single['type'], 'uptime');
    });

    test('ignores probes outside the policy window', () async {
      add(120, 100);
      final s = (await getJson('/api/status'))['services'].single;
      expect(s['state'], 'unknown');
    });
  });

  group('/api/history', () {
    test('returns points oldest first within the range', () async {
      add(90, 100);
      add(20, 200);
      add(10, 300);
      final body = await getJson('/api/history?provider=stripe&minutes=30');
      expect(body['minutes'], 30);
      expect(body['uptimePercent'], 100);
      expect((body['points'] as List).map((p) => p['latencyMs']), [200, 300]);
    });

    test('defaults to 60 minutes', () async {
      add(90, 100);
      add(30, 200);
      final body = await getJson('/api/history?provider=stripe');
      expect(body['points'], hasLength(1));
    });

    test('rejects unknown providers and bad minutes', () async {
      expect((await get('/api/history?provider=nope')).statusCode, 404);
      expect((await get('/api/history')).statusCode, 404);
      expect(
        (await get('/api/history?provider=stripe&minutes=abc')).statusCode,
        400,
      );
      expect(
        (await get('/api/history?provider=stripe&minutes=0')).statusCode,
        400,
      );
    });
  });

  test('sends JSON with CORS headers', () async {
    final res = await get('/api/status');
    expect(res.headers['content-type'], 'application/json');
    expect(res.headers['access-control-allow-origin'], '*');
  });

  test('answers CORS preflight and rejects other methods', () async {
    expect((await get('/api/status', method: 'OPTIONS')).statusCode, 204);
    expect((await get('/api/status', method: 'POST')).statusCode, 405);
    expect((await get('/nope')).statusCode, 404);
  });
}
