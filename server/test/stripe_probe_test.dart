import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

StripeProbe probeWith(http.Client client, {Duration? timeout}) => StripeProbe(
      apiKey: 'sk_test_123',
      client: client,
      now: () => DateTime.utc(2026, 1, 1),
      timeout: timeout ?? const Duration(seconds: 10),
    );

void main() {
  test('records success with status code and sends bearer auth', () async {
    late http.Request seen;
    final probe = probeWith(MockClient((req) async {
      seen = req;
      return http.Response('{}', 200);
    }));

    final result = await probe.run();

    expect(seen.method, 'GET');
    expect(seen.url.toString(), 'https://api.stripe.com/v1/balance');
    expect(seen.headers['Authorization'], 'Bearer sk_test_123');
    expect(result.provider, 'stripe');
    expect(result.success, isTrue);
    expect(result.statusCode, 200);
    expect(result.error, isNull);
    expect(result.timestamp, DateTime.utc(2026, 1, 1));
  });

  test('marks non-2xx responses as failures', () async {
    final result =
        await probeWith(MockClient((_) async => http.Response('', 401))).run();
    expect(result.success, isFalse);
    expect(result.statusCode, 401);
    expect(result.error, 'HTTP 401');
  });

  test('captures network errors without throwing', () async {
    final result = await probeWith(
      MockClient((_) async => throw http.ClientException('offline')),
    ).run();
    expect(result.success, isFalse);
    expect(result.statusCode, isNull);
    expect(result.error, contains('offline'));
  });

  test('times out slow requests', () async {
    final result = await probeWith(
      MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 20),
    ).run();
    expect(result.success, isFalse);
    expect(result.error, contains('TimeoutException'));
  });
}
