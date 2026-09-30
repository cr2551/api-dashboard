import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

StripeProbe probeWith(
  http.Client client, {
  Duration? timeout,
  int retries = 0,
}) => StripeProbe(
  apiKey: 'sk_test_123',
  client: client,
  now: () => DateTime.utc(2026, 1, 1),
  timeout: timeout ?? const Duration(seconds: 10),
  retries: retries,
);

void main() {
  test('records success with status code and sends bearer auth', () async {
    late http.Request seen;
    final probe = probeWith(
      MockClient((req) async {
        seen = req;
        return http.Response('{}', 200);
      }),
    );

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
    final result = await probeWith(
      MockClient((_) async => http.Response('', 401)),
    ).run();
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

  group('error categories', () {
    Future<ProbeResult> failWith(Object error) =>
        probeWith(MockClient((_) async => throw error)).run();

    Future<ProbeResult> status(int code) =>
        probeWith(MockClient((_) async => http.Response('', code))).run();

    test('success has no category', () async {
      expect((await status(200)).errorKind, isNull);
    });

    test('timeout', () async {
      final r = await probeWith(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20),
      ).run();
      expect(r.errorKind, ProbeErrorKind.timeout);
    });

    test('connection: SocketException and DNS failure', () async {
      expect(
        (await failWith(const SocketException('refused'))).errorKind,
        ProbeErrorKind.connection,
      );
      expect(
        (await failWith(
          http.ClientException('Failed host lookup: api.stripe.com'),
        )).errorKind,
        ProbeErrorKind.connection,
      );
    });

    test('tls: handshake and certificate errors', () async {
      expect(
        (await failWith(const HandshakeException('bad'))).errorKind,
        ProbeErrorKind.tls,
      );
      expect(
        (await failWith(http.ClientException('CERTIFICATE_VERIFY_FAILED')))
            .errorKind,
        ProbeErrorKind.tls,
      );
    });

    test('http 4xx and 5xx', () async {
      expect((await status(401)).errorKind, ProbeErrorKind.http4xx);
      expect((await status(429)).errorKind, ProbeErrorKind.http4xx);
      expect((await status(500)).errorKind, ProbeErrorKind.http5xx);
      expect((await status(503)).errorKind, ProbeErrorKind.http5xx);
    });

    test('unexpected errors and odd statuses are other', () async {
      expect((await failWith(StateError('x'))).errorKind, ProbeErrorKind.other);
      expect((await status(302)).errorKind, ProbeErrorKind.other);
    });
  });

  group('retry policy', () {
    test('retries a transport failure once and can recover', () async {
      var calls = 0;
      final r = await probeWith(
        MockClient((_) async {
          calls++;
          if (calls == 1) throw http.ClientException('offline');
          return http.Response('{}', 200);
        }),
        retries: 1,
      ).run();
      expect(calls, 2);
      expect(r.success, isTrue);
      expect(r.errorKind, isNull);
    });

    test('reports failure when the retry fails too', () async {
      var calls = 0;
      final r = await probeWith(
        MockClient((_) async {
          calls++;
          throw http.ClientException('offline');
        }),
        retries: 1,
      ).run();
      expect(calls, 2);
      expect(r.success, isFalse);
      expect(r.errorKind, ProbeErrorKind.connection);
    });

    test('never retries an HTTP response', () async {
      var calls = 0;
      final r = await probeWith(
        MockClient((_) async {
          calls++;
          return http.Response('', 503);
        }),
        retries: 1,
      ).run();
      expect(calls, 1);
      expect(r.errorKind, ProbeErrorKind.http5xx);
    });

    test('retries are disabled with retries: 0', () async {
      var calls = 0;
      await probeWith(
        MockClient((_) async {
          calls++;
          throw http.ClientException('offline');
        }),
      ).run();
      expect(calls, 1);
    });
  });
}
