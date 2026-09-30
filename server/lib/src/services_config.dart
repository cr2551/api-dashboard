import 'dart:convert';
import 'dart:io';

import 'sla.dart';

/// Thrown for an invalid services config. [field] is the path to the bad
/// value, e.g. `services[1].sla.minUptimePercent`.
class ConfigException implements Exception {
  ConfigException(this.field, this.message);

  final String field;
  final String message;

  @override
  String toString() => 'Invalid config at $field: $message';
}

/// Probe types the backend knows how to run.
const supportedServiceTypes = {'stripe'};

/// One monitored service: what to probe, how often, and its SLA.
///
/// Secrets (API keys) are deliberately not part of this file; they stay in
/// env vars or the git-ignored `config.json`.
class ServiceConfig {
  const ServiceConfig({
    required this.name,
    required this.type,
    required this.interval,
    required this.timeout,
    required this.policy,
    this.endpoint,
  });

  final String name;
  final String type;

  /// Overrides the probe's default endpoint when set.
  final Uri? endpoint;
  final Duration interval;
  final Duration timeout;
  final SlaPolicy policy;
}

/// Reads and validates the services file at [path].
List<ServiceConfig> loadServicesConfig(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw ConfigException(path, 'file not found');
  }
  final Object? json;
  try {
    json = jsonDecode(file.readAsStringSync());
  } on FormatException catch (e) {
    throw ConfigException(path, 'not valid JSON (${e.message})');
  }
  return parseServicesConfig(json);
}

/// Validates decoded JSON of the form `{"services": [ ... ]}`.
///
/// Unknown keys are rejected so a typo like `intervalSecs` fails loudly
/// instead of silently falling back to a default.
List<ServiceConfig> parseServicesConfig(Object? json) {
  final root = _object(json, 'config');
  _rejectUnknown(root, {'services'}, 'config');
  final list = root['services'];
  if (list is! List) {
    throw ConfigException('services', 'required, must be a list');
  }
  if (list.isEmpty) {
    throw ConfigException('services', 'must contain at least one service');
  }

  final services = <ServiceConfig>[];
  final names = <String>{};
  for (var i = 0; i < list.length; i++) {
    final service = _parseService(list[i], 'services[$i]');
    if (!names.add(service.name)) {
      throw ConfigException(
        'services[$i].name',
        'duplicate name "${service.name}"',
      );
    }
    services.add(service);
  }
  return services;
}

ServiceConfig _parseService(Object? json, String at) {
  final map = _object(json, at);
  _rejectUnknown(map, {
    'name',
    'type',
    'endpoint',
    'intervalSeconds',
    'timeoutSeconds',
    'sla',
  }, at);

  final name = _requiredString(map, 'name', at);
  final type = _requiredString(map, 'type', at);
  if (!supportedServiceTypes.contains(type)) {
    throw ConfigException(
      '$at.type',
      'unknown type "$type" (supported: ${supportedServiceTypes.join(', ')})',
    );
  }

  Uri? endpoint;
  if (map.containsKey('endpoint')) {
    final raw = _requiredString(map, 'endpoint', at);
    endpoint = Uri.tryParse(raw);
    if (endpoint == null ||
        !{'http', 'https'}.contains(endpoint.scheme) ||
        endpoint.host.isEmpty) {
      throw ConfigException('$at.endpoint', 'must be an http(s) URL');
    }
  }

  final interval = _positiveInt(map, 'intervalSeconds', at, fallback: 60);
  final timeout = _positiveInt(map, 'timeoutSeconds', at, fallback: 10);

  return ServiceConfig(
    name: name,
    type: type,
    endpoint: endpoint,
    interval: Duration(seconds: interval),
    timeout: Duration(seconds: timeout),
    policy: _parsePolicy(name, map['sla'], '$at.sla'),
  );
}

SlaPolicy _parsePolicy(String provider, Object? json, String at) {
  const defaults = SlaPolicy(provider: '');
  if (json == null) return SlaPolicy(provider: provider);

  final map = _object(json, at);
  _rejectUnknown(map, {
    'maxP95LatencyMs',
    'minUptimePercent',
    'windowMinutes',
    'minSamples',
    'consecutiveFailures',
  }, at);

  final uptime = map['minUptimePercent'];
  if (map.containsKey('minUptimePercent') &&
      (uptime is! num || uptime < 0 || uptime > 100)) {
    throw ConfigException(
      '$at.minUptimePercent',
      'must be a number between 0 and 100',
    );
  }

  return SlaPolicy(
    provider: provider,
    maxP95Latency: Duration(
      milliseconds: _positiveInt(
        map,
        'maxP95LatencyMs',
        at,
        fallback: defaults.maxP95Latency.inMilliseconds,
      ),
    ),
    minUptimePercent: uptime is num
        ? uptime.toDouble()
        : defaults.minUptimePercent,
    window: Duration(
      minutes: _positiveInt(
        map,
        'windowMinutes',
        at,
        fallback: defaults.window.inMinutes,
      ),
    ),
    minSamples: _positiveInt(
      map,
      'minSamples',
      at,
      fallback: defaults.minSamples,
    ),
    consecutiveFailures: _positiveInt(
      map,
      'consecutiveFailures',
      at,
      fallback: defaults.consecutiveFailures,
    ),
  );
}

Map<String, Object?> _object(Object? value, String at) {
  if (value is! Map) throw ConfigException(at, 'must be an object');
  return {for (final e in value.entries) e.key.toString(): e.value};
}

void _rejectUnknown(Map<String, Object?> map, Set<String> known, String at) {
  for (final key in map.keys) {
    if (!known.contains(key)) {
      throw ConfigException(
        at == 'config' ? key : '$at.$key',
        'unknown field (allowed: ${(known.toList()..sort()).join(', ')})',
      );
    }
  }
}

String _requiredString(Map<String, Object?> map, String key, String at) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw ConfigException('$at.$key', 'required, must be a non-empty string');
  }
  return value.trim();
}

int _positiveInt(
  Map<String, Object?> map,
  String key,
  String at, {
  required int fallback,
}) {
  if (!map.containsKey(key)) return fallback;
  final value = map[key];
  if (value is! int || value < 1) {
    throw ConfigException('$at.$key', 'must be a whole number of 1 or more');
  }
  return value;
}
