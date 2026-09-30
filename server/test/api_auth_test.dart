import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

void main() {
  const token = 'correct-horse-battery-staple';
  const policy = SlaPolicy(provider: 'stripe');
  late ProbeStore store;
  late Handler handler;

  Future<Response> send(
    String path, {
    String method = 'GET',
    Map<String, String>? headers,
  }) async => handler(
    Request(method, Uri.parse('http://localhost$path'), headers: headers),
  );

  Map<String, String> bearer(String value) => {'authorization': value};

  setUp(() {
    store = ProbeStore.inMemory();
    handler = apiHandler(
      store: store,
      policies: const [policy],
      authToken: token,
    );
  });
  tearDown(() => store.close());

  group('with a token configured', () {
    test('a missing header is 401 with a Bearer challenge', () async {
      final r = await send('/api/status');
      expect(r.statusCode, 401);
      expect(r.headers['www-authenticate'], 'Bearer');
      expect(jsonDecode(await r.readAsString()), {'error': 'unauthorized'});
    });

    test('a wrong token is 401', () async {
      final r = await send(
        '/api/status',
        headers: bearer('Bearer not-the-token'),
      );
      expect(r.statusCode, 401);
    });

    test('near-miss tokens are 401', () async {
      for (final bad in [
        token.substring(1),
        '$token!',
        token.toUpperCase(),
        'x',
      ]) {
        final r = await send('/api/status', headers: bearer('Bearer $bad'));
        expect(r.statusCode, 401, reason: 'token "$bad"');
      }
    });

    test('other schemes and a bare token are 401', () async {
      for (final bad in [
        'Basic $token',
        token,
        'Bearer',
        'Bearer ',
        'Token $token',
      ]) {
        final r = await send('/api/status', headers: bearer(bad));
        expect(r.statusCode, 401, reason: 'header "$bad"');
      }
    });

    test('the right token is accepted on every endpoint', () async {
      final ok = bearer('Bearer $token');
      expect((await send('/api/status', headers: ok)).statusCode, 200);
      expect(
        (await send('/api/history?provider=stripe', headers: ok)).statusCode,
        200,
      );
    });

    test('the scheme is case-insensitive', () async {
      final r = await send('/api/status', headers: bearer('bearer $token'));
      expect(r.statusCode, 200);
    });

    test('unknown paths and methods do not get past auth', () async {
      expect((await send('/nope')).statusCode, 401);
      expect((await send('/api/status', method: 'POST')).statusCode, 401);
      // With valid credentials they behave as before.
      final ok = bearer('Bearer $token');
      expect((await send('/nope', headers: ok)).statusCode, 404);
      expect(
        (await send('/api/status', method: 'POST', headers: ok)).statusCode,
        405,
      );
    });
  });

  group('CORS keeps working', () {
    test('the preflight needs no credentials', () async {
      final r = await send('/api/status', method: 'OPTIONS');
      expect(r.statusCode, 204);
      expect(r.headers['access-control-allow-origin'], '*');
    });

    test('the preflight allows the Authorization header', () async {
      final r = await send('/api/status', method: 'OPTIONS');
      expect(
        r.headers['access-control-allow-headers'],
        contains('authorization'),
      );
    });

    test(
      'a 401 still carries CORS headers so the browser can read it',
      () async {
        final r = await send('/api/status');
        expect(r.headers['access-control-allow-origin'], '*');
      },
    );
  });

  group('without a token', () {
    test('the API stays open', () async {
      handler = apiHandler(store: store, policies: const [policy]);
      expect((await send('/api/status')).statusCode, 200);
    });
  });
}
