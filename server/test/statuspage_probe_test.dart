import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

String body(String indicator, [String? description]) => jsonEncode({
  'page': {'id': 'x', 'name': 'Square'},
  'status': {'indicator': indicator, 'description': ?description},
});

StatuspageProbe probeWith(
  Future<http.Response> Function(http.Request) handler, {
  int retries = 0,
}) => StatuspageProbe(
  provider: 'square-status',
  endpoint: Uri.parse('https://www.issquareup.com/api/v2/status.json'),
  retries: retries,
  client: MockClient(handler),
  now: () => DateTime.utc(2026, 1, 1),
);

Future<ProbeResult> run(String responseBody, [int code = 200]) =>
    probeWith((_) async => http.Response(responseBody, code)).run();

void main() {
  test('GETs the status page and succeeds when nothing is reported', () async {
    late http.Request seen;
    final r = await probeWith((req) async {
      seen = req;
      return http.Response(body('none', 'All Systems Operational'), 200);
    }).run();

    expect(seen.method, 'GET');
    expect(
      seen.url.toString(),
      'https://www.issquareup.com/api/v2/status.json',
    );
    expect(r.provider, 'square-status');
    expect(r.success, isTrue);
    expect(r.statusCode, 200);
    expect(r.error, isNull);
    expect(r.errorKind, isNull);
  });

  test(
    'fails with the provider description for every incident level',
    () async {
      for (final (indicator, description) in [
        ('minor', 'Partially Degraded Service'),
        ('major', 'Partial System Outage'),
        ('critical', 'Major Service Outage'),
        ('maintenance', 'Service Under Maintenance'),
      ]) {
        final r = await run(body(indicator, description));
        expect(r.success, isFalse, reason: indicator);
        expect(r.errorKind, ProbeErrorKind.reported, reason: indicator);
        expect(r.error, '$indicator: $description');
        expect(r.statusCode, 200);
      }
    },
  );

  test('uses the indicator alone when there is no description', () async {
    final r = await run(body('major'));
    expect(r.error, 'major');
    expect(r.errorKind, ProbeErrorKind.reported);
  });

  test('a body that is not a status page fails as other', () async {
    for (final bad in [
      'not json',
      '[]',
      '{}',
      '{"status": "ok"}',
      '{"status": {"indicator": 3}}',
    ]) {
      final r = await run(bad);
      expect(r.success, isFalse, reason: bad);
      expect(r.errorKind, ProbeErrorKind.other, reason: bad);
      expect(r.error, 'not a status page response');
    }
  });

  test('HTTP errors fail by status, without reading the body', () async {
    final r5 = await run(body('none'), 503);
    expect(r5.success, isFalse);
    expect(r5.errorKind, ProbeErrorKind.http5xx);
    expect(r5.error, 'HTTP 503');

    final r4 = await run('', 404);
    expect(r4.errorKind, ProbeErrorKind.http4xx);
  });

  test('a timeout is retried, then judged on the final answer', () async {
    var calls = 0;
    final r = await probeWith((_) async {
      calls++;
      if (calls == 1) throw TimeoutException('slow');
      return http.Response(body('none'), 200);
    }, retries: 1).run();
    expect(calls, 2);
    expect(r.success, isTrue);
  });

  test('a reported incident is a real answer and is not retried', () async {
    var calls = 0;
    final r = await probeWith((_) async {
      calls++;
      return http.Response(body('major', 'Partial System Outage'), 200);
    }, retries: 2).run();
    expect(calls, 1);
    expect(r.errorKind, ProbeErrorKind.reported);
  });
}
