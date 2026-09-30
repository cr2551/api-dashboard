import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

HttpProbe probeWith(
  Future<http.Response> Function(http.Request) handler, {
  int? expectedStatus,
  int retries = 0,
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 10),
}) => HttpProbe(
  provider: 'github',
  endpoint: Uri.parse('https://api.example.com/rate_limit'),
  headers: headers,
  expectedStatus: expectedStatus,
  retries: retries,
  timeout: timeout,
  client: MockClient(handler),
  now: () => DateTime.utc(2026, 1, 1),
);

void main() {
  test('GETs the endpoint and reports the provider name', () async {
    late http.Request seen;
    final r = await probeWith((req) async {
      seen = req;
      return http.Response('{}', 200);
    }).run();

    expect(seen.method, 'GET');
    expect(seen.url.toString(), 'https://api.example.com/rate_limit');
    expect(r.provider, 'github');
    expect(r.success, isTrue);
    expect(r.statusCode, 200);
    expect(r.errorKind, isNull);
    expect(r.timestamp, DateTime.utc(2026, 1, 1));
  });

  test('sends the configured headers', () async {
    late http.Request seen;
    await probeWith((req) async {
      seen = req;
      return http.Response('', 200);
    }, headers: {'X-Api-Key': 'abc'}).run();
    expect(seen.headers['X-Api-Key'], 'abc');
  });

  group('success rule', () {
    test('any 2xx is a success by default', () async {
      for (final code in [200, 201, 204, 299]) {
        final r = await probeWith((_) async => http.Response('', code)).run();
        expect(r.success, isTrue, reason: '$code');
      }
    });

    test('3xx, 4xx and 5xx fail by default with a category', () async {
      final cases = {
        302: ProbeErrorKind.other,
        404: ProbeErrorKind.http4xx,
        503: ProbeErrorKind.http5xx,
      };
      for (final entry in cases.entries) {
        final r = await probeWith((_) async => http.Response('', entry.key))
            .run();
        expect(r.success, isFalse, reason: '${entry.key}');
        expect(r.errorKind, entry.value);
        expect(r.error, 'HTTP ${entry.key}');
      }
    });

    test('expectedStatus accepts only that exact status', () async {
      final ok = await probeWith(
        (_) async => http.Response('', 204),
        expectedStatus: 204,
      ).run();
      expect(ok.success, isTrue);

      final wrong = await probeWith(
        (_) async => http.Response('', 200),
        expectedStatus: 204,
      ).run();
      expect(wrong.success, isFalse);
      expect(wrong.statusCode, 200);
    });

    test('expectedStatus can expect an error status', () async {
      final r = await probeWith(
        (_) async => http.Response('', 401),
        expectedStatus: 401,
      ).run();
      expect(r.success, isTrue);
      expect(r.errorKind, isNull);
    });
  });

  group('failures and retries (shared with StripeProbe)', () {
    test('timeouts are categorised', () async {
      final r = await probeWith(
        (_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 20),
      ).run();
      expect(r.errorKind, ProbeErrorKind.timeout);
    });

    test('a transport failure is retried once and can recover', () async {
      var calls = 0;
      final r = await probeWith((_) async {
        calls++;
        if (calls == 1) throw http.ClientException('offline');
        return http.Response('{}', 200);
      }, retries: 1).run();
      expect(calls, 2);
      expect(r.success, isTrue);
    });

    test('an HTTP error status is never retried', () async {
      var calls = 0;
      await probeWith((_) async {
        calls++;
        return http.Response('', 500);
      }, retries: 3).run();
      expect(calls, 1);
    });
  });

  test('StripeProbe is an HttpProbe with bearer auth and its own name', () {
    final probe = StripeProbe(apiKey: 'sk_test_1', name: 'stripe-eu');
    expect(probe, isA<HttpProbe>());
    expect(probe.provider, 'stripe-eu');
    expect(probe.headers['Authorization'], 'Bearer sk_test_1');
    expect(probe.endpoint.toString(), 'https://api.stripe.com/v1/balance');
  });
}
