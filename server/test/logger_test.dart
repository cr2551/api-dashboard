import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

void main() {
  final fixed = DateTime.utc(2026, 1, 1, 12, 30, 5);

  Logger loggerAt(LogLevel level, List<String> lines) =>
      Logger(level: level, sink: lines.add, now: () => fixed);

  test('formats a line with UTC timestamp, padded level and message', () {
    final lines = <String>[];
    loggerAt(LogLevel.debug, lines)
      ..debug('d')
      ..info('i')
      ..warn('w')
      ..error('e');
    expect(lines, [
      '2026-01-01T12:30:05.000Z DEBUG d',
      '2026-01-01T12:30:05.000Z INFO  i',
      '2026-01-01T12:30:05.000Z WARN  w',
      '2026-01-01T12:30:05.000Z ERROR e',
    ]);
  });

  test('drops messages below the level', () {
    final lines = <String>[];
    loggerAt(LogLevel.warn, lines)
      ..debug('d')
      ..info('i')
      ..warn('w')
      ..error('e');
    expect(lines.map((l) => l.split(' ')[1]), ['WARN', 'ERROR']);
  });

  test('error level only shows errors', () {
    final lines = <String>[];
    loggerAt(LogLevel.error, lines)
      ..warn('w')
      ..error('e');
    expect(lines, hasLength(1));
  });

  group('LOG_LEVEL', () {
    test('parses names case-insensitively', () {
      expect(parseLogLevel('debug'), LogLevel.debug);
      expect(parseLogLevel('WARN'), LogLevel.warn);
      expect(parseLogLevel(' Error '), LogLevel.error);
    });

    test('defaults to info when unset or unknown', () {
      expect(parseLogLevel(null), LogLevel.info);
      expect(parseLogLevel(''), LogLevel.info);
      expect(parseLogLevel('loud'), LogLevel.info);
    });

    test('fromEnv reads LOG_LEVEL', () {
      expect(Logger.fromEnv({'LOG_LEVEL': 'debug'}).level, LogLevel.debug);
      expect(Logger.fromEnv({}).level, LogLevel.info);
    });
  });
}
