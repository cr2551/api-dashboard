import 'dart:io';

import 'package:sla_monitor_server/sla_monitor_server.dart';

/// Probes every configured service on its own interval, stores results in
/// SQLite, checks each service's SLA and alerts. (`serve.dart` does the same
/// and also serves the dashboard API.)
///
/// Services come from `SERVICES_CONFIG` (default `../services.json`, see
/// services.example.json); without that file it monitors Stripe only with the
/// default thresholds. Stripe key: STRIPE_API_KEY env var, else
/// STRIPE_SECRET_KEY from the JSON file at CONFIG_PATH (default
/// ../config.json, git-ignored). Use a test-mode key.
/// Env: PROBE_INTERVAL_SECONDS (only for the no-file fallback, default 60),
/// DB_PATH (default probes.db), LOG_LEVEL (debug, info, warn, error; default
/// info).
Future<void> main() async {
  final env = Platform.environment;
  final logger = Logger.fromEnv(env);

  final store = ProbeStore.open(env['DB_PATH'] ?? 'probes.db');
  final List<RunningService> services;
  try {
    final configs = resolveServices(
      env,
      defaultIntervalSeconds:
          int.tryParse(env['PROBE_INTERVAL_SECONDS'] ?? '') ?? 60,
      onInfo: logger.info,
    );
    services = buildServices(
      configs,
      env: env,
      store: store,
      alerter: buildAlerter(env, onError: logger.error),
      logger: logger,
    );
  } on ConfigException catch (e) {
    stderr.writeln(e);
    store.close();
    exit(64);
  }

  final scheduler = ServiceScheduler(services, logger: logger);
  await scheduler.start();
  ProcessSignal.sigint.watch().listen((_) {
    scheduler.stop();
    store.close();
    exit(0);
  });
}
