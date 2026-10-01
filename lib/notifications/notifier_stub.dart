import 'system_notifier.dart';

/// A notifier for platforms that cannot show system notifications.
SystemNotifier createSystemNotifier() => const UnsupportedNotifier();

class UnsupportedNotifier implements SystemNotifier {
  const UnsupportedNotifier();

  @override
  bool get supported => false;

  @override
  Future<NotifPermission> permission() async => NotifPermission.unsupported;

  @override
  Future<NotifPermission> requestPermission() async =>
      NotifPermission.unsupported;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {}
}
