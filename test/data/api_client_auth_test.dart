import 'dart:convert';

import 'package:api_dashboard/data/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final okBody = jsonEncode({
  'generatedAt': '2026-01-01T12:00:00.000Z',
  'services': <Object>[],
});

ApiClient clientFor(
  Future<http.Response> Function(http.Request) handler, {
  String? token,
}) => ApiClient(
  baseUrl: 'http://api.test',
  apiToken: token,
  client: MockClient(handler),
);

void main() {
  test('sends the token as a bearer header on every request', () async {
    final seen = <String?>[];
    final client = clientFor((req) async {
      seen.add(req.headers['Authorization']);
      return http.Response(
        req.url.path == '/api/status'
            ? okBody
            : jsonEncode({
                'provider': 'stripe',
                'minutes': 60,
                'uptimePercent': null,
                'points': <Object>[],
              }),
        200,
      );
    }, token: 's3cret');

    await client.getStatus();
    await client.getHistory('stripe');

    expect(seen, ['Bearer s3cret', 'Bearer s3cret']);
  });

  test('sends no Authorization header without a token', () async {
    late http.Request seen;
    final client = clientFor((req) async {
      seen = req;
      return http.Response(okBody, 200);
    });
    await client.getStatus();
    expect(seen.headers.containsKey('Authorization'), isFalse);
  });

  test('a token set later is used by the next request', () async {
    final seen = <String?>[];
    final client = clientFor((req) async {
      seen.add(req.headers['Authorization']);
      return http.Response(okBody, 200);
    });
    await client.getStatus();
    client.apiToken = 'later';
    await client.getStatus();
    expect(seen, [null, 'Bearer later']);
  });

  test('blank tokens count as no token and are trimmed', () async {
    expect(
      clientFor((_) async => http.Response('', 200), token: '  ').apiToken,
      isNull,
    );
    final client = clientFor((_) async => http.Response('', 200));
    client.apiToken = '  abc \n';
    expect(client.apiToken, 'abc');
    client.apiToken = '';
    expect(client.apiToken, isNull);
  });

  group('401', () {
    test('without a token asks the user to enter one', () async {
      final client = clientFor((_) async => http.Response('{}', 401));
      await expectLater(
        client.getStatus(),
        throwsA(
          isA<UnauthorizedException>()
              .having((e) => e.hadToken, 'hadToken', isFalse)
              .having((e) => e.message, 'message', contains('requires')),
        ),
      );
    });

    test('with a token says it was rejected', () async {
      final client = clientFor(
        (_) async => http.Response('{}', 401),
        token: 'wrong',
      );
      await expectLater(
        client.getStatus(),
        throwsA(
          isA<UnauthorizedException>()
              .having((e) => e.hadToken, 'hadToken', isTrue)
              .having((e) => e.message, 'message', contains('rejected')),
        ),
      );
    });

    test('is still an ApiException and never leaks the token', () async {
      final client = clientFor(
        (_) async => http.Response('{}', 401),
        token: 'topsecret',
      );
      await expectLater(
        client.getHistory('stripe'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.toString(),
            'text',
            isNot(contains('topsecret')),
          ),
        ),
      );
    });

    test('other errors are not treated as auth problems', () async {
      final client = clientFor((_) async => http.Response('{}', 403));
      await expectLater(
        client.getStatus(),
        throwsA(isNot(isA<UnauthorizedException>())),
      );
    });
  });
}
