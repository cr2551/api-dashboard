import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

const breach = SlaBreach(
  provider: 'stripe',
  type: SlaBreachType.latency,
  message: 'p95 latency 900ms exceeds 500ms',
);

final fixedNow = DateTime.utc(2026, 1, 1, 12);

void main() {
  late List<http.Request> sent;
  late List<String> errors;

  NtfyAlerter alerter(
    Future<http.Response> Function(http.Request) handler, {
    String? token,
  }) => NtfyAlerter(
    topic: 'my-topic',
    token: token,
    client: MockClient((req) {
      sent.add(req);
      return handler(req);
    }),
    now: () => fixedNow,
    onError: errors.add,
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    sent = [];
    errors = [];
  });

  test(
    'posts the breach to the topic with service, type, values and time',
    () async {
      alerter((_) async => http.Response('', 200)).alert(breach);
      await settle();

      final req = sent.single;
      expect(req.method, 'POST');
      expect(req.url.toString(), 'https://ntfy.sh/my-topic');
      expect(req.headers['Title'], contains('stripe'));
      expect(req.headers['Title'], contains('latency'));
      expect(req.headers['Priority'], 'high');
      expect(req.body, contains('p95 latency 900ms exceeds 500ms'));
      expect(req.body, contains('2026-01-01T12:00:00.000Z'));
      expect(errors, isEmpty);
    },
  );

  test('sends a recovery message', () async {
    alerter((_) async => http.Response('', 200)).recovered(breach);
    await settle();

    final req = sent.single;
    expect(req.headers['Title'], contains('recovered'));
    expect(req.headers['Title'], contains('stripe'));
    expect(req.body, contains('p95 latency 900ms exceeds 500ms'));
  });

  test('sends a bearer token only when configured', () async {
    alerter((_) async => http.Response('', 200), token: 'tk_1').alert(breach);
    alerter((_) async => http.Response('', 200)).alert(breach);
    await settle();

    expect(sent[0].headers['Authorization'], 'Bearer tk_1');
    expect(sent[1].headers.containsKey('Authorization'), isFalse);
  });

  test('logs HTTP errors instead of throwing', () async {
    alerter((_) async => http.Response('nope', 403)).alert(breach);
    await settle();
    expect(errors.single, contains('403'));
  });

  test('logs network errors instead of throwing', () async {
    alerter((_) async => throw http.ClientException('offline')).alert(breach);
    await settle();
    expect(errors.single, contains('offline'));
  });

  test('MultiAlerter forwards to every alerter', () {
    final a = <SlaBreach>[];
    final b = <SlaBreach>[];
    MultiAlerter([_Recorder(a), _Recorder(b)]).alert(breach);
    expect(a, [breach]);
    expect(b, [breach]);
  });

  group('fromConfig', () {
    late Directory dir;
    late String configPath;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('ntfy_config_test');
      configPath = '${dir.path}/config.json';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('returns null without a topic', () {
      expect(NtfyAlerter.fromConfig({}, configPath: configPath), isNull);
    });

    test('reads topic, server and token from env', () {
      final a = NtfyAlerter.fromConfig({
        'NTFY_TOPIC': 't',
        'NTFY_SERVER': 'https://ntfy.example.com',
        'NTFY_TOKEN': 'tk',
      }, configPath: configPath)!;
      expect(a.topic, 't');
      expect(a.server.host, 'ntfy.example.com');
      expect(a.token, 'tk');
    });

    test('falls back to config.json and defaults the server', () {
      File(configPath).writeAsStringSync('{"NTFY_TOPIC": "from_file"}');
      final a = NtfyAlerter.fromConfig({}, configPath: configPath)!;
      expect(a.topic, 'from_file');
      expect(a.server.host, 'ntfy.sh');
      expect(a.token, isNull);
    });
  });
}

class _Recorder implements Alerter {
  _Recorder(this.breaches);
  final List<SlaBreach> breaches;

  @override
  void alert(SlaBreach breach) => breaches.add(breach);
}
