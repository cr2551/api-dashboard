import 'package:flutter/material.dart';

import '../data/service_event.dart';
import '../notifications/notification_center.dart';
import '../notifications/system_notifier.dart';
import '../widgets/service_card.dart';

/// The alerts list (breaches opened or resolved) plus the switch for system
/// notifications.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.center,
    this.onOpenService,
    this.now,
  });

  final NotificationCenter center;

  /// Called when an alert is tapped, to show that service.
  final void Function(ServiceEvent event)? onOpenService;

  /// Clock for the "x ago" labels; defaults to the real time.
  final DateTime Function()? now;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    _markReadAfterFrame();
    // Alerts arriving while this screen is open are read as they come.
    widget.center.addListener(_markReadAfterFrame);
  }

  /// Changing the unread count notifies the bell, which must not happen in
  /// the middle of a build, so it waits until the frame is done.
  void _markReadAfterFrame() {
    if (widget.center.unread == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.center.markAllRead();
    });
  }

  @override
  void dispose() {
    widget.center.removeListener(_markReadAfterFrame);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListenableBuilder(
        listenable: widget.center,
        builder: (context, _) {
          final events = widget.center.events;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SystemNotificationsCard(center: widget.center),
                  const SizedBox(height: 16),
                  Text(
                    'Recent alerts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (events.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          'No alerts yet. Breaches and recoveries show up '
                          'here.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  for (final e in events)
                    _EventTile(
                      event: e,
                      now: (widget.now ?? DateTime.now)(),
                      onTap: widget.onOpenService == null
                          ? null
                          : () => widget.onOpenService!(e),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SystemNotificationsCard extends StatelessWidget {
  const _SystemNotificationsCard({required this.center});

  final NotificationCenter center;

  String _subtitle() => switch (center.permission) {
    NotifPermission.unsupported =>
      'Not supported on this device. Alerts still appear in this list and '
          'as pop-ups while the app is open.',
    NotifPermission.denied =>
      'Blocked. Allow notifications for this site or app in your browser or '
          'Android settings, then switch this on again.',
    _ =>
      'Show a pop-up when a service breaches its SLA or recovers. Works '
          'while this app or tab is open; it cannot alert you once closed.',
  };

  @override
  Widget build(BuildContext context) {
    final unsupported = center.permission == NotifPermission.unsupported;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            SwitchListTile(
              title: const Text('System notifications'),
              subtitle: Text(_subtitle()),
              value: center.systemEnabled,
              // Null disables the switch where notifications cannot work.
              onChanged: unsupported
                  ? null
                  : (on) => center.setSystemNotifications(on),
            ),
            if (center.systemEnabled)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: TextButton.icon(
                    onPressed: center.sendTest,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Send test notification'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.now, this.onTap});

  final ServiceEvent event;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final opened = event.kind == EventKind.opened;
    final color = opened ? scheme.error : const Color(0xFF2E9E5B);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          opened ? Icons.warning_amber : Icons.check_circle_outline,
          color: color,
        ),
        title: Text(event.title),
        subtitle: Text('${event.body}\n${timeAgo(event.timestamp, now)}'),
        isThreeLine: true,
        trailing: Chip(
          label: Text(event.type.label),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
