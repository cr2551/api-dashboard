import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

/// The whole pipeline with real components and only the network faked:
/// StripeProbe -> ProbeStore (SQLite in memory) -> SLA -> BreachTracker ->
/// Monitor -> NtfyAlerter. The fake Stripe endpoint is healthy, then fails,
/// then heals again.
void main() {
  final start = DateTime.utc(2026, 1, 1, 12);
  late DateTime clock;
  late int stripeStatus;
  late ProbeStore store;
  late List<http.Request> ntfyRequests;
  late List<String> logLines;

  Monitor build({int consecutiveFailures = 1}) {
    final stripe = StripeProbe(
      apiKey: 'sk_test_fake',
      client: MockClient((_) async => http.Response('{}', stripeStatus)),
      now: () => clock,
      retries: 0,
    );
    final ntfy = NtfyAlerter(
      topic: 'drill-topic',
      client: MockClient((req) async {
        ntfyRequests.add(req);
        return http.Response('', 200);
      }),
      now: () => clock,
    );
    return Monitor(
      probe: stripe,
      store: store,
      policy: SlaPolicy(
        provider: StripeProbe.providerName,
        minUptimePercent: 100,
        window: const Duration(minutes: 1),
        minSamples: 2,
        consecutiveFailures: consecutiveFailures,
      ),
      alerter: ntfy,
      logger: Logger(
        level: LogLevel.debug,
        sink: logLines.add,
        now: () => clock,
      ),
      now: () => clock,
    );
  }

  /// Runs one cycle [seconds] after the start and lets async sends finish.
  Future<void> cycle(Monitor m, int seconds, int status) async {
    clock = start.add(Duration(seconds: seconds));
    stripeStatus = status;
    await m.runOnce();
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    clock = start;
    stripeStatus = 200;
    store = ProbeStore.inMemory();
    ntfyRequests = [];
    logLines = [];
  });
  tearDown(() => store.close());

  test('a failing endpoint alerts once, stays quiet, then recovers', () async {
    final m = build();

    await cycle(m, 0, 200);
    await cycle(m, 10, 200);
    expect(ntfyRequests, isEmpty, reason: 'healthy: no alert');

    await cycle(m, 20, 503); // uptime 66%: breach opens
    expect(ntfyRequests, hasLength(1));
    final alert = ntfyRequests.single;
    expect(alert.url.toString(), 'https://ntfy.sh/drill-topic');
    expect(alert.headers['Title'], contains('SLA breach'));
    expect(alert.headers['Title'], contains('stripe'));
    expect(alert.headers['Title'], contains('uptime'));
    expect(alert.body, contains('below 100.0%'));

    await cycle(m, 30, 503);
    await cycle(m, 40, 503);
    expect(ntfyRequests, hasLength(1), reason: 'persisting breach is silent');

    // Once the endpoint is back the failures age out of the 1-minute window.
    // A single sample is not enough data to judge, so the breach resolves.
    await cycle(m, 120, 200);
    expect(ntfyRequests, hasLength(2));
    final recovery = ntfyRequests.last;
    expect(recovery.headers['Title'], contains('SLA recovered'));
    expect(recovery.body, contains('after 1m 40s'));

    await cycle(m, 130, 200);
    await cycle(m, 140, 200);
    expect(ntfyRequests, hasLength(2), reason: 'recovery is sent once');
  });

  test('every probe is stored with its error category', () async {
    final m = build();
    await cycle(m, 0, 200);
    await cycle(m, 10, 503);
    await cycle(m, 20, 401);

    final rows = store.query('stripe', since: start);
    expect(rows.map((r) => r.success), [true, false, false]);
    expect(rows.map((r) => r.errorKind), [
      null,
      ProbeErrorKind.http5xx,
      ProbeErrorKind.http4xx,
    ]);
  });

  test('debounce: a single failed probe does not alert', () async {
    final m = build(consecutiveFailures: 2);

    await cycle(m, 0, 200);
    await cycle(m, 10, 200);
    await cycle(m, 20, 503); // first bad evaluation only
    expect(ntfyRequests, isEmpty);

    await cycle(m, 30, 503); // second in a row
    expect(ntfyRequests, hasLength(1));
  });

  test('the log tells the story of the incident', () async {
    final m = build();
    await cycle(m, 0, 200);
    await cycle(m, 10, 200);
    await cycle(m, 20, 503);

    expect(logLines.any((l) => l.contains('stripe ok')), isTrue);
    expect(logLines.any((l) => l.contains('stripe FAIL')), isTrue);
    expect(logLines.any((l) => l.contains('SLA breach opened')), isTrue);
    expect(logLines.any((l) => l.contains('alert sent')), isTrue);
  });
}
