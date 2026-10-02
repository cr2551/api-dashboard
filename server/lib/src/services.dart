import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'alerter.dart';
import 'config.dart';
import 'http_probe.dart';
import 'logger.dart';
import 'monitor.dart';
import 'probe.dart';
import 'probe_store.dart';
import 'services_config.dart';
import 'sla.dart';
import 'statuspage_probe.dart';
import 'stripe_probe.dart';

/// One monitored service: its settings and the [Monitor] that runs it.
class RunningService {
  RunningService(this.config, this.monitor);

  final ServiceConfig config;
  final Monitor monitor;

  SlaPolicy get policy => config.policy;
}

/// The services to run. Uses the file named by `SERVICES_CONFIG`, else
/// `../services.json` when it exists, else a single Stripe service with the
/// default policy (the behaviour before services.json existed).
///
/// A missing file that was asked for explicitly, or an invalid file, throws a
/// [ConfigException] naming the problem.
List<ServiceConfig> resolveServices(
  Map<String, String> env, {
  String? path,
  int defaultIntervalSeconds = 30,
  void Function(String message)? onInfo,
}) {
  final explicit = path ?? env['SERVICES_CONFIG'];
  final file = explicit ?? '../services.json';
  if (explicit != null || File(file).existsSync()) {
    onInfo?.call('services from $file');
    return loadServicesConfig(file);
  }
  onInfo?.call(
    'no services.json found: monitoring Stripe only with default thresholds',
  );
  return [
    ServiceConfig(
      name: StripeProbe.providerName,
      type: 'stripe',
      interval: Duration(seconds: defaultIntervalSeconds),
      timeout: const Duration(seconds: 10),
      policy: const SlaPolicy(provider: StripeProbe.providerName),
    ),
  ];
}

/// Creates the probe for [config]. Secrets come from [env] / `config.json`,
/// never from the services file.
Probe buildProbe(
  ServiceConfig config,
  Map<String, String> env, {
  String? configPath,
  http.Client? client,
  DateTime Function()? now,
}) {
  switch (config.type) {
    case 'stripe':
      final key = readStripeKey(env, configPath: configPath);
      if (key == null) {
        throw ConfigException(
          config.name,
          'needs a Stripe key: set STRIPE_API_KEY or STRIPE_SECRET_KEY in '
          'config.json (use a test-mode key)',
        );
      }
      return StripeProbe(
        apiKey: key,
        name: config.name,
        endpoint: config.endpoint,
        timeout: config.timeout,
        client: client,
        now: now,
      );
    case 'http':
      return HttpProbe(
        provider: config.name,
        endpoint: config.endpoint!,
        expectedStatus: config.expectedStatus,
        timeout: config.timeout,
        client: client,
        now: now,
      );
    case 'statuspage':
      return StatuspageProbe(
        provider: config.name,
        endpoint: config.endpoint!,
        timeout: config.timeout,
        client: client,
        now: now,
      );
  }
  throw ConfigException(config.name, 'unknown type "${config.type}"');
}

/// One [Monitor] per service, all sharing [store], [alerter] and [logger]
/// but each with its own probe and SLA policy.
List<RunningService> buildServices(
  List<ServiceConfig> configs, {
  required Map<String, String> env,
  required ProbeStore store,
  required Alerter alerter,
  Logger? logger,
  String? configPath,
  http.Client? client,
  DateTime Function()? now,
}) => [
  for (final c in configs)
    RunningService(
      c,
      Monitor(
        probe: buildProbe(
          c,
          env,
          configPath: configPath,
          client: client,
          now: now,
        ),
        store: store,
        policy: c.policy,
        alerter: alerter,
        logger: logger,
        now: now,
      ),
    ),
];

/// Runs every service on its own interval.
///
/// A failing cycle is logged and never stops the others, and a service whose
/// previous cycle is still running (a slow probe) is skipped rather than
/// started twice.
class ServiceScheduler {
  ServiceScheduler(this.services, {Logger? logger})
    : _logger = logger ?? Logger(level: LogLevel.error);

  final List<RunningService> services;
  final Logger _logger;
  final List<Timer> _timers = [];
  final Set<RunningService> _running = {};

  /// Runs each service once, all at the same time, then keeps running them on
  /// their own intervals. Completes after the first round.
  Future<void> start() async {
    await Future.wait(services.map(_cycle));
    for (final service in services) {
      _timers.add(
        Timer.periodic(service.config.interval, (_) => _cycle(service)),
      );
    }
  }

  void stop() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  Future<void> _cycle(RunningService service) async {
    if (!_running.add(service)) return;
    try {
      await service.monitor.runOnce();
    } catch (e) {
      _logger.error('probe cycle for ${service.config.name} failed: $e');
    } finally {
      _running.remove(service);
    }
  }
}
