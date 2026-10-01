/// Where the user stands on system notifications.
enum NotifPermission {
  /// Notifications may be shown.
  granted,

  /// The user (or the browser/OS) blocked them.
  denied,

  /// Not asked yet.
  undecided,

  /// This platform cannot show them.
  unsupported,
}

/// Shows notifications through the operating system or browser. The
/// dashboard polls the backend, so these only appear while the app or tab is
/// running.
abstract class SystemNotifier {
  /// Whether this platform can show system notifications at all.
  bool get supported;

  /// The current permission, without asking.
  Future<NotifPermission> permission();

  /// Asks the user. On the web this must be called from a user gesture such
  /// as a tap.
  Future<NotifPermission> requestPermission();

  /// Shows a notification. [id] replaces a notification with the same id.
  /// Never throws: failures are swallowed so alerting cannot crash the app.
  Future<void> show({
    required int id,
    required String title,
    required String body,
  });
}
