import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notifier_stub.dart';
import 'system_notifier.dart';

/// Android shows local notifications; other desktop and mobile platforms are
/// not set up yet and report "unsupported".
SystemNotifier createSystemNotifier() =>
    Platform.isAndroid ? AndroidNotifier() : const UnsupportedNotifier();

class AndroidNotifier implements SystemNotifier {
  AndroidNotifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _initialised;

  static const _channel = AndroidNotificationDetails(
    'sla_alerts',
    'SLA alerts',
    channelDescription: 'A service breached its SLA or recovered',
    importance: Importance.high,
    priority: Priority.high,
  );

  @override
  bool get supported => true;

  Future<void> _init() => _initialised ??= _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<NotifPermission> permission() async {
    try {
      await _init();
      final enabled = await _android?.areNotificationsEnabled();
      // Android cannot tell "never asked" from "blocked" without asking.
      return enabled == true
          ? NotifPermission.granted
          : NotifPermission.undecided;
    } catch (_) {
      return NotifPermission.undecided;
    }
  }

  @override
  Future<NotifPermission> requestPermission() async {
    try {
      await _init();
      final granted = await _android?.requestNotificationsPermission();
      return granted == true ? NotifPermission.granted : NotifPermission.denied;
    } catch (_) {
      return NotifPermission.denied;
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await _init();
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: _channel),
      );
    } catch (_) {
      // A notification failing to show must never crash the app.
    }
  }
}
