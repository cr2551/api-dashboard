import 'package:sqlite3/sqlite3.dart';

import 'breach_tracker.dart';
import 'probe_result.dart';
import 'sla.dart';
import 'stored_event.dart';

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
        error TEXT,
        error_kind TEXT
      )
    ''');
    _addErrorKindColumnIfMissing();
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_probe_results_provider_time
      ON probe_results (provider, timestamp_us)
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS breach_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        provider TEXT NOT NULL,
        breach_type TEXT NOT NULL,
        kind TEXT NOT NULL,
        message TEXT NOT NULL,
        timestamp_us INTEGER NOT NULL,
        duration_ms INTEGER
      )
    ''');
  }

  /// Databases created before error categories existed lack the column.
  void _addErrorKindColumnIfMissing() {
    final columns = _db.select('PRAGMA table_info(probe_results)');
    if (columns.any((c) => c['name'] == 'error_kind')) return;
    _db.execute('ALTER TABLE probe_results ADD COLUMN error_kind TEXT');
  }

  /// Opens (or creates) the database file at [path].
  factory ProbeStore.open(String path) => ProbeStore._(sqlite3.open(path));

  /// Creates a throwaway in-memory store, mainly for tests.
  factory ProbeStore.inMemory() => ProbeStore._(sqlite3.openInMemory());

  final Database _db;

  void insert(ProbeResult r) {
    _db.execute(
      'INSERT INTO probe_results '
      '(provider, timestamp_us, latency_us, success, status_code, error, '
      'error_kind) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        r.provider,
        r.timestamp.microsecondsSinceEpoch,
        r.latency.inMicroseconds,
        r.success ? 1 : 0,
        r.statusCode,
        r.error,
        r.errorKind?.name,
      ],
    );
  }

  /// Saves a breach that opened or resolved. The id is assigned here.
  void insertBreachEvent(StoredBreachEvent e) {
    _db.execute(
      'INSERT INTO breach_events '
      '(provider, breach_type, kind, message, timestamp_us, duration_ms) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        e.provider,
        e.type.name,
        e.kind.name,
        e.message,
        e.timestamp.microsecondsSinceEpoch,
        e.duration?.inMilliseconds,
      ],
    );
  }

  /// The most recent [limit] breach events with an id greater than [afterId]
  /// (all of them when null), **oldest first** so a client can append them
  /// and remember the last id.
  List<StoredBreachEvent> breachEvents({int? afterId, int limit = 50}) {
    if (limit < 0) throw ArgumentError.value(limit, 'limit', 'must be >= 0');
    final rows = _db.select(
      'SELECT * FROM ('
      'SELECT * FROM breach_events WHERE id > ? ORDER BY id DESC LIMIT ?'
      ') ORDER BY id ASC',
      [afterId ?? 0, limit],
    );
    return [
      for (final row in rows)
        StoredBreachEvent(
          id: row['id'] as int,
          provider: row['provider'] as String,
          type: SlaBreachType.values.byName(row['breach_type'] as String),
          kind: BreachEventKind.values.byName(row['kind'] as String),
          message: row['message'] as String,
          timestamp: DateTime.fromMicrosecondsSinceEpoch(
            row['timestamp_us'] as int,
            isUtc: true,
          ),
          duration: row['duration_ms'] == null
              ? null
              : Duration(milliseconds: row['duration_ms'] as int),
        ),
    ];
  }

  /// Results for [provider] at or after [since], oldest first.
  List<ProbeResult> query(String provider, {required DateTime since}) {
    final rows = _db.select(
      'SELECT * FROM probe_results '
      'WHERE provider = ? AND timestamp_us >= ? '
      'ORDER BY timestamp_us ASC, id ASC',
      [provider, since.microsecondsSinceEpoch],
    );
    return [for (final row in rows) _toResult(row)];
  }

  /// The most recent [limit] results for [provider], **newest first**. Returns
  /// fewer when less data exists and an empty list for an unknown provider or
  /// a [limit] of 0. Ties on the timestamp are broken by insertion order, so
  /// the last inserted comes first.
  List<ProbeResult> latest(String provider, int limit) {
    if (limit < 0) throw ArgumentError.value(limit, 'limit', 'must be >= 0');
    final rows = _db.select(
      'SELECT * FROM probe_results '
      'WHERE provider = ? '
      'ORDER BY timestamp_us DESC, id DESC '
      'LIMIT ?',
      [provider, limit],
    );
    return [for (final row in rows) _toResult(row)];
  }

  static ProbeResult _toResult(Row row) => ProbeResult(
    provider: row['provider'] as String,
    timestamp: DateTime.fromMicrosecondsSinceEpoch(
      row['timestamp_us'] as int,
      isUtc: true,
    ),
    latency: Duration(microseconds: row['latency_us'] as int),
    success: (row['success'] as int) == 1,
    statusCode: row['status_code'] as int?,
    error: row['error'] as String?,
    errorKind: _kindFromName(row['error_kind'] as String?),
  );

  static ProbeErrorKind? _kindFromName(String? name) {
    for (final kind in ProbeErrorKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }

  void close() => _db.close();
}
