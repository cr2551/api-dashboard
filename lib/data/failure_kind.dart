import 'package:flutter/material.dart';

/// Why a probe failed, as categorised by the backend.
enum FailureKind {
  timeout(
    label: 'Timeout',
    icon: Icons.timer_off_outlined,
    hint: 'The service did not answer in time.',
  ),
  connection(
    label: 'Connection / DNS',
    icon: Icons.link_off,
    hint:
        'Could not reach the host: DNS failure, connection refused or '
        'network down.',
  ),
  tls(
    label: 'TLS / certificate',
    icon: Icons.lock_open,
    hint:
        'The secure connection failed, for example an expired or invalid '
        'certificate.',
  ),
  http4xx(
    label: 'HTTP 4xx',
    icon: Icons.block,
    hint:
        'The service rejected the request (client error). Often a wrong key, '
        'URL or expected status.',
  ),
  http5xx(
    label: 'HTTP 5xx',
    icon: Icons.dns_outlined,
    hint: 'The service itself is failing (server error).',
  ),
  other(
    label: 'Other',
    icon: Icons.error_outline,
    hint: 'Unexpected status or error.',
  );

  const FailureKind({
    required this.label,
    required this.icon,
    required this.hint,
  });

  final String label;
  final IconData icon;

  /// One plain-language sentence on what this kind of failure usually means.
  final String hint;

  /// Reads the backend's `errorKind` string. Null stays null (success, or a
  /// result stored before categories existed); a kind this app does not know
  /// yet becomes [other].
  static FailureKind? parse(String? name) {
    if (name == null) return null;
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return other;
  }
}
