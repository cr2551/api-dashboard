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

  group('latest', () {
    void insertN(int n, {String provider = 'stripe'}) {
      for (var i = 0; i < n; i++) {
        store.insert(result(t0.add(Duration(minutes: i)), provider: provider));
      }
    }

    test('empty store returns no rows', () {
      expect(store.latest('stripe', 5), isEmpty);
    });

    test('fewer rows than the limit returns them all, newest first', () {
      insertN(3);
      final rows = store.latest('stripe', 10);
      expect(rows.map((r) => r.timestamp), [
        t0.add(const Duration(minutes: 2)),
        t0.add(const Duration(minutes: 1)),
        t0,
      ]);
    });

    test('more rows than the limit returns only the newest N', () {
      insertN(10);
      final rows = store.latest('stripe', 3);
      expect(rows.map((r) => r.timestamp), [
        t0.add(const Duration(minutes: 9)),
        t0.add(const Duration(minutes: 8)),
        t0.add(const Duration(minutes: 7)),
      ]);
    });

    test('exactly N rows returns all of them', () {
      insertN(4);
      expect(store.latest('stripe', 4), hasLength(4));
    });

    test('only returns the requested provider', () {
      insertN(3);
      insertN(5, provider: 'other');
      expect(store.latest('stripe', 10), hasLength(3));
      expect(store.latest('other', 2), hasLength(2));
      expect(store.latest('unknown', 10), isEmpty);
    });

    test('orders by time, not insertion order', () {
      store
        ..insert(result(t0.add(const Duration(minutes: 5))))
        ..insert(result(t0))
        ..insert(result(t0.add(const Duration(minutes: 2))));
      expect(store.latest('stripe', 2).map((r) => r.timestamp), [
        t0.add(const Duration(minutes: 5)),
        t0.add(const Duration(minutes: 2)),
      ]);
    });

    test('same timestamp: the last inserted comes first', () {
      store
        ..insert(result(t0, status: 200))
        ..insert(result(t0, ok: false, status: 500));
      expect(store.latest('stripe', 2).map((r) => r.statusCode), [500, 200]);
    });

    test('keeps every field, including the error category', () {
      store.insert(
        result(
          t0,
          ok: false,
          status: 503,
          error: 'HTTP 503',
          kind: ProbeErrorKind.http5xx,
        ),
      );
      final r = store.latest('stripe', 1).single;
      expect(r.success, isFalse);
      expect(r.statusCode, 503);
      expect(r.error, 'HTTP 503');
      expect(r.errorKind, ProbeErrorKind.http5xx);
    });

    test('limit 0 is empty and a negative limit is rejected', () {
      insertN(2);
      expect(store.latest('stripe', 0), isEmpty);
      expect(() => store.latest('stripe', -1), throwsArgumentError);
    });
  });
}
