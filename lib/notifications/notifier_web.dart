import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'system_notifier.dart';

/// Shows notifications with the browser's Notification API.
SystemNotifier createSystemNotifier() => WebNotifier();

class WebNotifier implements SystemNotifier {
  @override
  bool get supported {
    try {
      web.Notification.permission;
      return true;
    } catch (_) {
      return false;
    }
  }

  NotifPermission _fromString(String value) => switch (value) {
    'granted' => NotifPermission.granted,
    'denied' => NotifPermission.denied,
    _ => NotifPermission.undecided,
  };

  @override
  Future<NotifPermission> permission() async {
    if (!supported) return NotifPermission.unsupported;
    return _fromString(web.Notification.permission);
  }

  @override
  Future<NotifPermission> requestPermission() async {
    if (!supported) return NotifPermission.unsupported;
    try {
      final result = await web.Notification.requestPermission().toDart;
      return _fromString(result.toDart);
    } catch (_) {
      return _fromString(web.Notification.permission);
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      if (web.Notification.permission != 'granted') return;
      // A tag makes a repeat of the same id replace the earlier one.
      web.Notification(
        title,
        web.NotificationOptions(body: body, tag: 'sla-$id'),
      );
    } catch (_) {
      // Some mobile browsers only allow notifications from a service worker.
    }
  }
}
