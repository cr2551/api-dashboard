import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';

/// Latency-over-time line chart. Failed probes are drawn as red dots.
class LatencyChart extends StatelessWidget {
  const LatencyChart({super.key, required this.points, required this.range});

  final List<ProbePoint> points;

  /// Visible time span; the x axis ends at the newest point.
  final Duration range;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final end = points.last.timestamp;
    final start = end.subtract(range);

    double x(ProbePoint p) =>
        p.timestamp.difference(start).inMilliseconds / 60000;

    final spots = [
      for (final p in points) FlSpot(x(p), p.latencyMs.toDouble()),
    ];
    final maxY = points.map((p) => p.latencyMs).reduce((a, b) => a > b ? a : b);
    final rangeMinutes = range.inMinutes.toDouble();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: rangeMinutes,
        minY: 0,
        maxY: (maxY * 1.2).ceilToDouble().clamp(100, double.infinity),
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            axisNameWidget: const Text('ms'),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) =>
                  SideTitleWidget(meta: meta, child: Text('${value.toInt()}')),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: rangeMinutes / 4,
              getTitlesWidget: (value, meta) {
                final t = start.add(Duration(minutes: value.round()));
                return SideTitleWidget(
                  meta: meta,
                  child: Text(formatClock(t.toLocal())),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => [
              for (final t in touched)
                LineTooltipItem(
                  '${points[t.spotIndex].latencyMs} ms'
                  '${points[t.spotIndex].success ? '' : ' (failed)'}\n'
                  '${formatClock(points[t.spotIndex].timestamp.toLocal(), seconds: true)}',
                  TextStyle(color: scheme.onInverseSurface),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: scheme.primary,
            barWidth: 2,
            isCurved: false,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: points[index].success ? 2 : 4,
                color: points[index].success ? scheme.primary : Colors.red,
                strokeWidth: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String formatClock(DateTime t, {bool seconds = false}) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}${seconds ? ':${two(t.second)}' : ''}';
}
