import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

ProbeResult result(
  DateTime at, {
  String provider = 'stripe',
  bool ok = true,
  int? status = 200,
  String? error,
  ProbeErrorKind? kind,
}) => ProbeResult(
  provider: provider,
  timestamp: at,
  latency: const Duration(milliseconds: 123),
  success: ok,
  statusCode: status,
  error: error,
  errorKind: kind,
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
    expect(r.errorKind, isNull);
  });

  test('round-trips the error category', () {
    store.insert(
      result(t0, ok: false, status: 503, kind: ProbeErrorKind.http5xx),
    );
    expect(
      store.query('stripe', since: t0).single.errorKind,
      ProbeErrorKind.http5xx,
    );
  });

  test('adds the error_kind column to a pre-existing database', () {
    final dir = Directory.systemTemp.createTempSync('store_migration');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/old.db';
    final old = sqlite3.open(path);
    old.execute('''
      CREATE TABLE probe_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        provider TEXT NOT NULL,
        timestamp_us INTEGER NOT NULL,
        latency_us INTEGER NOT NULL,
        success INTEGER NOT NULL,
        status_code INTEGER,
        error TEXT
      )
    ''');
    old.execute(
      'INSERT INTO probe_results '
      '(provider, timestamp_us, latency_us, success, status_code, error) '
      "VALUES ('stripe', ${t0.microsecondsSinceEpoch}, 1000, 0, 500, 'HTTP 500')",
    );
    old.close();

    final migrated = ProbeStore.open(path);
    addTearDown(migrated.close);
    migrated.insert(result(t0, ok: false, kind: ProbeErrorKind.timeout));

    final rows = migrated.query('stripe', since: t0);
    expect(rows.first.errorKind, isNull); // old row keeps working
    expect(rows.last.errorKind, ProbeErrorKind.timeout);
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
