import 'dart:async';
import 'dart:io';

import 'package:sla_monitor_server/sla_monitor_server.dart';

/// Runs the Stripe probe on an interval, stores results in SQLite, checks the
/// SLA and prints alerts.
///
/// Key: STRIPE_API_KEY env var, else STRIPE_SECRET_KEY from the JSON file at
/// CONFIG_PATH (default ../config.json, git-ignored). Use a test-mode key.
/// Env: PROBE_INTERVAL_SECONDS (default 60), DB_PATH (default probes.db).
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

  final store = ProbeStore.open(env['DB_PATH'] ?? 'probes.db');
  final monitor = Monitor(
    probe: StripeProbe(apiKey: apiKey),
    store: store,
    policy: const SlaPolicy(provider: StripeProbe.providerName),
    alerter: buildAlerter(env),
  );

  Future<void> tick() async {
    final r = await monitor.runOnce();
    print(
      '${r.timestamp.toIso8601String()} ${r.provider} '
      '${r.success ? 'ok' : 'FAIL'} ${r.latency.inMilliseconds}ms '
      '${r.statusCode ?? r.error ?? ''}',
    );
  }

  await tick();
  final timer = Timer.periodic(interval, (_) => tick());
  ProcessSignal.sigint.watch().listen((_) {
    timer.cancel();
    store.close();
    exit(0);
  });
}
