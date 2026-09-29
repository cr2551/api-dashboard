import 'package:sqlite3/sqlite3.dart';

import 'probe_result.dart';

/// Persists [ProbeResult]s in SQLite.
class ProbeStore {
  ProbeStore._(this._db) {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS probe_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        provider TEXT NOT NULL,
        timestamp_us INTEGER NOT NULL,
        latency_us INTEGER NOT NULL,
        success INTEGER NOT NULL,
        status_code INTEGER,
        error TEXT
      )
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_probe_results_provider_time
      ON probe_results (provider, timestamp_us)
    ''');
  }

  /// Opens (or creates) the database file at [path].
  factory ProbeStore.open(String path) => ProbeStore._(sqlite3.open(path));

  /// Creates a throwaway in-memory store, mainly for tests.
  factory ProbeStore.inMemory() => ProbeStore._(sqlite3.openInMemory());

  final Database _db;

  void insert(ProbeResult r) {
    _db.execute(
      'INSERT INTO probe_results '
      '(provider, timestamp_us, latency_us, success, status_code, error) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        r.provider,
        r.timestamp.microsecondsSinceEpoch,
        r.latency.inMicroseconds,
        r.success ? 1 : 0,
        r.statusCode,
        r.error,
      ],
    );
  }

  /// Results for [provider] at or after [since], oldest first.
  List<ProbeResult> query(String provider, {required DateTime since}) {
    final rows = _db.select(
      'SELECT * FROM probe_results '
      'WHERE provider = ? AND timestamp_us >= ? '
      'ORDER BY timestamp_us ASC, id ASC',
      [provider, since.microsecondsSinceEpoch],
    );
    return [
      for (final row in rows)
        ProbeResult(
          provider: row['provider'] as String,
          timestamp: DateTime.fromMicrosecondsSinceEpoch(
            row['timestamp_us'] as int,
            isUtc: true,
          ),
          latency: Duration(microseconds: row['latency_us'] as int),
          success: (row['success'] as int) == 1,
          statusCode: row['status_code'] as int?,
          error: row['error'] as String?,
        ),
    ];
  }

  void close() => _db.close();
}
