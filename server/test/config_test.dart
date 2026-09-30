import 'dart:io';

import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late String configPath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('config_test');
    configPath = '${dir.path}/config.json';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('env var wins over the config file', () {
    File(configPath).writeAsStringSync('{"STRIPE_SECRET_KEY": "from_file"}');
    final key = readStripeKey({
      'STRIPE_API_KEY': 'from_env',
    }, configPath: configPath);
    expect(key, 'from_env');
  });

  test('falls back to STRIPE_SECRET_KEY in the config file', () {
    File(configPath).writeAsStringSync('{"STRIPE_SECRET_KEY": "from_file"}');
    expect(readStripeKey({}, configPath: configPath), 'from_file');
  });

  test('CONFIG_PATH env var selects the file', () {
    File(configPath).writeAsStringSync('{"STRIPE_SECRET_KEY": "k"}');
    expect(readStripeKey({'CONFIG_PATH': configPath}), 'k');
  });

  test('returns null for missing file, missing key or empty values', () {
    expect(readStripeKey({}, configPath: configPath), isNull);
    File(configPath).writeAsStringSync('{"OTHER": "x"}');
    expect(readStripeKey({}, configPath: configPath), isNull);
    File(configPath).writeAsStringSync('{"STRIPE_SECRET_KEY": ""}');
    expect(
      readStripeKey({'STRIPE_API_KEY': ''}, configPath: configPath),
      isNull,
    );
  });
}
