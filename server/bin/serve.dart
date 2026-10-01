import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sla_monitor_server/sla_monitor_server.dart';

/// Probes every configured service on its own interval AND serves the
/// dashboard API.
///
/// Services come from `SERVICES_CONFIG` (default `../services.json`, see
/// services.example.json); without that file it monitors Stripe only with the
/// default thresholds. Stripe key: see [readStripeKey] (STRIPE_API_KEY or
/// ../config.json); use a test-mode key. Env: PORT (default 8080),
/// PROBE_INTERVAL_SECONDS (only for the no-file fallback, default 30),
/// DB_PATH (default probes.db), API_TOKEN (env or config.json; when set the
/// API needs `Authorization: Bearer <token>`), LOG_LEVEL (debug, info, warn,
/// error; default info), HOST (listen address, default 127.0.0.1; any
/// non-loopback address needs API_TOKEN, see [resolveListenAddress]).
/// Stops cleanly on Ctrl+C and on SIGTERM (systemd, `docker stop`).
Future<void> main() async {
  final env = Platform.environment;
  final logger = Logger.fromEnv(env);
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;

  final authToken = readSetting('API_TOKEN', env);
  final InternetAddress host;
  try {
    host = resolveListenAddress(env, authToken: authToken);
  } on ConfigException catch (e) {
    stderr.writeln(e);
    exit(64);
  }

  final store = ProbeStore.open(env['DB_PATH'] ?? 'probes.db');
  final List<RunningService> services;
  try {
    final configs = resolveServices(
      env,
      defaultIntervalSeconds:
          int.tryParse(env['PROBE_INTERVAL_SECONDS'] ?? '') ?? 30,
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

  if (authToken == null) {
    logger.warn(
      'API_TOKEN is not set: the API is unauthenticated '
      '(fine on localhost, not when exposed).',
    );
  } else {
    logger.info('API requires a bearer token');
  }

  final server = await shelf_io.serve(
    apiHandler(
      store: store,
      policies: [for (final s in services) s.policy],
      serviceConfigs: {for (final s in services) s.config.name: s.config},
      displayNames: {
        for (final s in services)
          if (s.config.displayName != null)
            s.config.name: s.config.displayName!,
      },
      authToken: authToken,
    ),
    host,
    port,
  );
  final shownHost = host.isLoopback ? 'localhost' : host.address;
  logger.info(
    'API on http://$shownHost:${server.port}/api/status, monitoring '
    '${services.map((s) => '${s.config.name} (every '
        '${s.config.interval.inSeconds}s)').join(', ')}. Ctrl+C to stop',
  );

  final scheduler = ServiceScheduler(services, logger: logger);
  await scheduler.start();
  Future<void> shutDown(ProcessSignal signal) async {
    logger.info('$signal received, stopping');
    scheduler.stop();
    await server.close(force: true);
    store.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutDown);
  // systemd and `docker stop` send SIGTERM; Windows cannot watch it.
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutDown);
}
