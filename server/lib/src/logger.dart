/// Severity, lowest first. A [Logger] drops messages below its level.
enum LogLevel { debug, info, warn, error }

/// Small timestamped logger. The sink and clock are injectable for tests.
///
/// Line format: `2026-01-01T12:00:00.000Z INFO  message`.
class Logger {
  Logger({
    this.level = LogLevel.info,
    void Function(String line)? sink,
    DateTime Function()? now,
  }) : _sink = sink ?? print,
       _now = now ?? DateTime.now;

  /// Reads `LOG_LEVEL` (debug, info, warn, error; case-insensitive).
  /// Unset or unrecognised values fall back to info.
  factory Logger.fromEnv(
    Map<String, String> env, {
    void Function(String line)? sink,
  }) => Logger(level: parseLogLevel(env['LOG_LEVEL']), sink: sink);

  final LogLevel level;
  final void Function(String line) _sink;
  final DateTime Function() _now;

  void debug(String message) => _log(LogLevel.debug, message);
  void info(String message) => _log(LogLevel.info, message);
  void warn(String message) => _log(LogLevel.warn, message);
  void error(String message) => _log(LogLevel.error, message);

  void _log(LogLevel at, String message) {
    if (at.index < level.index) return;
    final label = at.name.toUpperCase().padRight(5);
    _sink('${_now().toUtc().toIso8601String()} $label $message');
  }
}

/// Parses a level name, returning info for null or unknown values.
LogLevel parseLogLevel(String? name) {
  final wanted = name?.trim().toLowerCase();
  for (final level in LogLevel.values) {
    if (level.name == wanted) return level;
  }
  return LogLevel.info;
}
