import 'dart:io';

import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

void main() {
  test('defaults to IPv4 loopback', () {
    expect(resolveListenAddress({}), InternetAddress.loopbackIPv4);
    expect(resolveListenAddress({'HOST': ''}), InternetAddress.loopbackIPv4);
    expect(
      resolveListenAddress({'HOST': 'localhost'}),
      InternetAddress.loopbackIPv4,
    );
  });

  test('loopback addresses need no token', () {
    expect(resolveListenAddress({'HOST': '127.0.0.1'}).isLoopback, isTrue);
    expect(resolveListenAddress({'HOST': '::1'}).isLoopback, isTrue);
  });

  test('a network address with a token is allowed', () {
    expect(
      resolveListenAddress({'HOST': '0.0.0.0'}, authToken: 't'),
      InternetAddress.anyIPv4,
    );
    expect(
      resolveListenAddress({'HOST': '::'}, authToken: 't'),
      InternetAddress.anyIPv6,
    );
  });

  test('a network address without a token is refused', () {
    expect(
      () => resolveListenAddress({'HOST': '0.0.0.0'}),
      throwsA(
        isA<ConfigException>()
            .having((e) => e.field, 'field', 'HOST')
            .having((e) => e.message, 'message', contains('API_TOKEN')),
      ),
    );
  });

  test('an unparseable host is refused', () {
    expect(
      () => resolveListenAddress({'HOST': 'example.com'}, authToken: 't'),
      throwsA(isA<ConfigException>()),
    );
  });
}
