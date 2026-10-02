import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_probe.dart';
import 'probe_result.dart';

/// Reads a provider's public Atlassian Statuspage summary
/// (`https://<status page>/api/v2/status.json`, no account or key needed).
///
/// The probe succeeds only while `status.indicator` is `none`. Any other
/// indicator (`minor`, `major`, `critical`, `maintenance`) fails with
/// [ProbeErrorKind.reported] and the page's own description, so an incident
/// the provider has declared shows up even when its API still answers our
/// own probes. HTTP status, timeouts and retries work as in [HttpProbe].
class StatuspageProbe extends HttpProbe {
  StatuspageProbe({
    required super.provider,
    required super.endpoint,
    super.timeout,
    super.retries,
    super.client,
    super.now,
    super.stopwatch,
  });

  @override
  ProbeFailure? judge(http.Response response) {
    final status = _status(response.body);
    if (status == null) {
      return (error: 'not a status page response', kind: ProbeErrorKind.other);
    }
    final (:indicator, :description) = status;
    if (indicator == 'none') return null;
    return (
      error: description == null ? indicator : '$indicator: $description',
      kind: ProbeErrorKind.reported,
    );
  }

  static ({String indicator, String? description})? _status(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final status = json['status'];
      if (status is! Map) return null;
      final indicator = status['indicator'];
      if (indicator is! String) return null;
      final description = status['description'];
      return (
        indicator: indicator,
        description: description is String ? description : null,
      );
    } on FormatException {
      return null;
    }
  }
}
