import 'dart:async';
import 'dart:io';

import 'package:sla_monitor_server/sla_monitor_server.dart';

/// Runs the Stripe probe on an interval, stores results in SQLite, checks the
/// SLA and prints alerts.
///
/// Key: STRIPE_API_KEY env var, else STRIPE_SECRET_KEY from the JSON file at
/// CONFIG_PATH (default ../config.json, git-ignored). Use a test-mode key.
/// Env: PROBE_INTERVAL_SECONDS (default 60), DB_PATH (default probes.db),
/// LOG_LEVEL (debug, info, warn, error; default info).
Future<void> main() async {
  final env = Platform.environment;
  final apiKey = readStripeKey(env);
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln(
      'No Stripe key: set STRIPE_API_KEY or STRIPE_SECRET_KEY '
      'in config.json (use a test-mode key).',
    );
    exit(64);
  }
  final interval = Duration(
    seconds: int.tryParse(env['PROBE_INTERVAL_SECONDS'] ?? '') ?? 60,
  );

  final logger = Logger.fromEnv(env);
  final store = ProbeStore.open(env['DB_PATH'] ?? 'probes.db');
  final monitor = Monitor(
    probe: StripeProbe(apiKey: apiKey),
    store: store,
    policy: const SlaPolicy(provider: StripeProbe.providerName),
    alerter: buildAlerter(env, onError: logger.error),
    logger: logger,
  );

  Future<void> tick() async {
    try {
      await monitor.runOnce();
    } catch (e) {
      logger.error('probe cycle failed: $e');
    }
  }

  await tick();
  final timer = Timer.periodic(interval, (_) => tick());
  ProcessSignal.sigint.watch().listen((_) {
    timer.cancel();
    store.close();
    exit(0);
  });
}
