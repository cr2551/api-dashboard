import 'dart:io';

import 'package:sla_monitor_server/sla_monitor_server.dart';

/// Manual pipeline drill: a deliberate, fake outage.
///
/// Starts a local fake "Stripe" that answers 200 for the first 3 probes, 503
/// for the next 4, then 200 again, and runs the real probe, store, SLA
/// detection, tracker and alerter against it once a second. No real API or
/// key is involved. Alerts go to the console, and also to ntfy when
/// NTFY_TOPIC is configured (see the README), so set it to see a real push.
///
///     dart run bin/drill.dart
Future<void> main() async {
  final env = Platform.environment;
  final logger = Logger(level: LogLevel.info);

  var calls = 0;
  final fake = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  fake.listen((request) {
    calls++;
    final failing = calls > 3 && calls <= 7;
    request.response
      ..statusCode = failing ? 503 : 200
      ..write('{}');
    request.response.close();
  });

  final store = ProbeStore.inMemory();
  final policy = SlaPolicy(
    provider: StripeProbe.providerName,
    minUptimePercent: 100,
    window: const Duration(seconds: 4),
    minSamples: 2,
  );
  final monitor = Monitor(
    probe: StripeProbe(
      apiKey: 'sk_test_drill',
      endpoint: Uri.parse('http://127.0.0.1:${fake.port}/v1/balance'),
      retries: 0,
    ),
    store: store,
    policy: policy,
    alerter: buildAlerter(env, onError: logger.error),
    logger: logger,
  );

  logger.info('drill: fake Stripe on port ${fake.port}, 14 cycles');
  for (var i = 0; i < 14; i++) {
    await monitor.runOnce();
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  // Give any in-flight ntfy request a moment to finish.
  await Future<void>.delayed(const Duration(seconds: 1));
  logger.info('drill: done');
  await fake.close(force: true);
  store.close();
  exit(0);
}
