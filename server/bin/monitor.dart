import 'dart:async';
import 'dart:io';

import 'package:sla_monitor_server/sla_monitor_server.dart';

/// Runs the Stripe probe on an interval, stores results in SQLite, checks the
/// SLA and prints alerts.
///
/// Env: STRIPE_API_KEY (required, test-mode key), PROBE_INTERVAL_SECONDS
/// (default 60), DB_PATH (default probes.db).
Future<void> main() async {
  final env = Platform.environment;
  final apiKey = env['STRIPE_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('STRIPE_API_KEY is not set (use a test-mode key).');
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
    alerter: ConsoleAlerter(),
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
