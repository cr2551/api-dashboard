import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/service_event.dart';
import 'service_card.dart';

/// One line of the explanation: what happens, and the real numbers.
class HandlingStep {
  const HandlingStep(this.icon, this.title, this.text);

  final IconData icon;
  final String title;
  final String text;
}

String _plural(int n, String one, String many) => n == 1 ? one : many;

/// Plain-language steps describing how failures of a service are detected,
/// retried, judged and reported, using the service's real settings.
List<HandlingStep> describeHandling(ServiceSettings s) {
  final interval = s.intervalSeconds;
  final timeout = s.timeoutSeconds;
  return [
    HandlingStep(
      Icons.schedule,
      'Checks',
      '${interval == null ? 'Checks on a schedule' : 'Checks every ${interval}s'}'
          ' with a GET request'
          '${timeout == null ? '' : ' and waits up to ${timeout}s for an answer'}.',
    ),
    HandlingStep(
      Icons.replay,
      'Retries',
      s.retries == 0
          ? 'A failed check is never retried: the first failure counts.'
          : 'If the connection fails, times out or has a certificate error, '
                'it retries ${s.retries} ${_plural(s.retries, 'time', 'times')} '
                'right away before counting a failure. HTTP error responses '
                '(4xx and 5xx) are real answers, so they are not retried.',
    ),
    HandlingStep(
      Icons.rule,
      'What counts as a failure',
      s.expectedStatus == null
          ? 'Anything other than a 2xx response, or no answer at all.'
          : 'Anything other than HTTP ${s.expectedStatus}, or no answer at '
                'all.',
    ),
    HandlingStep(
      Icons.speed,
      'Judging the SLA',
      'Looks at the last ${s.windowMinutes} min: uptime must be at least '
          '${_percent(s.minUptimePercent)}% and p95 latency under '
          '${s.maxP95LatencyMs} ms.'
          '${s.minSamples > 1 ? ' With fewer than ${s.minSamples} checks in that '
                    'window it does not judge yet.' : ''}',
    ),
    HandlingStep(
      Icons.hourglass_bottom,
      'Before alerting',
      s.consecutiveFailures <= 1
          ? 'A breach is reported as soon as it is detected.'
          : 'A breach must hold for ${s.consecutiveFailures} checks in a row '
                'before it is reported, so one bad moment does not alert.',
    ),
    const HandlingStep(
      Icons.notifications_outlined,
      'Alerting',
      'One alert when a breach opens and one when it recovers, with how long '
          'it lasted. Nothing more is sent while it continues.',
    ),
  ];
}

String _percent(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

/// Collapsible "How failures are handled" section for a service, followed by
/// that service's recent alerts.
class FailureHandlingPanel extends StatelessWidget {
  const FailureHandlingPanel({
    super.key,
    required this.settings,
    this.events = const [],
    this.now,
    this.initiallyExpanded = false,
  });

  final ServiceSettings settings;

  /// Recent alerts for this service, newest first.
  final List<ServiceEvent> events;
  final DateTime? now;
  final bool initiallyExpanded;

  static const _maxAlerts = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clock = now ?? DateTime.now();
    return Card(
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        leading: const Icon(Icons.health_and_safety_outlined),
        title: const Text('How failures are handled'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final step in describeHandling(settings))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        step.icon,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${step.title}. ',
                                style: theme.textTheme.labelLarge,
                              ),
                              TextSpan(
                                text: step.text,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(),
              Text(
                'Recent alerts for this service',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              if (events.isEmpty)
                Text('None yet.', style: theme.textTheme.bodySmall),
              for (final e in events.take(_maxAlerts))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        e.kind == EventKind.opened
                            ? Icons.warning_amber
                            : Icons.check_circle_outline,
                        size: 16,
                        color: e.kind == EventKind.opened
                            ? theme.colorScheme.error
                            : const Color(0xFF2E9E5B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${e.kind == EventKind.opened ? 'Breach' : 'Recovered'}'
                          ': ${e.body} · ${timeAgo(e.timestamp, clock)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
