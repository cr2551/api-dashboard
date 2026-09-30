import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../widgets/latency_chart.dart';
import '../widgets/service_card.dart';

/// Time ranges offered on the detail screen.
const historyRanges = <int, String>{
  15: '15 min',
  60: '1 hour',
  360: '6 hours',
  1440: '24 hours',
};

/// Uptime and latency trend for one service.
class ServiceDetailScreen extends StatefulWidget {
  const ServiceDetailScreen({
    super.key,
    required this.client,
    required this.provider,
    this.initialMinutes = 60,
  });

  final ApiClient client;
  final String provider;
  final int initialMinutes;

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  late int _minutes = widget.initialMinutes;
  ServiceHistory? _history;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final requested = _minutes;
    try {
      final history = await widget.client.getHistory(
        widget.provider,
        minutes: requested,
      );
      if (!mounted || requested != _minutes) return;
      setState(() {
        _history = history;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || requested != _minutes) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _selectRange(int minutes) {
    if (minutes == _minutes) return;
    _minutes = minutes;
    _history = null;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(providerLabel(widget.provider)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<int>(
                  segments: [
                    for (final e in historyRanges.entries)
                      ButtonSegment(value: e.key, label: Text(e.value)),
                  ],
                  selected: {_minutes},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _selectRange(s.first),
                ),
                const SizedBox(height: 16),
                Expanded(child: _content(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final history = _history;
    if (history == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? 'Something went wrong'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final points = history.points;
    final latencies = points.map((p) => p.latencyMs);
    final failures = points.where((p) => !p.success).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 32,
          runSpacing: 12,
          children: [
            _Stat(
              label: 'Uptime (${historyRanges[_minutes] ?? '$_minutes min'})',
              value: formatPercent(history.uptimePercent),
            ),
            _Stat(label: 'Probes', value: '${points.length}'),
            _Stat(label: 'Failures', value: '$failures'),
            _Stat(
              label: 'Min / max latency',
              value: points.isEmpty
                  ? '—'
                  : '${latencies.reduce((a, b) => a < b ? a : b)} / '
                        '${latencies.reduce((a, b) => a > b ? a : b)} ms',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Latency', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Expanded(
          child: points.isEmpty
              ? const Center(child: Text('No probes in this time range'))
              : Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: LatencyChart(
                    points: points,
                    range: Duration(minutes: _minutes),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

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
        Text(value, style: theme.textTheme.headlineSmall),
      ],
    );
  }
}
