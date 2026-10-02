import 'package:flutter/material.dart';

import '../data/models.dart';
import 'failure_chip.dart';

const _upColor = Color(0xFF2E9E5B);
const _degradedColor = Color(0xFFD99A1E);
const _downColor = Color(0xFFD64545);

Color stateColor(ServiceState state, ColorScheme scheme) => switch (state) {
  ServiceState.up => _upColor,
  ServiceState.degraded => _degradedColor,
  ServiceState.down => _downColor,
  ServiceState.unknown => scheme.outline,
};

String stateLabel(ServiceState state) => switch (state) {
  ServiceState.up => 'Operational',
  ServiceState.degraded => 'Degraded',
  ServiceState.down => 'Down',
  ServiceState.unknown => 'No data',
};

/// Title for a service: the configured [displayName] when there is one,
/// otherwise the provider key with its first letter capitalised.
String providerLabel(String provider, {String? displayName}) {
  if (displayName != null && displayName.trim().isNotEmpty) {
    return displayName;
  }
  return provider.isEmpty
      ? provider
      : provider[0].toUpperCase() + provider.substring(1);
}

String formatPercent(double? value) =>
    value == null ? '—' : '${value.toStringAsFixed(value == 100 ? 0 : 2)}%';

String formatMs(int? ms) => ms == null ? '—' : '$ms ms';

String timeAgo(DateTime time, DateTime now) {
  final d = now.difference(time);
  if (d.inSeconds < 5) return 'just now';
  if (d.inSeconds < 60) return '${d.inSeconds}s ago';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// One card per monitored service.
class ServiceCard extends StatelessWidget {
  const ServiceCard({super.key, required this.service, this.now, this.onTap});

  final ServiceStatus service;
  final DateTime? now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = stateColor(service.state, theme.colorScheme);
    final last = service.lastProbe;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.circle, size: 14, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      providerLabel(
                        service.provider,
                        displayName: service.displayName,
                      ),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  Chip(
                    label: Text(stateLabel(service.state)),
                    labelStyle: TextStyle(color: color),
                    side: BorderSide(color: color),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _Metric(
                    label: 'Uptime (${service.windowMinutes} min)',
                    value: formatPercent(service.uptimePercent),
                  ),
                  _Metric(
                    label: 'Last latency',
                    value: formatMs(last?.latencyMs),
                  ),
                  _Metric(
                    label: 'Avg latency',
                    value: formatMs(service.avgLatencyMs),
                  ),
                  _Metric(
                    label: 'p95 latency',
                    value: formatMs(service.p95LatencyMs),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                last == null
                    ? 'No probes in the last ${service.windowMinutes} minutes'
                    : 'Last probe ${timeAgo(last.timestamp, now ?? DateTime.now())}'
                          '${last.success ? '' : ' · ${last.error ?? 'failed'}'}',
                style: theme.textTheme.bodySmall,
              ),
              if (last != null && !last.success) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FailureChip(kind: last.errorKind),
                ),
              ],
              for (final b in service.breaches) ...[
                const SizedBox(height: 8),
                _BreachBanner(breach: b),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _BreachBanner extends StatelessWidget {
  const _BreachBanner({required this.breach});

  final SlaBreachInfo breach;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'SLA breach: ${breach.message}',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
