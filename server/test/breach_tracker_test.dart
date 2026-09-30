import 'package:sla_monitor_server/sla_monitor_server.dart';
import 'package:test/test.dart';

SlaBreach breach(SlaBreachType type, {String provider = 'stripe'}) =>
    SlaBreach(provider: provider, type: type, message: 'm');

void main() {
  late BreachTracker tracker;
  setUp(() => tracker = BreachTracker());

  test('no breaches means no events', () {
    expect(tracker.update('stripe', const []), isEmpty);
  });

  test('a new breach opens once', () {
    final events = tracker.update('stripe', [breach(SlaBreachType.uptime)]);
    expect(events.single.kind, BreachEventKind.opened);
    expect(events.single.breach.type, SlaBreachType.uptime);
  });

  test('a persisting breach is silent', () {
    tracker.update('stripe', [breach(SlaBreachType.uptime)]);
    expect(tracker.update('stripe', [breach(SlaBreachType.uptime)]), isEmpty);
    expect(tracker.update('stripe', [breach(SlaBreachType.uptime)]), isEmpty);
  });

  test('a breach that disappears is resolved once', () {
    tracker.update('stripe', [breach(SlaBreachType.uptime)]);
    final events = tracker.update('stripe', const []);
    expect(events.single.kind, BreachEventKind.resolved);
    expect(tracker.update('stripe', const []), isEmpty);
  });

  test('a breach can reopen after resolving', () {
    tracker.update('stripe', [breach(SlaBreachType.uptime)]);
    tracker.update('stripe', const []);
    final events = tracker.update('stripe', [breach(SlaBreachType.uptime)]);
    expect(events.single.kind, BreachEventKind.opened);
  });

  test('types are tracked independently', () {
    tracker.update('stripe', [breach(SlaBreachType.uptime)]);
    final events = tracker.update('stripe', [
      breach(SlaBreachType.uptime),
      breach(SlaBreachType.latency),
    ]);
    expect(events.single.kind, BreachEventKind.opened);
    expect(events.single.breach.type, SlaBreachType.latency);
  });

  test('providers are tracked independently', () {
    tracker.update('stripe', [breach(SlaBreachType.uptime)]);
    final events = tracker.update('paypal', [
      breach(SlaBreachType.uptime, provider: 'paypal'),
    ]);
    expect(events.single.kind, BreachEventKind.opened);
    // paypal's update must not resolve stripe's breach.
    expect(tracker.update('stripe', [breach(SlaBreachType.uptime)]), isEmpty);
  });
}
