import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sla_monitor_server/sla_monitor_server.dart';

/// Runs the Stripe probe on an interval AND serves the dashboard API.
///
/// Key: see [readStripeKey] (STRIPE_API_KEY or ../config.json). Use a
/// test-mode key. Env: PORT (default 8080), PROBE_INTERVAL_SECONDS (default
/// 30), DB_PATH (default probes.db). Listens on localhost only.
Future<void> main() async {
  final env = Platform.environment;
  final apiKey = readStripeKey(env);
  if (apiKey == null) {
    stderr.writeln(
      'No Stripe key: set STRIPE_API_KEY or STRIPE_SECRET_KEY '
      'in config.json (use a test-mode key).',
    );
    exit(64);
  }
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final interval = Duration(
    seconds: int.tryParse(env['PROBE_INTERVAL_SECONDS'] ?? '') ?? 30,
  );

  final store = ProbeStore.open(env['DB_PATH'] ?? 'probes.db');
  const policy = SlaPolicy(provider: StripeProbe.providerName);
  final monitor = Monitor(
    probe: StripeProbe(apiKey: apiKey),
    store: store,
    policy: policy,
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

  final server = await shelf_io.serve(
    apiHandler(store: store, policies: const [policy]),
    InternetAddress.loopbackIPv4,
    port,
  );
  print(
    'API on http://localhost:${server.port}/api/status '
    '(probing every ${interval.inSeconds}s, Ctrl+C to stop)',
  );

  await tick();
  final timer = Timer.periodic(interval, (_) => tick());
  ProcessSignal.sigint.watch().listen((_) async {
    timer.cancel();
    await server.close(force: true);
    store.close();
    exit(0);
  });
}
