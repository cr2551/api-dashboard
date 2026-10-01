import 'package:flutter/material.dart';

import '../data/failure_kind.dart';

/// Small pill naming the kind of failure, with a tooltip that explains it.
/// A null [kind] is shown as "Unclassified" (results stored before the
/// backend categorised failures).
class FailureChip extends StatelessWidget {
  const FailureChip({super.key, required this.kind, this.count});

  final FailureKind? kind;

  /// How many failures of this kind, when summarising a time range.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = kind?.label ?? 'Unclassified';
    final hint = kind?.hint ?? 'Failed before failures were categorised.';
    return Tooltip(
      message: hint,
      triggerMode: TooltipTriggerMode.tap,
      child: Chip(
        avatar: Icon(
          kind?.icon ?? Icons.help_outline,
          size: 16,
          color: scheme.onErrorContainer,
        ),
        label: Text(count == null ? label : '$label × $count'),
        labelStyle: TextStyle(color: scheme.onErrorContainer),
        backgroundColor: scheme.errorContainer,
        side: BorderSide.none,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
