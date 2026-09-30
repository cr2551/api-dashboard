import 'package:http/http.dart' as http;

import 'alerter.dart';
import 'config.dart';
import 'sla.dart';

/// Sends alerts to an ntfy.sh topic (https://docs.ntfy.sh/publish/).
///
/// Delivery failures are reported through [onError] (printed by default) and
/// never thrown, so a broken alert channel cannot stop probing. The HTTP
/// client and clock are injectable for tests.
class NtfyAlerter implements Alerter {
  NtfyAlerter({
    required this.topic,
    Uri? server,
    this.token,
    http.Client? client,
    DateTime Function()? now,
    void Function(String message)? onError,
  }) : server = server ?? Uri.parse('https://ntfy.sh'),
       _client = client ?? http.Client(),
       _now = now ?? DateTime.now,
       _onError = onError ?? print;

  /// Builds an alerter from `NTFY_TOPIC` (required), `NTFY_SERVER` and
  /// `NTFY_TOKEN` (env or config.json). Returns null when no topic is set.
  static NtfyAlerter? fromConfig(
    Map<String, String> env, {
    String? configPath,
    http.Client? client,
  }) {
    final topic = readSetting('NTFY_TOPIC', env, configPath: configPath);
    if (topic == null) return null;
    final server = readSetting('NTFY_SERVER', env, configPath: configPath);
    return NtfyAlerter(
      topic: topic,
      server: server == null ? null : Uri.parse(server),
      token: readSetting('NTFY_TOKEN', env, configPath: configPath),
      client: client,
    );
  }

  final String topic;
  final Uri server;
  final String? token;
  final http.Client _client;
  final DateTime Function() _now;
  final void Function(String message) _onError;

  @override
  void alert(SlaBreach breach) => _send(
    title: 'SLA breach: ${breach.provider} (${breach.type.name})',
    body: '${breach.message}\nat ${_now().toUtc().toIso8601String()}',
    priority: 'high',
    tags: 'rotating_light',
  );

  /// Tells the channel that [breach] is over.
  void recovered(SlaBreach breach) => _send(
    title: 'SLA recovered: ${breach.provider} (${breach.type.name})',
    body:
        'Back within SLA (was: ${breach.message})\n'
        'at ${_now().toUtc().toIso8601String()}',
    priority: 'default',
    tags: 'white_check_mark',
  );

  void _send({
    required String title,
    required String body,
    required String priority,
    required String tags,
  }) {
    final url = server.replace(
      pathSegments: [...server.pathSegments.where((s) => s.isNotEmpty), topic],
    );
    _client
        .post(
          url,
          headers: {
            'Title': title,
            'Priority': priority,
            'Tags': tags,
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: body,
        )
        .then((response) {
          if (response.statusCode < 200 || response.statusCode >= 300) {
            _onError('ntfy alert failed: HTTP ${response.statusCode}');
          }
        })
        .catchError((Object e) {
          _onError('ntfy alert failed: $e');
        });
  }

  void close() => _client.close();
}

/// Console alerts, plus ntfy when `NTFY_TOPIC` is configured.
Alerter buildAlerter(Map<String, String> env, {String? configPath}) {
  final ntfy = NtfyAlerter.fromConfig(env, configPath: configPath);
  return ntfy == null
      ? ConsoleAlerter()
      : MultiAlerter([ConsoleAlerter(), ntfy]);
}

/// Forwards every alert to several alerters (e.g. console plus ntfy).
class MultiAlerter implements Alerter {
  MultiAlerter(this.alerters);

  final List<Alerter> alerters;

  @override
  void alert(SlaBreach breach) {
    for (final a in alerters) {
      a.alert(breach);
    }
  }
}
