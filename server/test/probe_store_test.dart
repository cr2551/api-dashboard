import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

ProbeResult result(
  DateTime at, {
  String provider = 'stripe',
  bool ok = true,
  int? status = 200,
  String? error,
}) =>
    ProbeResult(
      provider: provider,
      timestamp: at,
      latency: const Duration(milliseconds: 123),
      success: ok,
      statusCode: status,
      error: error,
    );

void main() {
  late ProbeStore store;
  final t0 = DateTime.utc(2026, 1, 1, 12);

  setUp(() => store = ProbeStore.inMemory());
  tearDown(() => store.close());

  test('round-trips every field', () {
    store.insert(result(t0, ok: false, status: 500, error: 'HTTP 500'));
    final r = store.query('stripe', since: t0).single;
    expect(r.provider, 'stripe');
    expect(r.timestamp, t0);
    expect(r.latency, const Duration(milliseconds: 123));
    expect(r.success, isFalse);
    expect(r.statusCode, 500);
    expect(r.error, 'HTTP 500');
  });

  test('stores null status code and error', () {
    store.insert(result(t0, status: null));
    final r = store.query('stripe', since: t0).single;
    expect(r.statusCode, isNull);
    expect(r.error, isNull);
  });

  test('filters by provider and time, oldest first', () {
    store
      ..insert(result(t0.add(const Duration(minutes: 2))))
      ..insert(result(t0.subtract(const Duration(minutes: 5))))
      ..insert(result(t0))
      ..insert(result(t0, provider: 'other'));

    final rows = store.query('stripe', since: t0);

    expect(rows.map((r) => r.timestamp), [
      t0,
      t0.add(const Duration(minutes: 2)),
    ]);
  });

  test('empty store returns no rows', () {
    expect(store.query('stripe', since: t0), isEmpty);
  });
}
