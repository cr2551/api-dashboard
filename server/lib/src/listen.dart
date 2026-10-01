import 'dart:io';

import 'services_config.dart';

/// Where `serve.dart` listens: the `HOST` environment variable (an IP address
/// or `localhost`), default `127.0.0.1`.
///
/// Use `0.0.0.0` inside a container, where the reverse proxy reaches the API
/// over the container network. Throws [ConfigException] for an address it
/// cannot parse, and when a non-loopback address has no [authToken]: an open
/// API reachable from the network would hand out every probe result.
InternetAddress resolveListenAddress(
  Map<String, String> env, {
  String? authToken,
}) {
  final raw = env['HOST']?.trim() ?? '';
  final address = switch (raw) {
    '' || 'localhost' => InternetAddress.loopbackIPv4,
    _ => InternetAddress.tryParse(raw),
  };
  if (address == null) {
    throw ConfigException('HOST', 'not an IP address: "$raw"');
  }
  if (!address.isLoopback && authToken == null) {
    throw ConfigException(
      'HOST',
      '$raw is reachable from the network, so API_TOKEN must be set',
    );
  }
  return address;
}
