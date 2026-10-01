import 'package:flutter/material.dart';

import '../notifications/notification_center.dart';

/// App bar button that opens the alerts list, with a badge counting the
/// unread ones.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.center,
    required this.onPressed,
  });

  final NotificationCenter center;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: center,
      builder: (context, _) {
        final unread = center.unread;
        return IconButton(
          tooltip: unread == 0
              ? 'Notifications'
              : 'Notifications ($unread unread)',
          onPressed: onPressed,
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: Icon(
              unread > 0
                  ? Icons.notifications_active
                  : Icons.notifications_none,
            ),
          ),
        );
      },
    );
  }
}
